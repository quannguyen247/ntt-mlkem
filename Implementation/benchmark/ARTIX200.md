# NTT/INTT Artix-7, 200 MHz

## Measured result (2026-09-09)

| Metric | Baseline | Selected implementation |
|---|---:|---:|
| Post-route WNS / TNS (ns) | -1.394 / -19.458 | +0.226 / 0 |
| Post-route WHS / THS (ns) | +0.093 / 0 | +0.113 / 0 |
| LUT / FF | 868 / 289 | 620 / 255 |
| DSP48E1 / BRAM18 | 0 / 0 | 1 / 1 |
| NTT / INTT compute cycles | 904 / 1160 | 905 / 1161 |
| SAIF dynamic power estimate | 41 mW | 35 mW |
| Whole-device power estimate | 125 mW | 119 mW |
| SAIF net annotation | 89% | 87% |

See [raw reports and trial results](results/2026-09-09/README.md).
LUTs decrease by 28.6%, FFs by 11.8%; dynamic power is about 15% lower in
this estimated workload. One DSP and one BRAM18 replace part of the LUT logic.
This is not a claim of lower total silicon area or a measured power result.
The baseline fails timing at 200 MHz; its power value is a common-frequency
model comparison, not evidence of a working baseline at that frequency.

## Scope and reproduction

Target: `xc7a100tfgg676-3`, top `ntt_core_top`, n=256, q=3329,
Vivado 2025.2.1 on Linux. This is a **standalone OOC core benchmark**.
Clock period is 5 ns in synthesis and implementation. No timing exceptions
hide internal paths. External I/O paths are unconstrained because this benchmark
does not specify a surrounding circuit. `HD.CLK_SRC=BUFGCTRL_X0Y0` is an
assumed integration clock-buffer site, not an oscillator package-pin assignment.
An actual top-level design still needs its own timing closure.

Run commands from the repository root after adding Vivado's `bin` directory to
PATH (on the development machine: `/home/quan/tools/Xilinx/2025.2.1/Vivado/bin`).

```sh
python3 Implementation/benchmark/regress.py --random 128 --units
vivado -mode batch -source Implementation/benchmark/run_ooc.tcl \
  -tclargs build/ppa/reproduce AreaOptimized_high
```

The first command requires Python 3 and Icarus Verilog (`iverilog`, `vvp`).
Any numerical mismatch, timeout or missing PASS marker fails the regression.
The second command saves the routed checkpoint and reports under
`build/ppa/reproduce/`. Check `timing.rpt`: setup/hold/pulse-width failing
endpoints must be zero. `BENCHMARK_FINISHED` means the run finished, not that
timing necessarily passed. Baseline sources are Git commit `668f0e2`
(formerly `5c49e16`; identical source tree after commit-message rewriting).

For the Vivado GUI:

```sh
vivado -mode batch -source Implementation/benchmark/create_project.tcl \
  -tclargs build/ppa/my_gui_project
```

1. Open `build/ppa/my_gui_project/ntt_artix200.xpr` in Vivado.
2. Confirm part `xc7a100tfgg676-3`, top `ntt_core_top`, period 5 ns.
3. Run Synthesis, then Run Implementation.
4. Open Implemented Design; inspect Report Timing Summary, Utilization and DRC.
5. For the already measured result, open its `routed.dcp` instead of rebuilding.

For GUI behavioral simulation, first run
`python3 Implementation/benchmark/regress.py --out build/ppa/vectors` (default
74 cases), then click Run Simulation / Run Behavioral Simulation. The generated
project already selects `tb_ntt_core_top` and passes the vector directory.
`Implementation/testbench/tb_ntt_core_top.sv` is the only maintained testbench;
the duplicate `_iv.sv` was removed. The same file supports exhaustive multiplier
testing through `TEST_MULTIPLIER`, invoked by `regress.py --units`.
The legacy `ntt_gen.py` remains for demo scripts using the older `tv_all.mem`
format; that format is not the new testbench input.

The project script refuses to overwrite an existing project. Choose a new
output directory when creating another one. It uses source references, not RTL
copies. Settings: synthesis `AreaOptimized_high`, placement `Explore`, pre-route
`phys_opt_design` enabled, routing `Explore`; post-route physical optimization
disabled. The old local `Implementation/NTT.xpr` is not overwritten.
The original failing run ended in a Vivado signal-11 crash during post-route
physical optimization; a tool crash and a negative timing slack are separate issues.
The new flow addresses the datapath and does not depend on that crashing step.

## RTL changes

Only four design files change:

- `ntt_mod_mul_12b.v`: replace the explicit 12-partial-product adder tree with
  `a_reg * b_reg`, requested as one DSP using `use_dsp="yes"`; add registered
  operands. Montgomery reduction and canonical output remain unchanged.
- `ntt_butterfly.v`: align operand/valid/scale delay with the extra multiplier
  cycle. Hold the first data registers when `valid_i=0` to isolate idle/input-load
  activity. The clock itself is never gated in fabric.
- `ntt_core_top.v`: extend the drain by one cycle so `busy` owns RAM until the
  final writeback completes and `done` reports the complete result.
- `ntt_agu.v`: `use_dsp="no"` keeps small address arithmetic in LUTs and
  prevents `AreaOptimized_high` from adding an unnecessary second DSP.

The multiplier has five registered stages; butterfly has seven, including its
input and output registers. FIFO depth remains 16. Controller, address equations,
memory banking, twiddle constants and AXI register interface are unchanged.
Observed start-to-done latency is 905 cycles for NTT and 1161 for INTT,
or 4.525 and 5.805 us at 200 MHz; these exclude external load/readback.
The previous core needed 904/1160 cycles.

INTT retains the existing **invntt_tomont** convention:
`INTT(NTT(a)) = a * 65536 mod 3329`. To recover canonical input coefficients,
multiply the result by 169 mod 3329. Do not claim the raw output equals `a`,
or change the scale constant 1441 without changing the arithmetic contract.

## Verification and power

`regress.py` derives twiddles independently as powers of 17 with 7-bit
bit-reversed exponents. It does not parse the RTL ROM. It checks independent
NTT and INTT outputs, alternating modes without resets, on edge cases and
seeded random inputs. `--units` also checks all 3329² = 11,082,241 canonical
multiplier operand pairs against `a*b*169 mod 3329` and its five-cycle latency.

For routed functional simulation and SAIF:

```sh
python3 Implementation/benchmark/regress.py --out build/ppa/vectors
python3 Implementation/benchmark/simulate_netlist.py build/ppa/reproduce \
  --vectors build/ppa/vectors \
  --vivado-bin /home/quan/tools/Xilinx/2025.2.1/Vivado/bin
vivado -mode batch -source Implementation/benchmark/report_saif.tcl \
  -tclargs build/ppa/reproduce
```

Adjust `--vivado-bin` for another installation. Netlist simulation checks
74 transformations / 18,944 coefficients, using precisely the same vectors for
baseline and optimized designs. Simulation logs and `activity.saif` are in
the selected run's `simulation/` directory. `power_saif.rpt` shows annotation
coverage, confidence and model/environment settings.

Power is a **Vivado estimate**, not a current measurement on an Artix board.
SAIF comes from routed *functional* simulation: it includes workload switching,
but not SDF timing glitches. Activity covers input loading, transforms, output
reads and short idle gaps at 200 MHz, not only the active butterfly interval.
Unmatched nets receive probabilistic activity. Keep this distinction even when
Vivado calls confidence “High”. Do not use a blanket 50% internal toggle setting
to claim measured low power. Dynamic and whole-device static power must be
reported separately. Any energy derived from this average must be labelled a
workload estimate, not an isolated per-transform measurement.

Residual OOC warnings must remain visible: `RTSTAT-10` for the exported `done`
net with no physical load; `CFGBVS-1` without a board configuration voltage;
`DPIP-1` for inferred DSP input pipeline recommendations. Check the committed DRC report for
the selected run. None is a license to omit internal setup/hold checks.

## Research and comparison

| Design | FPGA | LUT | FF | DSP | BRAM18 | MHz | Reported cycles NTT/INTT |
|---|---|---:|---:|---:|---:|---:|---|
| Paper 1, hybrid gamma, two butterflies [1] | XC7A100T-FGG676-3 | 541 | 680 | 0 | 4 | 417 | 461/461 |
| Paper 2 [2] | XC7A100T-CSG324-3 | 503 | 545 | 1 | 2 | 200 | 1029/1285 |
| This core, selected OOC run | XC7A100T-FGG676-3 | 620 | 255 | 1 | 1 | 200 | 905/1161 |

Paper 1 reports the hybrid core separately from its forward-only alpha/beta
variants. Its ROM-based arithmetic and two butterflies trade BRAM for logic
and cycles. Adopting that entire architecture would change this project's
datapath/memory design substantially. The useful principle here is pipeline
balancing; the retained implementation does not claim to reproduce its method.
Paper 1 uses Vivado 2023.2, `AreaOptimized_high` and P&R `Explore`. [1]

Paper 2 uses one DSP for the full product, with LUT-based Barrett reduction
and ping-pong BRAM. “LUT-only” applies to reduction, not the whole multiplier.
We adopt the single-DSP/pipeline principle, while retaining existing Montgomery
arithmetic and LUTRAM banking to keep the RTL change small. [2]

Paper 2's corrected local PDF, pp. 14–15, reports “Vivado IDE (version 14.1)”;
that version string is reproduced as written, not independently resolved.
Its Eq. (8) uses reciprocal transform time but labels it Kbps. We use
transforms/s or explicitly multiply by a stated number of bits to get bit/s.
Its text separates 256-cycle input loading and output streaming from compute;
we therefore identify the timing boundary explicitly instead of blindly
comparing application end-to-end throughput. INTT normalization conventions
also need alignment when comparing complete operations. [2]

Do not equate one LUT with one DSP/BRAM or use LUT count alone to claim lowest
silicon area. Different tool versions/packages and unavailable original RTL
prevent a controlled reproduction of both papers. Their cited result tables
do not supply directly comparable measured power for this workload. A global
“best PPA” or lower-power-than-paper claim is not established.

### Sources

1. *Compact and Low-Latency FPGA-Based Number Theoretic Transform Architecture
   for CRYSTALS Kyber Postquantum Cryptography Scheme*, Information 2024, 15,
   400, Section 4.2 / Table 1. DOI: https://doi.org/10.3390/info15070400 .
   Published-paper text: https://inspirehep.net/files/ac7814a0ef52654f7d1dbafd6bfd0449 .
   Author preprint for architectural description:
   https://www.preprints.org/manuscript/202405.1452 .
2. Sonbul et al., *Deeply Pipelined NTT Accelerator with Ping-Pong Memory and
   LUT-Only Barrett Reduction for Post-Quantum Cryptography*, Electronics 2026,
   15, 513, Section 3.5 and Sections 4.1.1–4.1.3 / Tables 1–2.
   https://doi.org/10.3390/electronics15030513 . Local supplied source:
   `/home/quan/Desktop/electronics-15-00513-v2.pdf`, corrected 23 July 2026.
3. AMD UG901, multiplier inference and USE_DSP:
   https://docs.amd.com/r/2024.1-English/ug901-vivado-synthesis/USE_DSP .
4. AMD UG907, Power Analysis and Optimization:
   https://docs.amd.com/api/khub/documents/34c_HGWWD2BlUy_tqfiKQg/content .

## AI-agent handoff

Keep work on `dev_quan`; publication/history rewriting requires explicit instruction.
The 2026-09-09 publication was explicitly authorized. Reports below `results/`
are dated evidence, not automatically current after RTL changes. Rerun regression,
implementation and SAIF after changing the pipeline. Keep invalid-signal sensor
gating and software BPM/SpO2 estimates separate from arithmetic correctness.
This change has not been loaded onto the KV260: its earlier bitstream and live
sensor test do not validate the newly compiled Artix implementation.
Do not change `form(donotedit)/` or commit generated DCPs/projects/SAIF files.
