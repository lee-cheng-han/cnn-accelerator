`timescale 1ns/1ps

module tb_cnn_axi_lite_slave;

  localparam int AXI_ADDR_WIDTH = 12;
  localparam int AXI_DATA_WIDTH = 32;

  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CONTROL     = 12'h000;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STATUS      = 12'h004;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_WIDTH       = 12'h008;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_HEIGHT      = 12'h00C;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODE_FLAGS  = 12'h010;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PIXEL_IN    = 12'h020;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PIXEL_INDEX = 12'h024;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_RESULT_DATA = 12'h030;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_RESULT_STAT = 12'h034;
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

  logic start_pulse;
  logic clear_pulse;

  logic [15:0] image_width;
  logic [15:0] image_height;
  logic kernel_mode;
  logic relu_enable;
  logic bias_enable;
  logic quant_enable;
  logic [4:0] quant_shift;

  logic weight_valid;
  logic [7:0] weight_index;
  logic signed [7:0] weight_data;

  logic bias_valid;
  logic [1:0] bias_index;
  logic signed [31:0] bias_data;

  logic pixel_valid;
  logic [31:0] pixel_index;
  logic signed [7:0] pixel_data;

  logic core_busy;
  logic core_done;
  logic result_valid;
  logic signed [7:0] result_data;
  logic result_last;
  logic result_ready;

  int errors;
  int checks;

  cnn_axi_lite_slave dut (
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
    .s_axi_rready(rready),

    .start_pulse(start_pulse),
    .clear_pulse(clear_pulse),

    .image_width(image_width),
    .image_height(image_height),
    .kernel_mode(kernel_mode),
    .relu_enable(relu_enable),
    .bias_enable(bias_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),

    .weight_valid(weight_valid),
    .weight_index(weight_index),
    .weight_data(weight_data),

    .bias_valid(bias_valid),
    .bias_index(bias_index),
    .bias_data(bias_data),

    .pixel_valid(pixel_valid),
    .pixel_index(pixel_index),
    .pixel_data(pixel_data),

    .core_busy(core_busy),
    .core_done(core_done),
    .result_valid(result_valid),
    .result_data(result_data),
    .result_last(result_last),
    .result_ready(result_ready)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic check_eq(input string name, input logic [31:0] got, input logic [31:0] exp);
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

  logic [31:0] rd;

  initial begin
    errors = 0;
    checks = 0;

    rst_n = 1'b0;

    awaddr  = '0;
    awvalid = 1'b0;
    wdata   = '0;
    wstrb   = 4'h0;
    wvalid  = 1'b0;
    bready  = 1'b0;

    araddr  = '0;
    arvalid = 1'b0;
    rready  = 1'b0;

    core_busy    = 1'b0;
    core_done    = 1'b0;
    result_valid = 1'b0;
    result_data  = 8'sd0;
    result_last  = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    $display("[TEST] config registers");

    axi_write(ADDR_WIDTH, 32'd4);
    check_eq("image_width output", {16'd0, image_width}, 32'd4);

    axi_write(ADDR_HEIGHT, 32'd4);
    check_eq("image_height output", {16'd0, image_height}, 32'd4);

    axi_write(ADDR_MODE_FLAGS, 32'h0000_050F);
    check_eq("kernel_mode", {31'd0, kernel_mode}, 32'd1);
    check_eq("relu_enable", {31'd0, relu_enable}, 32'd1);
    check_eq("bias_enable", {31'd0, bias_enable}, 32'd1);
    check_eq("quant_enable", {31'd0, quant_enable}, 32'd1);
    check_eq("quant_shift", {27'd0, quant_shift}, 32'd5);

    axi_read(ADDR_WIDTH, rd);
    check_eq("read width", rd, 32'd4);

    axi_read(ADDR_HEIGHT, rd);
    check_eq("read height", rd, 32'd4);

    axi_read(ADDR_MODE_FLAGS, rd);
    check_eq("read mode flags", rd, 32'h0000_050F);

    $display("[TEST] control pulses");

    axi_write(ADDR_CONTROL, 32'h1);
    repeat (2) @(posedge clk);
    #1;
    check_eq("start pulse returns low", {31'd0, start_pulse}, 32'd0);

    axi_write(ADDR_CONTROL, 32'h2);
    repeat (2) @(posedge clk);
    #1;
    check_eq("clear pulse returns low", {31'd0, clear_pulse}, 32'd0);

    $display("[TEST] weights");

    axi_write(ADDR_WEIGHT_BASE + 12'd0, 32'h0000_0001);
    check_eq("weight_valid after write", {31'd0, weight_valid}, 32'd1);
    check_eq("weight_index", {24'd0, weight_index}, 32'd0);
    check_eq("weight_data", {{24{weight_data[7]}}, weight_data}, 32'd1);

    axi_write(ADDR_WEIGHT_BASE + 12'd4, 32'h0000_00FE);
    check_eq("weight_index 1", {24'd0, weight_index}, 32'd1);
    check_eq("weight_data -2", {{24{weight_data[7]}}, weight_data}, 32'hFFFF_FFFE);

    axi_read(ADDR_WEIGHT_BASE + 12'd4, rd);
    check_eq("read weight 1 sign extended", rd, 32'hFFFF_FFFE);

    $display("[TEST] bias");

    axi_write(ADDR_BIAS_BASE + 12'd0, 32'h0000_0012);
    check_eq("bias_valid", {31'd0, bias_valid}, 32'd1);
    check_eq("bias_index", {30'd0, bias_index}, 32'd0);
    check_eq("bias_data", bias_data, 32'h0000_0012);

    axi_write(ADDR_BIAS_BASE + 12'd4, 32'hFFFF_FF80);
    check_eq("bias_index 1", {30'd0, bias_index}, 32'd1);
    check_eq("bias_data -128", bias_data, 32'hFFFF_FF80);

    axi_read(ADDR_BIAS_BASE + 12'd4, rd);
    check_eq("read bias 1", rd, 32'hFFFF_FF80);

    $display("[TEST] pixel input");

    axi_write(ADDR_PIXEL_INDEX, 32'd7);
    check_eq("pixel index", pixel_index, 32'd7);

    axi_write(ADDR_PIXEL_IN, 32'h0000_0052);
    check_eq("pixel_valid", {31'd0, pixel_valid}, 32'd1);
    check_eq("pixel_data", {{24{pixel_data[7]}}, pixel_data}, 32'h0000_0052);

    $display("[TEST] status/result read");

    core_busy    = 1'b1;
    core_done    = 1'b0;
    result_valid = 1'b1;
    result_data  = -8'sd3;
    result_last  = 1'b1;

    axi_read(ADDR_STATUS, rd);
    check_eq("status", rd[4:0], 5'b11010);

    axi_read(ADDR_RESULT_STAT, rd);
    check_eq("result status", rd, 32'd3);

    axi_read(ADDR_RESULT_DATA, rd);
    check_eq("result data sign extended", rd, 32'hFFFF_FFFD);

    repeat (5) @(posedge clk);

    $display("");
    $display("CNN AXI-LITE SLAVE TEST SUMMARY");
    $display("Checks run   : %0d", checks);
    $display("Total errors : %0d", errors);

    if (errors == 0) begin
      $display("[PASS] tb_cnn_axi_lite_slave");
      $finish;
    end else begin
      $display("[FAIL] tb_cnn_axi_lite_slave");
      $fatal;
    end
  end

endmodule
