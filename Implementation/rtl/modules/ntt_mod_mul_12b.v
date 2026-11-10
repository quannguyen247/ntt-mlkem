`timescale 1ns / 1ps
`include "ntt_defs.vh"

(* use_dsp = "no" *) module ntt_mod_mul_12b (
    input wire clk,
    input wire [11:0] a_i,
    input wire [11:0] b_i,
    output reg [11:0] r_o
);

    // Stage 1: operands. b (the twiddle) comes straight from a register, so
    // its triple is formed here and the product needs no multiplier array.
    reg [11:0] a_reg, b_reg;
    reg [13:0] b3_reg;

    // Stage 2: radix-4 product, six partial products a[2j+1:2j] * b
    wire [13:0] pp0, pp1, pp2, pp3, pp4, pp5;
    wire [17:0] sum_lo;
    wire [17:0] sum_hi;
    wire [23:0] t_comb;
    reg [23:0] t_reg;

    wire [15:0] t_16;
    wire [15:0] p1_m;
    wire [15:0] p2_m;
    wire [15:0] m_comb;
    reg [15:0] m_reg;
    reg [23:0] t_reg_d1;

    wire [28:0] m_29;
    wire [28:0] p1_mq;
    wire [28:0] p2_mq;
    wire [28:0] mq_comb;
    wire [28:0] t_plus_comb;
    reg [28:0] t_plus_reg;

    wire [12:0] u_comb;
    wire [13:0] sub_val;
    wire [11:0] reduced_comb;

    // Partial product digit * b for digit = 0..3
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

    // Registered operands break the INTT subtract -> multiply path.
    // Five-cycle latency: operands, product, m, t+m*q, canonical result.
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

    // Two three-input adders, then one two-input adder
    assign sum_lo = {4'd0, pp0} + {2'd0, pp1, 2'd0} + {pp2, 4'd0};
    assign sum_hi = {4'd0, pp3} + {2'd0, pp4, 2'd0} + {pp5, 4'd0};
    assign t_comb = {6'd0, sum_lo} + {sum_hi, 6'd0};

    always @(posedge clk) begin
        t_reg <= t_comb;
    end

    assign t_16 = t_reg[15:0];
    assign p1_m = (t_16 << 12) - (t_16 << 9); // t × 4096 - t × 512 = t × 3584
    assign p2_m = (t_16 << 8)  + t_16;        // t × 256  + t × 1   = t × 257
    assign m_comb = p1_m - p2_m;              // t × 3584 - t × 257 = t × 3327

    always @(posedge clk) begin
        m_reg <= m_comb;
        t_reg_d1 <= t_reg;
    end

    assign m_29 = {13'd0, m_reg};
    assign p1_mq = (m_29 << 12) - (m_29 << 9); // m × 4096 - m × 512 = m × 3584
    assign p2_mq = (m_29 << 8)  - m_29;        // m × 256  - m × 1   = m × 255
    assign mq_comb = p1_mq - p2_mq;            // m × 3584 - m × 255 = m × 3329
    assign t_plus_comb = {5'd0, t_reg_d1} + mq_comb;

    always @(posedge clk) begin
        t_plus_reg <= t_plus_comb;
    end

    assign u_comb = t_plus_reg[28:16];
    assign sub_val = {1'b0, u_comb} - 14'd3329;
    assign reduced_comb = sub_val[13] ? u_comb[11:0] : sub_val[11:0];

    always @(posedge clk) begin
        r_o <= reduced_comb;
    end

endmodule
