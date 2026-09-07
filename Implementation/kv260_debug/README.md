# KV260 JTAG/VIO debug build

Generated `project/` and `output/` stay local and are not shipped in Git.
Rebuild them after cloning; this optional VIO flow is separate from the sensor demo.

For the step-by-step presentation in Vietnamese, see [DEMO_VIVADO.md](DEMO_VIVADO.md).
The saved `output/` files are historical artifacts from the August 12, 2026
build/test session. They are not evidence of a fresh build or board test after
later edits. Rebuild and rerun the test before presenting changed RTL.

This build preserves the existing `ntt_core_top` RTL interface and makes it
controllable through Vivado VIO over the KV260 on-board JTAG connection.

No NTT signal is assigned to a physical PL pin. The Zynq Processing System
provides a mandatory 200 MHz PL clock and active-low reset.

## Quick start

Connect the KV260 12 V supply and USB-A to micro-USB JTAG cable. Then run these
commands from PowerShell:

```powershell
Set-Location C:\Users\Quan\Desktop\Github-repo\ntt-mlkem\Implementation\kv260_debug

python ..\vector\ntt_gen.py

# Rebuild only when RTL or the debug design changes.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1

# Run after every board power cycle.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\init_and_program.ps1

# Verify a non-zero golden NTT vector on the physical FPGA.
& 'C:\AMDDesignTools\2025.2.1\Vivado\bin\vivado.bat' `
  -mode batch -source .\hardware_ntt_vector_test.tcl `
  -log .\hardware_ntt_vector_test_vivado.log `
  -journal .\hardware_ntt_vector_test_vivado.jou

Get-Content .\output\hardware_ntt_vector_test.log
```

Expected final lines:

```text
COEFFICIENTS_CHECKED=256
MISMATCHES=0
HARDWARE_NTT_VECTOR_TEST_PASS
```

## VIO mapping

Outputs driven from Hardware Manager:

| VIO probe | NTT signal | Width |
|---|---|---:|
| `probe_out0` | `vio_resetn` | 1 |
| `probe_out1` | `start` | 1 |
| `probe_out2` | `mode` (`0=NTT`, `1=INTT`) | 1 |
| `probe_out3` | `ext_we` | 1 |
| `probe_out4` | `ext_addr` | 8 |
| `probe_out5` | `ext_din` | 12 |

Inputs observed in Hardware Manager:

| VIO probe | NTT signal | Width |
|---|---|---:|
| `probe_in0` | `ext_dout` | 12 |
| `probe_in1` | `busy` | 1 |
| `probe_in2` | `done` | 1 |
| `probe_in3` | `done_sticky` | 1 |

`done_sticky` stays high after completion. Pulse `vio_resetn` low then high to
clear it.

## Build

From PowerShell:

```powershell
Set-Location C:\Users\Quan\Desktop\Github-repo\ntt-mlkem\Implementation\kv260_debug
.\build.ps1
```

Expected output:

```text
output\ntt_kv260_debug.bit
output\ntt_kv260_debug.ltx
output\ntt_kv260_debug.xsa
```

The PS must be initialized so its `pl_clk0` runs. The exported XSA contains the
generated `psu_init.tcl` used by Vitis/XSCT for that initialization.

## Initialize the PS and program the bitstream

Connect the KV260 12 V supply and the USB-A to micro-USB JTAG cable. Close
Hardware Manager before running:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\init_and_program.ps1
```

This initializes the KV260 Processing System, starts `pl_clk0`, and programs
`output\ntt_kv260_debug.bit`.

After the command reports
`KV260_PS_INITIALIZED_AND_BITSTREAM_PROGRAMMED`, open Vivado Hardware Manager,
select **Open Target > Auto Connect**, and open the VIO dashboard.

## Automated on-board checks

With the programmed board still powered:

```powershell
& 'C:\AMDDesignTools\2025.2.1\Vivado\bin\vivado.bat' `
  -mode batch -source .\hardware_smoke_test.tcl `
  -log .\hardware_smoke_test_vivado.log `
  -journal .\hardware_smoke_test_vivado.jou

& 'C:\AMDDesignTools\2025.2.1\Vivado\bin\vivado.bat' `
  -mode batch -source .\hardware_ntt_vector_test.tcl `
  -log .\hardware_ntt_vector_test_vivado.log `
  -journal .\hardware_ntt_vector_test_vivado.jou
```

The first check verifies VIO RAM write/read and a zero-vector NTT. The second
loads non-zero golden-vector case 2 from `Implementation\vector`, runs NTT on
the FPGA, and compares all 256 output coefficients.

## Manual VIO use

1. Open Vivado Hardware Manager.
2. Select **Open Target > Auto Connect**.
3. Select `xck26_0`.
4. Set **Probes file** to `output\ntt_kv260_debug.ltx`.
5. Refresh the device and open the VIO dashboard.

Important sequence:

1. Pulse `probe_out0` low then high to reset.
2. To write RAM, set address/data, set `probe_out3=1`, commit, then return it
   to `0`.
3. Set `probe_out2=0` for NTT or `1` for INTT.
4. Pulse `probe_out1` from `0` to `1` and back to `0`.
5. Wait until `done_sticky` (`probe_in3`) becomes `1`.
6. Change `probe_out4` to read each address through `probe_in0`.
