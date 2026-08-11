# PDK experiments — sky130hd `.lib` / `.lef`

Day 5. The PDK is the contract between logic and silicon: the **liberty (`.lib`)**
tells every tool how fast/how much power a cell is, and the **LEF (`.lef`)** tells
every tool how big it is and where its pins are. This experiment opens one
standard cell (`sky130_fd_sc_hd__inv_2`) in *both* views and proves that STA delay
is nothing more than a 2-D interpolation of the characterized `.lib` table.

Full reasoning (why each step, why this way): `../../day5_explanation.md`
(kept outside the repo on purpose).

## Result

Our own bilinear lookup of the raw `cell_rise` / `cell_fall` tables matches
OpenSTA's arc delay to **< 0.01 ps**:

| slew (ns) | load (pF) | arc | predicted | OpenSTA | \|err\| |
|---|---|---|---|---:|---:|
| 0.05313 *(grid node)* | 0.01287 *(grid node)* | rise (A↓→Y↑) | 0.07601 | 0.07601 | 0.003 ps |
| 0.05313 | 0.01287 | fall (A↑→Y↓) | 0.04870 | 0.04870 | 0.004 ps |
| 0.20000 *(off-grid)* | 0.05000 *(off-grid)* | rise | 0.25816 | 0.25816 | 0.003 ps |
| 0.20000 | 0.05000 | fall | 0.16076 | 0.16076 | 0.004 ps |

Same cell, two files, one consistency check:
`area : 3.7536` in the `.lib` == `SIZE 1.380 × 2.720` in the `.lef`, and
`1.380 / 0.460 = 3` — `inv_2` is exactly three `unithd` placement sites wide.

## Running it

Requires Docker + `openroad/orfs:latest` and an ORFS checkout at
`~/OpenROAD-flow-scripts` (only the sky130hd platform files are read).

```bash
bash pdk-experiments/run_pdk.sh
```

Three steps: (1) `inspect_pdk.sh` carves readable slices out of the 12.8 MB
liberty and 2.3 MB LEF; (2) `arc_delay.tcl` runs OpenSTA on a one-cell netlist
at chosen (slew, load) points; (3) `interp_check.py` does the same lookup by hand
and prints predicted-vs-measured.

## Layout

```
tiny_inv.v         one inv_2 in a top module (the whole "design")
arc_delay.tcl      OpenSTA: fix input slew + output load, report the A->Y arc delay
inspect_pdk.sh     awk slices: lib header, one cell's .lib model, its .lef macro, tech-LEF
interp_check.py    parse the NLDM table + bilinear interpolate; compare to OpenSTA
run_pdk.sh         driver (host awk -> OpenSTA in container -> python compare)
reports/           extracted slices + OpenSTA report + comparison (reproducible)
```

## Optional: the sizing view (why this feeds gate sizing)

Re-run the extractor on the other drive strengths and diff:

```bash
CELL=sky130_fd_sc_hd__inv_1 bash pdk-experiments/inspect_pdk.sh
CELL=sky130_fd_sc_hd__inv_4 bash pdk-experiments/inspect_pdk.sh
```

| cell | `.lib` area (µm²) | input cap (fF) | `.lef` width (µm) | sites |
|---|---:|---:|---:|---:|
| `inv_1` | 3.7536 | 2.30 | 1.38 | 3 |
| `inv_2` | 3.7536 | 4.46 | 1.38 | 3 |
| `inv_4` | 6.2560 | 9.00 | 2.30 | 5 |

Upsizing 1→2 buys ~2× drive for ~2× input cap at **zero** extra area (same
footprint, bigger transistors); 2→4 costs both cap and a genuinely wider cell.
That trade — drive vs. input cap vs. area — is exactly what a sizer decides, and
it lives entirely in these two files.
