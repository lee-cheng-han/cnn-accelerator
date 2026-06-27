`timescale 1ns/1ps

module tb_cnn_axi_system_top;

  localparam int AXI_ADDR_WIDTH = 12;
  localparam int AXI_DATA_WIDTH = 32;

  localparam int WIDTH  = 4;
  localparam int HEIGHT = 4;
  localparam int IC     = 3;
  localparam int OC     = 4;
  localparam int TAPS   = 9;
  localparam int NUM_WEIGHTS = OC * IC * TAPS;
  localparam int NUM_PIXELS  = WIDTH * HEIGHT * IC;
  localparam int NUM_RESULTS = WIDTH * HEIGHT * OC;

  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CONTROL     = 12'h000;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_WIDTH       = 12'h008;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_HEIGHT      = 12'h00C;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODE_FLAGS  = 12'h010;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PIXEL_IN    = 12'h020;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_RESULT_DATA = 12'h030;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_WEIGHT_BASE = 12'h100;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_BIAS_BASE   = 12'h400;

  logic clk;
  logic rst_n;

  logic [AXI_ADDR_WIDTH-1:0] awaddr;
  logic awvalid;
  logic awready;

  logic [AXI_DATA_WIDTH-1:0] wdata;
  logic [3:0] wstrb;
  logic wvalid;
  logic wready;

  logic [1:0] bresp;
  logic bvalid;
  logic bready;

  logic [AXI_ADDR_WIDTH-1:0] araddr;
  logic arvalid;
  logic arready;

  logic [AXI_DATA_WIDTH-1:0] rdata;
  logic [1:0] rresp;
  logic rvalid;
  logic rready;

  int errors;
  int checks;

  logic signed [7:0] image [0:NUM_PIXELS-1];
  logic signed [7:0] expected [0:NUM_RESULTS-1];

  cnn_axi_system_top dut (
    .s_axi_aclk(clk),
    .s_axi_aresetn(rst_n),

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
    .s_axi_rready(rready)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function automatic int weight_addr(input int oc, input int ic, input int tap);
    return ADDR_WEIGHT_BASE + 4 * ((oc * IC * TAPS) + (ic * TAPS) + tap);
  endfunction

  task automatic check_eq(input string name, input logic signed [31:0] got, input logic signed [31:0] exp);
    begin
      checks++;
      if (got !== exp) begin
        errors++;
        $error("%s got=0x%08h expected=0x%08h", name, got, exp);
      end
    end
  endtask

  task automatic axi_write(input logic [AXI_ADDR_WIDTH-1:0] addr, input logic [31:0] data);
    begin
      @(negedge clk);
      awaddr  = addr;
      awvalid = 1'b1;
      wdata   = data;
      wstrb   = 4'hF;
      wvalid  = 1'b1;
      bready  = 1'b1;

      fork
        begin
          wait (awready === 1'b1);
        end
        begin
          wait (wready === 1'b1);
        end
      join

      @(negedge clk);
      awvalid = 1'b0;
      wvalid  = 1'b0;

      wait (bvalid === 1'b1);
      check_eq("bresp", {30'd0, bresp}, 32'd0);

      @(negedge clk);
      bready = 1'b0;
    end
  endtask

  task automatic axi_read(input logic [AXI_ADDR_WIDTH-1:0] addr, output logic [31:0] data);
    begin
      @(negedge clk);
      araddr  = addr;
      arvalid = 1'b1;
      rready  = 1'b1;

      wait (arready === 1'b1);

      @(negedge clk);
      arvalid = 1'b0;

      wait (rvalid === 1'b1);
      data = rdata;
      check_eq("rresp", {30'd0, rresp}, 32'd0);

      @(negedge clk);
      rready = 1'b0;
    end
  endtask

  task automatic build_demo_data;
    int idx;
    int out_idx;
    int ch0;
    int ch1;
    int ch2;
    int sum;
    begin
      idx = 0;
      out_idx = 0;

      for (int y = 0; y < HEIGHT; y++) begin
        for (int x = 0; x < WIDTH; x++) begin
          ch0 = x + 1;
          ch1 = y + 1;
          ch2 = x + y + 1;

          image[idx + 0] = ch0[7:0];
          image[idx + 1] = ch1[7:0];
          image[idx + 2] = ch2[7:0];

          sum = ch0 + ch1 + ch2;

          expected[out_idx + 0] = ch0[7:0];
          expected[out_idx + 1] = ch1[7:0];
          expected[out_idx + 2] = ch2[7:0];
          expected[out_idx + 3] = sum[7:0];

          idx += 3;
          out_idx += 4;
        end
      end
    end
  endtask

  logic [31:0] rd;
  logic signed [7:0] got;

  initial begin
    errors = 0;
    checks = 0;

    awaddr  = '0;
    awvalid = 1'b0;
    wdata   = '0;
    wstrb   = 4'h0;
    wvalid  = 1'b0;
    bready  = 1'b0;

    araddr  = '0;
    arvalid = 1'b0;
    rready  = 1'b0;

    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    build_demo_data();

    $display("[TEST] clear");
    axi_write(ADDR_CONTROL, 32'h2);
    repeat (5) @(posedge clk);

    $display("[TEST] config");
    axi_write(ADDR_WIDTH, WIDTH);
    axi_write(ADDR_HEIGHT, HEIGHT);
    axi_write(ADDR_MODE_FLAGS, 32'h0); // 1x1, no ReLU, no bias, no quant

    $display("[TEST] weights");
    for (int i = 0; i < NUM_WEIGHTS; i++) begin
      axi_write(ADDR_WEIGHT_BASE + i * 4, 32'd0);
    end

    axi_write(weight_addr(0, 0, 0), 32'd1);
    axi_write(weight_addr(1, 1, 0), 32'd1);
    axi_write(weight_addr(2, 2, 0), 32'd1);
    axi_write(weight_addr(3, 0, 0), 32'd1);
    axi_write(weight_addr(3, 1, 0), 32'd1);
    axi_write(weight_addr(3, 2, 0), 32'd1);

    $display("[TEST] bias");
    for (int i = 0; i < OC; i++) begin
      axi_write(ADDR_BIAS_BASE + i * 4, 32'd0);
    end

    $display("[TEST] start");
    axi_write(ADDR_CONTROL, 32'h1);
    repeat (10) @(posedge clk);

    $display("[TEST] stream image");
    for (int i = 0; i < NUM_PIXELS; i++) begin
      axi_write(ADDR_PIXEL_IN, {{24{image[i][7]}}, image[i]});
    end

    $display("[TEST] wait for results");

    for (int timeout = 0; timeout < 5000; timeout++) begin
      if (dut.result_write_count == NUM_RESULTS) begin
        break;
      end
      @(posedge clk);
    end

    if (dut.result_write_count != NUM_RESULTS) begin
      errors++;
      $error("Timed out waiting for results. result_write_count=%0d expected=%0d", dut.result_write_count, NUM_RESULTS);
      $display("DEBUG config_loaded      = %0d", dut.config_loaded);
      $display("DEBUG weights_loaded     = %0d", dut.weights_loaded);
      $display("DEBUG bias_loaded        = %0d", dut.bias_loaded);
      $display("DEBUG cfg_image_width    = %0d", dut.cfg_image_width);
      $display("DEBUG cfg_image_height   = %0d", dut.cfg_image_height);
      $display("DEBUG cfg_kernel_mode    = %0d", dut.cfg_kernel_mode);
      $display("DEBUG core_pixel_ready   = %0d", dut.core_pixel_ready);
      $display("DEBUG windows_seen       = %0d", dut.windows_seen);
      $display("DEBUG outputs_seen       = %0d", dut.outputs_seen);
      $display("DEBUG core_out_valid     = %0d", dut.core_out_valid);
      $display("DEBUG core_out_ready     = %0d", dut.core_out_ready);
      $display("DEBUG result_write_count = %0d", dut.result_write_count);
      $display("DEBUG result_stored_count= %0d", dut.result_stored_count);
      $fatal;
    end

    repeat (20) @(posedge clk);

    $display("[TEST] read results");
    for (int i = 0; i < NUM_RESULTS; i++) begin
      axi_read(ADDR_RESULT_DATA, rd);
      got = rd[7:0];
      check_eq($sformatf("result[%0d]", i), {{24{got[7]}}, got}, {{24{expected[i][7]}}, expected[i]});
    end

    repeat (10) @(posedge clk);

    $display("");
    $display("CNN AXI SYSTEM TOP TEST SUMMARY");
    $display("Checks run   : %0d", checks);
    $display("Total errors : %0d", errors);

    if (errors == 0) begin
      $display("[PASS] tb_cnn_axi_system_top");
      $finish;
    end else begin
      $display("[FAIL] tb_cnn_axi_system_top");
      $fatal;
    end
  end

endmodule
