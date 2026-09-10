`timescale 1ns / 1ps

module ntt_kv260_debug_bridge (
    input  wire        clk,
    input  wire        ps_resetn,
    input  wire        vio_resetn,
    input  wire        start,
    input  wire        mode,
    input  wire        ext_we,
    input  wire [7:0]  ext_addr,
    input  wire [11:0] ext_din,
    output wire [11:0] ext_dout,
    output wire        busy,
    output wire        done,
    output reg         done_sticky
);

    wire core_resetn;

    assign core_resetn = ps_resetn && vio_resetn;

    ntt_core_top u_ntt_core (
        .clk(clk),
        .rst_n(core_resetn),
        .start(start),
        .mode(mode),
        .ext_we(ext_we),
        .ext_addr(ext_addr),
        .ext_din(ext_din),
        .ext_dout(ext_dout),
        .busy(busy),
        .done(done)
    );

    always @(posedge clk) begin
        if (!core_resetn)
            done_sticky <= 1'b0;
        else if (done)
            done_sticky <= 1'b1;
    end

endmodule
