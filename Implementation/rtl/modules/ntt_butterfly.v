`timescale 1ns / 1ps
`include "ntt_defs.vh"

module ntt_butterfly (
    input wire clk,
    input wire rst_n,
    input wire mode,
    input wire is_scale,
    input wire [11:0] a_i,
    input wire [11:0] b_i,
    input wire [11:0] zeta_i,
    input wire valid_i,
    output reg valid_o,
    output reg [11:0] out0,
    output reg [11:0] out1
);

    `include "ntt_funcs.vh"

    reg [11:0] a_st1;
    reg [11:0] b_st1;
    reg [11:0] zeta_st1;
    reg valid_st1;
    reg is_scale_st1;

    reg [11:0] a_st2, a_st3, a_st4, a_st5;
    reg [11:0] b_st2, b_st3, b_st4, b_st5;
    reg valid_st2, valid_st3, valid_st4, valid_st5;
    reg is_scale_st2, is_scale_st3, is_scale_st4, is_scale_st5;

    wire [11:0] sub_st1;
    wire [11:0] mul_a_in;
    wire [11:0] mod_mul_out;

    wire [11:0] add_tmp;
    wire [11:0] sub_tmp;
    wire [11:0] intt_add_out;
    wire [11:0] out0_comb;
    wire [11:0] out1_comb;

    assign sub_st1 = ntt_mod_sub(a_st1, b_st1);
    assign mul_a_in = is_scale_st1 ? a_st1 : (mode ? sub_st1 : b_st1);

    ntt_mod_mul_12b u_mul (
        .clk(clk),
        .a_i(mul_a_in),
        .b_i(zeta_st1),
        .r_o(mod_mul_out)
    );

    assign add_tmp = ntt_mod_add(a_st5, mod_mul_out);
    assign sub_tmp = ntt_mod_sub(a_st5, mod_mul_out);
    assign intt_add_out = ntt_mod_add(a_st5, b_st5);
    assign out0_comb = is_scale_st5 ? mod_mul_out : (mode ? intt_add_out : add_tmp);
    assign out1_comb = is_scale_st5 ? 12'd0 : (mode ? mod_mul_out : sub_tmp);

    always @(posedge clk) begin
        if (!rst_n) begin
            a_st1 <= 12'd0;
            b_st1 <= 12'd0;
            zeta_st1 <= 12'd0;
            valid_st1 <= 1'b0;
            is_scale_st1 <= 1'b0;
        end else begin
            a_st1 <= a_i;
            b_st1 <= b_i;
            zeta_st1 <= zeta_i;
            valid_st1 <= valid_i;
            is_scale_st1 <= is_scale;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            a_st2 <= 12'd0;
            b_st2 <= 12'd0;
            valid_st2 <= 1'b0;
            is_scale_st2 <= 1'b0;

            a_st3 <= 12'd0;
            b_st3 <= 12'd0;
            valid_st3 <= 1'b0;
            is_scale_st3 <= 1'b0;

            a_st4 <= 12'd0;
            b_st4 <= 12'd0;
            valid_st4 <= 1'b0;
            is_scale_st4 <= 1'b0;

            a_st5 <= 12'd0;
            b_st5 <= 12'd0;
            valid_st5 <= 1'b0;
            is_scale_st5 <= 1'b0;
        end else begin
            a_st2 <= a_st1;
            b_st2 <= b_st1;
            valid_st2 <= valid_st1;
            is_scale_st2 <= is_scale_st1;

            a_st3 <= a_st2;
            b_st3 <= b_st2;
            valid_st3 <= valid_st2;
            is_scale_st3 <= is_scale_st2;

            a_st4 <= a_st3;
            b_st4 <= b_st3;
            valid_st4 <= valid_st3;
            is_scale_st4 <= is_scale_st3;

            a_st5 <= a_st4;
            b_st5 <= b_st4;
            valid_st5 <= valid_st4;
            is_scale_st5 <= is_scale_st4;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_o <= 1'b0;
            out0 <= 12'd0;
            out1 <= 12'd0;
        end else begin
            valid_o <= valid_st5;
            out0 <= out0_comb;
            out1 <= out1_comb;
        end
    end

endmodule
