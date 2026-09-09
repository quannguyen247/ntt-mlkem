# Artix-7 optimization evidence, 2026-09-09

Selected device: `xc7a100tfgg676-3`. Tool: Vivado 2025.2.1 build 6403652,
Linux. Core-only OOC synthesis and routed implementation at 5 ns.
Source tree for baseline: `ca33f568565ba23b598fc73aaf4e577d96d370ad`
(commit `668f0e2`, previously `5c49e16`).

`baseline/` and `optimized/` contain Vivado text reports with trailing spaces
and blank EOF lines removed; numerical content is unchanged.
No DRC warning was disabled to obtain these results. The selected DRC report
has zero errors and four warnings: CFGBVS-1, two DPIP-1 and RTSTAT-10.
The reported 0.5 Block RAM Tile equals one RAMB18E1, not zero BRAMs.

## Controlled trials

All runs use the same part, 5 ns clock, virtual BUFG site, Explore placement,
pre-route physical optimization and Explore routing. Synthesis directive varies
only where stated. The early screenshot's 50% blanket switching assumptions
are not used in these power reports.

| Trial | Synthesis | LUT | FF | DSP | BRAM18 | WNS ns | Decision |
|---|---|---:|---:|---:|---:|---:|---|
| Original explicit partial-product tree | Default | 868 | 289 | 0 | 0 | -1.394 | Baseline fails |
| DSP product, original latency | Default | 653 | 251 | 1 | 1 | -0.618 | Still fails |
| Move INTT subtraction before input register | Default | 685 | 255 | 1 | 1 | -0.933 | RAM path becomes too long |
| DSP operands registered, idle isolation | Default | 636 | 256 | 1 | 1 | +0.128 | Pass; 34 mW SAIF dynamic |
| Same RTL | AreaOptimized_high | 604 | 264 | 2 | 1 | +0.234 | Extra AGU DSP inferred |
| Bit-concatenation AGU trial | AreaOptimized_high | 615 | 254 | 1 | 1 | +0.176 | Pass, but replaces AGU equations with seven cases |
| Original AGU equations, force LUT mapping | AreaOptimized_high | 620 | 255 | 1 | 1 | +0.226 | Selected: small RTL change, one DSP |

Intermediate trials are recorded to explain selection, not offered as separate
supported implementations. The selected candidate trades 5 LUTs and 1 FF
relative to the bit-concatenation trial for simpler source and more setup margin.
Relative to the Default-pipeline trial, it uses fewer LUTs but its estimated
dynamic power is 1 mW higher. This is a balanced selection, not proof of a global
PPA optimum. Original AGU functionality is retained.

Baseline and selected SAIF use identical 74 input transformations (37 forward,
37 independent inverse) and identical load/readback/idle scheduling. The selected
core takes one extra clock per transform. Baseline dynamic/total estimates:
41/125 mW; selected: 35/119 mW. Static is 84 mW for both. Annotation is 89%
(1510/1695 nets) versus 87% (1179/1353 nets). See report environment and
assumptions; neither value is board-measured power. The baseline does not meet
200 MHz timing. Functional SAIF does not model SDF glitches.

## Validation

```text
RTL: REGRESSION_PASS cases=266 coefficients=68096
Multiplier: MUL_EXHAUSTIVE_PASS pairs=11082241 latency=5
Routed functional netlist: REGRESSION_PASS cases=74 coefficients=18944
Generated Vivado GUI project / XSim: REGRESSION_PASS cases=74 coefficients=18944
Missing input/expected vectors: rejected with fatal error, exit=1
NTT cycles=905; INTT cycles=1161
Setup failing endpoints=0; hold failing endpoints=0; pulse-width failures=0
```

RTL tests include zero, all q-1, impulse, ramp, alternating 0/q-1 and 128 seeded
random polynomials. Forward and inverse are checked independently against
Python integer arithmetic deriving twiddles from 17. Mode changes do not reset
the DUT between transactions. Netlist/GUI workloads use the same five edges
and 32 seeded random polynomials. No physical Artix/KV260 execution was performed
for this revision. Existing KV260 artifacts must be rebuilt to incorporate it.

Exact optimized RTL SHA-256:

```text
a3b046a6b4b4ec607d76b62e9d0afc3122eb50db45a7ebedc22d690b0d127b88  ntt_agu.v
2ee40aba7a4566295fc9b4f2d829c10ef0996a46cd8c2f15f08f8abac706c9e0  ntt_butterfly.v
87ecc09ae824aa4a3b6c0f779f0e14db4aad16b77428b4d1a280a520c66107a2  ntt_core_top.v
15cfa41393a1c9ec7ac2ec4477732db28c8deb0da369612b1b5e16dce7cb647c  ntt_mod_mul_12b.v
```

## History rewrite

At explicit request, commit `b67c7e5` (Rename poly_ram_dual.v to ntt_ram_dual.v)
and its ancestors were retained. Three following messages were rewritten with
each original tree, author and dates preserved:

| Previous commit | Replacement | Message |
|---|---|---|
| c2fe04f | 3232d2f | Remove generated Vitis workspace |
| 402b979 | 6b2590d | Add KV260 sensor NTT demo |
| 5c49e16 | 668f0e2 | Update sensor guide and clean workspace |

The optimization is a new commit after those. Publication is restricted to
`dev_quan`, using an explicit lease against remote head
`5c49e163299c250240b64760be8098f1584eff9e`. No merge or force update of `main`.
