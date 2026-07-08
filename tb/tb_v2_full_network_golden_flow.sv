`timescale 1ns/1ps

module tb_v2_full_network_golden_flow;

  localparam int PC         = 4;
  localparam int PK         = 8;
  localparam int MAX_CIN    = 16;
  localparam int MAX_COUT   = 16;
  localparam int MAX_PIXELS = 64;
  localparam int INPUT_C    = 3;
  localparam int HIDDEN_C   = 16;
  localparam int OUTPUT_C   = 3;
  localparam int DATA_W     = 8;
  localparam int ACC_W      = 32;
  localparam int OUT_W      = 8;
  localparam int CFG_WORDS  = 5;

  localparam int CFG_INPUT_WIDTH  = 0;
  localparam int CFG_INPUT_HEIGHT = 1;
  localparam int CFG_OUTPUT_WIDTH = 2;
  localparam int CFG_OUTPUT_HEIGHT = 3;

  logic clk;
  logic rst_n;
  logic start;
  logic final_residual_enable;
  logic [15:0] image_width;
  logic [15:0] image_height;
  logic [15:0] output_width;
  logic [15:0] output_height;
  logic signed [DATA_W-1:0] input_tensor [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] weights_l0 [HIDDEN_C][INPUT_C][9];
  logic signed [DATA_W-1:0] weights_l1 [HIDDEN_C][HIDDEN_C][9];
  logic signed [DATA_W-1:0] weights_l2 [OUTPUT_C][HIDDEN_C][9];
  logic signed [ACC_W-1:0] bias_l0 [HIDDEN_C];
  logic signed [ACC_W-1:0] bias_l1 [HIDDEN_C];
  logic signed [ACC_W-1:0] bias_l2 [OUTPUT_C];
  logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT];
  logic [1:0] active_layer;
  logic busy;
  logic done;

  logic [31:0] cfg_mem [CFG_WORDS];
  logic signed [DATA_W-1:0] input_mem [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] weights_l0_mem [MAX_COUT*MAX_CIN*9];
  logic signed [DATA_W-1:0] weights_l1_mem [MAX_COUT*MAX_CIN*9];
  logic signed [DATA_W-1:0] weights_l2_mem [MAX_COUT*MAX_CIN*9];
  logic signed [ACC_W-1:0] bias_l0_mem [MAX_COUT];
  logic signed [ACC_W-1:0] bias_l1_mem [MAX_COUT];
  logic signed [ACC_W-1:0] bias_l2_mem [MAX_COUT];
  logic signed [OUT_W-1:0] expected_residual_mem [MAX_PIXELS*MAX_COUT];
  logic signed [OUT_W-1:0] expected_no_residual_mem [MAX_PIXELS*MAX_COUT];

  int tests;

  multi_layer_job_controller #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_PIXELS),
    .INPUT_C(INPUT_C),
    .HIDDEN_C(HIDDEN_C),
    .OUTPUT_C(OUTPUT_C),
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .BIAS_W(ACC_W),
    .OUT_W(OUT_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .final_residual_enable(final_residual_enable),
    .image_width(image_width),
    .image_height(image_height),
    .input_tensor(input_tensor),
    .weights_l0(weights_l0),
    .weights_l1(weights_l1),
    .weights_l2(weights_l2),
    .bias_l0(bias_l0),
    .bias_l1(bias_l1),
    .bias_l2(bias_l2),
    .output_tensor(output_tensor),
    .active_layer(active_layer),
    .busy(busy),
    .done(done)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function automatic string file_in_dir(input string dir, input string name);
    begin
      return {dir, "/", name};
    end
  endfunction

  task automatic clear_arrays;
    begin
      for (int i = 0; i < CFG_WORDS; i++) begin
        cfg_mem[i] = '0;
      end

      for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
        input_mem[i] = '0;
        input_tensor[i] = '0;
      end

      for (int i = 0; i < MAX_COUT*MAX_CIN*9; i++) begin
        weights_l0_mem[i] = '0;
        weights_l1_mem[i] = '0;
        weights_l2_mem[i] = '0;
      end

      for (int i = 0; i < MAX_COUT; i++) begin
        bias_l0_mem[i] = '0;
        bias_l1_mem[i] = '0;
        bias_l2_mem[i] = '0;
      end

      for (int i = 0; i < MAX_PIXELS*MAX_COUT; i++) begin
        expected_residual_mem[i] = '0;
        expected_no_residual_mem[i] = '0;
      end

      for (int co = 0; co < HIDDEN_C; co++) begin
        bias_l0[co] = '0;
        bias_l1[co] = '0;

        for (int ci = 0; ci < INPUT_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights_l0[co][ci][k] = '0;
          end
        end

        for (int ci = 0; ci < HIDDEN_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights_l1[co][ci][k] = '0;
          end
        end
      end

      for (int co = 0; co < OUTPUT_C; co++) begin
        bias_l2[co] = '0;

        for (int ci = 0; ci < HIDDEN_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights_l2[co][ci][k] = '0;
          end
        end
      end
    end
  endtask

  task automatic load_case(input string case_dir);
    begin
      clear_arrays();

      $readmemh(file_in_dir(case_dir, "config.mem"), cfg_mem);
      $readmemh(file_in_dir(case_dir, "input.mem"), input_mem);
      $readmemh(file_in_dir(case_dir, "weights_l0.mem"), weights_l0_mem);
      $readmemh(file_in_dir(case_dir, "weights_l1.mem"), weights_l1_mem);
      $readmemh(file_in_dir(case_dir, "weights_l2.mem"), weights_l2_mem);
      $readmemh(file_in_dir(case_dir, "bias_l0.mem"), bias_l0_mem);
      $readmemh(file_in_dir(case_dir, "bias_l1.mem"), bias_l1_mem);
      $readmemh(file_in_dir(case_dir, "bias_l2.mem"), bias_l2_mem);
      $readmemh(file_in_dir(case_dir, "expected_residual.mem"), expected_residual_mem);
      $readmemh(file_in_dir(case_dir, "expected_no_residual.mem"), expected_no_residual_mem);

      image_width = cfg_mem[CFG_INPUT_WIDTH][15:0];
      image_height = cfg_mem[CFG_INPUT_HEIGHT][15:0];
      output_width = cfg_mem[CFG_OUTPUT_WIDTH][15:0];
      output_height = cfg_mem[CFG_OUTPUT_HEIGHT][15:0];

      for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
        input_tensor[i] = input_mem[i];
      end

      for (int co = 0; co < HIDDEN_C; co++) begin
        bias_l0[co] = bias_l0_mem[co];
        bias_l1[co] = bias_l1_mem[co];

        for (int ci = 0; ci < INPUT_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights_l0[co][ci][k] = weights_l0_mem[((co * MAX_CIN + ci) * 9) + k];
          end
        end

        for (int ci = 0; ci < HIDDEN_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights_l1[co][ci][k] = weights_l1_mem[((co * MAX_CIN + ci) * 9) + k];
          end
        end
      end

      for (int co = 0; co < OUTPUT_C; co++) begin
        bias_l2[co] = bias_l2_mem[co];

        for (int ci = 0; ci < HIDDEN_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights_l2[co][ci][k] = weights_l2_mem[((co * MAX_CIN + ci) * 9) + k];
          end
        end
      end
    end
  endtask

  task automatic run_job(input string name, input logic enable_residual);
    int timeout;
    begin
      $display("[TEST] %s", name);

      final_residual_enable = enable_residual;
      start = 1'b1;
      @(posedge clk);
      start = 1'b0;

      timeout = 0;
      while (!done && (timeout < 300000)) begin
        @(posedge clk);
        timeout++;
      end

      if (!done) begin
        $display("[FAIL] %s: timed out waiting for done", name);
        $finish;
      end

      if (busy) begin
        $display("[FAIL] %s: busy stayed high with done", name);
        $finish;
      end

      tests++;
      @(posedge clk);
    end
  endtask

  task automatic check_outputs(input string name, input logic expect_residual);
    int out_idx;
    logic signed [OUT_W-1:0] expected;
    begin
      for (int oy = 0; oy < output_height; oy++) begin
        for (int ox = 0; ox < output_width; ox++) begin
          for (int co = 0; co < MAX_COUT; co++) begin
            out_idx = ((oy * output_width) + ox) * MAX_COUT + co;
            expected = expect_residual ? expected_residual_mem[out_idx] :
                                        expected_no_residual_mem[out_idx];

            if (output_tensor[out_idx] !== expected) begin
              $display("[FAIL] %s: pixel=(%0d,%0d) co=%0d expected=%0d got=%0d",
                       name, ox, oy, co, expected, output_tensor[out_idx]);
              $finish;
            end
          end
        end
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    start = 1'b0;
    final_residual_enable = 1'b1;
    image_width = '0;
    image_height = '0;
    output_width = '0;
    output_height = '0;
    tests = 0;

    clear_arrays();

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    load_case("../../build/v2_golden/full_network_3layer");

    run_job("python_golden_full_network_3layer_residual", 1'b1);
    check_outputs("python_golden_full_network_3layer_residual", 1'b1);

    run_job("python_golden_full_network_3layer_no_residual", 1'b0);
    check_outputs("python_golden_full_network_3layer_no_residual", 1'b0);

    $display("[PASS] tb_v2_full_network_golden_flow tests=%0d", tests);
    $finish;
  end

endmodule
