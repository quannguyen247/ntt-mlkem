`timescale 1ns / 1ps
`include "ntt_defs.vh"

module ntt_butterfly #(
    parameter BYPASS_MODE = 0,
    parameter FAST_OUT = 0
)(
    input wire clk,
    input wire rst_n,

    // Mode control
    input wire mode,
    input wire is_scale,
    input wire bm_pass,

    // Operand inputs
    input wire [11:0] a_i,
    input wire [11:0] b_i,
    input wire [11:0] zeta_i,
    input wire valid_i,

    // Butterfly outputs
    output reg valid_o,
    output reg [11:0] out0,
    output reg [11:0] out1
);

    `include "ntt_funcs.vh"

    // Stage 1 registers
    reg [11:0] a_st1;
    reg [11:0] b_st1;
    reg [11:0] zeta_st1;
    reg valid_st1;
    reg mode_st1;
    reg is_scale_st1;
    reg bm_pass_st1;

    // Delay pipeline registers (stages 2-7)
    reg [11:0] a_st2, a_st3, a_st4, a_st5, a_st6, a_st7;
    reg [11:0] b_st2, b_st3, b_st4, b_st5, b_st6, b_st7;
    reg valid_st2, valid_st3, valid_st4, valid_st5, valid_st6, valid_st7;
    reg mode_st2, mode_st3, mode_st4, mode_st5, mode_st6, mode_st7;
    reg is_scale_st2, is_scale_st3, is_scale_st4, is_scale_st5, is_scale_st6, is_scale_st7;
    reg bm_pass_st2, bm_pass_st3, bm_pass_st4, bm_pass_st5, bm_pass_st6, bm_pass_st7;

    wire [11:0] mul_a_in = (!BYPASS_MODE && is_scale_st1) ? a_st1 :
                           (mode_st1 ? ntt_mod_sub(a_st1, b_st1) : b_st1);
    wire [11:0] mod_mul_out;

    ntt_mod_mul_12b u_mul (
        .clk(clk),
        .a_i(mul_a_in),
        .b_i(zeta_st1),
        .r_o(mod_mul_out)
    );

    // Output add/sub selection
    wire [11:0] y_st7 = mode_st7 ? b_st7 : mod_mul_out;
    wire [11:0] add0_c = FAST_OUT ? ntt_mod_add_fast(a_st7, y_st7) : ntt_mod_add(a_st7, y_st7);
    wire [11:0] sub1_c = FAST_OUT ? ntt_mod_sub_fast(a_st7, mod_mul_out) : ntt_mod_sub(a_st7, mod_mul_out);

    wire [11:0] out0_comb = (!BYPASS_MODE && is_scale_st7) ? mod_mul_out :
                            (BYPASS_MODE && (is_scale_st7 || bm_pass_st7)) ? a_st7 : add0_c;
    wire [11:0] out1_comb = is_scale_st7 ? (BYPASS_MODE ? b_st7 : 12'd0) :
                            (mode_st7 || (BYPASS_MODE && bm_pass_st7)) ? mod_mul_out : sub1_c;

    // Stage 1 input capture
    always @(posedge clk) begin
        if (!rst_n) begin
            a_st1 <= 12'd0;
            b_st1 <= 12'd0;
            zeta_st1 <= 12'd0;
            valid_st1 <= 1'b0;
            mode_st1 <= 1'b0;
            is_scale_st1 <= 1'b0;
            bm_pass_st1 <= 1'b0;
        end else begin
            if (valid_i) begin
                a_st1 <= a_i;
                b_st1 <= b_i;
                zeta_st1 <= zeta_i;
            end
            valid_st1 <= valid_i;
            mode_st1 <= mode;
            is_scale_st1 <= is_scale;
            bm_pass_st1 <= BYPASS_MODE ? bm_pass : 1'b0;
        end
    end

    // Stages 2-6 operand delay (SRL)
    always @(posedge clk) begin
        a_st2 <= a_st1; b_st2 <= b_st1;
        a_st3 <= a_st2; b_st3 <= b_st2;
        a_st4 <= a_st3; b_st4 <= b_st3;
        a_st5 <= a_st4; b_st5 <= b_st4;
        a_st6 <= a_st5; b_st6 <= b_st5;
    end

    // Stage 7 operand registers
    always @(posedge clk) begin
        if (!rst_n) begin
            a_st7 <= 12'd0;
            b_st7 <= 12'd0;
        end else begin
            a_st7 <= a_st6;
            b_st7 <= b_st6;
        end
    end

    // Stages 2-7 control delay
    always @(posedge clk) begin
        if (!rst_n) begin
            valid_st2 <= 1'b0; mode_st2 <= 1'b0; is_scale_st2 <= 1'b0; bm_pass_st2 <= 1'b0;
            valid_st3 <= 1'b0; mode_st3 <= 1'b0; is_scale_st3 <= 1'b0; bm_pass_st3 <= 1'b0;
            valid_st4 <= 1'b0; mode_st4 <= 1'b0; is_scale_st4 <= 1'b0; bm_pass_st4 <= 1'b0;
            valid_st5 <= 1'b0; mode_st5 <= 1'b0; is_scale_st5 <= 1'b0; bm_pass_st5 <= 1'b0;
            valid_st6 <= 1'b0; mode_st6 <= 1'b0; is_scale_st6 <= 1'b0; bm_pass_st6 <= 1'b0;
            valid_st7 <= 1'b0; mode_st7 <= 1'b0; is_scale_st7 <= 1'b0; bm_pass_st7 <= 1'b0;
        end else begin
            valid_st2 <= valid_st1; mode_st2 <= mode_st1; is_scale_st2 <= is_scale_st1; bm_pass_st2 <= bm_pass_st1;
            valid_st3 <= valid_st2; mode_st3 <= mode_st2; is_scale_st3 <= is_scale_st2; bm_pass_st3 <= bm_pass_st2;
            valid_st4 <= valid_st3; mode_st4 <= mode_st3; is_scale_st4 <= is_scale_st3; bm_pass_st4 <= bm_pass_st3;
            valid_st5 <= valid_st4; mode_st5 <= mode_st4; is_scale_st5 <= is_scale_st4; bm_pass_st5 <= bm_pass_st4;
            valid_st6 <= valid_st5; mode_st6 <= mode_st5; is_scale_st6 <= is_scale_st5; bm_pass_st6 <= bm_pass_st5;
            valid_st7 <= valid_st6; mode_st7 <= mode_st6; is_scale_st7 <= is_scale_st6; bm_pass_st7 <= bm_pass_st6;
        end
    end

    // Stage 8 output registers
    always @(posedge clk) begin
        if (!rst_n) begin
            valid_o <= 1'b0;
            out0 <= 12'd0;
            out1 <= 12'd0;
        end else begin
            valid_o <= valid_st7;
            out0 <= out0_comb;
            out1 <= out1_comb;
        end
    end

endmodule
