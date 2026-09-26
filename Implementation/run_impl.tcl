set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir NTT.xpr]
update_compile_order -fileset sources_1

set synth_status [get_property STATUS [get_runs synth_1]]
if {$synth_status ne "synth_design Complete!"} {
    if {$synth_status ne "Not started"} {reset_run synth_1}
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
}
set impl_status [get_property STATUS [get_runs impl_1]]
if {$impl_status ne "route_design Complete!" &&
    $impl_status ne "post_route_phys_opt_design Complete!" &&
    $impl_status ne "write_bitstream Complete!"} {
    if {$impl_status ne "Not started"} {reset_run impl_1}
    launch_runs impl_1 -to_step route_design -jobs 4
    wait_on_run impl_1
}
open_run impl_1

set report_dir [file join $project_dir reports]
file mkdir $report_dir
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $report_dir timing.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_power -file [file join $report_dir power_vectorless.rpt]
puts "Implementation reports: $report_dir"
close_project
