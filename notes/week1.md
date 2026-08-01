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
