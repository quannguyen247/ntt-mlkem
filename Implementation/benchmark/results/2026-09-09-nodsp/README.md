# Zero-DSP Default run, 2026-09-09

This snapshot supersedes the single-DSP selection for the current RTL.
Historical reports in `../2026-09-09/` remain unchanged.

Vivado 2025.2.1 build 6403652, `xc7a100tfgg676-3`, 5 ns, OOC,
Default synthesis and Default implementation. `max_dsp=0` and
`use_dsp="no"`. Shared `Implementation/constraint/ntt.xdc`, including
virtual BUFG source and original 50% activity assumptions. No SAIF loaded
for the power report archived here.

- Batch `build/ppa/nodsp_final`: WNS +0.152 ns, WHS +0.078 ns,
  TNS/THS 0, all setup/hold/pulse-width failing endpoints 0.
- Original GUI project `Implementation/NTT.xpr`, rebuilt after repair:
  identical timing, 824 LUT / 311 FF / 0 DSP / 0 BRAM18.
- Of 824 LUTs, 160 are memory: 142 distributed RAM, 18 SRL.
- Power 148 mW total, 64 mW dynamic, 84 mW static; confidence High,
  post-route vectorless estimate with explicit 50% activity. Not measured
  hardware power, not evidence of lower energy than the papers or old SAIF run.
- Two DRC warnings: CFGBVS-1 (no board voltage), RTSTAT-10 (`done` OOC port).
  No DRC errors. No false-path/multicycle exceptions hide critical paths.

Tests:

```text
RTL: REGRESSION_PASS cases=266 coefficients=68096
Multiplier: MUL_EXHAUSTIVE_PASS pairs=11082241 latency=5
Routed functional: REGRESSION_PASS cases=74 coefficients=18944
Repaired GUI/XSim: REGRESSION_PASS cases=74 coefficients=18944
NTT cycles=905, INTT cycles=1161
```

RTL log: `build/ppa/nodsp_regression/regression.log`, multiplier `mul.log`.
Routed functional log: `build/ppa/nodsp_unified/simulation/simulate.log`.
That earlier routing omitted pre-route phys_opt; the final Default recipe
includes it to match Vivado2025.2.1 GUI Default. It produced identical
timing/utilization. The two routed.v files differ only in generated date/path
header comments; the simulated logic is identical. GUI reports: `build/ppa/nodsp_gui/`.
Simulation is functional, not SDF timing simulation or a physical board test.

Project repair removed the old NTT.bd/Zynq wrapper references and old board
metadata; no original BD file was removed. XPR backup before repair:
`build/ppa/project-backup-20260909-150137/NTT.xpr`. One failed Vivado
recreation attempt removed generated runs and the XPR; the XPR was restored
from this backup and the runs were rebuilt successfully. The maintained
repair script does not use that recreation approach.

Board warning qualification: `Project 1-5713` with an empty board name also
reproduced on a newly created part-only project with no IP. This Vivado
installation still emits the message. The project-specific message rule
reclassifies **only** `Board part ''` as INFO. This is a documented workaround,
not a repair of Vivado itself. Named missing-board warnings are unchanged.
Reopen verified PART=xc7a100tfgg676-3, BOARD_PART empty, IP_COUNT=0,
single common XDC, both strategies Default. BD41-1661 and Synth8-3323
are absent from the rebuilt flow.

Reports here copy final generated reports with trailing whitespace removed.
Critical source SHA-256:

```text
ntt_agu.v          a3b046a6b4b4ec607d76b62e9d0afc3122eb50db45a7ebedc22d690b0d127b88
ntt_butterfly.v    2ee40aba7a4566295fc9b4f2d829c10ef0996a46cd8c2f15f08f8abac706c9e0
ntt_controller.v   e93de3d130f4507fcea7540fb53d79894dffd38f317c3d3e4c201484bda413e4
ntt_core_top.v     87ecc09ae824aa4a3b6c0f779f0e14db4aad16b77428b4d1a280a520c66107a2
ntt_mod_mul_12b.v  0b6aa6e6e75bf11d71788f8e139b38f80709c09acb775fc338c1aeceae1f8b4c
ntt_ram_dual.v     c66b448e34d72f7e189ebd1c1383d4515443b83cf463d895135ac39ab01ecbe6
ntt_twiddle_rom.v  91926fa282eb2c1468fee5e22a56b00e9e16bc805d3c5f440eee7ed845b7dcb8
ntt.xdc           4b3146623301452899eebf1447bf4755d94c92e48ea4636b1dc945af971f1a15
run_ooc.tcl       1650fad8825c4ba80aa4326d3411f06529866bc0addc87962e80bf9ab842184e
```
