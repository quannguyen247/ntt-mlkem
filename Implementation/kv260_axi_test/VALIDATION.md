# Cleanup validation — 2026-09-07

## Checked in this cleanup session

- Python source syntax and offscreen PySide6 GUI import/render: passed.
- Replayed local raw capture that previously triggered empty min(): no exception,
  accepted by the existing quality heuristic. Low-signal capture remains rejected.
- A53 test ELF compiled using Vitis 2025.2.1 aarch64-none-elf-gcc.
- Recreated the GUI-preparation flow in a clean temporary directory using
  build.tcl then build_i2c.tcl with kv260_gui_only=1; Vivado validated the
  sensor block design and reported CLEAN_GUI_PROJECT_PASS.
- Ran publish_i2c.tcl with Vivado 2025.2.1 against the existing routed project:
  clk_pl_0 = 5 ns (200 MHz), WNS +0.470 ns, WHS +0.014 ns,
  no failing setup/hold endpoints. Exported kv260_sensor.xsa and i2c.bit locally.
  This reopens the existing implementation; it is not a new full synthesis build.
- Attempted run_test.tcl on hardware: NOT RUN, XSCT found no Cortex-A53 targets.
  USB enumeration at that time did not show the board's JTAG interface.
  No fresh hardware PASS is claimed by this cleanup commit.

## Earlier local evidence (not shipped in Git)

The earlier session's sensor-ntt-20260907-142221-678483/result.json records
NTT/INTT PASS, 1024 coefficients each, normalized_roundtrip_pass=true.
Sensor captures and old logs stay in ignored output/ and are historical evidence.
Rerun on the actual connected kit before presenting a changed build.

## Scope of cleanup

Removed obsolete live_plot.py calibration/verification UI, signal_check.py and
live_sensor.tcl. The retained raw_plot.py is the plotting widget used by
simple_demo.py. The demonstration now has one documented entry point.
The superseded scripts were backed up locally outside the repository before removal.
RTL/PPG thresholds were not changed in this cleanup session.

VIO scripts remain a separate optional flow. Generated Validation/ workspace
was already staged for removal from tracking; generated outputs are ignored.
The original Implementation/NTT.xpr local edits are not part of the demo commit.
