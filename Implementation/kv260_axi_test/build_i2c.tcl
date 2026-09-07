# Open existing AXI project; preserve its published NTT-only bitstream.
set here [file dirname [file normalize [info script]]]
if {[current_project -quiet] eq ""} {open_project $here/project/kv260_axi_test.xpr}
if {[file normalize [get_property DIRECTORY [current_project]]] ne [file normalize $here/project]} {error "Open the kv260_axi_test project first"}
open_bd_design [get_files ntt_system.bd]
if {![llength [get_bd_cells -quiet sensor_gpio]]} {
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* sensor_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {2} CONFIG.C_ALL_INPUTS {0} CONFIG.C_ALL_OUTPUTS {0} CONFIG.C_DOUT_DEFAULT {0x00000000} CONFIG.C_TRI_DEFAULT {0xFFFFFFFF}] [get_bd_cells sensor_gpio]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps/M_AXI_HPM0_FPD" Clk_master "/ps/pl_clk0 (200 MHz)" Clk_slave "/ps/pl_clk0 (200 MHz)" Clk_xbar "/ps/pl_clk0 (200 MHz)"} [get_bd_intf_pins sensor_gpio/S_AXI]
make_bd_intf_pins_external [get_bd_intf_pins sensor_gpio/GPIO]
set_property name sensor [get_bd_intf_ports GPIO_0]
assign_bd_address
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps/Data] -filter {NAME =~ *sensor_gpio*}]
set_property offset 0xA0010000 $seg
set_property range 64K $seg
}
validate_bd_design
save_bd_design
add_files -fileset constrs_1 -norecurse $here/sensor.xdc
generate_target all [get_files ntt_system.bd]
make_wrapper -files [get_files ntt_system.bd] -top
reset_run synth_1
if {[info exists ::kv260_gui_only] && $::kv260_gui_only} {
    puts "SENSOR_PROJECT_READY: Run Synthesis, Implementation, Generate Bitstream; then source publish_i2c.tcl."
    return
}
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {error "Build failed"}
source $here/publish_i2c.tcl
puts "I2C_BUILD_COMPLETE"
