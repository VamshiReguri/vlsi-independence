# STA experiments

Standalone OpenSTA runs and Python timing-report analytics on ORFS designs.

## gcd (sky130hd) — Day 2

### 1. Run standalone OpenSTA

Requires completed ORFS gcd flow (`6_final.v`, `6_final.sdc`, `6_final.spef`).

```bash
# Start Docker Desktop first if using container flow
cd sta-experiments/gcd
chmod +x run_sta.sh
./run_sta.sh
```

Outputs in `sta-experiments/gcd/reports/`:
- `report_checks_setup.rpt` — setup paths (for Python parser)
- `report_checks_hold.rpt` — hold paths
- `summary.rpt` — WNS/TNS

### 2. Parse timing report → WNS/TNS chart

```bash
# From standalone OpenSTA output
python sta-experiments/parse_timing_report.py \
  sta-experiments/gcd/reports/report_checks_setup.rpt

# From ORFS finish report (no standalone STA needed)
python sta-experiments/parse_timing_report.py --orfs \
  ~/OpenROAD-flow-scripts/flow/reports/sky130hd/gcd/base/6_finish.rpt \
  -o sta-experiments/gcd/reports
```

Produces `paths.csv`, `slack_histogram.png`, `summary.txt`.

### Inputs (from ORFS)

| File | Path |
|------|------|
| Netlist | `~/OpenROAD-flow-scripts/flow/results/sky130hd/gcd/base/6_final.v` |
| SDC | `.../6_final.sdc` |
| SPEF | `.../6_final.spef` |
| Liberty | `.../platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib` |

### gcd post-route timing (your run)

| Metric | Value |
|--------|-------|
| Target clock | 1.1 ns (~909 MHz) |
| WNS (setup) | **-1.48 ns** |
| TNS (setup) | **-66.81 ns** |
| Setup violations | 64 |
| Hold violations | 0 |
| Achievable period | ~2.58 ns (~388 MHz) |

The design does not close at 1.1 ns — expected for this aggressive ORFS default. The critical path is reg-to-reg through the subtract/compare datapath (`a_reg` → `a_reg`).
