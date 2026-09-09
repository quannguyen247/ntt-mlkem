# Repair the legacy Artix core project; preserve the original XPR and BD files.
# Run with Vivado closed for this project, then reopen it after this script exits.
set here [file normalize [file dirname [info script]]]
set root [file normalize $here/../..]
set project $root/Implementation/NTT.xpr
set backup $root/build/ppa/project-backup-[clock format [clock seconds] -format %Y%m%d-%H%M%S]
file mkdir $backup
file copy $project $backup/NTT.xpr
puts "PROJECT_BACKUP $backup/NTT.xpr"
# Install before open_project: Vivado emits the empty-board message while
# scanning the XPR, before a project-local command can change its severity.
set_msg_config -id {Project 1-5713} -string {Board part ''} -new_severity INFO
# Removing the locked BD in Vivado 2025.2.1 crashes. Sanitize only its XPR
# references before opening the project; preserve files and generated runs.
set fh [open $project r]
set xml [read $fh]
close $fh
if {![string match {*Name="Part" Val="xc7a100tfgg676-3"*} $xml]} {
    error "This repair is only for the Artix-7 core benchmark"
}
set cleaned {}
set skip 0
foreach line [split $xml \n] {
    if {[string match {*<File Path="*/bd/NTT/*} $line]} {set skip 1}
    if {$skip} {
        if {[string trim $line] eq "</File>"} {set skip 0}
        continue
    }
    if {[regexp {<Option Name="(BoardPart(RepoPaths)?|DSABoardId)"} $line]} {continue}
    lappend cleaned $line
}
set xml [join $cleaned \n]
set fh [open $project w]
puts -nonewline $fh $xml
close $fh
open_project $project
if {[llength [get_files -quiet */bd/NTT/*]] != 0} {error "Old BD reference remains"}
# Reproduced on a fresh part-only project: this is an empty-board tool warning.
# Keep it visible as INFO; never suppress a named missing board or timing DRC.
set_msg_config -id {Project 1-5713} -string {Board part ''} -new_severity INFO
set_property top ntt_core_top [get_filesets sources_1]
set_property strategy {Vivado Synthesis Defaults} [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.MAX_DSP 0 [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
set_property top tb_ntt_core_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property -name xsim.simulate.xsim.more_options -value [list -testplusarg "VEC_DIR=$root/build/ppa/vectors"] -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
if {[llength [get_ips -quiet]] != 0} {
    report_ip_status
} else {
    puts "CORE_PROJECT_IP_COUNT 0"
}
close_project
puts "PROJECT_REPAIR_FINISHED $project"
