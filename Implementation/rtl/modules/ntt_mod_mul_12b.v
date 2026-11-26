`timescale 1ns / 1ps
`include "ntt_defs.vh"

module ntt_mod_mul_12b (
    input wire clk,
    input wire [11:0] a_i,
    input wire [11:0] b_i,
    output reg [11:0] r_o
);

    // Operand registers
    reg [11:0] a_reg, b_reg;
    reg [13:0] b3_reg;

    // Radix-4 partial products and sums
    wire [13:0] pp0, pp1, pp2, pp3, pp4, pp5;
    wire [17:0] sum_lo;
    wire [17:0] sum_hi;
    reg [17:0] sum_lo_reg;
    reg [17:0] sum_hi_reg;
    wire [23:0] t_comb;
    reg [23:0] t_reg;

    // Two-step 8-bit Montgomery reduction
    reg [7:0] ka [0:15];
    reg [7:0] kb [0:15];
    integer ki;
    reg [15:0] t1_reg;
    reg [11:0] t2_reg;
    wire [12:0] sub_val;
    wire [11:0] reduced_comb;

    // Radix-4 partial product digit * b
    function [13:0] radix4_pp;
        input [1:0] digit;
        input [11:0] b;
        input [13:0] b3;
        begin
            case (digit)
                2'd0: radix4_pp = 14'd0;
                2'd1: radix4_pp = {2'b00, b};
                2'd2: radix4_pp = {1'b0, b, 1'b0};
                default: radix4_pp = b3;
            endcase
        end
    endfunction

    initial begin
        for (ki = 0; ki < 16; ki = ki + 1) begin
            ka[ki] = 8'd209 - 13 * ki;
            kb[ki] = 8'd195 - 13 * ki;
        end
    end

    // Stage 1: input operands and 3b
    always @(posedge clk) begin
        a_reg <= a_i;
        b_reg <= b_i;
        b3_reg <= {2'b00, b_i} + {1'b0, b_i, 1'b0};
    end

    assign pp0 = radix4_pp(a_reg[1:0], b_reg, b3_reg);
    assign pp1 = radix4_pp(a_reg[3:2], b_reg, b3_reg);
    assign pp2 = radix4_pp(a_reg[5:4], b_reg, b3_reg);
    assign pp3 = radix4_pp(a_reg[7:6], b_reg, b3_reg);
    assign pp4 = radix4_pp(a_reg[9:8], b_reg, b3_reg);
    assign pp5 = radix4_pp(a_reg[11:10], b_reg, b3_reg);

    assign sum_lo = {4'd0, pp0} + {2'd0, pp1, 2'd0} + {pp2, 4'd0};
    assign sum_hi = {4'd0, pp3} + {2'd0, pp4, 2'd0} + {pp5, 4'd0};

    // Stage 2: partial product group sums
    always @(posedge clk) begin
        sum_lo_reg <= sum_lo;
        sum_hi_reg <= sum_hi;
    end

    assign t_comb = {6'd0, sum_lo_reg} + {sum_hi_reg, 6'd0};

    // Stage 3: 24-bit product
    always @(posedge clk) begin
        t_reg <= t_comb;
    end

    // Stages 4-5: nibble-split 8-bit Montgomery steps
    always @(posedge clk) begin
        t1_reg <= t_reg[23:8] + {8'd0, ka[t_reg[3:0]]} + {4'd0, kb[t_reg[7:4]], 4'd0};
        t2_reg <= {4'd0, t1_reg[15:8]} + {4'd0, ka[t1_reg[3:0]]} + {kb[t1_reg[7:4]], 4'd0};
    end

    assign sub_val = {1'b0, t2_reg} - 13'd3329;
    assign reduced_comb = sub_val[12] ? t2_reg : sub_val[11:0];

    // Stage 6: conditional subtraction
    always @(posedge clk) begin
        r_o <= reduced_comb;
    end

endmodule
