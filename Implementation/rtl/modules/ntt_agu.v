`timescale 1ns / 1ps
`include "ntt_defs.vh"

// Address arithmetic is small; reserve the DSP for the pipelined data product.
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

    always @(posedge clk) begin
        if (!rst_n) begin
            addr_a <= 8'd0;
            addr_b <= 8'd0;
        end else begin
            if (start) begin
                addr_a <= (block_idx * (len << 1)) + pos;
                addr_b <= (block_idx * (len << 1)) + pos + len;
            end
        end
    end

endmodule
