`timescale 1ns / 1ps
`include "ntt_defs.vh"

module ntt_core_top (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire mode,
    input wire ext_we,
    input wire [7:0] ext_addr,
    input wire [11:0] ext_din,
    output wire [11:0] ext_dout,
    output wire busy,
    output wire done
);

    localparam AFIFO_DEPTH = 16;

    wire [1:0] fstate;
    wire f_busy;
    wire f_done;
    wire [7:0] len;
    wire [7:0] pos;
    wire [7:0] zidx;
    wire [7:0] cnt;
    wire is_scale_now;
    wire controller_start;
    wire advance_now;
    wire operation_mode;

    wire [7:0] addr_a;
    wire [7:0] addr_b;
    wire [11:0] zeta_d;

    wire [11:0] bf_out0;
    wire [11:0] bf_out1;
    wire bf_valid_out;
    reg bf_valid_in;

    wire [11:0] mem_dout0;
    wire [11:0] mem_dout1;
    wire mem_we0;
    wire mem_we1;
    wire [7:0] mem_wr_addr0;
    wire [7:0] mem_wr_addr1;
    wire [11:0] mem_wr_data0;
    wire [11:0] mem_wr_data1;

    wire ram_we0;
    wire ram_we1;
    wire [7:0] ram_addr_wr0;
    wire [7:0] ram_addr_wr1;
    wire [7:0] ram_addr_rd0;
    wire [7:0] ram_addr_rd1;
    wire [11:0] ram_din0;
    wire [11:0] ram_din1;

    reg start_d;
    reg mode_r;
    reg [7:0] zidx_d1;
    reg is_scale_d1;
    reg [7:0] done_delay;

    wire actual_done;
    wire actual_busy;

    reg [7:0] afifo_a [0:AFIFO_DEPTH-1];
    reg [7:0] afifo_b [0:AFIFO_DEPTH-1];
    reg afifo_scale [0:AFIFO_DEPTH-1];
    reg [3:0] afifo_wptr;
    reg [3:0] afifo_rptr;

    wire [7:0] wb_addr_a;
    wire [7:0] wb_addr_b;
    wire wb_scale;

    always @(posedge clk) begin
        if (!rst_n) begin
            start_d <= 1'b0;
            mode_r <= 1'b0;
        end else begin
            start_d <= start;
            if (controller_start) begin
                mode_r <= mode;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            zidx_d1 <= 8'd0;
            is_scale_d1 <= 1'b0;
        end else begin
            zidx_d1 <= zidx;
            is_scale_d1 <= is_scale_now;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            done_delay <= 8'd0;
        end else begin
            done_delay <= {done_delay[6:0], f_done};
        end
    end

    assign actual_done = done_delay[7];
    assign actual_busy = f_busy || f_done || |done_delay[6:0];
    assign controller_start = start && !start_d && !actual_busy;
    assign advance_now = f_busy && !f_done;
    assign operation_mode = controller_start ? mode : mode_r;

    assign busy = actual_busy;
    assign done = actual_done;

    assign ram_we0 = actual_busy ? mem_we0 : ext_we;
    assign ram_addr_wr0 = actual_busy ? mem_wr_addr0 : ext_addr;
    assign ram_din0 = actual_busy ? mem_wr_data0 : ext_din;

    assign ram_we1 = actual_busy ? mem_we1 : 1'b0;
    assign ram_addr_wr1 = actual_busy ? mem_wr_addr1 : 8'd0;
    assign ram_din1 = actual_busy ? mem_wr_data1 : 12'd0;

    assign ram_addr_rd0 = actual_busy ? addr_a : ext_addr;
    assign ram_addr_rd1 = actual_busy ? addr_b : 8'd0;

    assign ext_dout = mem_dout0;
    assign is_scale_now = (fstate == 2'd2);

    ntt_controller u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(controller_start),
        .mode(operation_mode),
        .advance(advance_now),
        .state(fstate),
        .busy(f_busy),
        .done(f_done),
        .len(len),
        .pos(pos),
        .zidx(zidx),
        .cnt(cnt)
    );

    ntt_agu u_agu (
        .clk(clk),
        .rst_n(rst_n),
        .start(f_busy),
        .len(len),
        .pos(pos),
        .block_idx(zidx),
        .addr_a(addr_a),
        .addr_b(addr_b)
    );

    ntt_ram_dual #(
        .DEPTH(256),
        .ADDR_WIDTH(8)
    ) u_mem (
        .clk(clk),
        .we0(ram_we0),
        .addr_wr0(ram_addr_wr0),
        .din0(ram_din0),
        .we1(ram_we1),
        .addr_wr1(ram_addr_wr1),
        .din1(ram_din1),
        .addr_rd0(ram_addr_rd0),
        .addr_rd1(ram_addr_rd1),
        .dout0(mem_dout0),
        .dout1(mem_dout1)
    );

    ntt_twiddle_rom u_rom (
        .addr(zidx_d1[6:0]),
        .is_inv(operation_mode),
        .d_out(zeta_d)
    );

    ntt_butterfly u_bf (
        .clk(clk),
        .rst_n(rst_n),
        .mode(operation_mode),
        .is_scale(is_scale_d1),
        .a_i(mem_dout0),
        .b_i(mem_dout1),
        .zeta_i(zeta_d),
        .valid_i(bf_valid_in),
        .valid_o(bf_valid_out),
        .out0(bf_out0),
        .out1(bf_out1)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            afifo_wptr <= 0;
        end else if (bf_valid_in) begin
            afifo_a[afifo_wptr] <= addr_a;
            afifo_b[afifo_wptr] <= addr_b;
            afifo_scale[afifo_wptr] <= is_scale_d1;
            afifo_wptr <= afifo_wptr + 1;
        end
    end

    assign wb_addr_a = afifo_a[afifo_rptr];
    assign wb_addr_b = afifo_b[afifo_rptr];
    assign wb_scale = afifo_scale[afifo_rptr];

    always @(posedge clk) begin
        if (!rst_n) begin
            afifo_rptr <= 0;
        end else if (bf_valid_out) begin
            afifo_rptr <= afifo_rptr + 1;
        end
    end

    assign mem_we0 = bf_valid_out;
    assign mem_wr_addr0 = wb_addr_a;
    assign mem_wr_data0 = bf_out0;

    assign mem_we1 = bf_valid_out && !wb_scale;
    assign mem_wr_addr1 = wb_addr_b;
    assign mem_wr_data1 = bf_out1;

    always @(posedge clk) begin
        if (!rst_n) begin
            bf_valid_in <= 1'b0;
        end else begin
            bf_valid_in <= 1'b0;
            if (f_busy && !f_done) begin
                bf_valid_in <= 1'b1;
            end
        end
    end

endmodule
