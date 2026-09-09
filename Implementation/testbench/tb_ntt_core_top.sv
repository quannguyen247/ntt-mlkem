`timescale 1ns/1ps
// Single testbench for Icarus/XSim and RTL/routed functional simulation.
// Define TEST_MULTIPLIER for exhaustive arithmetic/latency checking.
module tb_ntt_core_top;
    parameter CASES = 74;
    reg clk = 0;
    always #2.5 clk = ~clk;
`ifdef TEST_MULTIPLIER
    reg [11:0] a_i=0, b_i=0;
    wire [11:0] r_o;
    ntt_mod_mul_12b dut(.*);
    integer i,j,n=0;
    integer expected [0:4];
    always @(posedge clk) begin
        expected[4]=expected[3]; expected[3]=expected[2];
        expected[2]=expected[1]; expected[1]=expected[0];
        expected[0]=(int'(a_i)*int'(b_i)*169)%3329;
        n=n+1;
        #0.1;
        if(n>=5 && r_o !== expected[4][11:0])
            $fatal(1,"MUL mismatch n=%0d expected=%0d got=%0d",n,expected[4],r_o);
    end
    initial begin
        for(i=0;i<3329;i=i+1)
            for(j=0;j<3329;j=j+1) begin
                @(negedge clk); a_i=i; b_i=j;
            end
        repeat(5) @(negedge clk);
        $display("MUL_EXHAUSTIVE_PASS pairs=11082241 latency=5");
        $finish;
    end
`else
    reg rst_n=0, start=0, mode=0, ext_we=0;
    reg [7:0] ext_addr=0;
    reg [11:0] ext_din=0;
    wire [11:0] ext_dout;
    wire busy,done;
    ntt_core_top dut(.*);
    reg [11:0] inputs [0:CASES*256-1], expected [0:CASES*256-1];
    reg modes [0:CASES-1];
    integer c,j,cycles,checked=0,fd;
    string vector_dir;
    initial begin
        vector_dir=".";
        if($value$plusargs("VEC_DIR=%s",vector_dir)) begin end
        fd=$fopen({vector_dir,"/mode.mem"},"r");
        if(!fd) $fatal(1,"Generate vectors with benchmark/regress.py; use +VEC_DIR=directory");
        $fclose(fd);
        $readmemh({vector_dir,"/input.mem"},inputs);
        $readmemh({vector_dir,"/expected.mem"},expected);
        $readmemh({vector_dir,"/mode.mem"},modes);
        #200; // Allow FPGA glbl startup in routed functional simulation.
        repeat(4) @(negedge clk);
        rst_n=1;
        for(c=0;c<CASES;c=c+1) begin
            if(modes[c] !== 1'b0 && modes[c] !== 1'b1)
                $fatal(1,"Missing mode vector case=%0d",c);
            // Alternate modes without reset between transactions.
            for(j=0;j<256;j=j+1) begin
                if((^inputs[c*256+j]) === 1'bx || (^expected[c*256+j]) === 1'bx)
                    $fatal(1,"Missing/unknown vector case=%0d coeff=%0d",c,j);
                @(negedge clk); ext_we=1; ext_addr=j; ext_din=inputs[c*256+j];
            end
            @(negedge clk); ext_we=0; mode=modes[c]; start=1;
            @(negedge clk); start=0; cycles=0;
            while(!done && cycles<10000) begin
                @(negedge clk); cycles=cycles+1;
            end
            if(done !== 1'b1) $fatal(1,"TIMEOUT/UNKNOWN done case=%0d",c);
            $display("CASE=%0d MODE=%0d CYCLES=%0d",c,mode,cycles);
            for(j=0;j<256;j=j+1) begin
                @(negedge clk); ext_addr=j; #1;
                if(ext_dout !== expected[c*256+j])
                    $fatal(1,"MISMATCH case=%0d coeff=%0d got=%h expected=%h",c,j,ext_dout,expected[c*256+j]);
                checked=checked+1;
            end
            repeat(8) @(negedge clk);
        end
        $display("REGRESSION_PASS cases=%0d coefficients=%0d",CASES,checked);
        #100; $finish;
    end
`endif
endmodule
