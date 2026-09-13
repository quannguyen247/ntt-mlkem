# KV260 MAX30102 Demonstration

This directory contains the KV260 integration and validation flow. The
NTT/INTT core remains in `Implementation/rtl/`; its AXI wrapper, firmware,
sensor pin constraints, and orchestration scripts live here. `demo.py` is the
user entry point, while `demo.tcl` provides the Vivado, XSCT, and XSim
backend. The earlier collection of separate Tcl commands is no longer needed.

## Run the demonstration

From the repository root:

```sh
make demo-doctor
make demo
```

`make demo` opens the GUI. Place a finger on the MAX30102, keep it still,
and start a capture. Both red and infrared traces update as samples arrive.
At the configured 100 samples/s, collecting 1,024 new pairs takes about
10.24 seconds. The signal-quality check then decides whether ARM may send
coefficients to the NTT/INTT core over AXI. FPGA programming, firmware
compilation, and result comparison take additional time.

For a headless run:

```sh
python3 Demo/demo.py run --quality-gate
python3 Demo/demo.py latest
```

## Source layout

```text
Demo/
├── demo.py                  User entry point
├── demo.tcl                 Vivado, XSCT, and XSim backend
├── firmware/                Freestanding Cortex-A53 program
│   ├── entry.S
│   ├── link.ld
│   ├── sensor.c
│   ├── sensor_ntt.c
│   └── test.c
├── rtl/ntt_core_axi_lite.v  Validation wrapper; not part of the OOC core
├── sensor.xdc               KV260 I2C pin constraints
└── README.md
```

`project/`, `output/`, and `waveform/` are ignored local artifacts. Do not
commit bitstreams, XSA or ELF files, physiological samples, or waveform
databases.

## Requirements and wiring

| Component | Requirement |
| --- | --- |
| Board | KV260 with a suitable 12 V supply |
| Host connection | Data-capable USB-A to micro-USB cable at J4 (JTAG/UART) |
| Sensor | MAX30102 with soldered pins, 3.3 V supply, and common ground |
| Vivado/Vitis | 2025.2.1 with K26 support and board preset `xilinx.com:kv260_som:part0:1.4` |
| Python | Python 3.10 or newer; PySide6 is needed only for the GUI |

The tested connections use J2.1 for SCL and J2.3 for SDA. `sensor.xdc` maps
them to H12 and E10 with LVCMOS33. Switch off power before changing wires.
Check the sensor module before assuming a wire's color identifies a supply
pin or adding pull-ups.

If the tools are not on `PATH`, set their installation directories:

```sh
export VIVADO_HOME=/home/quan/tools/Xilinx/2025.2.1/Vivado
export VITIS_HOME=/home/quan/tools/Xilinx/2025.2.1/Vitis
```

The flow does not need an SD card, Linux on the board, Vitis HLS, or a BSP.
The small firmware runs at EL3 with MMU and caches disabled. Each run resets
ARM and programs the PL with a volatile configuration; it does not write
flash or an SD card.

## Commands

| Command | Purpose |
| --- | --- |
| `demo.py doctor` | Check tools, sources, and build artifacts |
| `demo.py doctor --hardware` | Also check the JTAG target; do not program PL |
| `demo.py regression` | Generate an independent oracle and run RTL regression |
| `demo.py artix --clean` | Run Artix-7 200 MHz OOC flow and export PPA reports |
| `demo.py build --clean` | Regenerate the KV260 project, bitstream, XSA, and manifest |
| `demo.py build --clean --ila` | Build a separate ILA-instrumented KV260 variant |
| `demo.py build --publish` | Export artifacts after generating a bitstream in the GUI |
| `demo.py waveform --clean` | Simulate NTT and INTT and save WDB/WCFG files |
| `demo.py arm-test` | Test three ARM–AXI–NTT vectors without the sensor |
| `demo.py trigger` | Run three NTT/INTT vectors for ILA observation without reprogramming PL |
| `demo.py run --quality-gate` | Run the sensor flow without the GUI |
| `demo.py present` | Open the one-button GUI; also the default action |
| `demo.py latest` | Print the latest result JSON |

`demo.py build` refuses to overwrite an existing `project/`. The explicit
`--clean` option rebuilds that generated project; captures under `output/`
are preserved.

## Hardware build

```sh
python3 Demo/demo.py build --clean
```

The backend builds the Zynq UltraScale+ PS, the AXI4-Lite NTT interface,
and a two-wire GPIO connection to MAX30102. The NTT interface is mapped at
`0xA0000000`, GPIO at `0xA0010000`, and the PL clock is 200 MHz. Artifacts
are published only when both setup and hold slack are nonnegative:

- `output/i2c.bit`
- `output/kv260_sensor.xsa`
- `output/psu_init.tcl`
- `output/i2c_timing.rpt`
- `output/i2c_drc.rpt`
- `output/build-manifest.json`

The manifest records hashes of the RTL, XDC, hardware-generation Tcl, and
produced artifacts. `doctor` rejects stale sources or changed artifacts so
an old bitstream cannot silently be presented as evidence for new RTL.

The ILA variant is a separate debug build. `demo.py trigger` confirms that
the ARM test completed; only captured data in Vivado can show what ILA
observed. Do not use the debug build's resource figures for the
uninstrumented Artix-7 OOC comparison.

To create only the block design for inspection in Vivado:

```sh
python3 Demo/demo.py build --clean --prepare-only
```

After **Generate Bitstream** in the GUI, publish and stamp the artifacts
through the script rather than editing the manifest by hand:

```sh
python3 Demo/demo.py build --publish
```

The batch `build --clean` path has fewer manual steps and is the reference
build flow.

## Data path and checks

1. Python compiles `sensor_ntt.c`, `entry.S`, and `link.ld` into a fresh ELF.
2. XSCT initializes PS and DDR, loads the bitstream and ELF, and starts
   Cortex-A53 core 0.
3. ARM checks MAX30102 `PART_ID` (`0x15`) at the 7-bit I2C address `0x57`.
4. ARM captures 1,024 red/IR pairs of 18-bit samples at a configured
   100 samples/s. The GUI plots samples as they arrive.
5. At the breakpoint, the host reads that capture and checks for dropped
   samples, amplitude, drift, red/IR correlation, and periodicity. BPM and
   SpO2 are estimated only when the signal passes the quality check.
6. If the signal fails, the host writes `approval=0`. ARM exits with
   `completed_blocks=0` without starting the NTT core.
7. If it passes, ARM takes the last 256 pairs and splits each 18-bit value
   into two 9-bit coefficients. Red-low, red-high, IR-low, and IR-high form
   four blocks of 256 coefficients, or 1,024 coefficients in total.
8. ARM transfers the four blocks over AXI and runs NTT followed by INTT on
   the PL.
9. The host checks all 1,024 results in each direction against the
   repository's golden model and checks the round trip after removing the
   Montgomery factor.

The sensor flow uses the repository's historical golden model. The separate
`demo.py regression` flow generates twiddle factors from primitive root 17
without reading the RTL ROM. These are project-level technical checks, not
cryptographic certification.

## Result interpretation

A `PASS` requires a new capture that passes the quality gate, four completed
blocks, 1,024/1,024 matching NTT coefficients, 1,024/1,024 matching INTT
coefficients, and recovery of all 1,024 normalized input coefficients.

`INSUFFICIENT_SIGNAL` returns exit code 0 because refusing the transform is
the expected behavior in that case; NTT and INTT must be `NOT_RUN`. A tool,
JTAG, I2C, or timeout failure means the test did not complete. It is not, by
itself, evidence that the RTL is incorrect.

Each run creates `output/sensor-ntt-TIMESTAMP/` with `live_raw.csv`, the raw
and comparison CSV files, `result.json`, `hardware.log`, the ELF, and a GUI
image. Keep this directory when investigating a failure.

## Scope

The demonstration checks the MAX30102 → ARM → AXI → NTT/INTT path and the
repository's mathematical comparisons. It is not a complete ML-KEM
implementation: there is no basemul/PolyEngine or encrypted sensor channel.
BPM and SpO2 are uncalibrated demonstration estimates. The Artix-7 PPA flow
(`demo.py artix`) is a different build from KV260 integration. See
[`Docs/SPEC.md`](../Docs/SPEC.md) for the core's interface and measurement scope.

The older VIO path was removed because it provided a second hardware route
without checking the sensor–ARM–AXI chain. Report waveforms now come from
`demo.py waveform` and the main self-checking testbench; live debug uses the
AXI flow's CSV and JSON evidence.
