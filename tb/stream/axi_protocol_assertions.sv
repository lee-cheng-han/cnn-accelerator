`timescale 1ns/1ps

module axis_stream_assertions #(
  parameter int DATA_WIDTH = 32,
  parameter string NAME = "axis"
)(
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic [DATA_WIDTH-1:0] tdata,
  input  logic                  tvalid,
  input  logic                  tready,
  input  logic                  tlast,

  output int unsigned           error_count
);

  logic [DATA_WIDTH-1:0] prev_tdata;
  logic                  prev_tvalid;
  logic                  prev_tready;
  logic                  prev_tlast;

  function automatic int unsigned note_error(input string msg);
    begin
      $display("[ASSERT][%s] %s", NAME, msg);
      return 1;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prev_tdata   <= '0;
      prev_tvalid  <= 1'b0;
      prev_tready  <= 1'b0;
      prev_tlast   <= 1'b0;
      error_count  <= 0;
    end else begin
      int unsigned errors_this_cycle;

      errors_this_cycle = 0;

      if (prev_tvalid && !prev_tready) begin
        if (!tvalid) begin
          errors_this_cycle += note_error("TVALID dropped before handshake");
        end

        if (tdata !== prev_tdata) begin
          $display("[ASSERT][%s] TDATA changed while stalled: expected=0x%08x got=0x%08x",
                   NAME, prev_tdata, tdata);
          errors_this_cycle++;
        end

        if (tlast !== prev_tlast) begin
          errors_this_cycle += note_error("TLAST changed while stalled");
        end
      end

      if (errors_this_cycle != 0) begin
        error_count <= error_count + errors_this_cycle;
      end

      prev_tdata  <= tdata;
      prev_tvalid <= tvalid;
      prev_tready <= tready;
      prev_tlast  <= tlast;
    end
  end

endmodule

module axi_lite_protocol_assertions #(
  parameter int ADDR_WIDTH = 12,
  parameter int DATA_WIDTH = 32,
  parameter string NAME = "s_axi"
)(
  input  logic                    clk,
  input  logic                    rst_n,

  input  logic [ADDR_WIDTH-1:0]   awaddr,
  input  logic                    awvalid,
  input  logic                    awready,

  input  logic [DATA_WIDTH-1:0]   wdata,
  input  logic [(DATA_WIDTH/8)-1:0] wstrb,
  input  logic                    wvalid,
  input  logic                    wready,

  input  logic [1:0]              bresp,
  input  logic                    bvalid,
  input  logic                    bready,

  input  logic [ADDR_WIDTH-1:0]   araddr,
  input  logic                    arvalid,
  input  logic                    arready,

  input  logic [DATA_WIDTH-1:0]   rdata,
  input  logic [1:0]              rresp,
  input  logic                    rvalid,
  input  logic                    rready,

  output int unsigned             error_count
);

  logic [ADDR_WIDTH-1:0]     prev_awaddr;
  logic                      prev_awvalid;
  logic                      prev_awready;

  logic [DATA_WIDTH-1:0]     prev_wdata;
  logic [(DATA_WIDTH/8)-1:0] prev_wstrb;
  logic                      prev_wvalid;
  logic                      prev_wready;

  logic [1:0]                prev_bresp;
  logic                      prev_bvalid;
  logic                      prev_bready;

  logic [ADDR_WIDTH-1:0]     prev_araddr;
  logic                      prev_arvalid;
  logic                      prev_arready;

  logic [DATA_WIDTH-1:0]     prev_rdata;
  logic [1:0]                prev_rresp;
  logic                      prev_rvalid;
  logic                      prev_rready;

  function automatic int unsigned note_error(input string msg);
    begin
      $display("[ASSERT][%s] %s", NAME, msg);
      return 1;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prev_awaddr  <= '0;
      prev_awvalid <= 1'b0;
      prev_awready <= 1'b0;

      prev_wdata   <= '0;
      prev_wstrb   <= '0;
      prev_wvalid  <= 1'b0;
      prev_wready  <= 1'b0;

      prev_bresp   <= '0;
      prev_bvalid  <= 1'b0;
      prev_bready  <= 1'b0;

      prev_araddr  <= '0;
      prev_arvalid <= 1'b0;
      prev_arready <= 1'b0;

      prev_rdata   <= '0;
      prev_rresp   <= '0;
      prev_rvalid  <= 1'b0;
      prev_rready  <= 1'b0;

      error_count  <= 0;
    end else begin
      int unsigned errors_this_cycle;

      errors_this_cycle = 0;

      if (prev_awvalid && !prev_awready) begin
        if (!awvalid) errors_this_cycle += note_error("AWVALID dropped before handshake");
        if (awaddr !== prev_awaddr) errors_this_cycle += note_error("AWADDR changed while stalled");
      end

      if (prev_wvalid && !prev_wready) begin
        if (!wvalid) errors_this_cycle += note_error("WVALID dropped before handshake");
        if (wdata !== prev_wdata) errors_this_cycle += note_error("WDATA changed while stalled");
        if (wstrb !== prev_wstrb) errors_this_cycle += note_error("WSTRB changed while stalled");
      end

      if (prev_bvalid && !prev_bready) begin
        if (!bvalid) errors_this_cycle += note_error("BVALID dropped before handshake");
        if (bresp !== prev_bresp) errors_this_cycle += note_error("BRESP changed while stalled");
      end

      if (prev_arvalid && !prev_arready) begin
        if (!arvalid) errors_this_cycle += note_error("ARVALID dropped before handshake");
        if (araddr !== prev_araddr) errors_this_cycle += note_error("ARADDR changed while stalled");
      end

      if (prev_rvalid && !prev_rready) begin
        if (!rvalid) errors_this_cycle += note_error("RVALID dropped before handshake");
        if (rdata !== prev_rdata) errors_this_cycle += note_error("RDATA changed while stalled");
        if (rresp !== prev_rresp) errors_this_cycle += note_error("RRESP changed while stalled");
      end

      if (errors_this_cycle != 0) begin
        error_count <= error_count + errors_this_cycle;
      end

      prev_awaddr  <= awaddr;
      prev_awvalid <= awvalid;
      prev_awready <= awready;

      prev_wdata   <= wdata;
      prev_wstrb   <= wstrb;
      prev_wvalid  <= wvalid;
      prev_wready  <= wready;

      prev_bresp   <= bresp;
      prev_bvalid  <= bvalid;
      prev_bready  <= bready;

      prev_araddr  <= araddr;
      prev_arvalid <= arvalid;
      prev_arready <= arready;

      prev_rdata   <= rdata;
      prev_rresp   <= rresp;
      prev_rvalid  <= rvalid;
      prev_rready  <= rready;
    end
  end

endmodule
