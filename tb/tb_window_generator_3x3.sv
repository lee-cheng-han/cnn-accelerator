`timescale 1ns/1ps

module tb_window_generator_3x3;

  localparam int DATA_WIDTH = 8;
  localparam int KERNEL_TAPS = 9;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic signed [DATA_WIDTH-1:0] taps  [KERNEL_TAPS];
  logic                         taps_valid;
  logic signed [DATA_WIDTH-1:0] window[KERNEL_TAPS];
  logic                         window_valid;

  int tests;
  int errors;
  int seed;

  window_generator_3x3 #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .taps(taps),
    .taps_valid(taps_valid),
    .window(window),
    .window_valid(window_valid)
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
  // Self-check task
  // Drive on negedge, check after posedge.
  // ------------------------------------------------------------
  task automatic drive_and_check(input string name, input bit valid);
    begin
      @(negedge clk);
      taps_valid = valid;

      @(posedge clk);
      #1;

      tests++;

      if (window_valid !== taps_valid) begin
        errors++;
        $display("[FAIL] %s valid mismatch", name);
        $display("       got      = %0b", window_valid);
        $display("       expected = %0b", taps_valid);
        $fatal(1);
      end

      for (int i = 0; i < KERNEL_TAPS; i++) begin
        tests++;

        if (window[i] !== taps[i]) begin
          errors++;
          $display("[FAIL] %s tap mismatch", name);
          $display("       tap      = %0d", i);
          $display("       got      = %0d", window[i]);
          $display("       expected = %0d", taps[i]);
          $fatal(1);
        end
      end

      $display("[PASS] %s", name);
    end
  endtask

  initial begin
    $dumpfile("tb_window_generator_3x3.vcd");
    $dumpvars(0, tb_window_generator_3x3);

    if (!$value$plusargs("ntb_random_seed=%d", seed)) begin
      seed = 32'h5bad_c0de;
    end

    $display("============================================================");
    $display("tb_window_generator_3x3 started");
    $display("SEED = %0d", seed);
    $display("============================================================");

    tests = 0;
    errors = 0;
    taps_valid = 1'b0;

    for (int i = 0; i < KERNEL_TAPS; i++) begin
      taps[i] = '0;
    end

    repeat (2) @(posedge clk);

    // ----------------------------------------------------------
    // Directed ramp, valid high
    // ----------------------------------------------------------
    @(negedge clk);
    for (int i = 0; i < KERNEL_TAPS; i++) begin
      taps[i] = i;
    end
    drive_and_check("ramp valid", 1'b1);

    // ----------------------------------------------------------
    // Directed negative ramp, valid low
    // Data should still pass through, valid should be low.
    // ----------------------------------------------------------
    @(negedge clk);
    for (int i = 0; i < KERNEL_TAPS; i++) begin
      taps[i] = -i;
    end
    drive_and_check("ramp invalid still passes data combinationally", 1'b0);

    // ----------------------------------------------------------
    // All zeros
    // ----------------------------------------------------------
    @(negedge clk);
    for (int i = 0; i < KERNEL_TAPS; i++) begin
      taps[i] = 8'sd0;
    end
    drive_and_check("all zeros valid", 1'b1);

    // ----------------------------------------------------------
    // INT8 edge values
    // ----------------------------------------------------------
    @(negedge clk);
    taps[0] = 8'sd127;
    taps[1] = -8'sd128;
    taps[2] = 8'sd0;
    taps[3] = 8'sd1;
    taps[4] = -8'sd1;
    taps[5] = 8'sd64;
    taps[6] = -8'sd64;
    taps[7] = 8'sd32;
    taps[8] = -8'sd32;
    drive_and_check("int8 edge values", 1'b1);

    // ----------------------------------------------------------
    // Randomized tests
    // ----------------------------------------------------------
    for (int t = 0; t < 300; t++) begin
      @(negedge clk);

      for (int i = 0; i < KERNEL_TAPS; i++) begin
        taps[i] = rand_range(-128, 127);
      end

      taps_valid = rand_range(0, 1);

      @(posedge clk);
      #1;

      tests++;

      if (window_valid !== taps_valid) begin
        errors++;
        $display("[FAIL] random_%0d valid mismatch", t);
        $display("       got      = %0b", window_valid);
        $display("       expected = %0b", taps_valid);
        $fatal(1);
      end

      for (int i = 0; i < KERNEL_TAPS; i++) begin
        tests++;

        if (window[i] !== taps[i]) begin
          errors++;
          $display("[FAIL] random_%0d tap mismatch", t);
          $display("       tap      = %0d", i);
          $display("       got      = %0d", window[i]);
          $display("       expected = %0d", taps[i]);
          $fatal(1);
        end
      end
    end

    $display("============================================================");
    $display("tb_window_generator_3x3 summary");
    $display("Tests run : %0d", tests);
    $display("Errors    : %0d", errors);
    $display("============================================================");

    if (errors != 0) begin
      $fatal(1, "tb_window_generator_3x3 FAILED: tests=%0d errors=%0d", tests, errors);
    end else begin
      $display("[PASS] tb_window_generator_3x3 tests=%0d", tests);
    end

    $finish;
  end

endmodule