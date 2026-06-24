`timescale 1ns/1ps

module tb_conv_engine;

  localparam int DATA_WIDTH         = 8;
  localparam int WEIGHT_WIDTH       = 8;
  localparam int ACC_WIDTH          = 32;
  localparam int OUT_WIDTH          = 8;
  localparam int BIAS_WIDTH         = 32;
  localparam int NUM_INPUT_CHANNELS = 3;
  localparam int KERNEL_TAPS        = 9;

  logic clk;
  logic rst_n;
  logic pipe_en;
  logic valid_in;
  logic kernel_mode;

  logic signed [DATA_WIDTH-1:0]   windows [NUM_INPUT_CHANNELS][KERNEL_TAPS];
  logic signed [WEIGHT_WIDTH-1:0] weights [NUM_INPUT_CHANNELS][KERNEL_TAPS];
  logic signed [BIAS_WIDTH-1:0]   bias;

  logic relu_enable;
  logic bias_enable;
  logic quant_enable;
  logic [4:0] quant_shift;

  logic valid_out;
  logic signed [ACC_WIDTH-1:0] acc_raw;
  logic signed [OUT_WIDTH-1:0] out_data;

  int errors;
  int total_tests;
  int passed_tests;
  int failed_tests;
  int seed;
  int initial_seed;

  conv_engine #(
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUT_WIDTH(OUT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS),
    .KERNEL_TAPS(KERNEL_TAPS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .pipe_en(pipe_en),
    .valid_in(valid_in),
    .kernel_mode(kernel_mode),

    .windows(windows),
    .weights(weights),
    .bias(bias),

    .relu_enable(relu_enable),
    .bias_enable(bias_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),

    .valid_out(valid_out),
    .acc_raw(acc_raw),
    .out_data(out_data)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function automatic logic signed [ACC_WIDTH-1:0] ref_raw_sum;
    logic signed [ACC_WIDTH-1:0] sum;
    begin
      sum = '0;

      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        if (kernel_mode) begin
          // 3x3 mode: use all 9 taps.
          for (int k = 0; k < KERNEL_TAPS; k++) begin
            sum += $signed(windows[c][k]) * $signed(weights[c][k]);
          end
        end else begin
          // 1x1 mode: use only tap 0.
          sum += $signed(windows[c][0]) * $signed(weights[c][0]);
        end
      end

      ref_raw_sum = sum;
    end
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] ref_postprocess(
    input logic signed [ACC_WIDTH-1:0] raw_in,
    input logic signed [BIAS_WIDTH-1:0] bias_in,
    input logic bias_en,
    input logic relu_en,
    input logic quant_en,
    input logic [4:0] shift_in
  );
    logic signed [ACC_WIDTH-1:0] temp;
    begin
      temp = raw_in;

      if (bias_en) begin
        temp = temp + ACC_WIDTH'(bias_in);
      end

      if (relu_en && temp[ACC_WIDTH-1]) begin
        temp = '0;
      end

      if (quant_en) begin
        temp = temp >>> shift_in;
      end

      ref_postprocess = temp;
    end
  endfunction

  function automatic logic signed [OUT_WIDTH-1:0] ref_saturate(
    input logic signed [ACC_WIDTH-1:0] value
  );
    logic signed [ACC_WIDTH-1:0] max_val;
    logic signed [ACC_WIDTH-1:0] min_val;
    begin
      max_val = (ACC_WIDTH'(1) <<< (OUT_WIDTH - 1)) - ACC_WIDTH'(1);
      min_val = -(ACC_WIDTH'(1) <<< (OUT_WIDTH - 1));

      if (value > max_val) begin
        ref_saturate = 8'sd127;
      end else if (value < min_val) begin
        ref_saturate = -8'sd128;
      end else begin
        ref_saturate = value[OUT_WIDTH-1:0];
      end
    end
  endfunction

  function automatic logic signed [7:0] rand_s8;
    int value;
    begin
      value = $random(seed);
      rand_s8 = value[7:0];
    end
  endfunction

  function automatic logic signed [BIAS_WIDTH-1:0] rand_bias;
    int value;
    begin
      value = $random(seed);
      rand_bias = value % 256;
    end
  endfunction

  task automatic clear_inputs;
    begin
      valid_in     = 1'b0;
      pipe_en      = 1'b1;
      kernel_mode  = 1'b1;  // default old behavior: 3x3 mode

      bias         = '0;
      relu_enable  = 1'b0;
      bias_enable  = 1'b0;
      quant_enable = 1'b0;
      quant_shift  = 5'd0;

      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        for (int k = 0; k < KERNEL_TAPS; k++) begin
          windows[c][k] = '0;
          weights[c][k] = '0;
        end
      end
    end
  endtask

  task automatic wait_for_valid_out;
    input string test_name;
    int timeout;
    begin
      timeout = 0;

      while ((valid_out !== 1'b1) && (timeout < 30)) begin
        @(posedge clk);
        #1;
        timeout++;
      end

      if (valid_out !== 1'b1) begin
        $error("%s timeout waiting for valid_out", test_name);
        errors++;
      end
    end
  endtask

  task automatic check_case;
    input string test_name;

    logic signed [ACC_WIDTH-1:0] expected_raw;
    logic signed [ACC_WIDTH-1:0] expected_post;
    logic signed [OUT_WIDTH-1:0] expected_out;
    bit case_failed;

    begin
      case_failed = 1'b0;
      total_tests++;

      expected_raw = ref_raw_sum();

      expected_post = ref_postprocess(
        expected_raw,
        bias,
        bias_enable,
        relu_enable,
        quant_enable,
        quant_shift
      );

      expected_out = ref_saturate(expected_post);

      @(negedge clk);
      valid_in = 1'b1;

      @(posedge clk);
      #1;
      valid_in = 1'b0;

      wait_for_valid_out(test_name);

      if (valid_out !== 1'b1) begin
        case_failed = 1'b1;
      end else begin
        if (acc_raw !== expected_raw) begin
          $error(
            "%s raw mismatch: got=%0d expected=%0d",
            test_name,
            acc_raw,
            expected_raw
          );
          errors++;
          case_failed = 1'b1;
        end

        if (out_data !== expected_out) begin
          $error(
            "%s out mismatch: got=%0d expected=%0d raw=%0d bias=%0d relu=%0d bias_en=%0d quant_en=%0d shift=%0d",
            test_name,
            out_data,
            expected_out,
            expected_raw,
            bias,
            relu_enable,
            bias_enable,
            quant_enable,
            quant_shift
          );
          errors++;
          case_failed = 1'b1;
        end
      end

      if (case_failed) begin
        failed_tests++;
      end else begin
        passed_tests++;
      end

      @(posedge clk);
      #1;
    end
  endtask

  task automatic set_all_values;
    input logic signed [DATA_WIDTH-1:0] pixel_value;
    input logic signed [WEIGHT_WIDTH-1:0] weight_value;
    begin
      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        for (int k = 0; k < KERNEL_TAPS; k++) begin
          windows[c][k] = pixel_value;
          weights[c][k] = weight_value;
        end
      end
    end
  endtask

  task automatic set_random_values;
    begin
      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        for (int k = 0; k < KERNEL_TAPS; k++) begin
          windows[c][k] = rand_s8();
          weights[c][k] = rand_s8();
        end
      end

      bias         = rand_bias();
      relu_enable  = $random(seed) & 1;
      bias_enable  = $random(seed) & 1;
      quant_enable = $random(seed) & 1;
      quant_shift  = ($random(seed) & 5'h7);
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("CONV_ENGINE TEST SUMMARY");
      $display("============================================================");
      $display("Total tests   : %0d", total_tests);
      $display("Passed tests  : %0d", passed_tests);
      $display("Failed tests  : %0d", failed_tests);
      $display("Total errors  : %0d", errors);
      $display("Seed          : %0d", initial_seed);

      if (errors == 0) begin
        $display("Status        : PASS");
      end else begin
        $display("Status        : FAIL");
      end

      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    errors       = 0;
    total_tests  = 0;
    passed_tests = 0;
    failed_tests = 0;
    seed         = 12345;
    initial_seed = 12345;

    if ($value$plusargs("SEED=%d", seed)) begin
      $display("[INFO] Using SEED=%0d", seed);
    end else begin
      $display("[INFO] Using default SEED=%0d", seed);
    end

    initial_seed = seed;

    clear_inputs();

    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    $display("[TEST] all zeros");
    set_all_values(8'sd0, 8'sd0);
    bias         = 32'sd0;
    relu_enable  = 1'b0;
    bias_enable  = 1'b0;
    quant_enable = 1'b0;
    quant_shift  = 5'd0;
    check_case("all_zeros");

    $display("[TEST] all ones");
    set_all_values(8'sd1, 8'sd1);
    bias         = 32'sd0;
    relu_enable  = 1'b0;
    bias_enable  = 1'b0;
    quant_enable = 1'b0;
    quant_shift  = 5'd0;
    check_case("all_ones");

    $display("[TEST] bias enabled");
    set_all_values(8'sd1, 8'sd1);
    bias         = 32'sd10;
    relu_enable  = 1'b0;
    bias_enable  = 1'b1;
    quant_enable = 1'b0;
    quant_shift  = 5'd0;
    check_case("bias_enabled");

    $display("[TEST] relu negative");
    set_all_values(8'sd1, -8'sd1);
    bias         = 32'sd0;
    relu_enable  = 1'b1;
    bias_enable  = 1'b0;
    quant_enable = 1'b0;
    quant_shift  = 5'd0;
    check_case("relu_negative");

    $display("[TEST] quant shift");
    set_all_values(8'sd2, 8'sd2);
    bias         = 32'sd0;
    relu_enable  = 1'b0;
    bias_enable  = 1'b0;
    quant_enable = 1'b1;
    quant_shift  = 5'd2;
    check_case("quant_shift");

    $display("[TEST] positive saturation");
    set_all_values(8'sd20, 8'sd20);
    bias         = 32'sd0;
    relu_enable  = 1'b0;
    bias_enable  = 1'b0;
    quant_enable = 1'b0;
    quant_shift  = 5'd0;
    check_case("positive_saturation");

    $display("[TEST] negative saturation");
    set_all_values(-8'sd20, 8'sd20);
    bias         = 32'sd0;
    relu_enable  = 1'b0;
    bias_enable  = 1'b0;
    quant_enable = 1'b0;
    quant_shift  = 5'd0;
    check_case("negative_saturation");


    $display("[TEST] 1x1 ignores taps 1 to 8");
    clear_inputs();
    kernel_mode = 1'b0;  // 1x1 mode

    // Tap 0 should be used.
    windows[0][0] = 8'sd2;   weights[0][0] = 8'sd3;   // 6
    windows[1][0] = 8'sd4;   weights[1][0] = -8'sd2;  // -8
    windows[2][0] = -8'sd5;  weights[2][0] = 8'sd6;   // -30
    // raw = 6 - 8 - 30 = -32

    // Taps 1..8 should be ignored. Use huge/weird values to prove it.
    for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
      for (int k = 1; k < KERNEL_TAPS; k++) begin
        windows[c][k] = 8'sd100;
        weights[c][k] = -8'sd100;
      end
    end

    bias         = 32'sd0;
    relu_enable  = 1'b0;
    bias_enable  = 1'b0;
    quant_enable = 1'b0;
    quant_shift  = 5'd0;
    check_case("one_by_one_ignores_extra_taps");

    $display("[TEST] 1x1 with bias relu quant");
    clear_inputs();
    kernel_mode = 1'b0;  // 1x1 mode

    windows[0][0] = 8'sd10;  weights[0][0] = 8'sd2;   // 20
    windows[1][0] = 8'sd3;   weights[1][0] = 8'sd4;   // 12
    windows[2][0] = 8'sd1;   weights[2][0] = -8'sd8;  // -8
    // raw = 24
    // + bias 40 = 64
    // >> 2 = 16

    for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
      for (int k = 1; k < KERNEL_TAPS; k++) begin
        windows[c][k] = -8'sd77;
        weights[c][k] = 8'sd55;
      end
    end

    bias         = 32'sd40;
    relu_enable  = 1'b1;
    bias_enable  = 1'b1;
    quant_enable = 1'b1;
    quant_shift  = 5'd2;
    check_case("one_by_one_bias_relu_quant");

    $display("[TEST] 1x1 relu clamps negative");
    clear_inputs();
    kernel_mode = 1'b0;  // 1x1 mode

    windows[0][0] = 8'sd5;   weights[0][0] = -8'sd10; // -50
    windows[1][0] = 8'sd2;   weights[1][0] = -8'sd4;  // -8
    windows[2][0] = 8'sd1;   weights[2][0] = -8'sd3;  // -3
    // raw = -61, ReLU should clamp to 0

    for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
      for (int k = 1; k < KERNEL_TAPS; k++) begin
        windows[c][k] = 8'sd99;
        weights[c][k] = 8'sd99;
      end
    end

    bias         = 32'sd0;
    relu_enable  = 1'b1;
    bias_enable  = 1'b0;
    quant_enable = 1'b0;
    quant_shift  = 5'd0;
    check_case("one_by_one_relu_negative");

    // Return to old default before the random 3x3 tests.
    kernel_mode = 1'b1;


    $display("[TEST] random tests");
    for (int i = 0; i < 600; i++) begin
      string name;
      name = $sformatf("random_%0d", i);
      set_random_values();
      check_case(name);
    end

    print_summary();

    $finish;
  end

endmodule