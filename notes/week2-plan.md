# Week 2 plan — SDC linter (Phase 1, "software ship")

Read from the roadmap's *Phase 1 / Week 2* table on Day 7 and turned into a concrete plan
against what Week 1 actually produced. Goal for the week: **`sdc_lint` v0.1 shipped** — a
CLI that reads an SDC and reports real constraint bugs, with tests and a worked sky130
example.

## Why this is the right next project

Week 1's measured result is that the open flow's *analysis engine* is sound (NLDM lookup
matched OpenSTA to < 0.01 ps) while everything *around* it is thin. The roadmap's gap list
says the same thing about constraints: open source has **sdcx** (a Rust SDC parser and
formatter) and nascent CDC-constraint emission in rtl-buddy, but **nothing does semantic
validation of an SDC against the design it constrains**. That is the piece my day-job
background is strongest on, and it needs no ML, no C++ upstream work, and no new tool
access to be useful.

## Day-by-day (from the roadmap, ~22 h)

| Day | Hrs | Learn | Build |
|---|---|---|---|
| Mon | 2.5 | SDC spec, [sdcx docs](https://docs.rs/sdcx) | Install sdcx; run `sdcx check` on the gcd SDCs — establishes the baseline of what an existing open tool already catches |
| Tue | 3 | CDC / clock domains (Bhasker & Chadha Ch. 8–9), [rtl-buddy](https://github.com/rtl-buddy/rtl_buddy) | Map ibex's clock domains from its SDC |
| Wed | 3 | Python `dataclasses` + `re`; sdcx command list | `sdc_lint.py`: parse `create_clock`, `set_input_delay`, `set_output_delay` |
| Thu | 2.5 | [liberty-parser](https://github.com/chipsalliance/liberty-parser), sky130hd liberty | Extract pin capacitances; cross-check SDC clock/port names against the library and netlist |
| Fri | 2.5 | Lint-rule design (my own signoff checklist) | Rules: duplicate clocks, unconstrained I/O, generated clock with no master |
| Sat | 6 | — | Ship v0.1: CLI with `--check`, 5 unit tests, example sky130 workflow |
| Sun | 3 | — | Publish: GitHub release `v0.1.0` + LinkedIn post with a screenshot |

## What Week 1 already hands to Week 2

Nothing here needs to be re-earned — these are inputs, not homework:

- **Four real SDCs to lint**: `sta-experiments/gcd/gcd_hand.sdc` (hand-written, so it has
  the kind of mistakes a linter should find), `gcd_false.sdc`, `gcd_mcp.sdc`, and ORFS's
  ibex `constraint.sdc`.
- **Five *staged* SDCs** from the ibex run (`1_synth` … `6_final`), which differ only in
  `set_propagated_clock`. A linter that understands stage context is a differentiator, and
  Day 6 already proved reading the wrong one produces silently wrong timing.
- **A liberty I can already navigate** — Day 5 extracted the `inv_2` cell, pin caps and
  NLDM tables out of the 12.8 MB sky130hd `.lib`, so the Thursday cross-check is an
  extension of working code, not a fresh start.
- **A ground-truth loop**: OpenSTA runs on both designs in a container, so any lint rule
  can be validated by "change the SDC → re-run STA → did the slack move the way the rule
  predicts?" That is exactly how the Day 3 false-path result (5 ps, not the expected large
  jump) was measured.
- **A parser to reuse**: `sta-experiments/parse_timing_report.py`.

## Decisions taken up front

- **Where the code lives:** develop as `sdc-lint/` inside this repo for Weeks 2–4, then
  split into the standalone `timing-toolkit` repo at Week 5 when the linter, the dashboard
  and the agent are integrated. One public artifact per week beats an empty second repo.
- **Parse, don't wrap:** write the parser in Python rather than shelling out to sdcx. sdcx
  is the *syntax* baseline to measure against; the value I add is semantic checks that need
  the netlist and the liberty alongside the SDC.
- **Every rule needs a demonstrable failure.** A rule ships only with an SDC that triggers
  it and a note on what goes wrong downstream if it is ignored. No rules copied from a
  checklist without a reproducible example.
- **Boundary:** public tools, public PDKs, public designs, my own hardware and time. No
  employer data, tooling, or methodology — same rule as Week 1.

## Candidate rules for v0.1

Ordered by "how often this actually causes a respin-class bug":

1. Clock defined on a port that does not exist in the netlist (typo → silently untimed logic).
2. Generated clock whose `-source` master clock is never defined.
3. Duplicate / overlapping `create_clock` on the same object.
4. Input or output ports with no `set_input_delay` / `set_output_delay` — the classic
   unconstrained-I/O hole.
5. `set_false_path` / `set_multicycle_path` whose from/to objects match nothing (a waiver
   that silently waives nothing — Day 3 showed how small a *working* exception can look, so
   a broken one is easy to miss).
6. Driving cell / load / transition not set on primary inputs, making I/O timing fictional.

## Success criteria (Sunday)

- `sdc_lint --check <file.sdc>` runs on all four Week 1 SDCs and finds at least one real
  issue in the hand-written gcd SDC.
- 5 unit tests, each pinned to a minimal SDC fixture.
- README section with a copy-pasteable sky130 example.
- Release tagged `v0.1.0`, blog/LinkedIn post published.
