`timescale 1ns / 1ps

module tb_ntt_core_top;

    localparam integer CLK_PERIOD_NS = 4;
    localparam integer TIMEOUT_CYCLES = 10000;
    localparam integer MAX_BUFFER = 1024;
    localparam integer Q = 3329;

    typedef struct packed {
        logic [255:0][11:0] intt;
        logic [255:0][11:0] ntt;
        logic [255:0][11:0] poly;
    } test_vector_t;

    logic clk;
    logic rst_n;
    logic start;
    logic [1:0] op_mode;
    logic scale_kg;
    logic stream_out;

    logic bm_valid;
    logic bm_acc;
    logic [5:0] bm_m;
    logic bm_odd;
    logic [11:0] bm_a0, bm_a1, bm_b0, bm_b1;
    logic bm_busy;

    logic stream_v;
    logic [5:0] stream_idx;
    logic [47:0] stream_data;

    logic ext_we;
    logic [5:0] ext_waddr;
    logic [47:0] ext_din;
    logic [5:0] ext_raddr;
    logic [47:0] ext_dout;

    logic busy;
    logic done;

    test_vector_t vec_all [0:MAX_BUFFER-1];
    logic [639:0] line_buffer;

    int tv_count_actual;
    int case_idx;
    int ntt_error_count;
    int intt_error_count;
    int roundtrip_error_count;
    int extra_error_count;
    int ntt_report_fd;
    int intt_report_fd;
    int spec_fd;
    logic timeout_flag;

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

    function automatic logic [11:0] fqmul_ref(input logic [11:0] a, input logic [11:0] b);
        int prod;
        int m;
        int u;
        begin
            prod = a * b;
            m = (prod * 3327) & 16'hFFFF;
            u = (prod + m * Q) >> 16;
            if (u >= Q)
                u -= Q;
            fqmul_ref = u[11:0];
        end
    endfunction

    ntt_core_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .op_mode(op_mode),
        .scale_kg(scale_kg),
        .stream_out(stream_out),
        .bm_valid(bm_valid),
        .bm_acc(bm_acc),
        .bm_m(bm_m),
        .bm_odd(bm_odd),
        .bm_a0(bm_a0),
        .bm_a1(bm_a1),
        .bm_b0(bm_b0),
        .bm_b1(bm_b1),
        .bm_busy(bm_busy),
        .stream_v(stream_v),
        .stream_idx(stream_idx),
        .stream_data(stream_data),
        .ext_we(ext_we),
        .ext_waddr(ext_waddr),
        .ext_din(ext_din),
        .ext_raddr(ext_raddr),
        .ext_dout(ext_dout),
        .busy(busy),
        .done(done)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    task automatic reset_dut();
    begin
        @(posedge clk); #0.5;
        rst_n = 1'b0;
        start = 1'b0;
        op_mode = 2'd0;
        scale_kg = 1'b0;
        stream_out = 1'b0;
        bm_valid = 1'b0;
        bm_acc = 1'b0;
        bm_m = 6'd0;
        bm_odd = 1'b0;
        bm_a0 = 12'd0;
        bm_a1 = 12'd0;
        bm_b0 = 12'd0;
        bm_b1 = 12'd0;
        ext_we = 1'b0;
        ext_waddr = 6'd0;
        ext_din = 48'd0;
        ext_raddr = 6'd0;
        repeat (5) @(posedge clk); #0.5;
        rst_n = 1'b1;
        repeat (2) @(posedge clk); #0.5;
    end
    endtask

    task automatic load_polynomial(input logic [255:0][11:0] poly);
    begin
        for (int g = 0; g < 64; g++) begin
            @(posedge clk); #0.5;
            ext_we = 1'b1;
            ext_waddr = g[5:0];
            ext_din = {poly[4*g + 3], poly[4*g + 2], poly[4*g + 1], poly[4*g + 0]};
        end
        @(posedge clk); #0.5;
        ext_we = 1'b0;
        repeat (2) @(posedge clk); #0.5;
    end
    endtask

    task automatic read_polynomial(output logic [255:0][11:0] poly);
    begin
        for (int g = 0; g < 64; g++) begin
            @(posedge clk); #0.5;
            ext_raddr = g[5:0];
            @(posedge clk); #0.5;
            poly[4*g + 0] = ext_dout[11:0];
            poly[4*g + 1] = ext_dout[23:12];
            poly[4*g + 2] = ext_dout[35:24];
            poly[4*g + 3] = ext_dout[47:36];
        end
    end
    endtask

    task automatic run_op(
        input logic [1:0] mode_i,
        input logic scale_kg_i,
        input logic stream_out_i,
        output logic [255:0][11:0] stream_poly,
        output int stream_cnt
    );
    begin
        int cyc;
        stream_cnt = 0;
        timeout_flag = 1'b0;

        @(posedge clk); #0.5;
        op_mode = mode_i;
        scale_kg = scale_kg_i;
        stream_out = stream_out_i;
        start = 1'b1;
        @(posedge clk); #0.5;
        start = 1'b0;

        cyc = 0;
        while (!done && cyc < TIMEOUT_CYCLES) begin
            @(posedge clk); #0.5;
            if (stream_v) begin
                stream_poly[4*stream_idx + 0] = stream_data[11:0];
                stream_poly[4*stream_idx + 1] = stream_data[23:12];
                stream_poly[4*stream_idx + 2] = stream_data[35:24];
                stream_poly[4*stream_idx + 3] = stream_data[47:36];
                stream_cnt++;
            end
            cyc++;
        end
        if (!done)
            timeout_flag = 1'b1;
        repeat (2) @(posedge clk); #0.5;
    end
    endtask

    task automatic run_pass(
        input integer idx,
        input logic [1:0] pass_mode,
        input logic [255:0][11:0] in_poly,
        input logic [255:0][11:0] exp_poly,
        output logic pass,
        input int report_fd
    );
    begin
        logic [255:0][11:0] result_poly, dummy_stream;
        string mode_str;
        int mismatch_count, scnt;

        mode_str = (pass_mode == 2'd0) ? "NTT" : "INTT";
        mismatch_count = 0;

        reset_dut();
        load_polynomial(in_poly);
        run_op(pass_mode, 1'b0, 1'b0, dummy_stream, scnt);

        pass = 1'b1;
        if (timeout_flag) begin
            $display("[%0t] FAIL: Case %0d - %s TIMEOUT", $time, idx + 1, mode_str);
            if (report_fd != 0)
                $fwrite(report_fd, "Case %0d | FAIL (TIMEOUT)\n", idx + 1);
            pass = 1'b0;
        end else begin
            read_polynomial(result_poly);
            for (int j = 0; j < 256; j++) begin
                if (result_poly[j] !== exp_poly[j]) begin
                    if (mismatch_count < 10)
                        $display("[%0t] FAIL: Case %0d - %s coeff[%0d] exp=%03h got=%03h",
                                 $time, idx + 1, mode_str, j, exp_poly[j], result_poly[j]);
                    if (report_fd != 0)
                        $fwrite(report_fd, "  coeff[%0d] exp=%03h got=%03h\n",
                                j, exp_poly[j], result_poly[j]);
                    mismatch_count++;
                    pass = 1'b0;
                end
            end
            if (report_fd != 0) begin
                if (pass)
                    $fwrite(report_fd, "Case %0d | PASS\n", idx + 1);
                else
                    $fwrite(report_fd, "Case %0d | FAIL (%0d mismatches)\n", idx + 1, mismatch_count);
            end
            if (mismatch_count > 10)
                $display("[%0t] ... and %0d more mismatches (Case %0d %s)",
                         $time, mismatch_count - 10, idx + 1, mode_str);
        end
    end
    endtask

    task automatic run_roundtrip_test(input integer idx);
    begin
        logic [255:0][11:0] intt_result, dummy_stream;
        logic pass;
        int mismatch_count, scnt;

        reset_dut();
        load_polynomial(vec_all[idx].poly);

        run_op(2'd0, 1'b0, 1'b0, dummy_stream, scnt);
        if (timeout_flag) begin
            $display("[%0t] ROUNDTRIP FAIL: Case %0d - NTT timeout", $time, idx + 1);
            roundtrip_error_count++;
            return;
        end

        run_op(2'd3, 1'b0, 1'b0, dummy_stream, scnt);
        if (timeout_flag) begin
            $display("[%0t] ROUNDTRIP FAIL: Case %0d - SCALE_INTT timeout", $time, idx + 1);
            roundtrip_error_count++;
            return;
        end

        read_polynomial(intt_result);
        pass = 1'b1;
        mismatch_count = 0;
        for (int j = 0; j < 256; j++) begin
            if (intt_result[j] !== vec_all[idx].intt[j]) begin
                if (mismatch_count < 5)
                    $display("[%0t] ROUNDTRIP FAIL: Case %0d coeff[%0d] exp=%03h got=%03h",
                             $time, idx + 1, j, vec_all[idx].intt[j], intt_result[j]);
                mismatch_count++;
                pass = 1'b0;
            end
        end
        if (!pass)
            roundtrip_error_count++;
    end
    endtask

    task automatic run_extra_modes_test();
    begin
        logic [255:0][11:0] stream_poly, ram_poly;
        int scnt;

        // 1) NTT with stream_out=1 (stream matches ntt and RAM is zeroed)
        reset_dut();
        load_polynomial(vec_all[0].poly);
        run_op(2'd0, 1'b0, 1'b1, stream_poly, scnt);
        if (timeout_flag || scnt != 64) begin
            $display("FAIL: NTT stream_out timeout=%0b scnt=%0d", timeout_flag, scnt);
            extra_error_count++;
        end
        read_polynomial(ram_poly);
        for (int j = 0; j < 256; j++) begin
            if (stream_poly[j] !== vec_all[0].ntt[j] || ram_poly[j] !== 12'd0) begin
                $display("FAIL: NTT stream_out idx=%0d strm=%03h exp=%03h ram=%03h",
                         j, stream_poly[j], vec_all[0].ntt[j], ram_poly[j]);
                extra_error_count++;
            end
        end

        // 2) Unscaled INTT (op_mode=1) followed by SCALE_ONLY (op_mode=2, scale_kg=0, stream_out=1)
        reset_dut();
        load_polynomial(vec_all[0].ntt);
        run_op(2'd1, 1'b0, 1'b0, stream_poly, scnt);
        run_op(2'd2, 1'b0, 1'b1, stream_poly, scnt);
        if (timeout_flag || scnt != 64) begin
            $display("FAIL: INTT+SCALE timeout=%0b scnt=%0d", timeout_flag, scnt);
            extra_error_count++;
        end
        for (int j = 0; j < 256; j++) begin
            if (stream_poly[j] !== vec_all[0].intt[j]) begin
                $display("FAIL: INTT+SCALE idx=%0d exp=%03h got=%03h",
                         j, vec_all[0].intt[j], stream_poly[j]);
                extra_error_count++;
            end
        end

        // 3) SCALE_ONLY with scale_kg=1 (*1353*2^-16 mod q)
        reset_dut();
        load_polynomial(vec_all[0].poly);
        run_op(2'd2, 1'b1, 1'b1, stream_poly, scnt);
        for (int j = 0; j < 256; j++) begin
            logic [11:0] exp_s;
            exp_s = fqmul_ref(vec_all[0].poly[j], 12'd1353);
            if (stream_poly[j] !== exp_s) begin
                $display("FAIL: SCALE_KG idx=%0d exp=%03h got=%03h", j, exp_s, stream_poly[j]);
                extra_error_count++;
            end
        end

        // 4) Streaming Karatsuba BaseMul (overwrite then accumulate)
        reset_dut();
        for (int pass_acc = 0; pass_acc < 2; pass_acc++) begin
            for (int m = 0; m < 64; m++) begin
                for (int odd = 0; odd < 2; odd++) begin
                    @(posedge clk); #0.5;
                    bm_valid = 1'b1;
                    bm_acc = pass_acc[0];
                    bm_m = m[5:0];
                    bm_odd = odd[0];
                    bm_a0 = vec_all[0].ntt[4*m + 2*odd + 0];
                    bm_a1 = vec_all[0].ntt[4*m + 2*odd + 1];
                    bm_b0 = vec_all[1].ntt[4*m + 2*odd + 0];
                    bm_b1 = vec_all[1].ntt[4*m + 2*odd + 1];
                end
            end
            @(posedge clk); #0.5;
            bm_valid = 1'b0;
            while (bm_busy) @(posedge clk);
            repeat (4) @(posedge clk);
        end

        read_polynomial(ram_poly);
        for (int m = 0; m < 64; m++) begin
            logic [11:0] gamma;
            gamma = u_dut.u_rom_a.rom[{1'b0, 1'b1, m[5:0]}];
            for (int odd = 0; odd < 2; odd++) begin
                logic [11:0] a0, a1, b0, b1, g_eff, p0, p1, p2, c0, c1, e0, e1;
                a0 = vec_all[0].ntt[4*m + 2*odd + 0];
                a1 = vec_all[0].ntt[4*m + 2*odd + 1];
                b0 = vec_all[1].ntt[4*m + 2*odd + 0];
                b1 = vec_all[1].ntt[4*m + 2*odd + 1];
                g_eff = odd ? (gamma == 0 ? 12'd0 : (Q - gamma)) : gamma;
                p0 = fqmul_ref(a0, b0);
                p1 = fqmul_ref(a1, b1);
                p2 = fqmul_ref(p1, g_eff);
                c0 = (p0 + p2) % Q;
                c1 = (fqmul_ref(a0, b1) + fqmul_ref(a1, b0)) % Q;
                e0 = (c0 + c0) % Q;
                e1 = (c1 + c1) % Q;
                if (ram_poly[4*m + 2*odd + 0] !== e0 || ram_poly[4*m + 2*odd + 1] !== e1) begin
                    $display("FAIL: BaseMul m=%0d odd=%0d exp=(%03h,%03h) got=(%03h,%03h)",
                             m, odd, e0, e1, ram_poly[4*m + 2*odd + 0], ram_poly[4*m + 2*odd + 1]);
                    extra_error_count++;
                end
            end
        end
    end
    endtask

    task automatic run_one_case(input integer idx);
    begin
        logic pass;

        run_pass(idx, 2'd0, vec_all[idx].poly, vec_all[idx].ntt, pass, ntt_report_fd);
        if (!pass) ntt_error_count++;

        run_pass(idx, 2'd3, vec_all[idx].ntt, vec_all[idx].intt, pass, intt_report_fd);
        if (!pass) intt_error_count++;

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
        extra_error_count = 0;
        rst_n = 1'b0;
        start = 1'b0;
        op_mode = 2'd0;
        scale_kg = 1'b0;
        stream_out = 1'b0;
        bm_valid = 1'b0;
        bm_acc = 1'b0;
        bm_m = 6'd0;
        bm_odd = 1'b0;
        bm_a0 = 12'd0;
        bm_a1 = 12'd0;
        bm_b0 = 12'd0;
        bm_b1 = 12'd0;
        ext_we = 1'b0;
        ext_waddr = 6'd0;
        ext_din = 48'd0;
        ext_raddr = 6'd0;

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

        if (tv_count_actual > MAX_BUFFER) begin
            $display("ERROR: tv_count=%0d exceeds MAX_BUFFER=%0d", tv_count_actual, MAX_BUFFER);
            $finish;
        end

        $readmemh({tv_dir, "/tv_all.mem"}, vec_all);
        $display("NTT/INTT/BaseMul 4-Butterfly Core Testbench - %0d test vectors loaded", tv_count_actual);

        #100;
        for (case_idx = 0; case_idx < tv_count_actual; case_idx++) begin
            $display("Case %0d / %0d", case_idx + 1, tv_count_actual);
            run_one_case(case_idx);
        end

        run_extra_modes_test();

        $display(">>> NTT PASSED: %0d/%0d CASES (%0d ERRORS)",
                tv_count_actual - ntt_error_count, tv_count_actual, ntt_error_count);
        $display(">>> INTT PASSED: %0d/%0d CASES (%0d ERRORS)",
                tv_count_actual - intt_error_count, tv_count_actual, intt_error_count);
        $display(">>> ROUNDTRIP: %0d/%0d CASES (%0d ERRORS)",
                tv_count_actual - roundtrip_error_count, tv_count_actual, roundtrip_error_count);
        $display(">>> STREAM / SCALE / BASEMUL ERRORS: %0d", extra_error_count);

        if (ntt_error_count == 0 && intt_error_count == 0 &&
            roundtrip_error_count == 0 && extra_error_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        if (ntt_report_fd != 0) $fclose(ntt_report_fd);
        if (intt_report_fd != 0) $fclose(intt_report_fd);
        #100;
        $finish;
    end

endmodule
