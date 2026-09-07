# Run after Generate Bitstream in the sensor project (GUI or batch).
set here [file dirname [file normalize [info script]]]
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
