`timescale 1ns/1ps

module tb_v2_image2image_system_top;

  localparam logic [11:0] ADDR_CONTROL      = 12'h000;
  localparam logic [11:0] ADDR_STATUS       = 12'h004;
  localparam logic [11:0] ADDR_IRQ_STATUS   = 12'h008;
  localparam logic [11:0] ADDR_IRQ_ENABLE   = 12'h00C;
  localparam logic [11:0] ADDR_IMAGE_WIDTH  = 12'h010;
  localparam logic [11:0] ADDR_IMAGE_HEIGHT = 12'h014;
  localparam logic [11:0] ADDR_MODE_FLAGS   = 12'h018;
  localparam logic [11:0] ADDR_ERROR_CODE   = 12'h01C;

  logic clk;
  logic rst_n;
  logic [11:0] awaddr;
  logic awvalid;
  logic awready;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wvalid;
  logic wready;
  logic [1:0] bresp;
  logic bvalid;
  logic bready;
  logic [11:0] araddr;
  logic arvalid;
  logic arready;
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rvalid;
  logic rready;
  logic [31:0] s_axis_tdata;
  logic s_axis_tvalid;
  logic s_axis_tready;
  logic s_axis_tlast;
  logic [31:0] m_axis_tdata;
  logic m_axis_tvalid;
  logic m_axis_tready;
  logic m_axis_tlast;
  logic irq;
  logic busy;
  logic done;
  logic error;

  int checks;
  int errors;
  logic [31:0] rd;

  cnn_image2image_system_top #(
    .MAX_PIXELS(4)
  ) dut (
    .aclk(clk),
    .aresetn(rst_n),
    .s_axi_awaddr(awaddr),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_araddr(araddr),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .irq(irq),
    .busy(busy),
    .done(done),
    .error(error)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic check_eq(
    input string name,
    input logic [31:0] got,
    input logic [31:0] expected
  );
    begin
      checks++;
      if (got !== expected) begin
        errors++;
        $error("%s got=0x%08h expected=0x%08h", name, got, expected);
      end
    end
  endtask

  task automatic axi_write(
    input logic [11:0] addr,
    input logic [31:0] data
  );
    begin
      @(negedge clk);
      awaddr = addr;
      awvalid = 1'b1;
      wdata = data;
      wstrb = 4'hF;
      wvalid = 1'b1;
      bready = 1'b1;
      fork
        wait (awready === 1'b1);
        wait (wready === 1'b1);
      join
      @(negedge clk);
      awvalid = 1'b0;
      wvalid = 1'b0;
      wait (bvalid === 1'b1);
      check_eq("write response", {30'd0, bresp}, 32'd0);
      @(negedge clk);
      bready = 1'b0;
    end
  endtask

  task automatic axi_read(
    input logic [11:0] addr,
    output logic [31:0] data
  );
    begin
      @(negedge clk);
      araddr = addr;
      arvalid = 1'b1;
      rready = 1'b1;
      wait (arready === 1'b1);
      @(negedge clk);
      arvalid = 1'b0;
      wait (rvalid === 1'b1);
      data = rdata;
      check_eq("read response", {30'd0, rresp}, 32'd0);
      @(negedge clk);
      rready = 1'b0;
    end
  endtask

  initial begin
    checks = 0;
    errors = 0;
    rst_n = 1'b0;
    awaddr = '0;
    awvalid = 1'b0;
    wdata = '0;
    wstrb = '0;
    wvalid = 1'b0;
    bready = 1'b0;
    araddr = '0;
    arvalid = 1'b0;
    rready = 1'b0;
    s_axis_tdata = '0;
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;
    m_axis_tready = 1'b1;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    axi_write(ADDR_IMAGE_WIDTH, 32'd1);
    axi_write(ADDR_IMAGE_HEIGHT, 32'd1);
    axi_write(ADDR_MODE_FLAGS, 32'd1);
    axi_write(ADDR_IRQ_ENABLE, 32'd2);
    axi_write(ADDR_CONTROL, 32'd1);

    repeat (2) @(posedge clk);
    axi_read(ADDR_STATUS, rd);
    check_eq("busy after start", rd & 32'h1, 32'h1);

    @(negedge clk);
    s_axis_tdata = 32'h0000_0000;
    s_axis_tvalid = 1'b1;
    s_axis_tlast = 1'b0;
    wait (s_axis_tready === 1'b1);
    @(negedge clk);
    s_axis_tvalid = 1'b0;

    repeat (3) @(posedge clk);
    axi_read(ADDR_STATUS, rd);
    check_eq("error status", (rd >> 2) & 32'h1, 32'h1);
    axi_read(ADDR_ERROR_CODE, rd);
    check_eq("bad magic error code", rd, 32'h0000_0003);
    axi_read(ADDR_IRQ_STATUS, rd);
    check_eq("error IRQ status", rd, 32'h0000_0002);
    check_eq("IRQ output", irq, 32'h1);

    axi_write(ADDR_CONTROL, 32'd2);
    repeat (3) @(posedge clk);
    axi_read(ADDR_STATUS, rd);
    check_eq("error cleared", (rd >> 2) & 32'h1, 32'h0);
    axi_read(ADDR_IRQ_STATUS, rd);
    check_eq("IRQ status cleared", rd, 32'h0);
    check_eq("IRQ output cleared", irq, 32'h0);

    if (errors == 0) begin
      $display("[PASS] tb_v2_image2image_system_top tests=%0d", checks);
    end else begin
      $display(
        "[FAIL] tb_v2_image2image_system_top errors=%0d checks=%0d",
        errors,
        checks
      );
      $fatal(1);
    end

    $finish;
  end

endmodule
