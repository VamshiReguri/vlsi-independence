# Day 6 — Ibex full-flow timing across stages (close the loop)

The ibex `sky130hd` RTL→GDS run is complete (`6_final.gds`, signoff WNS/TNS = 0.00,
0 setup / 0 hold violations, f_max 100.74 MHz). Day 4 timed only **synth / place / route**.
Day 6 closes the loop by timing **every** ORFS stage on the same 10 ns `core_clock`, so the
only variable between rows is the stage itself — and the two mid-stages Day 4 skipped
(**floorplan**, **CTS**) are exactly where the interesting behaviour hides.

All artifacts: `synth-experiments/ibex/`. Reproduce with `scripts/run_day6.sh`.

## Stage-by-stage timing table

Same design, one SDC per stage, `core_clock` = 10.0 ns:

| Stage | Database | Clock | Parasitics | Setup WNS | Setup TNS | Hold WNS | f_max |
|---|---|---|---|---:|---:|---:|---:|
| synth | `1_synth.odb` | ideal | none (pin cap) | −16.3004 | −22482.33 | +0.2265 | 38.02 MHz |
| floorplan | `2_floorplan.odb` | ideal | none | −16.2477 | −22387.78 | +0.2265 | 38.10 MHz |
| place | `3_place.odb` | ideal | est. (placement) | **+0.0462** | 0 | +0.2409 | 100.46 MHz |
| cts | `4_cts.odb` | propagated | est. (placement) | +0.0011 | 0 | +0.4280 | 100.01 MHz |
| route | `6_final.odb` | propagated | real SPEF | **+0.0686** | 0 | +0.4284 | 100.74 MHz |

All values in ns unless noted; f_max = 1000 / (10 − setup WNS). Source of truth:
`reports/fullflow/metrics_fullflow.txt`; chart: `reports/fullflow/ibex_stage_wns.png`.

**Cross-checks (all pass):** synth = Day 4 `synth_odb` (−16.3004); floorplan = ORFS
`2_floorplan_final.rpt` (−16.25); place = Day 4 (+0.0462); cts = ORFS `4_cts_final.rpt`
(0.00); route = Day 4 (+0.0686) and ORFS `6_finish` f_max 100.74.

## Where the −16 ns actually closes

- **synth → floorplan: nothing happens (−16.30 → −16.25).** Floorplan sets the die/core
  area, drops tapcells and the power grid, and — via `REMOVE_ABC_BUFFERS = 1`, which runs
  in `floorplan.tcl`, not synthesis — *strips* buffering. Standard cells are still unplaced,
  so there is no RC to speak of and the slack barely moves. The full −16 ns is still there.
- **floorplan → place: the cliff (−16.25 → +0.046).** The OpenROAD resizer
  (`repair_timing`: buffer insertion + gate up/downsizing) does 100% of the closure at
  placement — a 16.3 ns swing on a 10 ns clock. This is the Day 1 "Yosys has no
  timing-driven optimization engine" gap, measured end to end: synthesis hands the back end
  an unbuffered, minimum-size netlist and the placer's resizer fixes all of it.
- **place → cts: setup costs ~45 ps (+0.046 → +0.001).** The ideal clock is replaced by a
  real, propagated clock tree. Source latency is now ≈ 1.23 ns and the setup skew is
  +0.14 ns (target latency ≈ 1.09 ns, essentially the SDC's ideal 1.095 ns budget — the tree
  was built to that number). Meanwhile **hold margin grows** (+0.24 → +0.43 ns) because the
  tree's insertion delay pushes the capture edge out on short paths.
- **cts → route: setup recovers (+0.001 → +0.069).** Real extracted SPEF plus post-route
  optimization; f_max lands at 100.74 MHz, matching the ORFS `6_finish` signoff exactly.

**One-line story:** timing closure in this flow is a *back-end* event — it happens at
**placement**, not synthesis, and CTS/route only nudge an already-closed design by tens of
picoseconds (CTS trades a little setup for hold; routing gives the setup back).

## Method note

- Each stage is read with **its own stage SDC** (`N_*.sdc`). That matters: `1_synth`,
  `2_floorplan` and `3_place` SDCs carry an **ideal** clock, while `4_cts` and `6_final`
  SDCs contain `set_propagated_clock`. Reading the matching SDC is what makes the clock
  model correct per stage without any manual toggling.
- Parasitics are stage-appropriate: nothing pre-placement (pin capacitance only),
  `estimate_parasitics -placement` once cells are placed (place, cts), and real
  `read_spef` at route. This mirrors what each ORFS stage itself saw.
- Everything runs inside `openroad/orfs:latest` (same tool build as the RTL→GDS run) so the
  numbers are directly comparable to ORFS's own per-stage reports.

## Reproduce

```bash
bash synth-experiments/ibex/scripts/run_day6.sh
```

Requires the `openroad/orfs:latest` image and an ORFS checkout at `~/OpenROAD-flow-scripts`
with the ibex flow already run (the STA steps read `results/sky130hd/ibex/base/`). The driver
runs OpenROAD STA on each of the five stages, tees a per-stage `sta_<stage>.rpt`, and greps
the machine-readable `METRIC` lines into `reports/fullflow/metrics_fullflow.txt` in flow order.
The Day 6 notebook `sta-experiments/notebooks/ibex_fullflow_timing.ipynb` parses that file
into the table and the two-panel WNS chart.
