`timescale 1ns/1ps

module cnn_axi_system_bd_wrapper (
  input  wire         s_axi_aclk,
  input  wire         s_axi_aresetn,

  input  wire [11:0]  s_axi_awaddr,
  input  wire         s_axi_awvalid,
  output wire         s_axi_awready,

  input  wire [31:0]  s_axi_wdata,
  input  wire [3:0]   s_axi_wstrb,
  input  wire         s_axi_wvalid,
  output wire         s_axi_wready,

  output wire [1:0]   s_axi_bresp,
  output wire         s_axi_bvalid,
  input  wire         s_axi_bready,

  input  wire [11:0]  s_axi_araddr,
  input  wire         s_axi_arvalid,
  output wire         s_axi_arready,

  output wire [31:0]  s_axi_rdata,
  output wire [1:0]   s_axi_rresp,
  output wire         s_axi_rvalid,
  input  wire         s_axi_rready
);

  cnn_axi_system_top #(
    .AXI_ADDR_WIDTH(12),
    .AXI_DATA_WIDTH(32),
    .DATA_WIDTH(8),
    .WEIGHT_WIDTH(8),
    .ACC_WIDTH(32),
    .OUT_WIDTH(8),
    .BIAS_WIDTH(32),
    .NUM_INPUT_CHANNELS(3),
    .NUM_OUTPUT_CHANNELS(4),
    .KERNEL_TAPS(9),
    .MAX_IMG_WIDTH(64),
    .RESULT_DEPTH(16384)
  ) u_cnn_axi_system_top (
    .s_axi_aclk    (s_axi_aclk),
    .s_axi_aresetn (s_axi_aresetn),

    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),

    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),

    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),

    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),

    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready)
  );

endmodule
