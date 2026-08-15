# Week 1 — Open-source EDA landscape + first flow

## Sources read

- MDPI (2026) survey: *From RTL to Fabrication: Survey of Open-Source EDA Tools and PDKs* (electronics-15-01048).
- EuroCDP: *Open EDA Tool Gap Analysis and Recommendations*.

## Key landscape takeaways

- Full open RTL→GDSII is feasible today: **Yosys → OpenSTA → OpenROAD/OpenLane** on **SKY130 / GF180MCU** (open PDKs down to ~130 nm).
- Domain maturity (EuroCDP): **Digital = most mature** > Analog (usable) > **Mixed-signal / RF / Photonics = big gaps**.

## Gaps found (candidate first projects)

1. **[MY LEAD] Integrated, constraint-driven timing closure is fragmented.**
  - Yosys has **no built-in timing-driven optimization engine** — no aggressive gate sizing, path balancing, or automated constraint-driven closure (does area/delay via ABC only).
  - OpenROAD has a Resizer (`rsz`, `repair_timing`) but it's **back-end only and requires orchestration** for full flows.
  - **My angle (software-first climb):** SDC linter → timing/closure analytics → closure-orchestration helper → (north star) contribute sizing / path-balancing to Yosys/OpenROAD.
  - **Why me:** gate sizing / path balancing / closure is literally my expertise.
2. **Advanced SystemVerilog support is incomplete** in Yosys (Surelog/UHDM front-end still maturing; verification-oriented constructs and complex interfaces).
3. **No native VHDL in Yosys** — relies on external GHDL front-end (integration/compatibility gaps).
4. **Mixed-signal integration is immature** (future big bet; needs analog domain knowledge I don't have yet).
5. **iEDA is less mature / smaller user base** — easier place to land meaningful contributions.



## Tool limitations table (from MDPI, physical design)

- OpenROAD: backend only; requires orchestration for full flows.
- OpenLane: limited analog support; heavy reliance on sub-tools.
- iEDA: less mature; smaller user base; evolving docs.
- SiliconCompiler: PDK/tool integrations still evolving.



## Decision

Both sources independently point to **digital timing/constraint tooling** as the best entry gap — mature enough to be respected, still imperfect, and squarely in my wheelhouse.
**Project #1 candidate: SDC linter/validator.**

## Day 1 progress

- MDPI survey: done. Logged the Yosys "no timing-driven optimization engine" limitation (gate sizing / path balancing / constraint-driven closure) as my lead gap.
- EuroCDP gap analysis: done. Confirms digital is the most mature domain, so my timing/SDC gap sits in the mature-but-still-imperfect zone — a defensible, reachable first target. Mixed-signal/RF/photonics have bigger gaps but need domain knowledge I don't have yet.
- Flow bring-up: done. WSL2 + Docker + ORFS installed. Ran `gcd` RTL→GDS on sky130hd; `6_final.gds` produced (953K). Flow path: `~/OpenROAD-flow-scripts/flow`.



## Day 2 progress — STA in the open flow + Python

- [x] OpenSTA standalone on gcd with hand-written SDC (`sta-experiments/gcd/gcd_hand.sdc`)
- [x] Saved `report_checks.rpt` + `opensta_full.rpt` (WNS line: `wns max -1.49`)
- [x] Notebook: `sta-experiments/notebooks/gcd_timing.ipynb` → WNS/TNS chart
- [ ] Push notebook + SDC to GitHub
- [ ] ibex flow kicked off (`make DESIGN_CONFIG=./designs/sky130hd/ibex/config.mk`)

- **gcd post-route timing (from ORFS signoff):**


| Metric                      | Value              |
| --------------------------- | ------------------ |
| Target clock (`core_clock`) | 1.1 ns             |
| WNS (setup)                 | -1.48 ns           |
| TNS (setup)                 | -66.81 ns          |
| Setup violations            | 64                 |
| Hold violations             | 0                  |
| Min achievable period       | 2.58 ns (~388 MHz) |


- **Takeaway:** gcd does not close at the default 1.1 ns target. Critical path is reg-to-reg through datapath subtract/compare logic (`a_reg.out[8]` → `a_reg.out[6]`). This is the baseline for future SDC linter / sta-dash work.
- **Next (Day 3+):** Run `./run_sta.sh` with Docker up to generate standalone OpenSTA reports; push parsed chart to GitHub; start ibex flow.



## Day 3 progress — STA fundamentals, re-anchored

- Full walkthrough (local only, not in git): `C:\Users\regur\Downloads\day3_explanation.md`
- Baseline frozen: `sta-experiments/gcd/reports/baseline/` (WNS −1.495 ns)
- SDC variants ready: `gcd_mcp.sdc` (multicycle), `gcd_false.sdc` (false path — **this run**)
- `run_sta.sh` now honors `SDC=` under Docker
- [x] Re-run: `SDC=gcd_false.sdc ./run_sta.sh` (WSL + Docker)
- [x] Parse + compare `summary.txt` vs baseline
- [x] Recorded measured ΔWNS below

### Day 3 results (measured — false path)

| | Baseline | After false path (`gcd_false.sdc`) |
|--|----------|-------------------------------------|
| WNS setup (ns) | −1.495 | **−1.490** |
| TNS setup (ns) | −67.457 | −67.425 |
| Hold still clean? | yes (0) | yes |
| New worst path | `a_reg.out[8]` → `a_reg.out[6]` | `b_reg.out[3]` → `a_reg.out[15]` |

**Why WNS changed:** Waived the single worst setup path (`a_reg.out[8]` → `a_reg.out[6]`); the next-worst path became WNS, so slack only improved by ~5 ps (−1.495 → −1.490). Capture edge stayed at 1.1 ns (not a multicycle). Lesson: with a cluster of similar datapath violators, one false path barely moves WNS.



## Day 4 progress — synthesis with Yosys (RTL → gates)

- [x] Source correction: the roadmap's `yosyshq.net/.../yosys_manual.pdf` is **dead (HTTP 500)** and chapter numbering no longer exists. Replacements + what "Ch. 4–6" actually were: `notes/day4-yosys-manual-ch4-6.md`
- [x] Standalone Yosys synthesis of `ibex_core` → sky130hd: `synth-experiments/ibex/`
- [x] Committed synth log (`logs/1_yosys_synth.log`) + per-stage `stat` dumps
- [x] Staged STA: synth / post-place / post-route on one SDC
- [x] Comparison note: `notes/day4-synth-vs-postplace.md`

### Day 4 results (ibex, `core_clock` = 10.0 ns)

| Stage | Setup WNS | Instances | Area (µm²) |
|--|--|--|--|
| Synth (my Yosys script) | −4.887 | 15,307 | 127,250 |
| Synth (ORFS) | −16.300 | 14,043 | 129,314 |
| Post-place | **+0.046** | 18,980 | 147,399 |
| Post-route | **+0.069** | 19,409 | 154,642 |

**Takeaway:** synth-stage WNS is not predictive in this flow — a 16.35 ns swing on a 10 ns clock, and the script with the *worse* synth WNS is the one that closes. ORFS deliberately hands floorplanning an unbuffered, minimum-size netlist (`abc_speed_gia_only` + `REMOVE_ABC_BUFFERS`) and lets the resizer do the drive fixing; the final design carries 1,405 timing-repair buffers that do not exist at synth time. Missing wire load accounts for only ~0.5 ns of the gap. What *does* hold from synth: sequential cell count (1,938 vs 1,939 final, essentially exact), area to within ~20%, and logic structure — my ripple-carry ALU (11 chained `maj3`) vs ORFS's Han-Carlson prefix adder shows up clearly at 48 vs 31 levels.

**Relevance to my lead gap:** this is the "Yosys has no timing-driven optimization engine" limitation from Day 1, measured. Yosys/ABC gets structure and area right and then stops; every bit of timing closure happens in the OpenROAD resizer, with no feedback path back into synthesis.



## Day 5 progress — the PDK: `.lib` (timing) + `.lef` (physical)

- Full walkthrough (local only, not in git): `D:\vlsi-work\day5_explanation.md`
- New experiment: `pdk-experiments/` — opens one standard cell (`sky130_fd_sc_hd__inv_2`) in **both** PDK views and proves STA delay is just a table lookup.
- [x] Extracted readable slices from the 12.8 MB liberty + 2.3 MB LEF (`inspect_pdk.sh` → `reports/*.txt`)
- [x] Reproduced the NLDM delay lookup by hand (bilinear) and confirmed against OpenSTA (`arc_delay.tcl` + `interp_check.py`)
- [x] Cross-checked that the two files describe the same cell (`.lib` `area` == `.lef` `SIZE`)

### Day 5 results (inv_2 `A→Y` arc, `tt_025C_1v80`)

| input slew (ns) | output load (pF) | arc | predicted (my bilinear) | OpenSTA | Δ |
|--|--|--|--|--|--|
| 0.05313 *(grid node)* | 0.01287 *(grid node)* | rise | 0.07601 | 0.07601 | ~3 fs |
| 0.20 *(off-grid)* | 0.05 *(off-grid)* | rise | 0.25816 | 0.25816 | ~3 fs |
| 0.20 | 0.05 | fall | 0.16076 | 0.16076 | ~4 fs |

**What `.lib` / `.lef` drive:** liberty = the timing/power *brain* (Yosys `dfflibmap` / `abc -liberty`, OpenSTA `read_liberty`, the resizer); LEF = the physical *body* (SITE rows + cell `SIZE` for placement, pin shapes + `OBS` for routing). Day 2 STA read only liberty + SPEF; Day 4 synth-stage STA additionally `read_lef` + `setRC` precisely because with no placement there are no parasitics, so the LEF's layer geometry is what lets `estimate_parasitics` invent any RC at all.

**Cross-check:** `area : 3.7536` (.lib) == `SIZE 1.380 × 2.720` (.lef) = 3.7536 µm²; `1.380 / 0.460 = 3`, so inv_2 is exactly 3 `unithd` sites wide.

**Relevance to my lead gap:** the delay a linter / timing-analytics tool reasons about is a *deterministic* 2-D interpolation of these characterized tables — verified here to < 0.01 ps. Gate sizing (my north star) is nothing but choosing among inv_1 / inv_2 / inv_4, whose only differences are these `.lib` tables (drive vs. input cap) and `.lef` width — and inv_1→inv_2 is 2× drive at **0×** extra area.



## Day 6 progress — close the loop: full-flow timing across stages

- Full walkthrough (local only, not in git): `D:\vlsi-work\day6_explanation.md`
- Committed analysis: `notes/day6-full-flow-timing.md`
- [x] Confirmed ibex reached final GDS (`6_final.gds`, 21 MB; signoff WNS/TNS = 0.00, 0 setup / 0 hold violations, f_max 100.74 MHz)
- [x] New driver `synth-experiments/ibex/scripts/run_day6.sh` + `sta_fullflow.tcl`: STA on **every** ORFS stage, one SDC per stage, into `reports/fullflow/metrics_fullflow.txt`
- [x] Filled in the two mid-stages Day 4 skipped (floorplan, CTS) for a complete stage-by-stage table
- [x] Presentable chart + notebook: `sta-experiments/notebooks/ibex_fullflow_timing.ipynb` → `reports/fullflow/ibex_stage_wns.png`

### Day 6 results (ibex, `core_clock` = 10.0 ns)

| Stage | Clock | Setup WNS | Setup TNS | Hold WNS | f_max |
|--|--|--:|--:|--:|--:|
| synth | ideal | −16.3004 | −22482.33 | +0.2265 | 38.02 MHz |
| floorplan | ideal | −16.2477 | −22387.78 | +0.2265 | 38.10 MHz |
| place | ideal | **+0.0462** | 0 | +0.2409 | 100.46 MHz |
| cts | propagated | +0.0011 | 0 | +0.4280 | 100.01 MHz |
| route | propagated | **+0.0686** | 0 | +0.4284 | 100.74 MHz |

**Takeaway:** timing closure here is a *back-end* event. Floorplan ≈ synth (buffers stripped in `floorplan.tcl`, std cells still unplaced), so the whole −16 ns survives; the OpenROAD resizer at **placement** does 100% of the closure; CTS then trades ~45 ps of setup for hold when the ideal clock becomes a propagated tree (source latency ≈ 1.23 ns, setup skew ≈ +0.14 ns; hold WNS +0.24 → +0.43); routing gives the setup back with real SPEF. Every value cross-checks against ORFS's own per-stage reports and against Day 4.

**Relevance to my lead gap:** this is Day 4's "Yosys has no timing-driven optimization engine" result localized to a single stage transition — synthesis and floorplan hand over an unbuffered netlist at −16 ns, and one back-end step (placement + resizer) closes it. A closure-analytics/orchestration tool only has a real job *after* placement; synth/floorplan slack is not a signal.



## Day 7 progress — publish + join the community

- Full walkthrough (local only, not in git): `D:\vlsi-work\day7_explanation.md`
- [x] **Blog post #1 (510 words)** — "Week 1: open-source STA vs. what I do at work":
  `docs/_posts/2026-08-15-week1-open-source-sta-vs-what-i-do-at-work.md`, served by GitHub
  Pages from `docs/` at <https://vamshireguri.github.io/vlsi-independence/>
- [x] All artifacts pushed; Days 4–7 merged to `master` (they had been sitting on feature
  branches since Day 4), blog linked from the README
- [x] Repo cleaned: README rewritten with the week's results and an artifact map, MIT
  `LICENSE` added, executed-notebook copies (`*_out.ipynb`) gitignored
- [x] Open-source silicon Slack: joined and introduced myself in `#introductions`
- [x] Week 2 (SDC linter) roadmap section read → `notes/week2-plan.md`

### Week 1 retrospective

**What shipped:** two designs RTL→GDS on sky130hd (`gcd`, `ibex` — `6_final.gds` for both),
standalone OpenSTA re-timing of both, a five-stage full-flow timing study with a chart, a
hand-verified NLDM delay model, three SDC variants with measured ΔWNS, two notebooks, a
report parser, five committed notes, and a live blog post. Seven commits, one public repo.

**The one result worth remembering:** closure in this flow is a *back-end* event. −16.30 ns
at synth → +0.046 ns after placement, with floorplan changing nothing. Every downstream
tooling decision I make should assume synth-stage slack carries no information here.

**What I got wrong / had to correct:**
- The roadmap's Yosys manual link is dead and its chapter numbering no longer exists
  (Day 4) — replaced with the current docs and recorded in `notes/day4-yosys-manual-ch4-6.md`.
- I expected a false path on the worst gcd violator to move WNS meaningfully; it moved it
  5 ps (Day 3). Cluster violations do not respond to point waivers — a good lesson to
  encode into the Week 2 linter's messaging.
- `ltp` must run before `dfflibmap`, or every sequential loop is reported as combinational
  (208,835 warnings, 15 MB log). Ordering matters more than I assumed in Yosys scripts.
- Days 4–6 were committed to feature branches and never merged; `master` sat three days
  stale. Fixed on Day 7 — from now on, merge to `master` the same day.

**Time:** ~22 h, per plan. Heaviest days were 4 and 6 (synthesis + full-flow STA).

**Next:** Week 2 — SDC linter v0.1. Plan in [`week2-plan.md`](week2-plan.md).