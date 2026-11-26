`timescale 1ns / 1ps
`include "ntt_defs.vh"

module ntt_twiddle_rom (
    input wire [6:0] addr,
    input wire is_inv,
    output wire [`NTT_DATA_WIDTH-1:0] d_out
);

    `include "ntt_funcs.vh"

    reg [`NTT_DATA_WIDTH-1:0] rom [0:255];
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            rom[i] = ntt_twiddle_u(i[6:0], i[7]);
        end
    end

    assign d_out = rom[{is_inv, addr}];

endmodule
