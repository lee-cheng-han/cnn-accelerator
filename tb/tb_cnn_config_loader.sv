`timescale 1ns/1ps

module tb_cnn_config_loader;

  localparam int IC = 3;
  localparam int OC = 4;
  localparam int K  = 9;
  localparam int NUM_WEIGHTS = IC * OC * K;

  logic clk;
  logic rst_n;
  logic clear;

  logic cfg_valid;
  logic [15:0] cfg_width;
  logic [15:0] cfg_height;
  logic cfg_kernel_mode;
  logic cfg_relu_enable;
  logic cfg_bias_enable;
  logic cfg_quant_enable;
  logic [4:0] cfg_quant_shift;

  logic weight_valid;
  logic [7:0] weight_index;
  logic signed [7:0] weight_data;
  logic weights_done;

  logic bias_valid;
  logic [1:0] bias_index;
  logic signed [31:0] bias_data;
  logic bias_done;

  logic [15:0] image_width;
  logic [15:0] image_height;
  logic kernel_mode;
  logic relu_enable;
  logic bias_enable;
  logic quant_enable;
  logic [4:0] quant_shift;

  logic signed [7:0] weights [OC][IC][K];
  logic signed [31:0] bias [OC];

  logic config_loaded;
  logic weights_loaded;
  logic bias_loaded;

  logic [31:0] cfg_write_count;
  logic [31:0] weight_write_count;
  logic [31:0] bias_write_count;

  int errors;
  int checks;

  cnn_config_loader #(
    .NUM_INPUT_CHANNELS(IC),
    .NUM_OUTPUT_CHANNELS(OC),
    .KERNEL_TAPS(K)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .cfg_valid(cfg_valid),
    .cfg_width(cfg_width),
    .cfg_height(cfg_height),
    .cfg_kernel_mode(cfg_kernel_mode),
    .cfg_relu_enable(cfg_relu_enable),
    .cfg_bias_enable(cfg_bias_enable),
    .cfg_quant_enable(cfg_quant_enable),
    .cfg_quant_shift(cfg_quant_shift),

    .weight_valid(weight_valid),
    .weight_index(weight_index),
    .weight_data(weight_data),
    .weights_done(weights_done),

    .bias_valid(bias_valid),
    .bias_index(bias_index),
    .bias_data(bias_data),
    .bias_done(bias_done),

    .image_width(image_width),
    .image_height(image_height),
    .kernel_mode(kernel_mode),
    .relu_enable(relu_enable),
    .bias_enable(bias_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),

    .weights(weights),
    .bias(bias),

    .config_loaded(config_loaded),
    .weights_loaded(weights_loaded),
    .bias_loaded(bias_loaded),

    .cfg_write_count(cfg_write_count),
    .weight_write_count(weight_write_count),
    .bias_write_count(bias_write_count)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic pulse_cfg(
    input logic [15:0] width,
    input logic [15:0] height,
    input logic mode,
    input logic relu,
    input logic bias_en,
    input logic quant,
    input logic [4:0] shift
  );
    begin
      @(negedge clk);
      cfg_width = width;
      cfg_height = height;
      cfg_kernel_mode = mode;
      cfg_relu_enable = relu;
      cfg_bias_enable = bias_en;
      cfg_quant_enable = quant;
      cfg_quant_shift = shift;
      cfg_valid = 1'b1;

      @(negedge clk);
      cfg_valid = 1'b0;
    end
  endtask

  task automatic pulse_weight(input int idx, input logic signed [7:0] value);
    begin
      @(negedge clk);
      weight_index = idx[7:0];
      weight_data = value;
      weight_valid = 1'b1;

      @(negedge clk);
      weight_valid = 1'b0;
    end
  endtask

  task automatic pulse_bias(input int idx, input logic signed [31:0] value);
    begin
      @(negedge clk);
      bias_index = idx[1:0];
      bias_data = value;
      bias_valid = 1'b1;

      @(negedge clk);
      bias_valid = 1'b0;
    end
  endtask

  task automatic pulse_weights_done;
    begin
      @(negedge clk);
      weights_done = 1'b1;
      @(negedge clk);
      weights_done = 1'b0;
    end
  endtask

  task automatic pulse_bias_done;
    begin
      @(negedge clk);
      bias_done = 1'b1;
      @(negedge clk);
      bias_done = 1'b0;
    end
  endtask

  task automatic check_int(input string name, input int got, input int expected);
    begin
      checks++;
      if (got !== expected) begin
        errors++;
        $error("%s got=%0d expected=%0d", name, got, expected);
      end
    end
  endtask

  task automatic check_s8(input string name, input logic signed [7:0] got, input logic signed [7:0] expected);
    begin
      checks++;
      if (got !== expected) begin
        errors++;
        $error("%s got=%0d expected=%0d", name, got, expected);
      end
    end
  endtask

  task automatic check_s32(input string name, input logic signed [31:0] got, input logic signed [31:0] expected);
    begin
      checks++;
      if (got !== expected) begin
        errors++;
        $error("%s got=%0d expected=%0d", name, got, expected);
      end
    end
  endtask

  task automatic reset_dut;
    begin
      clear = 1'b0;

      cfg_valid = 1'b0;
      cfg_width = '0;
      cfg_height = '0;
      cfg_kernel_mode = 1'b1;
      cfg_relu_enable = 1'b0;
      cfg_bias_enable = 1'b0;
      cfg_quant_enable = 1'b0;
      cfg_quant_shift = '0;

      weight_valid = 1'b0;
      weight_index = '0;
      weight_data = '0;
      weights_done = 1'b0;

      bias_valid = 1'b0;
      bias_index = '0;
      bias_data = '0;
      bias_done = 1'b0;

      rst_n = 1'b0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic test_config;
    begin
      $display("[TEST] config loading");

      pulse_cfg(16'd64, 16'd32, 1'b0, 1'b1, 1'b1, 1'b1, 5'd3);
      repeat (2) @(posedge clk);

      check_int("image_width", image_width, 64);
      check_int("image_height", image_height, 32);
      check_int("kernel_mode", kernel_mode, 0);
      check_int("relu_enable", relu_enable, 1);
      check_int("bias_enable", bias_enable, 1);
      check_int("quant_enable", quant_enable, 1);
      check_int("quant_shift", quant_shift, 3);
      check_int("config_loaded", config_loaded, 1);
      check_int("cfg_write_count", cfg_write_count, 1);
    end
  endtask

  task automatic test_weights;
    int oc;
    int ic;
    int tap;
    logic signed [7:0] expected;
    begin
      $display("[TEST] weight loading");

      for (int i = 0; i < NUM_WEIGHTS; i++) begin
        expected = i[7:0] - 8'sd54;
        pulse_weight(i, expected);
      end

      pulse_weights_done();
      repeat (2) @(posedge clk);

      for (int i = 0; i < NUM_WEIGHTS; i++) begin
        oc = i / (IC * K);
        ic = (i / K) % IC;
        tap = i % K;

        expected = i[7:0] - 8'sd54;
        check_s8($sformatf("weights[%0d][%0d][%0d]", oc, ic, tap), weights[oc][ic][tap], expected);
      end

      check_int("weight_write_count", weight_write_count, NUM_WEIGHTS);
      check_int("weights_loaded", weights_loaded, 1);
    end
  endtask

  task automatic test_bias;
    logic signed [31:0] vals [OC];
    begin
      $display("[TEST] bias loading");

      vals[0] = 32'sd10;
      vals[1] = -32'sd20;
      vals[2] = 32'sd300;
      vals[3] = -32'sd400;

      for (int i = 0; i < OC; i++) begin
        pulse_bias(i, vals[i]);
      end

      pulse_bias_done();
      repeat (2) @(posedge clk);

      for (int i = 0; i < OC; i++) begin
        check_s32($sformatf("bias[%0d]", i), bias[i], vals[i]);
      end

      check_int("bias_write_count", bias_write_count, OC);
      check_int("bias_loaded", bias_loaded, 1);
    end
  endtask

  task automatic test_clear;
    begin
      $display("[TEST] clear");

      @(negedge clk);
      clear = 1'b1;
      @(negedge clk);
      clear = 1'b0;
      repeat (2) @(posedge clk);

      check_int("image_width after clear", image_width, 0);
      check_int("image_height after clear", image_height, 0);
      check_int("config_loaded after clear", config_loaded, 0);
      check_int("weights_loaded after clear", weights_loaded, 0);
      check_int("bias_loaded after clear", bias_loaded, 0);
      check_int("cfg_write_count after clear", cfg_write_count, 0);
      check_int("weight_write_count after clear", weight_write_count, 0);
      check_int("bias_write_count after clear", bias_write_count, 0);
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("CNN CONFIG LOADER TEST SUMMARY");
      $display("============================================================");
      $display("Checks run         : %0d", checks);
      $display("Total errors       : %0d", errors);
      $display("Config writes      : %0d", cfg_write_count);
      $display("Weight writes      : %0d", weight_write_count);
      $display("Bias writes        : %0d", bias_write_count);
      $display("Status             : %s", (errors == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;

    reset_dut();

    test_config();
    test_weights();
    test_bias();
    test_clear();

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_cnn_config_loader");
    end else begin
      $fatal(1, "[FAIL] tb_cnn_config_loader errors=%0d", errors);
    end

    $finish;
  end

endmodule
