`timescale 1ns / 1ps

module tb_ntt_core_top;

    localparam integer CLK_PERIOD_NS = 5;
    localparam integer TIMEOUT_CYCLES = 30000;
    localparam integer MAX_TV = 1024;
    localparam integer EXPECTED_NTT_CYCLES = 905;
    localparam integer EXPECTED_INTT_CYCLES = 1161;
    localparam integer EXPECTED_NTT_ISSUES = 896;
    localparam integer EXPECTED_INTT_ISSUES = 1152;

    logic clk;
    logic rst_n;
    logic start;
    logic mode;
    logic ext_we;
    logic [7:0] ext_addr;
    logic [11:0] ext_din;
    logic [11:0] ext_dout;
    logic busy;
    logic done;

    reg [11:0] tv_poly [0:MAX_TV*256-1];
    reg [11:0] tv_ntt  [0:MAX_TV*256-1];
    reg [11:0] tv_intt [0:MAX_TV*256-1];
    reg [11:0] result_buf [0:255];
    reg [11:0] ntt_result_buf [0:255];
    reg [11:0] intt_result_buf [0:255];
    reg [639:0] line_buffer;

    int tv_count_actual;
    int case_idx;
    int ntt_error_count;
    int intt_error_count;
    int roundtrip_error_count;
    int protocol_error_count;
    int ntt_report_fd;
    int intt_report_fd;
    int spec_fd;
    logic timeout_flag;
    integer cycle_cnt;
    integer issue_count;

    string tb_file;
    string tb_dir;
    string tv_dir;
    string ntt_report_path;
    string intt_report_path;

    function automatic string dirname(string path);
        for (int i = path.len() - 1; i >= 0; i--)
            if (path[i] == "/" || path[i] == "\\")
                return path.substr(0, i - 1);
        return ".";
    endfunction

    ntt_core_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .mode(mode),
        .ext_we(ext_we),
        .ext_addr(ext_addr),
        .ext_din(ext_din),
        .ext_dout(ext_dout),
        .busy(busy),
        .done(done)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n)
            issue_count = 0;
        else if (u_dut.bf_valid_in)
            issue_count = issue_count + 1;
    end

    task automatic wait_for_done();
    begin
        timeout_flag = 1'b0;
        fork : wait_block
            begin
                wait (done == 1'b1);
                disable wait_block;
            end
            begin
                repeat (TIMEOUT_CYCLES) @(posedge clk);
                timeout_flag = 1'b1;
                disable wait_block;
            end
        join
    end
    endtask

    task load_from_tv_poly(input int base);
    begin
        integer j;
        for (j = 0; j < 256; j = j + 1) begin
            @(posedge clk); #0.5;
            ext_we = 1'b1;
            ext_addr = j[7:0];
            ext_din = tv_poly[base + j];
        end
        @(posedge clk); #0.5;
        ext_we = 1'b0;
    end
    endtask

    task load_from_tv_ntt(input int base);
    begin
        integer j;
        for (j = 0; j < 256; j = j + 1) begin
            @(posedge clk); #0.5;
            ext_we = 1'b1;
            ext_addr = j[7:0];
            ext_din = tv_ntt[base + j];
        end
        @(posedge clk); #0.5;
        ext_we = 1'b0;
    end
    endtask

    task load_from_result_buf();
    begin
        integer j;
        for (j = 0; j < 256; j = j + 1) begin
            @(posedge clk); #0.5;
            ext_we = 1'b1;
            ext_addr = j[7:0];
            ext_din = ntt_result_buf[j];
        end
        @(posedge clk); #0.5;
        ext_we = 1'b0;
    end
    endtask

    task read_to_result_buf();
    begin
        integer j;
        for (j = 0; j < 256; j = j + 1) begin
            @(posedge clk); #0.5;
            ext_addr = j[7:0];
            #0.5;
            result_buf[j] = ext_dout;
        end
    end
    endtask

    task run_ntt_pass(input integer idx, input int report_fd);
    begin
        integer mismatch_count;
        integer base;
        integer j;
        logic pass;

        base = idx * 256;
        mismatch_count = 0;
        timeout_flag = 1'b0;

        @(posedge clk); #0.5;
        rst_n = 1'b0; start = 1'b0; mode = 1'b0;
        ext_we = 1'b0; ext_addr = 8'd0; ext_din = 12'd0;
        repeat (5) @(posedge clk); #0.5;
        rst_n = 1'b1;
        repeat (2) @(posedge clk); #0.5;

        load_from_tv_poly(base);

        @(posedge clk); #0.5; start = 1'b1;
        cycle_cnt = 0;
        @(posedge clk); #0.5; start = 1'b0;

        fork : ntt_wait
            begin
                while (!done) begin
                    @(posedge clk);
                    cycle_cnt = cycle_cnt + 1;
                end
                disable ntt_wait;
            end
            begin
                repeat (TIMEOUT_CYCLES) @(posedge clk);
                timeout_flag = 1'b1;
                disable ntt_wait;
            end
        join

        pass = 1'b1;

        if (timeout_flag) begin
            $display("[%0t] FAIL: Case %0d - NTT TIMEOUT", $time, idx + 1);
            if (report_fd != 0)
                $fwrite(report_fd, "Case %0d | FAIL (TIMEOUT)\n", idx + 1);
            pass = 1'b0;
        end else begin
            $display("  NTT done in %0d cycles", cycle_cnt);
            if ((cycle_cnt != EXPECTED_NTT_CYCLES) || (issue_count != EXPECTED_NTT_ISSUES)) begin
                $display("[%0t] FAIL: Case %0d - NTT timing exp=%0d/%0d got=%0d/%0d",
                         $time, idx + 1, EXPECTED_NTT_CYCLES, EXPECTED_NTT_ISSUES,
                         cycle_cnt, issue_count);
                if (report_fd != 0)
                    $fwrite(report_fd, "  timing exp=%0d/%0d got=%0d/%0d\n",
                            EXPECTED_NTT_CYCLES, EXPECTED_NTT_ISSUES, cycle_cnt, issue_count);
                pass = 1'b0;
            end
            read_to_result_buf();

            for (j = 0; j < 256; j = j + 1) begin
                if (result_buf[j] !== tv_ntt[base + j]) begin
                    if (mismatch_count < 10)
                        $display("[%0t] FAIL: Case %0d - NTT coeff[%0d] exp=%03h got=%03h",
                                 $time, idx + 1, j, tv_ntt[base + j], result_buf[j]);
                    if (report_fd != 0)
                        $fwrite(report_fd, "  coeff[%0d] exp=%03h got=%03h\n",
                                j, tv_ntt[base + j], result_buf[j]);
                    mismatch_count = mismatch_count + 1;
                    pass = 1'b0;
                end
            end

            if (report_fd != 0) begin
                if (pass)
                    $fwrite(report_fd, "Case %0d | PASS (%0d cycles)\n", idx + 1, cycle_cnt);
                else
                    $fwrite(report_fd, "Case %0d | FAIL (%0d mismatches)\n", idx + 1, mismatch_count);
            end

            if (mismatch_count > 10)
                $display("[%0t] ... and %0d more mismatches (Case %0d NTT)",
                         $time, mismatch_count - 10, idx + 1);
        end

        if (!pass) ntt_error_count = ntt_error_count + 1;
    end
    endtask

    task run_intt_pass(input integer idx, input int report_fd);
    begin
        integer mismatch_count;
        integer base;
        integer j;
        logic pass;

        base = idx * 256;
        mismatch_count = 0;
        timeout_flag = 1'b0;

        @(posedge clk); #0.5;
        rst_n = 1'b0; start = 1'b0; mode = 1'b1;
        ext_we = 1'b0; ext_addr = 8'd0; ext_din = 12'd0;
        repeat (5) @(posedge clk); #0.5;
        rst_n = 1'b1;
        repeat (2) @(posedge clk); #0.5;

        load_from_tv_ntt(base);

        @(posedge clk); #0.5; start = 1'b1;
        cycle_cnt = 0;
        @(posedge clk); #0.5; start = 1'b0;

        fork : intt_wait
            begin
                while (!done) begin
                    @(posedge clk);
                    cycle_cnt = cycle_cnt + 1;
                end
                disable intt_wait;
            end
            begin
                repeat (TIMEOUT_CYCLES) @(posedge clk);
                timeout_flag = 1'b1;
                disable intt_wait;
            end
        join

        pass = 1'b1;

        if (timeout_flag) begin
            $display("[%0t] FAIL: Case %0d - INTT TIMEOUT", $time, idx + 1);
            if (report_fd != 0)
                $fwrite(report_fd, "Case %0d | FAIL (TIMEOUT)\n", idx + 1);
            pass = 1'b0;
        end else begin
            $display("  INTT done in %0d cycles", cycle_cnt);
            if ((cycle_cnt != EXPECTED_INTT_CYCLES) || (issue_count != EXPECTED_INTT_ISSUES)) begin
                $display("[%0t] FAIL: Case %0d - INTT timing exp=%0d/%0d got=%0d/%0d",
                         $time, idx + 1, EXPECTED_INTT_CYCLES, EXPECTED_INTT_ISSUES,
                         cycle_cnt, issue_count);
                if (report_fd != 0)
                    $fwrite(report_fd, "  timing exp=%0d/%0d got=%0d/%0d\n",
                            EXPECTED_INTT_CYCLES, EXPECTED_INTT_ISSUES, cycle_cnt, issue_count);
                pass = 1'b0;
            end
            read_to_result_buf();

            for (j = 0; j < 256; j = j + 1) begin
                if (result_buf[j] !== tv_intt[base + j]) begin
                    if (mismatch_count < 10)
                        $display("[%0t] FAIL: Case %0d - INTT coeff[%0d] exp=%03h got=%03h",
                                 $time, idx + 1, j, tv_intt[base + j], result_buf[j]);
                    if (report_fd != 0)
                        $fwrite(report_fd, "  coeff[%0d] exp=%03h got=%03h\n",
                                j, tv_intt[base + j], result_buf[j]);
                    mismatch_count = mismatch_count + 1;
                    pass = 1'b0;
                end
            end

            if (report_fd != 0) begin
                if (pass)
                    $fwrite(report_fd, "Case %0d | PASS (%0d cycles)\n", idx + 1, cycle_cnt);
                else
                    $fwrite(report_fd, "Case %0d | FAIL (%0d mismatches)\n", idx + 1, mismatch_count);
            end

            if (mismatch_count > 10)
                $display("[%0t] ... and %0d more mismatches (Case %0d INTT)",
                         $time, mismatch_count - 10, idx + 1);
        end

        if (!pass) intt_error_count = intt_error_count + 1;
    end
    endtask

    task run_roundtrip_test(input integer idx);
    begin
        logic pass;
        integer mismatch_count;
        integer base;
        integer j;

        base = idx * 256;

        @(posedge clk); #0.5;
        rst_n = 1'b0; start = 1'b0; mode = 1'b0;
        ext_we = 1'b0; ext_addr = 8'd0; ext_din = 12'd0;
        repeat (5) @(posedge clk); #0.5;
        rst_n = 1'b1;
        repeat (2) @(posedge clk); #0.5;

        load_from_tv_poly(base);
        @(posedge clk); #0.5; start = 1'b1;
        @(posedge clk); #0.5; start = 1'b0;
        wait_for_done();
        if (timeout_flag) begin
            $display("[%0t] ROUNDTRIP FAIL: Case %0d - NTT timeout", $time, idx + 1);
            roundtrip_error_count = roundtrip_error_count + 1;
            return;
        end
        read_to_result_buf();
        for (j = 0; j < 256; j = j + 1)
            ntt_result_buf[j] = result_buf[j];

        @(posedge clk); #0.5;
        rst_n = 1'b0; mode = 1'b1;
        repeat (5) @(posedge clk); #0.5;
        rst_n = 1'b1;
        repeat (2) @(posedge clk); #0.5;

        load_from_result_buf();
        @(posedge clk); #0.5; start = 1'b1;
        @(posedge clk); #0.5; start = 1'b0;
        wait_for_done();
        if (timeout_flag) begin
            $display("[%0t] ROUNDTRIP FAIL: Case %0d - INTT timeout", $time, idx + 1);
            roundtrip_error_count = roundtrip_error_count + 1;
            return;
        end
        read_to_result_buf();

        pass = 1'b1;
        mismatch_count = 0;
        for (j = 0; j < 256; j = j + 1) begin
            if (result_buf[j] !== tv_intt[base + j]) begin
                if (mismatch_count < 5)
                    $display("[%0t] ROUNDTRIP FAIL: Case %0d coeff[%0d] exp=%03h got=%03h",
                             $time, idx + 1, j, tv_intt[base + j], result_buf[j]);
                mismatch_count = mismatch_count + 1;
                pass = 1'b0;
            end
        end
        if (!pass) roundtrip_error_count = roundtrip_error_count + 1;
    end
    endtask

    task run_protocol_tests();
    begin
        integer base;
        integer j;
        integer wait_cycles;
        integer mismatch_count;
        logic [11:0] coeff0_before;

        base = (tv_count_actual > 3) ? (3 * 256) : 0;
        mismatch_count = 0;

        @(posedge clk); #0.5;
        rst_n = 1'b0; start = 1'b0; mode = 1'b0;
        ext_we = 1'b0; ext_addr = 8'd0; ext_din = 12'd0;
        repeat (5) @(posedge clk); #0.5;
        rst_n = 1'b1;
        repeat (2) @(posedge clk); #0.5;

        load_from_tv_poly(base);
        @(posedge clk); #0.5; start = 1'b1; mode = 1'b0;

        wait_cycles = 0;
        while (!done && (wait_cycles < TIMEOUT_CYCLES)) begin
            @(posedge clk); #0.5;
            mode = ~mode;
            wait_cycles = wait_cycles + 1;
        end

        if (!done || busy) begin
            $display("[%0t] FAIL: Protocol held-start/mode test", $time);
            protocol_error_count = protocol_error_count + 1;
        end

        start = 1'b0;
        mode = 1'b0;
        read_to_result_buf();

        for (j = 0; j < 256; j = j + 1) begin
            if (result_buf[j] !== tv_ntt[base + j])
                mismatch_count = mismatch_count + 1;
        end

        if (mismatch_count != 0) begin
            $display("[%0t] FAIL: Protocol mode latch (%0d mismatches)", $time, mismatch_count);
            protocol_error_count = protocol_error_count + 1;
        end

        repeat (8) begin
            @(posedge clk); #0.5;
            if (busy || done) begin
                $display("[%0t] FAIL: Protocol held-start restart", $time);
                protocol_error_count = protocol_error_count + 1;
            end
        end

        load_from_tv_ntt(base);
        @(posedge clk); #0.5; start = 1'b1; mode = 1'b1;
        @(posedge clk); #0.5; start = 1'b0;
        repeat (8) @(posedge clk); #0.5;
        start = 1'b1;
        mode = 1'b0;
        @(posedge clk); #0.5; start = 1'b0;

        wait_cycles = 0;
        while (!done && (wait_cycles < TIMEOUT_CYCLES)) begin
            @(posedge clk); #0.5;
            wait_cycles = wait_cycles + 1;
        end

        if (!done || busy) begin
            $display("[%0t] FAIL: Protocol start-while-busy test", $time);
            protocol_error_count = protocol_error_count + 1;
        end

        ext_addr = 8'd0;
        #0.5;
        coeff0_before = ext_dout;
        if (coeff0_before !== tv_intt[base]) begin
            $display("[%0t] FAIL: Protocol done-cycle read", $time);
            protocol_error_count = protocol_error_count + 1;
        end

        ext_we = 1'b1;
        ext_din = 12'h123;
        @(posedge clk); #0.5;
        ext_we = 1'b0;
        ext_addr = 8'd0;
        #0.5;
        if (ext_dout !== 12'h123) begin
            $display("[%0t] FAIL: Protocol done-cycle write", $time);
            protocol_error_count = protocol_error_count + 1;
        end

        mismatch_count = 0;
        for (j = 1; j < 256; j = j + 1) begin
            @(posedge clk); #0.5;
            ext_addr = j[7:0];
            #0.5;
            if (ext_dout !== tv_intt[base + j])
                mismatch_count = mismatch_count + 1;
        end

        if (mismatch_count != 0) begin
            $display("[%0t] FAIL: Protocol back-to-back INTT (%0d mismatches)", $time, mismatch_count);
            protocol_error_count = protocol_error_count + 1;
        end
    end
    endtask

    task run_one_case(input integer idx);
    begin
        run_ntt_pass(idx, ntt_report_fd);
        run_intt_pass(idx, intt_report_fd);
        run_roundtrip_test(idx);
        repeat (2) @(posedge clk);
    end
    endtask

    initial begin
        tb_file = `__FILE__;
        tb_dir = dirname(tb_file);
        tv_dir = {dirname(tb_dir), "/vector"};
        ntt_report_path = {tb_dir, "/ntt_result.log"};
        intt_report_path = {tb_dir, "/intt_result.log"};

        ntt_error_count = 0;
        intt_error_count = 0;
        roundtrip_error_count = 0;
        protocol_error_count = 0;
        timeout_flag = 0;
        issue_count = 0;
        rst_n = 0; start = 0; mode = 0; ext_we = 0; ext_addr = 0; ext_din = 0;

        ntt_report_fd = $fopen(ntt_report_path, "w");
        intt_report_fd = $fopen(intt_report_path, "w");
        spec_fd = $fopen({tv_dir, "/tv_spec.txt"}, "r");

        if (spec_fd == 0) begin
            $display("ERROR: Cannot open %s/tv_spec.txt", tv_dir);
            $finish;
        end

        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "tv_count=%d", tv_count_actual));
        $fclose(spec_fd);

        if (tv_count_actual > MAX_TV) begin
            $display("ERROR: tv_count=%0d exceeds MAX_TV=%0d", tv_count_actual, MAX_TV);
            $finish;
        end

        $readmemh({tv_dir, "/tv_poly.mem"}, tv_poly, 0, (tv_count_actual * 256) - 1);
        $readmemh({tv_dir, "/tv_ntt.mem"}, tv_ntt, 0, (tv_count_actual * 256) - 1);
        $readmemh({tv_dir, "/tv_intt.mem"}, tv_intt, 0, (tv_count_actual * 256) - 1);
        $display("NTT/INTT Core Testbench - %0d test vectors loaded", tv_count_actual);

        #100;
        @(posedge clk); #0.5; rst_n = 1'b1;
        repeat (5) @(posedge clk);

        for (case_idx = 0; case_idx < tv_count_actual; case_idx++) begin
            $display("Case %0d / %0d", case_idx + 1, tv_count_actual);
            run_one_case(case_idx);
        end

        run_protocol_tests();

        $display(">>> NTT PASSED: %0d/%0d CASES (%0d ERRORS)",
                tv_count_actual - ntt_error_count, tv_count_actual, ntt_error_count);
        $display(">>> INTT PASSED: %0d/%0d CASES (%0d ERRORS)",
                tv_count_actual - intt_error_count, tv_count_actual, intt_error_count);
        $display(">>> ROUNDTRIP: %0d/%0d CASES (%0d ERRORS)",
                tv_count_actual - roundtrip_error_count, tv_count_actual, roundtrip_error_count);
        $display(">>> PROTOCOL: %s (%0d ERRORS)",
                (protocol_error_count == 0) ? "PASS" : "FAIL", protocol_error_count);

        if (ntt_error_count == 0 && intt_error_count == 0 &&
            roundtrip_error_count == 0 && protocol_error_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        if (ntt_report_fd != 0) $fclose(ntt_report_fd);
        if (intt_report_fd != 0) $fclose(intt_report_fd);
        #100;
        $finish;
    end

endmodule
