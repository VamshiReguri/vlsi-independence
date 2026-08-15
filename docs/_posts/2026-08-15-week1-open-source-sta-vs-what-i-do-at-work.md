---
layout: post
title: "Week 1: open-source STA vs. what I do at work"
date: 2026-08-15
tags: [sta, opensta, openroad, yosys, sky130, sdc]
---

I spend my working hours inside commercial timing and library flows. Last week I spent
22 hours inside the fully open one — Yosys, OpenROAD/ORFS, OpenSTA, sky130hd — and taped
out two designs to GDS: `gcd` and `ibex`. Here is the honest comparison.

## The engine math is not the gap

I picked one standard cell, `sky130_fd_sc_hd__inv_2`, pulled its `A→Y` NLDM tables out of
the 12.8 MB liberty, and did the delay lookup by hand. Bilinear interpolation on
(input slew, output load) gave 0.25816 ns at an off-grid point; OpenSTA gave 0.25816 ns.
The two agreed to under 0.01 ps on every arc I tried.

That is the reassuring half of the week. Delay calculation, slack propagation, setup/hold
semantics, `.lib` vs `.lef` roles — it is the same discipline I already practise, just
without a license file. Nothing I know transfers at a discount.

## Where timing actually closes surprised me

I ran STA on **every** ORFS stage of ibex, same 10 ns `core_clock`, one SDC per stage:

| Stage | Setup WNS | f_max |
|---|---:|---:|
| synth | −16.30 ns | 38 MHz |
| floorplan | −16.25 ns | 38 MHz |
| place | **+0.046 ns** | 100.5 MHz |
| cts | +0.001 ns | 100.0 MHz |
| route | **+0.069 ns** | 100.7 MHz |

![ibex full-flow WNS]({{ site.baseurl }}/assets/img/ibex_stage_wns.png)

A 16.3 ns swing on a 10 ns clock, and **all of it happens in one step**. Synthesis and
floorplan hand the back end an unbuffered, minimum-size netlist on purpose (ORFS even
strips ABC's buffers in `floorplan.tcl`), and the placement resizer does 100% of the
closure. CTS then gives back 45 ps of setup to buy hold margin when the ideal clock becomes
a real tree; routing returns it with extracted parasitics.

Practical consequence: **synth-stage slack is not a signal in this flow.** Two synthesis
scripts, −4.89 ns and −16.30 ns at synth, converge on the same closed design. What synthesis
*does* predict is exact: 1,938 sequential cells at synth vs. 1,939 at signoff, area within
20%, and logic structure — my ripple-carry ALU showed up as 48 logic levels against ORFS's
31 for a Han-Carlson prefix adder.

## What is genuinely missing

Not the analysis core — the **signoff surface** around it. No CCS/ECSM, no LVF, no
crosstalk/SI, no path-based analysis, single-mode MCMM. And everything comes out as text:
`gcd` misses its aggressive 1.1 ns default target at −1.49 ns WNS, −66.8 ns TNS across 64
endpoints, and there is no tooling to tell me those 64 violations are one cluster of sibling
paths. I proved they were: waiving the single worst path with `set_false_path` improved WNS
by **5 picoseconds**, because the next path was right behind it.

That gap — constraint validation and timing analytics on top of a solid open engine — is
where I am spending Week 2, starting with an SDC linter.

Everything is reproducible: [github.com/VamshiReguri/vlsi-independence](https://github.com/VamshiReguri/vlsi-independence).

*Personal project, my own time and hardware. Public tools, public PDK, public designs only —
no employer data, tools, or methodology involved.*
