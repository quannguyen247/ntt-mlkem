# Shared constraints for the standalone Artix-7 NTT/INTT OOC core.
# This is not a KV260 board pinout. No false paths or multicycle exceptions.
create_clock -period 5.000 -name sys_clk [get_ports clk]

# Virtual integration BUFG site for OOC clock/hold analysis, not a package pin.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]

# Reproducible vectorless POWER ASSUMPTION, not measured workload activity.
# A High confidence label does not validate this assumption experimentally.
# Preserve the original 50% activity scenario for before/after comparisons.
set_switching_activity -default_toggle_rate 50.000
set_switching_activity -toggle_rate 50.000 -type {lut} -static_probability 0.500 -all
set_switching_activity -toggle_rate 50.000 -type {register} -static_probability 0.500 -all
set_switching_activity -toggle_rate 50.000 -type {shift_register} -static_probability 0.500 -all
set_switching_activity -toggle_rate 50.000 -type {lut_ram} -static_probability 0.500 -all
set_switching_activity -toggle_rate 50.000 -type {io_output} -static_probability 0.500 -all
