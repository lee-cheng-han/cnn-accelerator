`timescale 1ns/1ps

module tb_mac_array_3x3;

  localparam int DATA_WIDTH = 8;
  localparam int WEIGHT_WIDTH = 8;
  localparam int PRODUCT_WIDTH = DATA_WIDTH + WEIGHT_WIDTH;
  localparam int KERNEL_TAPS = 9;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic signed [DATA_WIDTH-1:0]    window [KERNEL_TAPS];
  logic signed [WEIGHT_WIDTH-1:0]  weights[KERNEL_TAPS];
  logic                            enable;
  logic signed [PRODUCT_WIDTH-1:0] products[KERNEL_TAPS];

  int tests;
  int errors;
  int seed;

  mac_array_3x3 #(
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .PRODUCT_WIDTH(PRODUCT_WIDTH),
    .KERNEL_TAPS(KERNEL_TAPS)
  ) dut (
    .window(window),
    .weights(weights),
    .enable(enable),
    .products(products)
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
  // Self-check current vector
  // ------------------------------------------------------------
  task automatic drive_and_check(input string name);
    logic signed [PRODUCT_WIDTH-1:0] expected;

    begin
      @(posedge clk);
      #1;

      for (int i = 0; i < KERNEL_TAPS; i++) begin
        if (enable) begin
          expected = window[i] * weights[i];
        end else begin
          expected = '0;
        end

        tests++;

        if (products[i] !== expected) begin
          errors++;
          $display("[FAIL] %s", name);
          $display("       tap      = %0d", i);
          $display("       window   = %0d", window[i]);
          $display("       weight   = %0d", weights[i]);
          $display("       enable   = %0b", enable);
          $display("       expected = %0d", expected);
          $display("       got      = %0d", products[i]);
          $fatal(1);
        end
      end

      $display("[PASS] %s", name);
    end
  endtask

  task automatic apply_vector(input string name, input bit en);
    begin
      @(negedge clk);
      enable = en;
      drive_and_check(name);
    end
  endtask

  initial begin
    $dumpfile("tb_mac_array_3x3.vcd");
    $dumpvars(0, tb_mac_array_3x3);

    if (!$value$plusargs("ntb_random_seed=%d", seed)) begin
      seed = 32'h2bad_c0de;
    end

    $display("============================================================");
    $display("tb_mac_array_3x3 started");
    $display("SEED = %0d", seed);
    $display("============================================================");

    tests = 0;
    errors = 0;
    enable = 1'b0;

    for (int i = 0; i < KERNEL_TAPS; i++) begin
      window[i]  = '0;
      weights[i] = '0;
    end

    repeat (2) @(posedge clk);

    // ----------------------------------------------------------
    // Directed signed ramp
    // ----------------------------------------------------------
    @(negedge clk);
    for (int i = 0; i < KERNEL_TAPS; i++) begin
      window[i]  = i - 4;
      weights[i] = 8'sd2;
    end
    enable = 1'b1;
    drive_and_check("directed signed ramp");

    // ----------------------------------------------------------
    // Enable-off test
    // ----------------------------------------------------------
    apply_vector("enable zeroes all products", 1'b0);

    // ----------------------------------------------------------
    // INT8 edge cases
    // ----------------------------------------------------------
    @(negedge clk);
    enable = 1'b1;

    window[0]  = 8'sd127;
    weights[0] = 8'sd127;

    window[1]  = -8'sd128;
    weights[1] = 8'sd127;

    window[2]  = -8'sd128;
    weights[2] = -8'sd128;

    window[3]  = 8'sd127;
    weights[3] = -8'sd128;

    for (int i = 4; i < KERNEL_TAPS; i++) begin
      window[i]  = i;
      weights[i] = -i;
    end

    drive_and_check("edge products");

    // ----------------------------------------------------------
    // All zeros
    // ----------------------------------------------------------
    @(negedge clk);
    enable = 1'b1;
    for (int i = 0; i < KERNEL_TAPS; i++) begin
      window[i]  = 8'sd0;
      weights[i] = 8'sd0;
    end
    drive_and_check("all zeros");

    // ----------------------------------------------------------
    // All ones
    // ----------------------------------------------------------
    @(negedge clk);
    enable = 1'b1;
    for (int i = 0; i < KERNEL_TAPS; i++) begin
      window[i]  = 8'sd1;
      weights[i] = 8'sd1;
    end
    drive_and_check("all ones");

    // ----------------------------------------------------------
    // Alternating signs
    // ----------------------------------------------------------
    @(negedge clk);
    enable = 1'b1;
    for (int i = 0; i < KERNEL_TAPS; i++) begin
      if (i % 2 == 0) begin
        window[i]  = 8'sd5;
        weights[i] = -8'sd3;
      end else begin
        window[i]  = -8'sd5;
        weights[i] = 8'sd3;
      end
    end
    drive_and_check("alternating signs");

    // ----------------------------------------------------------
    // Randomized tests
    // ----------------------------------------------------------
    for (int t = 0; t < 300; t++) begin
      @(negedge clk);

      enable = rand_range(0, 1);

      for (int i = 0; i < KERNEL_TAPS; i++) begin
        window[i]  = rand_range(-128, 127);
        weights[i] = rand_range(-128, 127);
      end

      drive_and_check($sformatf("random_array_%0d", t));
    end

    $display("============================================================");
    $display("tb_mac_array_3x3 summary");
    $display("Tests run : %0d", tests);
    $display("Errors    : %0d", errors);
    $display("============================================================");

    if (errors != 0) begin
      $fatal(1, "tb_mac_array_3x3 FAILED: tests=%0d errors=%0d", tests, errors);
    end else begin
      $display("[PASS] tb_mac_array_3x3 tests=%0d", tests);
    end

    $finish;
  end

endmodule