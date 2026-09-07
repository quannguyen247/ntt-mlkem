set script_dir [file normalize [file dirname [info script]]]
set impl_dir [file normalize [file join $script_dir ..]]
set probes_file [file normalize [file join $script_dir output \
    ntt_kv260_debug.ltx]]
set vector_file [file normalize [file join $impl_dir vector tv_all.mem]]
set result_file [file normalize [file join $script_dir output \
    hardware_ntt_vector_test.log]]
set case_index 1

proc read_hex_lines {path} {
    set fd [open $path r]
    set values {}
    while {[gets $fd line] >= 0} {
        set clean [string trim $line]
        if {$clean ne ""} {
            scan $clean %x value
            lappend values $value
        }
    }
    close $fd
    return $values
}

proc number_value {value} {
    set clean [string trim $value]
    if {[string match "0x*" $clean]} {
        scan $clean %x result
        return $result
    }
    if {[regexp {^[01]+$} $clean]} {
        scan $clean %b result
        return $result
    }
    scan $clean %x result
    return $result
}

proc set_out {probe value} {
    set probe_name [get_property NAME $probe]
    if {[string match "*probe_out4" $probe_name]} {
        set encoded [format "%02X" $value]
    } elseif {[string match "*probe_out5" $probe_name]} {
        set encoded [format "%03X" $value]
    } else {
        set encoded [format "%01X" $value]
    }
    set_property OUTPUT_VALUE $encoded $probe
}

proc commit_outputs {outputs} {
    commit_hw_vio $outputs
    after 2
}

proc read_input {vio probe} {
    refresh_hw_vio $vio
    return [number_value [get_property INPUT_VALUE $probe]]
}

# ntt_gen.py packs each line as INTT | NTT | input, coefficient 0 at LSB.
set fd [open $vector_file r]
set vector_lines [split [string trim [read $fd]] \n]
close $fd
set packed [string trim [lindex $vector_lines $case_index]]
if {![regexp {^[0-9a-fA-F]{2304}$} $packed]} {
    error "Missing/invalid vector case $case_index; run python ntt_gen.py first."
}
set input_poly {}
set expected_ntt {}
for {set addr 0} {$addr < 256} {incr addr} {
    set last [expr {2303 - 3 * $addr}]
    scan [string range $packed [expr {$last - 2}] $last] %x value
    lappend input_poly $value
    incr last -768
    scan [string range $packed [expr {$last - 2}] $last] %x value
    lappend expected_ntt $value
}

set status 1
set log_fd [open $result_file w]

if {[catch {
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
        error "VIO core was not found."
    }

    set resetn [lindex [get_hw_probes *probe_out0 -of_objects $vio] 0]
    set start [lindex [get_hw_probes *probe_out1 -of_objects $vio] 0]
    set mode [lindex [get_hw_probes *probe_out2 -of_objects $vio] 0]
    set ext_we [lindex [get_hw_probes *probe_out3 -of_objects $vio] 0]
    set ext_addr [lindex [get_hw_probes *probe_out4 -of_objects $vio] 0]
    set ext_din [lindex [get_hw_probes *probe_out5 -of_objects $vio] 0]
    set ext_dout [lindex [get_hw_probes *ext_dout -of_objects $vio] 0]
    set busy [lindex [get_hw_probes *busy -of_objects $vio] 0]
    set done_sticky [lindex [get_hw_probes *done_sticky -of_objects $vio] 0]
    set outputs [list $resetn $start $mode $ext_we $ext_addr $ext_din]

    set_out $resetn 0
    set_out $start 0
    set_out $mode 0
    set_out $ext_we 0
    set_out $ext_addr 0
    set_out $ext_din 0
    commit_outputs $outputs
    set_out $resetn 1
    commit_outputs $outputs

    set_out $ext_we 1
    for {set addr 0} {$addr < 256} {incr addr} {
        set_out $ext_addr $addr
        set_out $ext_din [lindex $input_poly $addr]
        commit_outputs $outputs
    }
    set_out $ext_we 0
    commit_outputs $outputs

    set_out $mode 0
    set_out $start 1
    commit_outputs $outputs
    set_out $start 0
    commit_outputs $outputs

    set completed 0
    for {set poll 0} {$poll < 100} {incr poll} {
        if {[read_input $vio $done_sticky] == 1} {
            set completed 1
            break
        }
        after 5
    }
    if {!$completed} {
        error "NTT timeout; busy=[read_input $vio $busy]"
    }

    set mismatches 0
    for {set addr 0} {$addr < 256} {incr addr} {
        set_out $ext_addr $addr
        commit_outputs $outputs
        set actual [read_input $vio $ext_dout]
        set expected [lindex $expected_ntt $addr]
        if {$actual != $expected} {
            if {$mismatches < 10} {
                puts $log_fd [format \
                    "MISMATCH addr=%d expected=%03X got=%03X" \
                    $addr $expected $actual]
            }
            incr mismatches
        }
    }

    puts $log_fd "CASE_INDEX=$case_index"
    puts $log_fd "COEFFICIENTS_CHECKED=256"
    puts $log_fd "MISMATCHES=$mismatches"
    if {$mismatches != 0} {
        error "Non-zero NTT vector failed with $mismatches mismatches."
    }

    puts $log_fd "HARDWARE_NTT_VECTOR_TEST_PASS"
    puts "HARDWARE_NTT_VECTOR_TEST_PASS"
    set status 0
} message options]} {
    puts $log_fd "HARDWARE_NTT_VECTOR_TEST_FAIL: $message"
    puts stderr "HARDWARE_NTT_VECTOR_TEST_FAIL: $message"
}

close $log_fd
catch {close_hw_target}
catch {disconnect_hw_server}
catch {close_hw_manager}
exit $status
