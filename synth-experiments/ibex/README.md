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
scripts/sta.tcl          STA driver, switches on $STA_MODE
scripts/run_day4.sh      container orchestration for all five steps
logs/1_yosys_synth.log   full synthesis log
reports/stat_0{1..4}*    cell counts at each abstraction level
reports/ltp.txt          longest topological path (pre-dfflibmap)
reports/sta_*.rpt        report_checks at each stage
reports/metrics.txt      one-line WNS/TNS summary per stage
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
