`timescale 1ns / 1ps

module ntt_core_axi_lite #(
    parameter integer C_S_AXI_ADDR_WIDTH = 12,
    parameter integer C_S_AXI_DATA_WIDTH = 32
) (
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output wire                              s_axi_awready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output wire                              s_axi_wready,

    output reg  [1:0]                        s_axi_bresp,
    output reg                               s_axi_bvalid,
    input  wire                              s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output wire                              s_axi_arready,

    output reg  [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                        s_axi_rresp,
    output reg                               s_axi_rvalid,
    input  wire                              s_axi_rready,

    output wire                              irq
);

    localparam [1:0] AXI_OKAY   = 2'b00;
    localparam [1:0] AXI_SLVERR = 2'b10;
    localparam [1:0] AXI_DECERR = 2'b11;

    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONTROL = 12'h000;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_STATUS  = 12'h004;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CLEAR   = 12'h008;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_COEFF0  = 12'h400;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_COEFFN  = 12'h7fc;

    reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_reg;
    reg [C_S_AXI_DATA_WIDTH-1:0] wdata_reg;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_reg;
    reg aw_pending;
    reg w_pending;

    reg [C_S_AXI_ADDR_WIDTH-1:0] araddr_reg;
    reg read_pending;

    reg mode_reg;
    reg done_sticky;
    reg core_start;
    reg core_ext_we;
    reg [7:0] core_ext_wr_addr;
    reg [7:0] core_ext_rd_addr;
    wire [7:0] core_ext_addr;
    reg [11:0] core_ext_din;
    wire [11:0] core_ext_dout;
    wire core_busy;
    wire core_done;

    wire unused_prot = ^{s_axi_awprot, s_axi_arprot};
    wire write_execute = aw_pending && w_pending && !s_axi_bvalid;
    wire coeff_write_addr = (awaddr_reg >= ADDR_COEFF0) &&
                            (awaddr_reg <= ADDR_COEFFN);
    wire coeff_read_addr = (araddr_reg >= ADDR_COEFF0) &&
                           (araddr_reg <= ADDR_COEFFN);

    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !read_pending && !s_axi_rvalid;
    assign irq = done_sticky;
    assign core_ext_addr = core_ext_we ? core_ext_wr_addr : core_ext_rd_addr;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            awaddr_reg <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            wdata_reg <= {C_S_AXI_DATA_WIDTH{1'b0}};
            wstrb_reg <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
            aw_pending <= 1'b0;
            w_pending <= 1'b0;
            s_axi_bresp <= AXI_OKAY;
            s_axi_bvalid <= 1'b0;
            mode_reg <= 1'b0;
            done_sticky <= 1'b0;
            core_start <= 1'b0;
            core_ext_we <= 1'b0;
            core_ext_wr_addr <= 8'd0;
            core_ext_din <= 12'd0;
        end else begin
            core_start <= 1'b0;
            core_ext_we <= 1'b0;

            if (core_done)
                done_sticky <= 1'b1;

            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_reg <= s_axi_awaddr;
                aw_pending <= 1'b1;
            end

            if (s_axi_wvalid && s_axi_wready) begin
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
                w_pending <= 1'b1;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (write_execute) begin
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= AXI_OKAY;

                if (awaddr_reg[1:0] != 2'b00) begin
                    s_axi_bresp <= AXI_DECERR;
                end else if (awaddr_reg == ADDR_CONTROL) begin
                    if (wstrb_reg[0]) begin
                        mode_reg <= wdata_reg[1];
                        if (wdata_reg[0]) begin
                            if (core_busy) begin
                                s_axi_bresp <= AXI_SLVERR;
                            end else begin
                                core_start <= 1'b1;
                                done_sticky <= 1'b0;
                            end
                        end
                    end
                end else if (awaddr_reg == ADDR_CLEAR) begin
                    if (wstrb_reg[0] && wdata_reg[0])
                        done_sticky <= 1'b0;
                end else if (awaddr_reg == ADDR_STATUS) begin
                    s_axi_bresp <= AXI_SLVERR;
                end else if (coeff_write_addr) begin
                    if (core_busy || (wstrb_reg[1:0] != 2'b11)) begin
                        s_axi_bresp <= AXI_SLVERR;
                    end else begin
                        core_ext_wr_addr <= awaddr_reg[9:2];
                        core_ext_din <= wdata_reg[11:0];
                        core_ext_we <= 1'b1;
                    end
                end else begin
                    s_axi_bresp <= AXI_DECERR;
                end
            end
        end
    end

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            araddr_reg <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            core_ext_rd_addr <= 8'd0;
            read_pending <= 1'b0;
            s_axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
            s_axi_rresp <= AXI_OKAY;
            s_axi_rvalid <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                araddr_reg <= s_axi_araddr;
                read_pending <= 1'b1;
                if ((s_axi_araddr >= ADDR_COEFF0) &&
                    (s_axi_araddr <= ADDR_COEFFN))
                    core_ext_rd_addr <= s_axi_araddr[9:2];
            end

            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            if (read_pending && !s_axi_rvalid) begin
                read_pending <= 1'b0;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= AXI_OKAY;
                s_axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};

                if (araddr_reg[1:0] != 2'b00) begin
                    s_axi_rresp <= AXI_DECERR;
                end else if (araddr_reg == ADDR_CONTROL) begin
                    s_axi_rdata <= {{(C_S_AXI_DATA_WIDTH-2){1'b0}}, mode_reg, 1'b0};
                end else if (araddr_reg == ADDR_STATUS) begin
                    s_axi_rdata <= {{(C_S_AXI_DATA_WIDTH-2){1'b0}},
                                    done_sticky, core_busy};
                end else if (araddr_reg == ADDR_CLEAR) begin
                    s_axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
                end else if (coeff_read_addr) begin
                    if (core_busy)
                        s_axi_rresp <= AXI_SLVERR;
                    else
                        s_axi_rdata <= {{(C_S_AXI_DATA_WIDTH-12){1'b0}},
                                       core_ext_dout};
                end else begin
                    s_axi_rresp <= AXI_DECERR;
                end
            end
        end
    end

    ntt_core_top u_core (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .start(core_start),
        .mode(mode_reg),
        .ext_we(core_ext_we),
        .ext_addr(core_ext_addr),
        .ext_din(core_ext_din),
        .ext_dout(core_ext_dout),
        .busy(core_busy),
        .done(core_done)
    );

endmodule
