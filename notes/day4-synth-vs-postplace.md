# Day 4 — Ibex on sky130hd: synth-stage vs post-place timing

Standalone Yosys synthesis of `ibex_core` mapped to `sky130_fd_sc_hd`, compared against
the completed ORFS RTL→GDS run of the same design. Constraint in both cases is the ORFS
`designs/sky130hd/ibex/constraint.sdc`: `core_clock` at **10.0 ns**, ideal clock latency
1.095 ns, I/O delays at 20% of the period on a virtual clock.

All artifacts: `synth-experiments/ibex/`. Reproduce with `scripts/run_day4.sh`.

## Headline

**Synth-stage slack did not predict post-place slack, and was not even directionally
useful.** The design shows **−16.30 ns** WNS at the ORFS synth stage and closes at
**+0.046 ns** after placement — a 16.35 ns swing on a 10 ns clock. Gate count and area,
by contrast, tracked the final result to within about 20%.

## Numbers

Setup/hold from `report_checks` on the same SDC at four points in the flow:

| Stage | Netlist source | Setup WNS | Setup TNS | Hold WNS | Worst-path depth |
|---|---|---:|---:|---:|---:|
| Synthesis | my standalone Yosys script | −4.8873 | −3130.61 | +0.2257 | 48 |
| Synthesis | ORFS `1_synth.odb` | −16.3004 | −22482.33 | +0.2265 | 31 |
| Post-place | ORFS `3_place.odb`, estimated parasitics | **+0.0462** | 0 | +0.2409 | 36 |
| Post-route | ORFS `6_final.odb` + SPEF | **+0.0686** | 0 | +0.4284 | — |

All values in ns. Depth = combinational cells on the reported worst path.

Area and instance count over the same points:

| Stage | Instances | Cell area (µm²) | Sequential cells |
|---|---:|---:|---:|
| Synthesis (mine) | 15,307 | 127,250 | 1,938 |
| Synthesis (ORFS) | 14,043 | 129,314 | 1,939 |
| Post-place | 18,980 | 147,399 | 1,939 |
| Post-route (final) | 19,409 | 154,642 | 1,939 |

Final f_max on `core_clock` is 100.74 MHz; utilization goes 57.4% → 60.2% from place to finish.

## Why the synth-stage number is meaningless here

Not because of missing wire parasitics. I checked that separately: at the synth stage
OpenSTA is applying **no** wire model at all — the sky130hd liberty does define wire-load
models (`default_wire_load : "Small"`, mode `top`), but OpenROAD does not enable them, so
nets carry pin capacitance only. Forcing the `Small` model on explicitly moves my WNS from
−4.887 to −5.371, i.e. wire estimation is worth about **0.5 ns** here. That is nowhere near
the 16 ns gap.

The gap is **drive strength**, and it is deliberate. Reading the ORFS worst path at synth:

```
12.1387   13.2337 ^ if_stage_i.instr_rdata_id_o[16]$_DFFE_PP_/Q (sky130_fd_sc_hd__edfxtp_1)
 2.7855   16.0192 v _21300_/Y (sky130_fd_sc_hd__nor2b_1)
 ...
 2.1335   23.8152 ^ _17321_/X (sky130_fd_sc_hd__and4b_1)
 2.5651   26.9220 ^ _17556_/Y (sky130_fd_sc_hd__o31ai_1)
```

A single 12.1 ns stage out of a 26.9 ns path. That is one minimum-size flop driving a large
fanout with nothing buffering it. ORFS's ibex config runs ABC through the `abc_speed_gia_only`
script (selected by `SWAP_ARITH_OPERATORS = 1`), which maps to minimum-size cells and skips
ABC's `buffer -c` / `upsize -c` / `dnsize -c` steps entirely, then `REMOVE_ABC_BUFFERS = 1`
strips whatever buffers survive — and it does that in `floorplan.tcl`, not in synthesis. The
netlist handed to floorplanning is intentionally unbuffered and unsized, because OpenROAD's
resizer is going to redo all of it anyway. The final design contains **1,405 timing-repair
buffers**, 217 clock buffers and 129 clock inverters that simply do not exist at synth time.

My own script gets a much better-looking synth number (−4.89) purely because I called plain
`abc -liberty` with its default script, which *does* buffer and size. My netlist has ~1,480
buffers/inverters versus roughly 210 in the ORFS one, and drive variants (`maj3_2`, `a21oi_2`,
`o21ai_2`) rather than ORFS's near-uniform `_0`/`_1` cells.

**So comparing synth-stage WNS between two synthesis scripts told me nothing about which one
closes.** The script with the worse synth WNS is the one that reached +0.046 ns.

## Where my vanilla script is genuinely worse

One real structural difference does show up, and synth-stage analysis catches it correctly:

- My worst path contains **eleven consecutive `maj3_2` cells** — a ripple-carry adder chain.
- The ORFS path goes through `ALU_33_0_33_0_33_unused_CO_X_Y[0]_HAN_CARLSON`, a Han-Carlson
  parallel-prefix adder.

ORFS gets this from `SWAP_ARITH_OPERATORS = 1`, which extracts arithmetic operators and
re-implements them from a prefix-adder library. My path is 48 logic levels against ORFS's 31.
That difference is architectural and would survive any amount of buffering, which is exactly
the class of problem synth-stage review *should* be used for.

Note the ibex config also sets `ADDER_MAP_FILE :=` (empty) with the comment "Adders degrade
ibex setup repair" — the operator-swap path replaces it.

## What synth stage is actually good for

- **Sequential cell count is exact.** 1,938 at synth vs 1,939 final. Registers are decided at
  synthesis and nothing downstream changes them, so this is the one number worth trusting.
- **Area within ~20%.** 129,314 µm² at synth → 154,642 µm² final (+19.6%). Good enough for
  floorplan budgeting; the delta is buffers, tap cells and resizer upsizing.
- **Logic depth and structure.** `ltp -noff` reported a 98-level longest topological path on
  generic gates. Combined with the worst-path cell sequence, this is what exposes the
  ripple-vs-prefix adder issue, unintended latches, and bad FSM encodings.
- **Not slack.** In this flow the synth-stage WNS is an artifact of the ABC script's buffering
  policy, not a property of the design.

## Method note

`ltp` has to run **before** `dfflibmap`. Once flops become liberty blackboxes Yosys stops
recognising them as sequential, `-noff` no longer breaks register loops, and every sequential
loop is reported as a combinational one. Running it after mapping produced 208,835
"Detected loop" warnings and a 15 MB log; moving it earlier gives a clean 424 KB log and a
usable depth number.

## Runtime

My vanilla script: **21.5 s** total, 56% of it in ABC (12 s). The ORFS synth stage spent
**68 s** in `abc9` alone across 9 invocations — the parallel-prefix extraction and the more
aggressive `&dch`/`&syn2` iteration are not free.
