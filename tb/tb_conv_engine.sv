`timescale 1ns/1ps

module tb_conv_engine;

  localparam int DATA_WIDTH = 8;
  localparam int WEIGHT_WIDTH = 8;
  localparam int ACC_WIDTH = 32;
  localparam int OUT_WIDTH = 8;
  localparam int BIAS_WIDTH = 32;
  localparam int NUM_INPUT_CHANNELS = 3;
  localparam int KERNEL_TAPS = 9;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic signed [DATA_WIDTH-1:0]   windows [NUM_INPUT_CHANNELS][KERNEL_TAPS];
  logic signed [WEIGHT_WIDTH-1:0] weights [NUM_INPUT_CHANNELS][KERNEL_TAPS];
  logic signed [BIAS_WIDTH-1:0]   bias;
  logic                           relu_enable;
  logic                           bias_enable;
  logic                           quant_enable;
  logic [4:0]                     quant_shift;
  logic signed [ACC_WIDTH-1:0]    acc_raw;
  logic signed [OUT_WIDTH-1:0]    out_data;

  int tests;
  int errors;
  int seed;

  int cov_relu_on;
  int cov_relu_off;
  int cov_quant_on;
  int cov_quant_off;
  int cov_shift_zero;
  int cov_shift_low;
  int cov_shift_high;
  int cov_cross[2][2];

`ifdef USE_COVERGROUPS
  covergroup cg_config @(posedge clk);
    cp_relu:  coverpoint relu_enable  { bins off = {0}; bins on = {1}; }
    cp_quant: coverpoint quant_enable { bins off = {0}; bins on = {1}; }
    cp_shift: coverpoint quant_shift  {
      bins zero = {0};
      bins low  = {[1:3]};
      bins high = {[4:6]};
    }
    cx_relu_quant: cross cp_relu, cp_quant;
  endgroup

  cg_config cg = new();
`endif

  conv_engine #(
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUT_WIDTH(OUT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS),
    .KERNEL_TAPS(KERNEL_TAPS)
  ) dut (
    .windows(windows),
    .weights(weights),
    .bias(bias),
    .relu_enable(relu_enable),
    .bias_enable(bias_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),
    .acc_raw(acc_raw),
    .out_data(out_data)
  );

  // ------------------------------------------------------------
  // Vivado/XSim-compatible random helper.
  // Avoids $urandom and $urandom_range.
  // ------------------------------------------------------------
  function automatic int rand_range(input int min_val, input int max_val);
    int r;
    begin
      r = $random(seed);

      if (r < 0) begin
        r = -r;
      end

      rand_range = min_val + (r % (max_val - min_val + 1));
    end
  endfunction

  // ------------------------------------------------------------
  // Golden raw convolution sum
  // ------------------------------------------------------------
  function automatic signed [ACC_WIDTH-1:0] golden_raw;
    begin
      golden_raw = '0;

      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        for (int k = 0; k < KERNEL_TAPS; k++) begin
          golden_raw += windows[c][k] * weights[c][k];
        end
      end
    end
  endfunction

  // ------------------------------------------------------------
  // INT8 saturation
  // ------------------------------------------------------------
  function automatic signed [OUT_WIDTH-1:0] saturate_int8(
    input signed [ACC_WIDTH-1:0] value
  );
    begin
      if (value > 32'sd127) begin
        saturate_int8 = 8'sd127;
      end else if (value < -32'sd128) begin
        saturate_int8 = -8'sd128;
      end else begin
        saturate_int8 = value[OUT_WIDTH-1:0];
      end
    end
  endfunction

  // ------------------------------------------------------------
  // Golden final output
  // ------------------------------------------------------------
  function automatic signed [OUT_WIDTH-1:0] golden_out;
    logic signed [ACC_WIDTH-1:0] value;

    begin
      value = golden_raw();

      if (bias_enable) begin
        value += bias;
      end

      if (relu_enable && value < 0) begin
        value = '0;
      end

      if (quant_enable) begin
        value = value >>> quant_shift;
      end

      golden_out = saturate_int8(value);
    end
  endfunction

  // ------------------------------------------------------------
  // Manual coverage
  // ------------------------------------------------------------
  task automatic sample_manual_coverage;
    begin
      if (relu_enable) begin
        cov_relu_on++;
      end else begin
        cov_relu_off++;
      end

      if (quant_enable) begin
        cov_quant_on++;
      end else begin
        cov_quant_off++;
      end

      if (quant_shift == 0) begin
        cov_shift_zero++;
      end else if (quant_shift >= 1 && quant_shift <= 3) begin
        cov_shift_low++;
      end else if (quant_shift >= 4 && quant_shift <= 6) begin
        cov_shift_high++;
      end

      cov_cross[relu_enable][quant_enable]++;
    end
  endtask

  task automatic check_coverage;
    begin
      if (
        cov_relu_on == 0 ||
        cov_relu_off == 0 ||
        cov_quant_on == 0 ||
        cov_quant_off == 0 ||
        cov_shift_zero == 0 ||
        cov_shift_low == 0 ||
        cov_shift_high == 0 ||
        cov_cross[0][0] == 0 ||
        cov_cross[0][1] == 0 ||
        cov_cross[1][0] == 0 ||
        cov_cross[1][1] == 0
      ) begin
        errors++;
        $error(
          "Coverage miss: relu_on=%0d relu_off=%0d quant_on=%0d quant_off=%0d shift_zero=%0d shift_low=%0d shift_high=%0d cross00=%0d cross01=%0d cross10=%0d cross11=%0d",
          cov_relu_on,
          cov_relu_off,
          cov_quant_on,
          cov_quant_off,
          cov_shift_zero,
          cov_shift_low,
          cov_shift_high,
          cov_cross[0][0],
          cov_cross[0][1],
          cov_cross[1][0],
          cov_cross[1][1]
        );
      end else begin
        $display("[COVERAGE] config bins hit: relu on/off, quant on/off, shift zero/low/high, reluXquant cross");
      end
    end
  endtask

  // ------------------------------------------------------------
  // Check current DUT output against golden model
  // ------------------------------------------------------------
  task automatic check_case(input string name);
    logic signed [ACC_WIDTH-1:0] exp_raw;
    logic signed [OUT_WIDTH-1:0] exp_out;

    begin
      @(posedge clk);
      #1;

      sample_manual_coverage();

      exp_raw = golden_raw();
      exp_out = golden_out();

      tests++;

      if (acc_raw !== exp_raw) begin
        errors++;
        $error("%s raw mismatch: got=%0d expected=%0d", name, acc_raw, exp_raw);
      end

      tests++;

      if (out_data !== exp_out) begin
        errors++;
        $error(
          "%s out mismatch: got=%0d expected=%0d raw=%0d bias=%0d relu=%0b bias_en=%0b quant_en=%0b shift=%0d",
          name,
          out_data,
          exp_out,
          exp_raw,
          bias,
          relu_enable,
          bias_enable,
          quant_enable,
          quant_shift
        );
      end
    end
  endtask

  // ------------------------------------------------------------
  // Fill all windows/weights with constants
  // ------------------------------------------------------------
  task automatic fill_all(
    input signed [7:0] wval,
    input signed [7:0] kval
  );
    begin
      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        for (int k = 0; k < KERNEL_TAPS; k++) begin
          windows[c][k] = wval;
          weights[c][k] = kval;
        end
      end
    end
  endtask

  // ------------------------------------------------------------
  // Apply controls
  // ------------------------------------------------------------
  task automatic apply_controls(
    input bit r,
    input bit b,
    input bit q,
    input int sh
  );
    begin
      relu_enable  = r;
      bias_enable  = b;
      quant_enable = q;
      quant_shift  = sh[4:0];
    end
  endtask

  // ------------------------------------------------------------
  // Main test
  // ------------------------------------------------------------
  initial begin
    $dumpfile("tb_conv_engine.vcd");
    $dumpvars(0, tb_conv_engine);

    if (!$value$plusargs("ntb_random_seed=%d", seed)) begin
      seed = 32'h4bad_c0de;
    end

    $display("[TB] ntb_random_seed=%0d", seed);

    tests = 0;
    errors = 0;

    cov_relu_on = 0;
    cov_relu_off = 0;
    cov_quant_on = 0;
    cov_quant_off = 0;
    cov_shift_zero = 0;
    cov_shift_low = 0;
    cov_shift_high = 0;

    cov_cross[0][0] = 0;
    cov_cross[0][1] = 0;
    cov_cross[1][0] = 0;
    cov_cross[1][1] = 0;

    fill_all(8'sd0, 8'sd0);
    bias = '0;
    apply_controls(0, 0, 0, 0);

    repeat (2) @(posedge clk);

    // ----------------------------------------------------------
    // Directed tests
    // ----------------------------------------------------------
    @(negedge clk);
    fill_all(8'sd1, 8'sd1);
    bias = 32'sd5;
    apply_controls(1, 1, 1, 1);
    check_case("all ones with bias quant");

    @(negedge clk);
    bias = 32'sd1000;
    apply_controls(1, 0, 0, 0);
    check_case("bias disabled");

    @(negedge clk);
    fill_all(8'sd1, -8'sd2);
    bias = 32'sd0;
    apply_controls(1, 1, 1, 0);
    check_case("relu clamps negative");

    @(negedge clk);
    apply_controls(0, 1, 1, 0);
    check_case("relu disabled keeps negative");

    @(negedge clk);
    fill_all(8'sd127, 8'sd127);
    bias = 32'sd0;
    apply_controls(0, 1, 0, 0);
    check_case("positive saturation");

    @(negedge clk);
    fill_all(8'sd127, -8'sd128);
    bias = 32'sd0;
    apply_controls(0, 1, 0, 0);
    check_case("negative saturation");

    // ----------------------------------------------------------
    // Randomized tests
    // ----------------------------------------------------------
    for (int t = 0; t < 750; t++) begin
      @(negedge clk);

      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        for (int k = 0; k < KERNEL_TAPS; k++) begin
          windows[c][k] = $signed(rand_range(0, 31)) - 8'sd16;
          weights[c][k] = $signed(rand_range(0, 31)) - 8'sd16;
        end
      end

      bias = $signed(rand_range(0, 511)) - 32'sd255;

      apply_controls(
        rand_range(0, 1),
        rand_range(0, 1),
        rand_range(0, 1),
        rand_range(0, 6)
      );

      check_case($sformatf("random_%0d", t));
    end

    check_coverage();

    $display("============================================================");
    $display("tb_conv_engine summary");
    $display("Tests run : %0d", tests);
    $display("Errors    : %0d", errors);
    $display("============================================================");


    if (errors != 0) begin
      $fatal(1, "tb_conv_engine FAILED: tests=%0d errors=%0d", tests, errors);
    end else begin
      $display("[PASS] tb_conv_engine tests=%0d", tests);
    end

    $finish;
  end

endmodule