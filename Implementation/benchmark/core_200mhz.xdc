# Core-only OOC benchmark. External I/O delays require an integration context.
create_clock -period 5.000 -name sys_clk [get_ports clk]
