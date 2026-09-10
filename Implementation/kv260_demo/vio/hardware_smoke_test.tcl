set script_dir [file normalize [file dirname [info script]]]
set probes_file [file normalize [file join $script_dir output \
    ntt_kv260_debug.ltx]]
set result_file [file normalize [file join $script_dir output \
    hardware_smoke_test.log]]

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

    # RAM path sanity check.
    set_out $ext_addr 42
    set_out $ext_din 0xABC
    set_out $ext_we 1
    commit_outputs $outputs
    set_out $ext_we 0
    commit_outputs $outputs
    set_out $ext_addr 42
    commit_outputs $outputs
    set ram_value [read_input $vio $ext_dout]
    puts $log_fd [format "RAM_SANITY addr=42 expected=ABC got=%03X" $ram_value]
    if {$ram_value != 0xABC} {
        error [format "RAM sanity failed: expected ABC, got %03X" $ram_value]
    }

    # Load a zero polynomial.
    set_out $ext_din 0
    set_out $ext_we 1
    for {set addr 0} {$addr < 256} {incr addr} {
        set_out $ext_addr $addr
        commit_outputs $outputs
    }
    set_out $ext_we 0
    commit_outputs $outputs

    # Forward NTT, mode=0.
    set_out $mode 0
    set_out $start 1
    commit_outputs $outputs
    set_out $start 0
    commit_outputs $outputs

    set completed 0
    for {set poll 0} {$poll < 100} {incr poll} {
        set sticky_value [read_input $vio $done_sticky]
        if {$sticky_value == 1} {
            set completed 1
            break
        }
        after 5
    }
    if {!$completed} {
        set busy_value [read_input $vio $busy]
        error "NTT timeout; busy=$busy_value"
    }

    set mismatches 0
    for {set addr 0} {$addr < 256} {incr addr} {
        set_out $ext_addr $addr
        commit_outputs $outputs
        set value [read_input $vio $ext_dout]
        if {$value != 0} {
            if {$mismatches < 10} {
                puts $log_fd [format "ZERO_NTT_MISMATCH addr=%d got=%03X" \
                    $addr $value]
            }
            incr mismatches
        }
    }

    if {$mismatches != 0} {
        error "Zero-vector NTT failed with $mismatches mismatches."
    }

    puts $log_fd "HARDWARE_SMOKE_TEST_PASS"
    puts "HARDWARE_SMOKE_TEST_PASS"
    set status 0
} message options]} {
    puts $log_fd "HARDWARE_SMOKE_TEST_FAIL: $message"
    puts stderr "HARDWARE_SMOKE_TEST_FAIL: $message"
}

close $log_fd
catch {close_hw_target}
catch {disconnect_hw_server}
catch {close_hw_manager}
exit $status
