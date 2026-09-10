set script_dir [file normalize [file dirname [info script]]]
set probes_file [file normalize [file join $script_dir output \
    ntt_kv260_debug.ltx]]

open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices xck26_0] 0]
if {$device eq ""} {
    error "xck26_0 was not found."
}

set_property PROBES.FILE $probes_file $device
set_property FULL_PROBES.FILE $probes_file $device
set_property BSCAN_SWITCH_USER_MASK 0001 $device
refresh_hw_device $device

set vio [lindex [get_hw_vios -of_objects $device] 0]
if {$vio eq ""} {
    error "VIO core was not found. Check PL clock and the matching .ltx file."
}

puts "KV260_VIO_FOUND=[get_property CELL_NAME $vio]"
puts "KV260_VIO_PROBES_BEGIN"
foreach probe [get_hw_probes -of_objects $vio] {
    puts "[get_property NAME $probe]"
}
puts "KV260_VIO_PROBES_END"

close_hw_target
disconnect_hw_server
close_hw_manager
exit
