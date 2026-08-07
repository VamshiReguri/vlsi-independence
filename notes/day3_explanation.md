# Day 3 Explanation — STA Fundamentals, Re-Anchored

**Canonical full copy also at:** `C:\Users\regur\Downloads\day3_explanation.md`  
(Use that Downloads-root file as the complete standalone guide. This notes copy matches it.)

**Project:** `C:\Users\regur\Downloads\vlsi-independence`  
**Duration:** ~2.5 hours (Monday)  
**Topic:** Solidify STA theory in open-tool terms (OpenSTA + your own gcd reports).

This file is the **complete Day 3 guide**. Everything you need — schedule, theory, how it maps to your files, what was prepared, what to re-run, predicted numbers, and how to know you are done — is here.

---

## 1. Goal in one sentence

Take the Day-2 OpenSTA numbers you already have, learn the setup/hold and exception theory behind them, change one SDC exception, **predict** the new WNS, re-run, and write down *why* WNS changed.

---

## 2. How Day 3 fits the week

| Day | What you did | What Day 3 adds |
|-----|--------------|-----------------|
| Day 1 | Open-source EDA landscape + ORFS gcd RTL→GDS | Context for why timing/SDC tooling matters |
| Day 2 | Standalone OpenSTA on gcd + hand SDC + `report_checks` | Baseline WNS = **−1.495 ns** |
| **Day 3** | **Theory ↔ your report; edit SDC; re-run; explain ΔWNS** | Numbers become **predictions** |

Day 2 answered: “Can I run the tool?”  
Day 3 answers: “Do I understand what the tool is computing, and can I change constraints on purpose?”

That skill is the foundation of your lead project idea (SDC linter / timing analytics): a linter is useful only if you can forecast what a constraint will do.

---

## 3. Time budget (~2.5 h)

| Block | Time | What to do |
|-------|------|------------|
| A. Setup/hold + path types + clocks | ~60 min | Read actively; after each section, find the same idea in your Day-2 report |
| B. Delay columns (optional but useful) | ~30 min | Skim library / parasitics / delay calc so slew/cap/delay columns make sense |
| C. Build | ~45 min | Use prepared SDC → re-run OpenSTA → parse → compare to baseline |
| D. Write-up | ~15 min | Fill Day 3 results in `vlsi-independence\notes\week1.md` |

---

## 4. What to read (and a book note)

**Assigned framing:** Bhasker & Chadha, *Static Timing Analysis for Nanometer Designs*, with focus on setup/hold, path types, and clocks.

**Edition note:** In the common edition, Chapters 3–5 are **Standard Cell Library**, **Interconnect Parasitics**, and **Delay Calculation**. Setup/hold checks, path groups, clocks, false paths, and multicycle paths are typically **Ch. 7 (Configuring the STA Environment)** and **Ch. 8 (Timing Verification)**.

Practical split for your 2.5 h:

- **Must do for the build:** setup/hold equations, path groups, false path, multicycle path (+ hold companion).
- **Worth skimming:** library timing arcs, SPEF/parasitics, how stage delay is looked up — those explain the columns in your report.

You do **not** need a perfect chapter map. You need to be able to point at a line in your report and say what it means.

---

## 5. Your Day-2 baseline (already frozen)

These files were copied so a re-run does not erase Day 2:

```
C:\Users\regur\Downloads\vlsi-independence\sta-experiments\gcd\reports\baseline\
  opensta_full.rpt
  report_checks.rpt
  summary.txt
  paths.csv
```

| Metric | Value |
|--------|-------|
| Design | gcd (sky130hd, post-route) |
| Clock | `core_clock`, period **1.1 ns** |
| WNS (setup) | **−1.495 ns** |
| TNS (setup) | **−67.457 ns** |
| Worst path | `dpath.a_reg.out[8]` → `dpath.a_reg.out[6]` |
| Data arrival | **2.632 ns** |
| Data required | **1.137 ns** |
| Hold (Day 2) | **0 violations** (clean) |

Source summary file:

```
wns_setup_ns -1.495
tns_setup_ns -67.457
paths_parsed 123
```

---

## 6. Setup check — explained on YOUR worst path

OpenSTA reports this path type as `max` (setup). Conceptually:

```
slack = data_required_time − data_arrival_time
```

### 6.1 Data arrival (launch side)

From the rising edge of `core_clock` at the **launch** flop:

1. Clock network delay (propagated from SPEF) to launch `CLK`
2. Clock-to-Q of the flop
3. Combinational delay through the datapath
4. Arrival at capture flop `D`

On your critical path that sum is **2.632 ns**.

### 6.2 Data required (capture side)

From the rising edge of `core_clock` at the **capture** flop (same edge for single-cycle setup):

1. Capture edge time = **1.100 ns** (one period after launch at t=0)
2. Plus clock network delay to capture `CLK` ≈ **0.292 ns**
3. Minus library setup time ≈ **0.255 ns**

```
required ≈ 1.100 + 0.292 − 0.255 = 1.137 ns
```

### 6.3 Slack

```
slack = 1.137 − 2.632 = −1.495 ns  (VIOLATED)
```

That −1.495 ns **is** WNS for Day 2, because it is the worst (most negative) setup slack among reported paths.

### 6.4 Ideal latency vs propagated clock

Your hand SDC still has:

```tcl
set_clock_latency 0.290 [get_clocks core_clock]
```

But `run_sta.tcl` also does:

```tcl
set_propagated_clock [get_clocks core_clock]
```

So OpenSTA uses **real clock-tree delay from SPEF** (~0.29 ns), not a pure ideal 0.290. That is why the report says `clock network delay (propagated)` instead of a fixed ideal latency.

---

## 7. Hold check (min paths) — what you need for Day 3

Setup asks: “Is data **early enough** before the capture edge?”  
Hold asks: “Is data **late enough** after the same/launch edge so the old value is not corrupted?”

- Path type in OpenSTA: `min` (hold).
- Day-2 gcd hold was **clean** (0 violations).
- When you add a **multicycle setup**, OpenSTA’s default hold edge moves with the setup edge unless you also set a hold multicycle. That invents false hold fails. The industry fix is the companion:

```tcl
set_multicycle_path 1 -hold ...
```

Your Day-3 primary SDC already includes that line. Part of the lesson is understanding **why** it is there.

---

## 8. Path types and path groups (map to your report)

| Report field | Meaning |
|--------------|---------|
| `Path Type: max` | Setup (late) path |
| `Path Type: min` | Hold (early) path |
| `Path Group: core_clock` | Timing group for that clock’s reg→reg (and related) checks |
| Startpoint / Endpoint | Launch pin → capture pin |

Path categories you should be able to name:

| Path class | Example in gcd flow |
|------------|---------------------|
| Reg → reg | Your critical path (`a_reg` → `a_reg`) |
| In → reg | Input delay vs `vclk_core_clock` |
| Reg → out | Output delay vs `vclk_core_clock` |
| In → out | Combinational through (if unconstrained carefully, can be noisy) |

Your Day-2 SDC uses a **virtual clock** `vclk_core_clock` for I/O delays so pad timing is relative to a clean ideal clock while on-chip flops use `core_clock`.

---

## 9. Exceptions: false path vs multicycle path

### 9.1 False path (`set_false_path`)

Tells STA: **do not time this path at all** (or do not consider it for that check).

Prepared file:

`C:\Users\regur\Downloads\vlsi-independence\sta-experiments\gcd\gcd_false.sdc`

It waives only the Day-2 worst path:

```tcl
set_false_path \
  -from [get_pins {dpath.a_reg.out[8]$_DFFE_PP_/CLK}] \
  -to   [get_pins {dpath.a_reg.out[6]$_DFFE_PP_/D}]
```

**Why braces?** Without `{...}`, Tcl treats `$_DFFE_PP_` as a variable and `[8]` as a command. Always brace hierarchical names with `$` and `[ ]`.

**Predicted effect:**

- Path with slack −1.495 disappears from analysis.
- Next worst in `paths.csv` is about **−1.490 ns**.
- WNS barely moves (Δ ≈ **+5 ps**).

**Lesson:** With dozens of similar violating datapath paths, waiving one path does almost nothing to WNS. A good SDC linter would warn about “waive one of many equivalent violators.”

### 9.2 Multicycle path (`set_multicycle_path`) — primary Day-3 experiment

Tells STA: data is allowed **N clock cycles** between launch and capture for setup (instead of 1).

Prepared file:

`C:\Users\regur\Downloads\vlsi-independence\sta-experiments\gcd\gcd_mcp.sdc`

Key lines added on top of the Day-2 hand SDC:

```tcl
set_multicycle_path 2 -setup -from [get_clocks core_clock] -to [get_clocks core_clock]
set_multicycle_path 1 -hold  -from [get_clocks core_clock] -to [get_clocks core_clock]
```

Meaning:

- **Setup N=2:** capture edge moves **one full period later** (from edge at 1.1 ns to edge at 2.2 ns for a 1.1 ns clock).
- **Hold N=1:** restore same-edge (or appropriate) hold check so hold does not falsely fail.

**Predicted math (do this before you re-run):**

```
Old capture edge:     1.100
New capture edge:     2.200   (+1 × period)

New required ≈ 2.200 + 0.292 − 0.255 = 2.237
New slack    ≈ 2.237 − 2.632         = −0.395 ns
```

So:

```
ΔWNS ≈ +1.100 ns
WNS:  −1.495  →  ≈ −0.395
```

**Reality check:** Applying MCP to *all* `core_clock` paths is **not** a real tapeout fix for gcd (the design still needs a slower clock or better logic). It is a **controlled experiment** so the arithmetic is obvious. You are learning how exceptions move numbers, not claiming timing closure.

---

## 10. Files prepared for you under Downloads

| Path under `C:\Users\regur\Downloads\vlsi-independence\` | Role |
|----------------------------------------------------------|------|
| `sta-experiments\gcd\gcd_hand.sdc` | Day-2 baseline SDC (unchanged) |
| `sta-experiments\gcd\gcd_mcp.sdc` | **Primary** Day-3 SDC (multicycle) |
| `sta-experiments\gcd\gcd_false.sdc` | Alternate Day-3 SDC (false path) |
| `sta-experiments\gcd\run_sta.sh` | Runner; now honors `SDC=` even in Docker |
| `sta-experiments\gcd\run_sta.tcl` | OpenSTA script (`report_wns`, setup/hold `report_checks`) |
| `sta-experiments\gcd\reports\baseline\` | Frozen Day-2 numbers |
| `sta-experiments\parse_timing_report.py` | Parses report → WNS/TNS + CSV |
| `notes\week1.md` | Log Day-3 results here after the run |
| `C:\Users\regur\Downloads\day3_explanation.md` | **Complete standalone guide (Downloads root)** |

### 10.1 `run_sta.sh` fix (why it mattered)

Previously the Docker branch always used `gcd_hand.sdc`, so:

```bash
SDC=gcd_mcp.sdc ./run_sta.sh
```

would silently ignore your exception under Docker. It now maps the host SDC into `/work/...` on the container. Always confirm the script prints:

```
Using SDC: .../gcd_mcp.sdc
```

---

## 11. Active reading checklist (do this while studying)

Open:

`vlsi-independence\sta-experiments\gcd\reports\baseline\report_checks.rpt`

After each theory section, find:

- [ ] Launch edge / capture edge times  
- [ ] Propagated clock network delay  
- [ ] Library setup time  
- [ ] Data arrival / data required / slack  
- [ ] `Path Type: max`  
- [ ] `Path Group: core_clock`  
- [ ] At least one hold (`min`) path in `opensta_full.rpt`  
- [ ] Mentally apply: “If MCP=2, which number on this page moves?”

---

## 12. What to re-run (full commands)

Run in **WSL** (bash), not PowerShell. Need: Docker Desktop running, ORFS gcd results still present (`6_final.v`, `6_final.spef`).

Adjust the first `cd` if your WSL path to Downloads differs (common: `/mnt/c/Users/regur/Downloads/...`).

### Step 1 — Multicycle experiment (primary)

```bash
cd /mnt/c/Users/regur/Downloads/vlsi-independence/sta-experiments/gcd
SDC=gcd_mcp.sdc ./run_sta.sh
```

Confirm output shows `Using SDC: .../gcd_mcp.sdc`, then WNS/worst slack lines.

### Step 2 — Parse the new report

```bash
cd /mnt/c/Users/regur/Downloads/vlsi-independence
python3 sta-experiments/parse_timing_report.py \
  sta-experiments/gcd/reports/report_checks.rpt \
  -o sta-experiments/gcd/reports
```

### Step 3 — Compare to baseline

```bash
echo "=== baseline (Day 2) ==="
cat sta-experiments/gcd/reports/baseline/summary.txt

echo "=== after MCP (Day 3) ==="
cat sta-experiments/gcd/reports/summary.txt

grep -E '^(wns|worst slack)' sta-experiments/gcd/reports/opensta_full.rpt
```

**Expect roughly:** WNS ≈ **−0.395 ns** (about 1.1 ns better than −1.495).

### Step 4 — Spot-check hold still clean

In `opensta_full.rpt`, find the section `=== report_checks hold (min) ===` and confirm slacks are MET (or hold violation count stays 0). That validates the `-hold 1` companion.

### Step 5 — Optional: false-path experiment

Save MCP results first, then re-run with the false-path SDC:

```bash
mkdir -p sta-experiments/gcd/reports/day3_mcp
cp sta-experiments/gcd/reports/opensta_full.rpt \
   sta-experiments/gcd/reports/report_checks.rpt \
   sta-experiments/gcd/reports/summary.txt \
   sta-experiments/gcd/reports/paths.csv \
   sta-experiments/gcd/reports/day3_mcp/

cd sta-experiments/gcd
SDC=gcd_false.sdc ./run_sta.sh

cd ../..
python3 sta-experiments/parse_timing_report.py \
  sta-experiments/gcd/reports/report_checks.rpt \
  -o sta-experiments/gcd/reports

cat sta-experiments/gcd/reports/summary.txt
# Expect WNS ≈ -1.490 (tiny change vs baseline -1.495)
```

### If `./run_sta.sh` is not executable

```bash
chmod +x sta-experiments/gcd/run_sta.sh
```

### If Python deps are missing

```bash
pip install -r sta-experiments/requirements.txt
# or: pip install pandas matplotlib
```

---

## 13. What “good” looks like after the re-run

| Check | Pass criteria |
|-------|----------------|
| SDC used | Script printed `gcd_mcp.sdc` |
| Setup WNS | Near **−0.395 ns** (not still −1.495) |
| ΔWNS | About **+1.1 ns** vs baseline |
| Hold | Still clean with `-hold 1` present |
| Notes | You can explain the mechanism in one sentence |

Fill this table in `vlsi-independence\notes\week1.md`:

| | Baseline | After MCP |
|--|----------|-----------|
| WNS setup (ns) | −1.495 | _(your measured)_ |
| TNS setup (ns) | −67.457 | _(your measured)_ |
| Hold clean? | yes | _(yes/no)_ |

**One-sentence model answer:**

> Multicycle 2 moved the setup capture edge one period later (1.1 → 2.2 ns), so required time rose by ~1.1 ns and WNS went from −1.495 to ≈ −0.395; `-hold 1` kept hold MET because the hold reference edge was restored instead of following the moved setup edge.

If you can write that without looking it up, Day 3 is done.

---

## 14. How this connects to your bigger plan

Your Week-1 lead gap is **constraint-driven timing tooling**. Day 3 practices the exact judgments an SDC linter must encode:

1. **False path on one of many similar violators** → WNS almost unchanged → suspicious / low-value exception.  
2. **Multicycle without hold companion** → hold pollution → classic SDC footgun.  
3. **Multicycle on an entire clock** → huge WNS move, but may be **architecturally wrong** unless the RTL really has a 2-cycle contract.

Day 3 is not about “fixing” gcd. It is about **owning the relationship between SDC text and slack numbers** in an open flow (OpenSTA + sky130 + your scripts).

---

## 15. Quick glossary

| Term | Meaning |
|------|---------|
| WNS | Worst Negative Slack — most negative (or least positive) slack |
| TNS | Total Negative Slack — sum of negative slacks |
| Setup (max) | Data must arrive before required time |
| Hold (min) | Data must stay stable long enough after launch/capture relationship |
| SDC | Synopsys Design Constraints — clocks, I/O delays, exceptions |
| False path | Do not analyze this path |
| Multicycle path | Allow N cycles for the check instead of 1 |
| SPEF | Parasitics file; enables propagated clock / wire delay |
| CRPR | Clock Reconvergence Pessimism Removal — adjusts shared clock-path pessimism (often 0.000 in simple reports) |

---

## 16. Done checklist

- [ ] Read setup/hold + exceptions; mapped each idea into `reports/baseline/report_checks.rpt`
- [ ] Predicted MCP WNS ≈ −0.395 **before** re-running
- [ ] Ran `SDC=gcd_mcp.sdc ./run_sta.sh` in WSL
- [ ] Parsed and compared to `reports/baseline/summary.txt`
- [ ] Confirmed hold still clean
- [ ] Wrote the “why WNS changed” sentence into `notes/week1.md`

**End of Day 3 explanation.**
