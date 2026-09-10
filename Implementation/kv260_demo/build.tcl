# Vivado sensor build; see README.md for prepare/publish modes.
set here [file dirname [file normalize [info script]]]
set impl [file dirname $here]
set action build
if {[info exists ::kv260_action]} {set action $::kv260_action}
if {$action ni {build prepare publish}} {error "kv260_action must be build, prepare or publish"}
if {$action ne "publish"} {
if {[file exists $here/project]} {error "Preserve existing project/ elsewhere before rebuilding"}
if {[current_project -quiet] ne ""} {error "Close the current project first"}
create_project kv260_axi_test $here/project -part xck26-sfvc784-2LV-c
set_property board_part xilinx.com:kv260_som:part0:1.4 [current_project]
add_files [glob $impl/rtl/modules/*.v]
add_files [glob $impl/rtl/utils/*.vh]
set_property include_dirs [list $impl/rtl/utils] [get_filesets sources_1]
create_bd_design ntt_system
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
set_property -dict [list CONFIG.PSU__USE__M_AXI_GP0 {1} CONFIG.PSU__USE__M_AXI_GP1 {0} CONFIG.PSU__USE__M_AXI_GP2 {0} CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {200}] $ps
create_bd_cell -type module -reference ntt_core_axi_lite ntt
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps/M_AXI_HPM0_FPD" Clk_master "/ps/pl_clk0 (200 MHz)" Clk_slave "/ps/pl_clk0 (200 MHz)" Clk_xbar "/ps/pl_clk0 (200 MHz)"} [get_bd_intf_pins ntt/s_axi]
assign_bd_address
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps/Data] -filter {NAME =~ *ntt*}]
if {[llength $seg] != 1} {error "Expected one NTT address segment: $seg"}
set_property offset 0xA0000000 $seg
set_property range 4K $seg
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* sensor_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {2} CONFIG.C_ALL_INPUTS {0} CONFIG.C_ALL_OUTPUTS {0} CONFIG.C_DOUT_DEFAULT {0x00000000} CONFIG.C_TRI_DEFAULT {0xFFFFFFFF}] [get_bd_cells sensor_gpio]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps/M_AXI_HPM0_FPD" Clk_master "/ps/pl_clk0 (200 MHz)" Clk_slave "/ps/pl_clk0 (200 MHz)" Clk_xbar "/ps/pl_clk0 (200 MHz)"} [get_bd_intf_pins sensor_gpio/S_AXI]
make_bd_intf_pins_external [get_bd_intf_pins sensor_gpio/GPIO]
set_property name sensor [get_bd_intf_ports GPIO_0]
assign_bd_address
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps/Data] -filter {NAME =~ *sensor_gpio*}]
set_property offset 0xA0010000 $seg
set_property range 64K $seg
validate_bd_design
save_bd_design
add_files -fileset constrs_1 -norecurse $here/sensor.xdc
set bd [get_files ntt_system.bd]
generate_target all $bd
add_files [make_wrapper -files $bd -top]
set_property top ntt_system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
if {$action eq "prepare"} {puts "SENSOR_PROJECT_READY"; return}
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
} else {
if {[current_project -quiet] eq ""} {open_project $here/project/kv260_axi_test.xpr}
if {[file normalize [get_property DIRECTORY [current_project]]] ne [file normalize $here/project]} {error "Open the sensor project in $here/project"}
}
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {error "Generate Bitstream first"}
open_run impl_1
file mkdir $here/output
report_timing_summary -delay_type min_max -file $here/output/i2c_timing.rpt
report_drc -file $here/output/i2c_drc.rpt
set c [get_clocks -quiet clk_pl_0]
if {[llength $c] != 1 || abs([get_property PERIOD $c]-5.0)>0.001} {error "PL clock must be 200 MHz"}
foreach type {max min} {
    set p [get_timing_paths -delay_type $type -max_paths 1]
    if {[llength $p] != 1 || [get_property SLACK $p]<0} {error "Timing failed: $type"}
}
if {[llength [get_ports -quiet {sensor_tri_io[*]}]]!=2} {error "Expected sensor I2C ports"}
write_hw_platform -fixed -include_bit -force -file $here/output/kv260_sensor.xsa
file copy -force $here/project/kv260_axi_test.runs/impl_1/ntt_system_wrapper.bit $here/output/i2c.bit
puts "SENSOR_ARTIFACTS_READY: 200 MHz, setup/hold pass"
