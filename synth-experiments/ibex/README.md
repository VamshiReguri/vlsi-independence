# Ibex standalone synthesis — Yosys → sky130hd

Standalone Yosys synthesis of `ibex_core` mapped to `sky130_fd_sc_hd`, plus staged STA
against the completed ORFS RTL→GDS run of the same design.

Findings are in [`notes/day4-synth-vs-postplace.md`](../../notes/day4-synth-vs-postplace.md).
Reading notes on the Yosys manual are in
[`notes/day4-yosys-manual-ch4-6.md`](../../notes/day4-yosys-manual-ch4-6.md).

## Results

Yosys 0.67+post, `core_clock` at 10.0 ns.

| Metric | Value |
|---|---:|
| Mapped cells | 15,307 |
| Cell area | 127,250 µm² |
| Sequential cells | 1,938 (39.2% of area) |
| Longest topological path (generic gates) | 98 levels |
| Synth-stage setup WNS | −4.8873 ns |
| Post-place setup WNS (ORFS) | +0.0462 ns |
| Post-route setup WNS (ORFS) | +0.0686 ns |
| Yosys runtime | 21.5 s (56% in ABC) |

## Day 6 — full-flow timing across stages

Day 4 timed synth / place / route. Day 6 closes the loop by timing **every** ORFS stage of
the completed run on the same 10 ns `core_clock` (adding the skipped **floorplan** and
**CTS** stages), so the stage-by-stage table shows exactly *where* the −16 ns synth slack
becomes a closed design. Full analysis: [`notes/day6-full-flow-timing.md`](../../notes/day6-full-flow-timing.md).

| Stage | Clock | Parasitics | Setup WNS | Setup TNS | Hold WNS | f_max |
|---|---|---|---:|---:|---:|---:|
| synth (`1_synth.odb`) | ideal | none | −16.3004 | −22482.33 | +0.2265 | 38.02 MHz |
| floorplan (`2_floorplan.odb`) | ideal | none | −16.2477 | −22387.78 | +0.2265 | 38.10 MHz |
| place (`3_place.odb`) | ideal | est. | **+0.0462** | 0 | +0.2409 | 100.46 MHz |
| cts (`4_cts.odb`) | propagated | est. | +0.0011 | 0 | +0.4280 | 100.01 MHz |
| route (`6_final.odb`) | propagated | SPEF | **+0.0686** | 0 | +0.4284 | 100.74 MHz |

Closure is a back-end event: floorplan ≈ synth (buffers stripped, cells unplaced), the
resizer at **placement** does all 16.3 ns of it, CTS trades ~45 ps of setup for hold when the
ideal clock becomes a propagated tree, and routing hands the setup back. `6_final.gds` is
produced; signoff WNS/TNS = 0.00 with 0 setup / 0 hold violations. Chart:
`reports/fullflow/ibex_stage_wns.png`; notebook:
[`sta-experiments/notebooks/ibex_fullflow_timing.ipynb`](../../sta-experiments/notebooks/ibex_fullflow_timing.ipynb).

```bash
bash scripts/run_day6.sh
```

## Running it

Requires the `openroad/orfs:latest` image and an ORFS checkout at
`~/OpenROAD-flow-scripts` with the ibex flow already run (the STA steps read
`results/sky130hd/ibex/base/`).

```bash
bash scripts/run_day4.sh
```

Everything executes inside the ORFS container so tool versions match the run being
compared against. The driver mounts the ORFS flow directory at `/flow` and its own
scratch directory at `/day4`, then does five steps: Yosys synthesis, followed by STA on
the synth netlist, the ORFS synth database, the placed database and the routed database.

## Layout

```
scripts/ibex_synth.tcl   Yosys script, stage-annotated (read_slang -> ABC -> reports)
scripts/sta.tcl          Day 4 STA driver, switches on $STA_MODE (synth_v/synth_odb/place/route)
scripts/run_day4.sh      Day 4 container orchestration for all five steps
scripts/sta_fullflow.tcl Day 6 STA driver, one row per ORFS stage (synth..route)
scripts/run_day6.sh      Day 6 orchestration: STA on every stage -> metrics_fullflow.txt
logs/1_yosys_synth.log   full synthesis log
reports/stat_0{1..4}*    cell counts at each abstraction level
reports/ltp.txt          longest topological path (pre-dfflibmap)
reports/sta_*.rpt        Day 4 report_checks at each stage
reports/metrics.txt      Day 4 one-line WNS/TNS summary per stage
reports/fullflow/        Day 6 full-flow: per-stage sta_*.rpt, metrics_fullflow.txt, WNS chart
```

The gate-level netlist (`ibex_yosys.v`, 2.5 MB) and its JSON form (13 MB) are not
committed; rerun the script to regenerate them into `~/vlsi-day4/out/`.

## Deliberate differences from the ORFS script

The Yosys script here is a plain textbook flow, not a copy of ORFS's tuned one, so the
comparison isolates what the tuning buys:

- plain `abc -liberty` with its default script, so buffering and gate sizing happen
  (ORFS uses `abc_speed_gia_only` and emits an unbuffered, minimum-size netlist)
- no `SWAP_ARITH_OPERATORS`, so the ALU stays a ripple chain instead of Han-Carlson
- flat, non-hierarchical synthesis
- `-D 10000` ps as the ABC delay target, matching the 10 ns SDC period

Shared with ORFS: the same sky130hd liberty, the same `DONT_USE_CELLS` list, the same
`abc.constr` driving cell and load, the same latch legalisation, and the same SDC.
