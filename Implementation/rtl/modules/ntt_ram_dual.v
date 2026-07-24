`timescale 1ns / 1ps
`include "ntt_defs.vh"

module ntt_ram_dual #(
    parameter DEPTH = 256,
    parameter ADDR_WIDTH = 8
)(
    input wire clk,
    input wire we0,
    input wire [ADDR_WIDTH-1:0] addr_wr0,
    input wire [11:0] din0,
    input wire we1,
    input wire [ADDR_WIDTH-1:0] addr_wr1,
    input wire [11:0] din1,
    input wire [ADDR_WIDTH-1:0] addr_rd0,
    input wire [ADDR_WIDTH-1:0] addr_rd1,
    output wire [11:0] dout0,
    output wire [11:0] dout1
);

    reg [11:0] bank0 [0:127];
    reg [11:0] bank1 [0:127];

    wire bank_wr0 = ^addr_wr0;
    wire bank_wr1 = ^addr_wr1;

    wire bank_rd0 = ^addr_rd0;
    wire bank_rd1 = ^addr_rd1;

    wire write_to_bank0 = (we0 && (bank_wr0 == 1'b0)) || (we1 && (bank_wr1 == 1'b0));
    wire [6:0] addr_wr_bank0 = (we0 && (bank_wr0 == 1'b0)) ? addr_wr0[6:0] : addr_wr1[6:0];
    wire [11:0] din_bank0 = (we0 && (bank_wr0 == 1'b0)) ? din0 : din1;

    wire write_to_bank1 = (we0 && (bank_wr0 == 1'b1)) || (we1 && (bank_wr1 == 1'b1));
    wire [6:0] addr_wr_bank1 = (we0 && (bank_wr0 == 1'b1)) ? addr_wr0[6:0] : addr_wr1[6:0];
    wire [11:0] din_bank1 = (we0 && (bank_wr0 == 1'b1)) ? din0 : din1;

    always @(posedge clk) begin
        if (write_to_bank0) begin
            bank0[addr_wr_bank0] <= din_bank0;
        end
    end

    always @(posedge clk) begin
        if (write_to_bank1) begin
            bank1[addr_wr_bank1] <= din_bank1;
        end
    end

    assign dout0 = (bank_rd0 == 1'b0) ? bank0[addr_rd0[6:0]] : bank1[addr_rd0[6:0]];
    assign dout1 = (bank_rd1 == 1'b0) ? bank0[addr_rd1[6:0]] : bank1[addr_rd1[6:0]];

endmodule
