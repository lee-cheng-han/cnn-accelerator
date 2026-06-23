`timescale 1ns/1ps

module tb_channel_accumulator;

  localparam int ACC_WIDTH = 32;
  localparam int NUM_INPUT_CHANNELS = 3;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic signed [ACC_WIDTH-1:0] channel_sums[NUM_INPUT_CHANNELS];
  logic signed [ACC_WIDTH-1:0] acc_out;

  int tests;
  int errors;
  int seed;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  channel_accumulator #(
    .ACC_WIDTH(ACC_WIDTH),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS)
  ) dut (
    .channel_sums(channel_sums),
    .acc_out(acc_out)
  );

  // ------------------------------------------------------------
  // Vivado/XSim-compatible random helper
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
  // Golden model
  // ------------------------------------------------------------
  function automatic signed [ACC_WIDTH-1:0] golden_sum(
    input signed [ACC_WIDTH-1:0] a,
    input signed [ACC_WIDTH-1:0] b,
    input signed [ACC_WIDTH-1:0] c
  );
    begin
      golden_sum = a + b + c;
    end
  endfunction

  // ------------------------------------------------------------
  // Self-checking task
  // Drive on negedge, check after posedge.
  // ------------------------------------------------------------
  task automatic apply_and_check(
    input string name,
    input signed [ACC_WIDTH-1:0] a,
    input signed [ACC_WIDTH-1:0] b,
    input signed [ACC_WIDTH-1:0] c
  );
    logic signed [ACC_WIDTH-1:0] expected;

    begin
      @(negedge clk);
      channel_sums[0] = a;
      channel_sums[1] = b;
      channel_sums[2] = c;

      @(posedge clk);
      #1;

      expected = golden_sum(a, b, c);
      tests++;

      if (acc_out !== expected) begin
        errors++;
        $display("[FAIL] %s", name);
        $display("       channel_sums[0] = %0d", a);
        $display("       channel_sums[1] = %0d", b);
        $display("       channel_sums[2] = %0d", c);
        $display("       expected        = %0d", expected);
        $display("       got             = %0d", acc_out);
        $fatal(1);
      end else begin
        $display("[PASS] %s | sums={%0d,%0d,%0d} acc_out=%0d",
                 name, a, b, c, acc_out);
      end
    end
  endtask

  // ------------------------------------------------------------
  // Main test
  // ------------------------------------------------------------
  initial begin
    $dumpfile("tb_channel_accumulator.vcd");
    $dumpvars(0, tb_channel_accumulator);

    if (!$value$plusargs("ntb_random_seed=%d", seed)) begin
      seed = 12345;
    end

    $display("============================================================");
    $display("tb_channel_accumulator started");
    $display("SEED = %0d", seed);
    $display("============================================================");

    tests  = 0;
    errors = 0;

    for (int i = 0; i < NUM_INPUT_CHANNELS; i++) begin
      channel_sums[i] = '0;
    end

    repeat (2) @(posedge clk);

    // ----------------------------------------------------------
    // Directed tests
    // ----------------------------------------------------------
    apply_and_check("mixed signs",    32'sd10,     -32'sd3,      32'sd5);
    apply_and_check("all zero",       32'sd0,       32'sd0,      32'sd0);
    apply_and_check("all positive",   32'sd100,     32'sd200,    32'sd300);
    apply_and_check("all negative",  -32'sd1000,   -32'sd2000,  -32'sd3000);
    apply_and_check("larger values",  32'sd100000, -32'sd50000,  32'sd12345);

    // ----------------------------------------------------------
    // Edge-style tests within safe range
    // Avoid full 32-bit overflow ambiguity.
    // ----------------------------------------------------------
    apply_and_check("positive negative cancel",
                    32'sd500000, -32'sd500000, 32'sd0);

    apply_and_check("two positives one negative",
                    32'sd250000, 32'sd125000, -32'sd300000);

    apply_and_check("two negatives one positive",
                    -32'sd250000, -32'sd125000, 32'sd300000);

    // ----------------------------------------------------------
    // Randomized tests
    // ----------------------------------------------------------
    for (int t = 0; t < 1000; t++) begin
      apply_and_check(
        $sformatf("random_%0d", t),
        rand_range(-100000, 100000),
        rand_range(-100000, 100000),
        rand_range(-100000, 100000)
      );
    end

    $display("============================================================");
    $display("tb_channel_accumulator summary");
    $display("Tests run : %0d", tests);
    $display("Errors    : %0d", errors);
    $display("============================================================");

    if (errors != 0) begin
      $fatal(1, "tb_channel_accumulator FAILED: tests=%0d errors=%0d", tests, errors);
    end else begin
      $display("[PASS] tb_channel_accumulator tests=%0d", tests);
    end

    $finish;
  end

endmodule