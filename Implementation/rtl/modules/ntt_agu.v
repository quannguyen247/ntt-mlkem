`timescale 1ns / 1ps
`include "ntt_defs.vh"

(* use_dsp = "no" *) module ntt_agu (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [7:0] len,
    input wire [7:0] pos,
    input wire [7:0] block_idx,
    output reg [7:0] addr_a,
    output reg [7:0] addr_b
);

    // Block base = block_idx * (2 * len), low 8 bits. len is a power of two,
    // so the product is a shift selected by the set bit of len (a one-hot
    // mux instead of a multiplier). len = 128 shifts everything out.
    reg [7:0] block_base;
    integer i;

    always @(*) begin
        block_base = 8'd0;
        for (i = 0; i < 7; i = i + 1) begin
            if (len[i]) begin
                block_base = block_base | (block_idx << (i + 1));
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            addr_a <= 8'd0;
            addr_b <= 8'd0;
        end else begin
            if (start) begin
                addr_a <= block_base + pos;
                addr_b <= block_base + pos + len;
            end
        end
    end

endmodule
