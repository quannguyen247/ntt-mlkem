# NTT/INTT Hardware IP Technical Specification

## Overview

This specification defines the architecture, hardware interfaces, and functional behavior of the standalone `ntt_core_top` RTL core. The core executes forward and inverse Number-Theoretic Transforms (NTT/INTT) for polynomial arithmetic in the ML-KEM post-quantum key encapsulation standard (NIST FIPS 203). It operates on polynomials of degree $n = 256$ with coefficients defined modulo $q = 3329$. All coefficients are represented as 12-bit unsigned integers in the range $[0, 3328]$.

The documentation structure follows the conventions of the [OpenTitan IP specification framework](https://opentitan.org/book/doc/contributing/doc/example_ip_block.html). This represents a documentation style convention and does not imply compliance with OpenTitan bus protocols (such as TL-UL) or physical security countermeasures. The core exposes a direct local coefficient-RAM interface rather than an integrated bus. An AXI4-Lite wrapper is provided as an optional integration adapter on the `demo` branch.

### Core Features

- **Bidirectional Transform Engine:** Executes forward Cooley-Tukey NTT and inverse Gentleman-Sande INTT using a single, shared butterfly datapath.
- **DSP-Free Modular Arithmetic:** Features a 5-cycle pipelined Montgomery multiplier ($R = 2^{16}$) realized entirely in slice logic without DSP blocks.
- **Dual-Bank Distributed Storage:** Implements a $2 \times 128 \times 12$-bit coefficient memory utilizing distributed RAM and SRL primitives. Memory banks are accessed via parity decoding to avoid read/write collisions.
- **Fixed-Latency Pipeline:** Features a synchronous address FIFO tracking write-back addresses across the 7-cycle datapath latency.
- **Deterministic Latency:** Completes forward NTT in exactly 905 clock cycles and inverse NTT in 1,161 clock cycles (including inverse scaling).

### Scope and Limitations

The core functions solely as a polynomial transform unit. It does not perform base-case polynomial multiplication (`basemul`), secret-key generation, encapsulation, decapsulation, or encryption of sensor data. The design contains no algorithmic masking or side-channel fault countermeasures.

## Mathematical Foundation and Conventions

### Number-Theoretic Transform

The transform processes polynomials in the ring $R_q = \mathbb{Z}_q[X]/(X^{256} + 1)$ with modulus $q = 3329$. Because $X^{256} + 1$ factors into 128 quadratic polynomials over $\mathbb{Z}_q$, the complete NTT consists of 7 stages. 

The forward transform maps coefficient vectors into bit-reversed Montgomery domain values using Cooley-Tukey decimation-in-time:

$$A_j = \sum_{i=0}^{n-1} a_i \cdot \psi^{(2\mathrm{bitrev}_7(j)+1)i} \pmod q$$

The inverse transform reconstructs polynomial coefficients using Gentleman-Sande decimation-in-frequency:

$$a_i = n^{-1} \sum_{j=0}^{n-1} A_j \cdot \psi^{-(2\mathrm{bitrev}_7(j)+1)i} \pmod q$$

Here $\psi = 17$ represents the primitive 256th root of unity modulo 3329 ($\psi^{256} \equiv -1 \pmod q$). Twiddle factors are stored in bit-reversed order within a 128-entry lookup table.

### Modular Arithmetic and Montgomery Reduction

Modular addition and subtraction yield fully reduced canonical residues in $[0, 3328]$. Multiplication relies on the Montgomery algorithm with radix $R = 2^{16}$:

$$\mathrm{MontMul}(a, b) = a \cdot b \cdot R^{-1} \bmod q$$

The arithmetic datapath computes:

```text
t = a * b
m = (t * 3327) mod 2^16
u = (t + m * 3329) / 2^16
result = (u < 3329) ? u : (u - 3329)
```

Constant factor multiplications are implemented using hardwired shift-and-add logic in [`ntt_mod_mul_12b.v`](../Implementation/rtl/modules/ntt_mod_mul_12b.v). 

### Normalization and Inverse Scaling

In this implementation, the inverse transform incorporates an inverse scaling stage that scales all 256 output coefficients:

$$\mathrm{scaled} = \mathrm{MontMul}(\mathrm{coeff}, 1441)$$

Due to internal Montgomery domain conventions, round-trip processing satisfies:

$$\mathrm{INTT}(\mathrm{NTT}(a)) = a \cdot R \pmod q = a \cdot 65536 \pmod{3329}$$

To recover the original canonical polynomial $a$, an external caller must scale each coefficient by $R^{-1} = 169 \pmod{3329}$:

$$a = \mathrm{MontMul}(\mathrm{INTT}(\mathrm{NTT}(a)), 169 \cdot R \bmod q) = \mathrm{INTT}(\mathrm{NTT}(a)) \cdot 169 \pmod{3329}$$

## Hardware Interfaces

The top-level interface ports are declared in [`ntt_core_top.v`](../Implementation/rtl/modules/ntt_core_top.v).

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `clk` | Input | 1 | System clock (rising edge). |
| `rst_n` | Input | 1 | Synchronous active-low reset. Clears control and pipeline state; RAM contents are preserved. |
| `start` | Input | 1 | Single-cycle pulse initiating transform execution. Sampled only when `busy = 0`. |
| `mode` | Input | 1 | Transform direction: `0` for forward NTT, `1` for inverse INTT. Sampled with `start`. |
| `ext_we` | Input | 1 | Write-enable for external coefficient RAM access. Valid only while `busy = 0`. |
| `ext_addr` | Input | 8 | Coefficient RAM address index, range 0 to 255. |
| `ext_din` | Input | 12 | Input coefficient data to write into RAM at `ext_addr`. |
| `ext_dout` | Output | 12 | Combinational read output from RAM at `ext_addr` while `busy = 0`. |
| `busy` | Output | 1 | Active-high status flag indicating transform processing or pipeline drain. |
| `done` | Output | 1 | Single-cycle completion pulse asserted upon final coefficient write-back. |

### Handshake and Operation Protocol

1. **Initialization:** Assert `rst_n = 0` for at least one clock cycle to initialize the control FSM.
2. **Coefficient Loading:** While `busy = 0`, write 256 input coefficients into memory using `ext_addr`, `ext_din`, and `ext_we`.
3. **Trigger:** Set `mode` (`0` for NTT, `1` for INTT) and pulse `start` high for exactly one clock cycle. Requests asserted while `busy = 1` are ignored.
4. **Execution:** The core asserts `busy = 1`. During execution, internal memory multiplexers isolate the external coefficient ports; `ext_dout` does not reflect valid data.
5. **Completion and Readback:** The core asserts `done = 1` for one cycle and deasserts `busy`. Read out the 256 transformed coefficients sequentially using `ext_addr` and sampling `ext_dout`.

## Microarchitecture and Theory of Operation

The core employs an in-place architecture centered around a single arithmetic butterfly.

```text
               +-------------------------------------------------------+
               |                     ntt_core_top                      |
               |                                                       |
               |   +-------------------+       +-------------------+   |
ext_addr ----->|   |                   |       |                   |   |
ext_din  ----->|   |   ntt_ram_dual    |<----->|   ntt_butterfly   |   |
ext_we   ----->|   |  (Bank 0, Bank 1) |       |  (Cooley-Tukey /  |   |
<----- ext_dout|   +-------------------+       | Gentleman-Sande)  |   |
               |             ^                 +-------------------+   |
               |             |                           ^             |
               |             v                           |             |
               |   +-------------------+       +-------------------+   |
clk, rst_n --->|   |      ntt_agu      |       |  ntt_twiddle_rom  |   |
start, mode -->|   |  (Address Gen)    |       |  (Twiddle Factors)|   |
               |   +-------------------+       +-------------------+   |
               |             ^                           ^             |
               |             |                           |             |
               |             +-------------+-------------+             |
               |                           |                           |
               |                 +-------------------+                 |
               |                 |  ntt_controller   |                 |
busy, done <---|-----------------|       (FSM)       |                 |
               |                 +-------------------+                 |
               +-------------------------------------------------------+
```

### Submodule Descriptions

- [`ntt_controller.v`](../Implementation/rtl/modules/ntt_controller.v): Coordinates stage progression and state transitions. The forward transform executes 7 stages with segment lengths of 128, 64, 32, 16, 8, 4, and 2. The inverse transform executes lengths of 2, 4, 8, 16, 32, 64, and 128, followed by a 256-cycle coefficient scaling phase.
- [`ntt_agu.v`](../Implementation/rtl/modules/ntt_agu.v): Generates bank addresses and select lines. Parity banking ensures that paired butterfly operands reside in opposing RAM banks across all 7 stages, preventing memory port conflicts.
- [`ntt_twiddle_rom.v`](../Implementation/rtl/modules/ntt_twiddle_rom.v): Stores precomputed 12-bit twiddle factors in bit-reversed order.
- [`ntt_ram_dual.v`](../Implementation/rtl/modules/ntt_ram_dual.v): Organizes 256 coefficients into two independent $128 \times 12$-bit memories implemented via distributed RAM (LUTRAM).
- [`ntt_butterfly.v`](../Implementation/rtl/modules/ntt_butterfly.v): Unified datapath supporting forward butterfly ($u + v \cdot \omega, u - v \cdot \omega$), inverse butterfly ($u + v, (u - v) \cdot \omega$), and scalar multiplication. Operands are held stable when valid is deasserted to reduce dynamic toggle activity.
- [`ntt_mod_mul_12b.v`](../Implementation/rtl/modules/ntt_mod_mul_12b.v): Pipelined Montgomery multiplier with 5 registered stages. Implements modular multiplication without DSP blocks.
- **Address Delay FIFO:** Top-level shift register FIFO synchronizing destination memory write-back addresses with the 7-cycle latency of the butterfly unit.

## Optional System Integration (AXI4-Lite Wrapper)

For SoC integration on FPGA platforms (such as the KV260 demonstration on the `demo` branch), an AXI4-Lite slave wrapper ([`Demo/rtl/ntt_core_axi_lite.v`](https://github.com/quannguyen247/ntt-mlkem/blob/demo/Demo/rtl/ntt_core_axi_lite.v)) adapts `ntt_core_top` to a 32-bit memory-mapped bus interface at base address `0xA0000000`.

### Register Memory Map

| Byte Offset | Register Name | Access | Bit Definitions and Operational Behavior |
| ---: | --- | :---: | --- |
| `0x000` | `CONTROL` | R/W | Bit 0: `start` pulse generation (auto-clearing). Bit 1: `mode` (`0` for NTT, `1` for INTT). |
| `0x004` | `STATUS` | RO | Bit 0: `busy` flag. Bit 1: `done_sticky` interrupt status. |
| `0x008` | `CLEAR` | WO | Write Bit 0 = 1 to clear `done_sticky`. |
| `0x400 + 4*i` | `COEFF[i]` | R/W | Bits 11:0: 12-bit polynomial coefficient at index $i \in [0, 255]$. |

### Protocol and Error Handling

- **Address Alignment:** Non-word-aligned accesses return an AXI `DECERR` response.
- **Bus Contention Protection:** Reading or writing `COEFF` registers or writing `CONTROL` while `busy = 1` yields an AXI `SLVERR` response.
- **Byte Enables:** Coefficient writes require the lower two byte enables (`wstrb[1:0] == 2'b11`) to be asserted.
- **Interrupt Output:** The top-level `irq` pin directly mirrors `done_sticky` to signal completion to the host processor.

## Target Performance and Implementation Specifications

The core is engineered to satisfy the following target specifications on AMD Artix-7 (`xc7a100tfgg676-3`):

| Parameter | Target Specification |
| --- | --- |
| Target Clock Frequency | $\ge 200.0\text{ MHz}$ ($T_{\mathrm{clk}} \le 5.0\text{ ns}$) |
| Dedicated DSP Hard Blocks | 0 (pure logic / shift-add architecture) |
| Dedicated Block RAM (BRAM18/36) | 0 (pure distributed RAM architecture) |
| Forward NTT Latency ($n = 256$) | 905 clock cycles (4.525 µs @ 200 MHz) |
| Inverse INTT Latency ($n = 256$) | 1,161 clock cycles (5.805 µs @ 200 MHz) |
| Setup / Hold Timing Slack | Non-negative ($WNS \ge 0$, $WHS \ge 0$) |

## Verification Methodology

The core verification framework is implemented in [`tb_ntt_core_top.sv`](../Implementation/testbench/tb_ntt_core_top.sv) and regression test scripts.

### Test Strategy and Regression Suite

Regression tests are executed via:

```sh
make test
```

The verification suite evaluates core functionality across three validation tiers:

1. **Self-Checking Regression:** Tests directed edge-case polynomials (all-zero, canonical impulse, maximum modular value 3328) and seeded pseudo-random polynomials. Both forward and inverse transforms are verified against an independent software reference model.
2. **Round-Trip Algebraic Consistency:** Verifies $\mathrm{INTT}(\mathrm{NTT}(a)) \cdot 169 \equiv a \pmod{3329}$ across all test cases.
3. **Exhaustive Multiplier Verification:** A dedicated verification routine tests all $3,329^2 = 11,082,241$ canonical input pairs against Montgomery reduction rules to confirm that no arithmetic corner-case overflows occur.

The golden software reference derives twiddle factors directly from primitive root $\psi = 17$ and bit-reversal indexing, ensuring validation independence from the synthesized RTL ROM table.

## References

1. National Institute of Standards and Technology, *Module-Lattice-Based Key-Encapsulation Mechanism Standard*, NIST Federal Information Processing Standards Publication (FIPS) 203, Aug. 2024. DOI: [10.6028/NIST.FIPS.203](https://doi.org/10.6028/NIST.FIPS.203).
2. OpenTitan Project, "Example IP Block Guide," *OpenTitan Documentation*, [Online]. Available: [https://opentitan.org/book/doc/contributing/doc/example_ip_block.html](https://opentitan.org/book/doc/contributing/doc/example_ip_block.html).
