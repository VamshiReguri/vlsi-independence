# Day 4 — Yosys manual, "Ch. 4–6": source correction + reading notes

## The source in my roadmap is dead

The roadmap points at `https://yosyshq.net/yosys/files/yosys_manual.pdf` for "Ch. 4–6".
That URL returns **HTTP 500** — the single-PDF `yosys_manual` was retired when YosysHQ
restructured the documentation (the docs site itself carries the notice: *"This documentation
recently went through a major restructure… Documentation from before the restructure can still
be found by switching to version 0.36 or earlier."*).

Two consequences worth recording:

1. **Chapter numbers no longer exist.** The restructured manual is organised by task, not by
   numbered chapters, so "Ch. 4–6" cannot be looked up in the current docs at all.
2. **What Ch. 4–6 actually were** is not what the roadmap intended. In the last numbered
   version ([v0.33](https://yosyshq.readthedocs.io/projects/yosys/en/0.33/)) they are:
   - Ch. 4 — Implementation overview (data flow, RTLIL, command interface and synthesis scripts, source tree)
   - Ch. 5 — Internal cell library (RTL cells, gates)
   - Ch. 6 — Programming Yosys extensions

   Ch. 6 is about writing C++ passes and is irrelevant to running a synthesis flow. The
   roadmap's actual instruction — "read the synthesis-flow chapter" — maps to Ch. 9
   (Technology mapping) in the old numbering, or to the *Synthesis in detail* section in the
   current docs.

### What to read instead

| Purpose | Current page |
|---|---|
| End-to-end worked flow | [Synthesis starter](https://yosyshq.readthedocs.io/projects/yosys/en/latest/getting_started/example_synth.html) |
| What `synth` actually runs | [Synth commands](https://yosyshq.readthedocs.io/projects/yosys/en/latest/using_yosys/synthesis/synth.html) |
| Gate-level mapping | [Technology mapping](https://yosyshq.readthedocs.io/projects/yosys/en/latest/using_yosys/synthesis/techmap_synth.html) |
| ABC integration | [The ABC toolbox](https://yosyshq.readthedocs.io/projects/yosys/en/latest/using_yosys/synthesis/abc.html) |
| `dfflibmap` / liberty | [Mapping to cell libraries](https://yosyshq.readthedocs.io/projects/yosys/en/latest/using_yosys/synthesis/cell_libs.html) |
| Old Ch. 4 equivalent | [Internal flow](https://yosyshq.readthedocs.io/projects/yosys/en/latest/yosys_internals/flow/index.html) + [RTLIL](https://yosyshq.readthedocs.io/projects/yosys/en/latest/yosys_internals/formats/rtlil_rep.html) |
| Old Ch. 5 equivalent | [Internal cell library](https://yosyshq.readthedocs.io/projects/yosys/en/latest/cell_index.html) |

Archived numbered manual, if a chapter reference must be resolved:
`https://yosyshq.readthedocs.io/projects/yosys/en/0.33/`.

## Reading notes, checked against the ibex run

### RTL → gates is three abstraction drops, not one

The manual's framing is that `synth` is a macro over a script, and the useful mental model is
which representation you are in. I dumped `stat` at each boundary on ibex to make it concrete:

| Point in flow | Cells | Representation |
|---|---:|---|
| after `hierarchy -check` | — | AST-derived RTLIL, hierarchical |
| after `synth -run :fine` | 1,533 | **word-level** RTLIL |
| after `synth -run fine: -noabc` | 16,928 | **bit-level** generic gates |
| after `dfflibmap` + `abc -liberty` | 15,307 | **sky130 standard cells** |

The word-level stage still holds `$alu` (14), `$macc_v2`, `$pmux` (99), `$mem_v2`, `$eq` (313).
This is the layer where architectural decisions are still expressible — and exactly where ORFS
intervenes with `SWAP_ARITH_OPERATORS` to swap `$alu`/`$add` for parallel-prefix adders. Once
`techmap` has run you are looking at 16,928 `$_AND_`/`$_MUX_`/`$_XOR_` cells and the adder
architecture is already frozen. **If you want to influence structure, you do it before `fine:`.**

The bit-level count going *down* (16,928 → 15,307) through ABC is the covering step finding
better multi-input cells (`a21oi`, `o211ai`, `maj3`) than the 2-input generic gates.

### Sequential and combinational logic are mapped by different tools

Not obvious from the command list, but it explains the script order:

- `dfflibmap -liberty` maps flops. It is Yosys-native, matches `$_DFF_*` patterns against
  liberty `ff()` groups, and only accepts **one** liberty file.
- `abc -liberty` maps combinational logic. It hands off to ABC entirely.
- `dfflegalize` sits in front for cells the library lacks. sky130hd has no async set/reset
  latch, so ORFS legalizes `$_DLATCH_*` into what `cells_latch_hd.v` provides. I copied this;
  ibex has exactly one latch (the clock-gate `dlxtn_1`), and it survives to the final GDS.

Order matters: run `abc` before `dfflibmap` and ABC sees flops it cannot map.

### ABC's delay target is in picoseconds

`abc -D <n>` takes **picoseconds**. I passed `-D 10000` for the 10 ns clock. ORFS passes
`-D 10.0` (it forwards the SDC period in ns straight through), which asks for a 10 ps target —
effectively "as fast as possible". Worth knowing before reading anyone's ABC delay numbers.

`abc.constr` matters more than it looks. Without `set_driving_cell` / `set_load` ABC optimises
against an infinitely strong driver and zero load:

```
set_driving_cell sky130_fd_sc_hd__buf_1
set_load 5
```

### The internal cell library is the actual interface

Old Ch. 5 is a reference, but it is the thing you need when reading a `stat` dump. The mapping
that mattered on ibex: `$adff`/`$adffe`/`$sdffce` (word-level, with enables and async resets
still attached) → `$_DFFE_PN0P_` etc. (bit-level, the letter suffix encodes clock polarity,
reset polarity and reset value) → `sky130_fd_sc_hd__dfrtp_1` / `edfxtp_1`. The 1,619
`$_DFFE_PN0P_` cells are ibex's register file and pipeline registers with active-low async
reset; they become the 1,655 `dfrtp_1` in the final netlist.

### Frontend: `read_verilog` cannot read ibex

Ibex is real SystemVerilog — packages, structs, parameterised interfaces. Yosys ≥ 0.67 ships
**`read_slang`** built in (no plugin load), and the ORFS ibex config selects it via
`SYNTH_HDL_FRONTEND = slang`. Flags that were needed:

```tcl
read_slang -D SYNTHESIS --keep-hierarchy --compat=vcs --ignore-assertions \
  --top ibex_core -I$SRC/vendor/lowrisc_ip/prim/rtl/ {*}$rtl_files
setattr -unset init
```

`--compat=vcs` for VCS-isms, `--ignore-assertions` because the SVA is unsynthesisable, and
`setattr -unset init` works around yosys-slang emitting `init` attributes that later passes
reject. Unlike `read_verilog`, slang wants **all files in one invocation** — it elaborates as
a unit rather than deferring.

## Commands worth keeping

| Command | Use |
|---|---|
| `stat -liberty <lib>` | cell counts **with real areas** — plain `stat` has no area column |
| `ltp -noff` | longest topological path; **run before `dfflibmap`** (see the comparison note) |
| `check -assert -mapped` | fails on anything left unmapped; caught nothing here, which is the point |
| `hilomap -singleton` | ties constants to `conb_1` instead of leaving `1'b0`/`1'b1` |
| `splitnets` | breaks up compound assigns the DEF/LEF writers choke on |
| `tee -o <file> <cmd>` | log a single pass to its own file without redirecting the whole run |
| `write_json` | netlist as JSON — the practical hook for scripted analysis later |
