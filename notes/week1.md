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

- Full walkthrough: [`notes/day3_explanation.md`](day3_explanation.md) (also at `C:\Users\regur\Downloads\day3_explanation.md`)
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