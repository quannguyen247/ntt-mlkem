# 12-bit NTT/INTT FPGA Core for ML-KEM

This repository contains synthesizable Verilog RTL for the 256-coefficient
number-theoretic transform used in ML-KEM polynomial arithmetic ($n = 256$,
$q = 3329$). The core shares a butterfly datapath between forward NTT and
inverse NTT. It is implemented with distributed memory and logic-only
multiplication, without DSP or Block RAM primitives in the reported Artix-7
build.

## Key results

The standalone out-of-context run uses AMD Vivado 2025.2.1 on Artix-7
`xc7a100tfgg676-3` at 200 MHz (5 ns clock period) without debug
instrumentation:

- **Resource utilization:** 824 Slice LUTs (664 logic LUTs, 142 LUTRAM,
  18 SRL), 311 Flip-Flops, 0 DSP48E1, 0 BRAM18.
- **Timing:** Worst Negative Slack (WNS) = +0.152 ns, Worst Hold Slack
  (WHS) = +0.078 ns, with zero failing endpoints.
- **Transform latency:** 905 clock cycles for forward NTT (4.525 µs at
  200 MHz); 1,161 clock cycles for inverse NTT (5.805 µs at 200 MHz),
  excluding external coefficient loading and unloading.
- **Power:** Total on-chip power is estimated by Vivado at 0.148 W (0.064 W
  dynamic, 0.084 W device static) under default 50% switching activity.
  This is a vectorless estimation, not a board measurement.

Resource figures from an ILA-instrumented KV260 build include integration and
debug overhead. They belong to a different implementation context and are not
compared as if they were the same implementation.

### Comparison with Prior Works

Table 1 compares this standalone implementation against peer-reviewed FPGA accelerators targeting ML-KEM/Kyber on AMD Artix-7 devices:

| Design | Target FPGA | LUT | FF | DSP48 | BRAM18 | Fmax (MHz) | Cycles<br>(NTT/INTT) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Kieu-Do-Nguyen et&nbsp;al.&nbsp;[1] | XC7A100T-3 | 541 | 680 | 0 | 4 | 417 | 461/461 |
| Sonbul et&nbsp;al.&nbsp;[2] | XC7A100T-3 | 503 | 545 | 1 | 2 | 200* | 1,029/1,285 |
| **This work** | **XC7A100T-3** | **824** | **311** | **0** | **0** | **206** | **905/1,161** |

\* Sonbul et al. [2] did not report a separate Fmax; evaluated at a fixed 200 MHz constraint. Fmax for this work is calculated as $1000 / (5.0 - 0.152) \approx 206.27\text{ MHz}$ from post-route WNS.

The architecture uses no dedicated DSP or Block RAM macros. Storage and arithmetic map to logic slices and distributed memory (142 LUTRAM, 18 SRL). At 311 Flip-Flops, register usage is 54.3% lower than Kieu-Do-Nguyen et al. [1] and 42.9% lower than Sonbul et al. [2]. Transform latency is 905 cycles for NTT and 1,161 cycles for INTT. Each transform saves 124 cycles compared to Sonbul et al. [2].

## Branches and source layout

`main` and `dev` contain the standalone Artix-7 IP project. The `demo` branch
also contains a KV260 integration with a MAX30102 sensor, ARM software, and
an AXI4-Lite wrapper. The wrapper is not part of the Artix-7 IP result.

| Path | Purpose |
| --- | --- |
| [`Implementation/rtl/`](Implementation/rtl/) | NTT/INTT RTL and arithmetic modules |
| [`Implementation/testbench/`](Implementation/testbench/) | Self-checking SystemVerilog simulation |
| [`Implementation/constraint/`](Implementation/constraint/) | Artix-7 timing and switching constraints |
| [`Docs/SPEC.md`](Docs/SPEC.md) | NTT/INTT core IP technical specification |
| [`Demo/`](https://github.com/quannguyen247/ntt-mlkem/tree/demo/Demo) (`demo`) | KV260 source, scripts, and a separate demo guide |

Generated Vivado and demo outputs are not source files. Rebuild them after
changing RTL, constraints, or software.

## Test and build

Install Vivado 2025.2.1 and put its tools on `PATH`, or set `VIVADO_HOME` to
its installation directory. Run these commands from the repository root:

```sh
make test
```

On `main` and `dev`, `make impl` opens `Implementation/NTT.xpr`, runs the
out-of-context implementation through routing, and writes reports to
`Implementation/reports/`. The project can also be opened in the Vivado GUI.
On `demo`, `make artix` runs the corresponding Artix-7 flow; `make demo-doctor`
and `make demo` prepare and launch the separate KV260 demonstration. See
[`Demo/README.md`](https://github.com/quannguyen247/ntt-mlkem/blob/demo/Demo/README.md) on that branch for hardware setup and result checks.

Simulation checks both transform directions against software-generated
vectors. It does not by itself establish performance on a physical board.
The KV260 demonstration exercises sensor acquisition, signal screening, and
NTT/INTT integration; it does not implement an encrypted sensor channel or
the complete ML-KEM protocol.

## Team

IC4Duck:

- Nguyễn Đông Quân — 24521438
- Huỳnh Nhật Phát — 24521294
- Nguyễn Đức Phúc — 24521385
- Ngô Gia Bảo — 24520164

## References

1. N. Kieu-Do-Nguyen, V. B. Dang, and C. Pham-Quoc, "Compact and Low-Latency FPGA-Based Number Theoretic Transform Architecture for CRYSTALS Kyber Postquantum Cryptography Scheme," *Information*, vol. 15, no. 7, p. 400, 2024. DOI: [10.3390/info15070400](https://doi.org/10.3390/info15070400).
2. O. S. Sonbul, M. Rashid, M. I. Masud, M. Aman, and A. Y. Jaffar, "Deeply Pipelined NTT Accelerator with Ping-Pong Memory and LUT-Only Barrett Reduction for Post-Quantum Cryptography," *Electronics*, vol. 15, no. 3, p. 513, 2026. DOI: [10.3390/electronics15030513](https://doi.org/10.3390/electronics15030513).

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE)
for details.
