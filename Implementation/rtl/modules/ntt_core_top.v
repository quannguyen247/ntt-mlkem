`timescale 1ns / 1ps
`include "ntt_defs.vh"

module ntt_core_top (
    input wire clk,
    input wire rst_n,

    // Pass-sequence control
    input wire start,
    input wire [1:0] op_mode,
    input wire scale_kg,
    input wire stream_out,

    // Streaming BaseMul input
    input wire bm_valid,
    input wire bm_acc,
    input wire [5:0] bm_m,
    input wire bm_odd,
    input wire [11:0] bm_a0,
    input wire [11:0] bm_a1,
    input wire [11:0] bm_b0,
    input wire [11:0] bm_b1,
    output wire bm_busy,

    // Linear stream output
    output reg stream_v,
    output reg [5:0] stream_idx,
    output reg [47:0] stream_data,

    // External group port
    input wire ext_we,
    input wire [5:0] ext_waddr,
    input wire [47:0] ext_din,
    input wire [5:0] ext_raddr,
    output reg [47:0] ext_dout,

    // Status
    output wire busy,
    output reg done
);

    `include "ntt_funcs.vh"

    localparam integer BF_LAT = 8;
    localparam integer WB_DLY_PRE = 2 * BF_LAT;

    // Bank index of coefficient address
    function [1:0] bank_of;
        input [7:0] i;
        begin
            bank_of = i[1:0] + i[3:2] + i[5:4] + i[7:6];
        end
    endfunction

    // Parallel CSA negated modular add: -(x + y) mod q
    function [11:0] neg_mod_add;
        input [11:0] x;
        input [11:0] y;
        reg [13:0] nx14, ny14, s1, c1, d1;
        reg [11:0] nx12, ny12, s2, c2, d2;
        begin
            nx14 = {2'b11, ~x};
            ny14 = {2'b11, ~y};
            s1 = nx14 ^ ny14 ^ 14'd3331;
            c1 = (nx14 & ny14) | ((nx14 | ny14) & 14'd3331);
            d1 = s1 + {c1[12:0], 1'b0};

            nx12 = ~x;
            ny12 = ~y;
            s2 = nx12 ^ ny12 ^ 12'd2564;
            c2 = (nx12 & ny12) | ((nx12 | ny12) & 12'd2564);
            d2 = s2 + {c2[10:0], 1'b0};

            neg_mod_add = ((x == 12'd0) && (y == 12'd0)) ? 12'd0 : (d1[13] ? d2 : d1[11:0]);
        end
    endfunction

    // Pass control
    reg run;
    reg [1:0] op_r;
    reg scale_kg_r;
    reg strm_r;

    reg [2:0] pass;
    reg [6:0] g;
    reg [5:0] pend;
    reg [5:0] bm_pend;
    reg bm_busy_q;
    wire issue = run && !g[6];
    wire wb_v;

    wire [2:0] pass_last = (op_r == 2'd0) ? 3'd3 :
                           (op_r == 2'd2) ? 3'd0 : 3'd4;
    wire is_scl_p = (op_r == 2'd2) || ((op_r == 2'd3) && (pass == 3'd0));
    wire is_intt_p = (op_r == 2'd1) || ((op_r == 2'd3) && (pass != 3'd0));

    reg [1:0] q;
    reg single;
    always @(*) begin
        if (is_scl_p) begin
            q = 2'd0;
            single = 1'b0;
        end else if (!is_intt_p) begin
            q = 2'd3 - pass[1:0];
            single = (pass == 3'd3);
        end else begin
            q = pass - 3'd1;
            single = (pass == 3'd1);
        end
    end

    wire is_strm_p = strm_r && (pass == pass_last) && (op_r == 2'd0 || op_r == 2'd2);
    wire gap5 = is_intt_p ? (pass == 3'd3) : (!is_scl_p && (pass == 3'd0));
    wire [6:0] g_last = gap5 ? 7'd66 : 7'd63;

    assign busy = run;
    assign bm_busy = bm_busy_q;

    reg bm_wr_q;
    wire [5:0] bm_pend_nx = bm_pend + {5'd0, bm_valid} - {5'd0, bm_wr_q};
    always @(posedge clk) begin
        if (!rst_n) begin
            run <= 1'b0;
            op_r <= 2'd0;
            scale_kg_r <= 1'b0;
            strm_r <= 1'b0;
            pass <= 3'd0;
            g <= 7'd0;
            pend <= 6'd0;
            bm_pend <= 6'd0;
            bm_busy_q <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            pend <= pend + {5'd0, issue} - {5'd0, run && wb_v};
            bm_pend <= bm_pend_nx;
            bm_busy_q <= (bm_pend_nx != 6'd0);
            if (!run) begin
                if (start) begin
                    run <= 1'b1;
                    op_r <= op_mode;
                    scale_kg_r <= scale_kg;
                    strm_r <= stream_out;
                    pass <= (op_mode == 2'd1) ? 3'd1 : 3'd0;
                    g <= 7'd0;
                end
            end else if (pass != pass_last) begin
                if (g == g_last) begin
                    pass <= pass + 3'd1;
                    g <= 7'd0;
                end else begin
                    g <= g + 7'd1;
                end
            end else if (issue) begin
                g <= g + 7'd1;
            end else if (pend == 6'd0) begin
                run <= 1'b0;
                done <= 1'b1;
            end
        end
    end

    // Group address and twiddle index generation
    reg [7:0] b_c;
    reg [5:0] hb_c;
    always @(*) begin
        case (q)
            2'd0: begin b_c = {g[5:0], 2'b00};        hb_c = g[5:0]; end
            2'd1: begin b_c = {g[5:2], 2'b00, g[1:0]}; hb_c = {2'd0, g[5:2]}; end
            2'd2: begin b_c = {g[5:4], 2'b00, g[3:0]}; hb_c = {4'd0, g[5:4]}; end
            default: begin b_c = {2'b00, g[5:0]};      hb_c = 6'd0; end
        endcase
    end

    reg [7:0] step_c;
    always @(*) begin
        case (q)
            2'd0: step_c = 8'd1;
            2'd1: step_c = 8'd4;
            2'd2: step_c = 8'd16;
            default: step_c = 8'd64;
        endcase
    end

    reg [6:0] za_c, zb_c;
    always @(*) begin
        if (!is_intt_p) begin
            za_c = (7'd64 >> (2 * q)) + {1'b0, hb_c};
            zb_c = ((q == 2'd0) ? 7'd0 : (8'd128 >> (2 * q))) + {hb_c, 1'b0};
        end else begin
            za_c = (8'd128 - (8'd128 >> (2 * q))) + {1'b0, hb_c};
            zb_c = (8'd128 - (9'd256 >> (2 * q))) + {hb_c, 1'b0};
        end
    end

    wire [1:0] r_c = bank_of(b_c);
    reg [5:0] ra_c [0:3];
    reg [1:0] el;
    reg [7:0] ei;
    integer t;
    always @(*) begin
        for (t = 0; t < 4; t = t + 1) begin
            el = t[1:0] - r_c;
            ei = b_c + el * step_c;
            ra_c[t] = ei[7:2];
        end
    end

    // Issue stage registers
    reg v1;
    reg [1:0] r1;
    reg [5:0] ra1 [0:3];
    reg [6:0] za1, zb1;
    reg single1, scl1, intt1, strm1;
    always @(posedge clk) begin
        if (!rst_n)
            v1 <= 1'b0;
        else
            v1 <= issue;
        single1 <= single;
        scl1 <= is_scl_p;
        intt1 <= is_intt_p;
        strm1 <= is_strm_p;
        r1 <= r_c;
        za1 <= za_c;
        zb1 <= zb_c;
        for (t = 0; t < 4; t = t + 1)
            ra1[t] <= ra_c[t];
    end

    // Four-bank coefficient RAM
    reg [5:0] bk_ra [0:3];
    wire [11:0] bk_rd [0:3];
    reg [3:0] bk_we;
    reg [5:0] bk_wa [0:3];
    reg [11:0] bk_wd [0:3];

    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin : g_bank
            reg [11:0] mem [0:63];
            always @(posedge clk) begin
                if (bk_we[k])
                    mem[bk_wa[k]] <= bk_wd[k];
            end
            assign bk_rd[k] = mem[bk_ra[k]];
        end
    endgenerate

    // Write-back metadata delay line
    wire [28:0] wa_in = v1 ? {scl1, strm1, intt1, r1, ra1[3], ra1[2], ra1[1], ra1[0]}
                           : {1'b0, bm_acc, bm_odd, bank_of({bm_m, 2'b00}), 18'd0, bm_m};
    wire [28:0] wa_pre;
    ntt_delay #(.W(29), .D(WB_DLY_PRE)) u_dwa (
        .clk(clk),
        .d(wa_in),
        .q(wa_pre)
    );
    reg [28:0] wa_q;
    always @(posedge clk)
        wa_q <= wa_pre;

    wire [5:0] bm_rd_m = wa_pre[5:0];
    wire [1:0] bm_rd_r = wa_pre[25:24];
    wire bm_rd_odd = wa_pre[26];

    // Bank read address mux
    wire [1:0] ext_rr = bank_of({ext_raddr, 2'b00});
    always @(*) begin
        for (t = 0; t < 4; t = t + 1)
            bk_ra[t] = v1 ? ra1[t] : bm_busy_q ? bm_rd_m : ext_raddr;
    end

    // External and BaseMul accumulate read registers
    reg [11:0] acc_rd0, acc_rd1;
    wire [1:0] bm_rd_b0 = bm_rd_r + (bm_rd_odd ? 2'd2 : 2'd0);
    wire [1:0] bm_rd_b1 = bm_rd_r + (bm_rd_odd ? 2'd3 : 2'd1);
    always @(posedge clk) begin
        for (t = 0; t < 4; t = t + 1)
            ext_dout[12*t +: 12] <= bk_rd[(ext_rr + t) % 4];
        acc_rd0 <= bk_rd[bm_rd_b0];
        acc_rd1 <= bk_rd[bm_rd_b1];
    end

    // Operand and twiddle capture
    reg v2;
    reg single2, scl2, intt2, bm2;
    reg [11:0] x2 [0:3];
    reg [12:0] sa_raw_q, sb_raw_q;
    wire [11:0] za_d, zb0_d, zb1_d;
    reg [11:0] za2, zb02, zb12;

    wire [11:0] scale_const = scale_kg_r ? 12'd1353 : 12'd1441;

    wire [6:0] rom_a_addr = v1 ? za1 : {1'b1, bm_m};
    wire rom_a_inv = v1 ? intt1 : 1'b0;
    ntt_twiddle_rom u_rom_a (
        .addr(rom_a_addr),
        .is_inv(rom_a_inv),
        .d_out(za_d)
    );

    reg [11:0] rom_b0 [0:63];
    reg [11:0] rom_b1 [0:63];
    integer ri;
    initial begin
        for (ri = 0; ri < 64; ri = ri + 1) begin
            rom_b0[ri] = ntt_twiddle_u({ri[5], ri[4:0], 1'b0}, ri[5]);
            rom_b1[ri] = ntt_twiddle_u({ri[5], ri[4:0], 1'b1}, ri[5]);
        end
    end
    assign zb0_d = rom_b0[{intt1, zb1[5:1]}];
    assign zb1_d = rom_b1[{intt1, zb1[5:1]}];

    always @(posedge clk) begin
        if (!rst_n) begin
            v2 <= 1'b0;
            bm2 <= 1'b0;
        end else begin
            v2 <= v1 || bm_valid;
            bm2 <= !v1 && bm_valid;
        end
        single2 <= v1 && single1;
        scl2 <= v1 && scl1;
        intt2 <= v1 && intt1;
        sa_raw_q <= {1'b0, bm_a0} + {1'b0, bm_a1};
        sb_raw_q <= {1'b0, bm_b0} + {1'b0, bm_b1};
        if (v1) begin
            for (t = 0; t < 4; t = t + 1)
                x2[t] <= bk_rd[(r1 + t) % 4];
            zb02 <= scl1 ? scale_const : zb0_d;
            zb12 <= scl1 ? scale_const : zb1_d;
            za2 <= scl1 ? scale_const : za_d;
        end else begin
            x2[2] <= bm_a1;
            x2[3] <= bm_a0;
            zb02 <= bm_b1;
            zb12 <= bm_b0;
            za2 <= za_d;
        end
    end

    // Karatsuba sum reduction
    wire [13:0] sa_sub = {1'b0, sa_raw_q} - 14'd3329;
    wire [13:0] sb_sub = {1'b0, sb_raw_q} - 14'd3329;
    wire [11:0] sa_red = sa_sub[13] ? sa_raw_q[11:0] : sa_sub[11:0];
    wire [11:0] sb_red = sb_sub[13] ? sb_raw_q[11:0] : sb_sub[11:0];

    // Butterfly stage 1
    wire [3:0] ctrl_s1;
    ntt_delay #(.W(4), .D(BF_LAT)) u_dsg1 (
        .clk(clk),
        .d({bm2, intt2, scl2, single2}),
        .q(ctrl_s1)
    );
    wire single_s1 = ctrl_s1[0];
    wire scl_s1 = ctrl_s1[1];
    wire intt_s1 = ctrl_s1[2];
    wire bm_s1 = ctrl_s1[3];

    wire pair_b = intt2 || scl2;
    wire [11:0] s1a_a = bm2 ? sa_red : x2[0];
    wire [11:0] s1a_b = pair_b ? x2[1] : x2[2];
    wire [11:0] s1b_a = bm2 ? sb_red : (pair_b ? x2[2] : x2[1]);
    wire [11:0] s1b_b = x2[3];
    wire [11:0] s1a_z = (intt2 || scl2 || bm2) ? zb02 : za2;
    wire [11:0] s1b_z = (intt2 || scl2 || bm2) ? zb12 : za2;
    wire s1_byp = intt2 && single2;
    wire s1_bmp = scl2 || bm2;

    wire s1a_v, s1b_v_unused;
    wire [11:0] s1a_o0, s1a_o1, s1b_o0, s1b_o1;
    ntt_butterfly #(.BYPASS_MODE(1)) u_bf1a (
        .clk(clk),
        .rst_n(rst_n),
        .mode(intt2),
        .is_scale(s1_byp),
        .bm_pass(s1_bmp),
        .a_i(s1a_a),
        .b_i(s1a_b),
        .zeta_i(s1a_z),
        .valid_i(v2),
        .valid_o(s1a_v),
        .out0(s1a_o0),
        .out1(s1a_o1)
    );
    ntt_butterfly #(.BYPASS_MODE(1)) u_bf1b (
        .clk(clk),
        .rst_n(rst_n),
        .mode(intt2),
        .is_scale(s1_byp),
        .bm_pass(s1_bmp),
        .a_i(s1b_a),
        .b_i(s1b_b),
        .zeta_i(s1b_z),
        .valid_i(v2),
        .valid_o(s1b_v_unused),
        .out0(s1b_o0),
        .out1(s1b_o1)
    );

    wire [11:0] y [0:3];
    assign y[0] = s1a_o0;
    assign y[1] = intt_s1 ? s1a_o1 : s1b_o0;
    assign y[2] = intt_s1 ? s1b_o0 : s1a_o1;
    assign y[3] = s1b_o1;

    // Stage 2 twiddle delay
    wire [23:0] z_dly;
    ntt_delay #(.W(24), .D(BF_LAT)) u_dz (
        .clk(clk),
        .d({(intt2 || scl2 || bm2) ? za2 : zb12, (intt2 || scl2 || bm2) ? za2 : zb02}),
        .q(z_dly)
    );
    wire [11:0] s2a_z = z_dly[11:0];
    wire [11:0] s2b_z = bm_s1 ? s1b_o0 : z_dly[23:12];

    // Butterfly stage 2
    wire [11:0] neg_p00_p11 = neg_mod_add(s1b_o1, s1a_o1);

    wire [11:0] s2a_a = bm_s1 ? s1b_o1 : (scl_s1 ? s1a_o1 : y[0]);
    wire [11:0] s2a_b = bm_s1 ? s1a_o1 : (scl_s1 ? s1a_o0 : (intt_s1 ? y[2] : y[1]));
    wire [11:0] s2b_a = bm_s1 ? neg_p00_p11 : (scl_s1 ? s1b_o1 : (intt_s1 ? y[1] : y[2]));
    wire [11:0] s2b_b = bm_s1 ? s1a_o0 : (scl_s1 ? s1b_o0 : y[3]);
    wire s2_byp = !intt_s1 && !scl_s1 && !bm_s1 && single_s1;
    wire s2_bmp = scl_s1;

    wire s2a_v, s2b_v_unused;
    wire [11:0] s2a_o0, s2a_o1, s2b_o0, s2b_o1;
    ntt_butterfly #(.BYPASS_MODE(1), .FAST_OUT(1)) u_bf2a (
        .clk(clk),
        .rst_n(rst_n),
        .mode(intt_s1),
        .is_scale(s2_byp),
        .bm_pass(s2_bmp),
        .a_i(s2a_a),
        .b_i(s2a_b),
        .zeta_i(s2a_z),
        .valid_i(s1a_v),
        .valid_o(s2a_v),
        .out0(s2a_o0),
        .out1(s2a_o1)
    );
    ntt_butterfly #(.BYPASS_MODE(1), .FAST_OUT(1)) u_bf2b (
        .clk(clk),
        .rst_n(rst_n),
        .mode(intt_s1),
        .is_scale(s2_byp),
        .bm_pass(s2_bmp),
        .a_i(s2b_a),
        .b_i(s2b_b),
        .zeta_i(s2b_z),
        .valid_i(s1a_v),
        .valid_o(s2b_v_unused),
        .out0(s2b_o0),
        .out1(s2b_o1)
    );

    assign wb_v = s2a_v;

    // Write-back and linear stream output
    wire [1:0] r_wb = wa_q[25:24];
    wire intt_wb = wa_q[26];
    wire strm_wb = wa_q[27];
    wire scl_wb = wa_q[28];

    wire [11:0] w [0:3];
    assign w[0] = scl_wb ? s2a_o1 : s2a_o0;
    assign w[1] = scl_wb ? s2a_o0 : (intt_wb ? s2b_o0 : s2a_o1);
    assign w[2] = scl_wb ? s2b_o1 : (intt_wb ? s2a_o1 : s2b_o0);
    assign w[3] = scl_wb ? s2b_o0 : s2b_o1;

    // BaseMul accumulate pipeline stage
    wire bm_wb_odd = wa_q[26];
    wire bm_wb_acc = wa_q[27];
    wire [5:0] bm_wb_m = wa_q[5:0];
    wire [11:0] bm_c0 = bm_wb_odd ? s2a_o1 : s2a_o0;
    wire [11:0] bm_c1 = s2b_o0;
    wire [11:0] acc0_sum = bm_wb_acc ? ntt_mod_add(acc_rd0, bm_c0) : bm_c0;
    wire [11:0] acc1_sum = bm_wb_acc ? ntt_mod_add(acc_rd1, bm_c1) : bm_c1;

    reg bm_wb_v_q;
    reg [5:0] bm_wb_m_q;
    reg [1:0] bm_wb_r_q, bm_wb_b0_q, bm_wb_b1_q;
    reg [11:0] acc0_q, acc1_q;
    always @(posedge clk) begin
        if (!rst_n)
            bm_wb_v_q <= 1'b0;
        else
            bm_wb_v_q <= !run && wb_v;
        bm_wb_m_q <= bm_wb_m;
        bm_wb_r_q <= r_wb;
        bm_wb_b0_q <= r_wb + (bm_wb_odd ? 2'd2 : 2'd0);
        bm_wb_b1_q <= r_wb + (bm_wb_odd ? 2'd3 : 2'd1);
        acc0_q <= acc0_sum;
        acc1_q <= acc1_sum;
    end

    // Bank write mux and stream output registers
    wire [1:0] ext_wr = bank_of({ext_waddr, 2'b00});
    always @(posedge clk) begin
        if (!rst_n) begin
            bk_we <= 4'd0;
            bm_wr_q <= 1'b0;
            stream_v <= 1'b0;
        end else begin
            bm_wr_q <= bm_wb_v_q;
            stream_v <= run && wb_v && strm_wb;
            if (run) begin
                bk_we <= {4{wb_v}};
            end else if (bm_wb_v_q) begin
                for (t = 0; t < 4; t = t + 1)
                    bk_we[t] <= (t[1:0] == bm_wb_b0_q) || (t[1:0] == bm_wb_b1_q);
            end else begin
                bk_we <= {4{ext_we}};
            end
        end

        stream_idx <= wa_q[5:0];
        stream_data <= {w[3], w[2], w[1], w[0]};

        for (t = 0; t < 4; t = t + 1) begin
            if (run) begin
                bk_wa[t] <= wa_q[6*t +: 6];
                bk_wd[t] <= strm_wb ? 12'd0 : w[(t + 4 - r_wb) % 4];
            end else if (bm_wb_v_q) begin
                bk_wa[t] <= bm_wb_m_q;
                bk_wd[t] <= (t[0] == bm_wb_r_q[0]) ? acc0_q : acc1_q;
            end else begin
                bk_wa[t] <= ext_waddr;
                bk_wd[t] <= ext_din[12*((t + 4 - ext_wr) % 4) +: 12];
            end
        end
    end

endmodule


module ntt_delay #(
    parameter W = 1,
    parameter D = 1
)(
    input wire clk,
    input wire [W-1:0] d,
    output wire [W-1:0] q
);

    generate
        if (D == 0) begin : g_wire
            assign q = d;
        end else begin : g_regs
            reg [W-1:0] sr [0:D-1];
            integer i;
            always @(posedge clk) begin
                sr[0] <= d;
                for (i = 1; i < D; i = i + 1)
                    sr[i] <= sr[i-1];
            end
            assign q = sr[D-1];
        end
    endgenerate

endmodule
