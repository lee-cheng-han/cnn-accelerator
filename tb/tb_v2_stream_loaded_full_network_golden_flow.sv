`timescale 1ns/1ps

module tb_v2_stream_loaded_full_network_golden_flow;

  localparam int PC         = 4;
  localparam int PK         = 8;
  localparam int MAX_CIN    = 16;
  localparam int MAX_COUT   = 16;
  localparam int MAX_PIXELS = 64;
  localparam int INPUT_C    = 3;
  localparam int HIDDEN_C   = 16;
  localparam int OUTPUT_C   = 3;
  localparam int DATA_W     = 8;
  localparam int BIAS_W     = 32;
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
  logic activation_stream_valid;
  logic activation_stream_ready;
  logic signed [DATA_W-1:0] activation_stream_data;
  logic bias_stream_valid;
  logic bias_stream_ready;
  logic signed [BIAS_W-1:0] bias_stream_data;
  logic weight_stream_valid;
  logic weight_stream_ready;
  logic signed [DATA_W-1:0] weight_stream_data;
  logic output_stream_valid;
  logic output_stream_ready;
  logic signed [OUT_W-1:0] output_stream_data;
  logic output_stream_last;
  logic [3:0] phase;
  logic [1:0] active_layer;
  logic busy;
  logic done;
  logic error;

  logic [31:0] cfg_mem [CFG_WORDS];
  logic signed [DATA_W-1:0] input_mem [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] weights_l0_mem [MAX_COUT*MAX_CIN*9];
  logic signed [DATA_W-1:0] weights_l1_mem [MAX_COUT*MAX_CIN*9];
  logic signed [DATA_W-1:0] weights_l2_mem [MAX_COUT*MAX_CIN*9];
  logic signed [BIAS_W-1:0] bias_l0_mem [MAX_COUT];
  logic signed [BIAS_W-1:0] bias_l1_mem [MAX_COUT];
  logic signed [BIAS_W-1:0] bias_l2_mem [MAX_COUT];
  logic signed [OUT_W-1:0] expected_residual_mem [MAX_PIXELS*MAX_COUT];
  logic signed [OUT_W-1:0] expected_no_residual_mem [MAX_PIXELS*MAX_COUT];

  int tests;
  int ready_cycle;
  int output_count;
  int last_count;

  stream_loaded_multi_layer_job_controller #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_PIXELS),
    .INPUT_C(INPUT_C),
    .HIDDEN_C(HIDDEN_C),
    .OUTPUT_C(OUTPUT_C),
    .DATA_W(DATA_W),
    .BIAS_W(BIAS_W),
    .OUT_W(OUT_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .final_residual_enable(final_residual_enable),
    .image_width(image_width),
    .image_height(image_height),
    .activation_stream_valid(activation_stream_valid),
    .activation_stream_ready(activation_stream_ready),
    .activation_stream_data(activation_stream_data),
    .bias_stream_valid(bias_stream_valid),
    .bias_stream_ready(bias_stream_ready),
    .bias_stream_data(bias_stream_data),
    .weight_stream_valid(weight_stream_valid),
    .weight_stream_ready(weight_stream_ready),
    .weight_stream_data(weight_stream_data),
    .output_stream_valid(output_stream_valid),
    .output_stream_ready(output_stream_ready),
    .output_stream_data(output_stream_data),
    .output_stream_last(output_stream_last),
    .phase(phase),
    .active_layer(active_layer),
    .busy(busy),
    .done(done),
    .error(error)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ready_cycle <= 0;
      output_stream_ready <= 1'b0;
    end else begin
      ready_cycle <= ready_cycle + 1;
      output_stream_ready <= (ready_cycle % 7) != 3;
    end
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
    end
  endtask

  task automatic clear_streams;
    begin
      activation_stream_valid = 1'b0;
      activation_stream_data = '0;
      bias_stream_valid = 1'b0;
      bias_stream_data = '0;
      weight_stream_valid = 1'b0;
      weight_stream_data = '0;
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
    end
  endtask

  task automatic feed_activation(input int valid_skew);
    int word_idx;
    int stall_cycle;
    int pixel;
    int channel;
    begin
      word_idx = 0;
      stall_cycle = 0;

      while (word_idx < (image_width * image_height * INPUT_C)) begin
        @(negedge clk);
        pixel = word_idx / INPUT_C;
        channel = word_idx % INPUT_C;
        activation_stream_data = input_mem[(pixel * MAX_CIN) + channel];
        activation_stream_valid = ((stall_cycle + valid_skew) % 4) != 1;
        @(posedge clk);
        stall_cycle++;

        if (activation_stream_valid && activation_stream_ready) begin
          word_idx++;
        end
      end

      @(negedge clk);
      activation_stream_valid = 1'b0;
      activation_stream_data = '0;
      @(posedge clk);
    end
  endtask

  task automatic feed_bias(
    input logic signed [BIAS_W-1:0] bias_mem [MAX_COUT],
    input int count,
    input int valid_skew
  );
    int word_idx;
    int stall_cycle;
    begin
      word_idx = 0;
      stall_cycle = 0;

      while (word_idx < count) begin
        @(negedge clk);
        bias_stream_data = bias_mem[word_idx];
        bias_stream_valid = ((stall_cycle + valid_skew) % 3) != 0;
        @(posedge clk);
        stall_cycle++;

        if (bias_stream_valid && bias_stream_ready) begin
          word_idx++;
        end
      end

      @(negedge clk);
      bias_stream_valid = 1'b0;
      bias_stream_data = '0;
      @(posedge clk);
    end
  endtask

  task automatic feed_weights(
    input logic signed [DATA_W-1:0] weights_mem [MAX_COUT*MAX_CIN*9],
    input int cout,
    input int cin,
    input int valid_skew
  );
    int word_idx;
    int stall_cycle;
    int co;
    int ci;
    int k;
    begin
      word_idx = 0;
      stall_cycle = 0;

      while (word_idx < (cout * cin * 9)) begin
        @(negedge clk);
        co = word_idx / (cin * 9);
        ci = (word_idx / 9) % cin;
        k = word_idx % 9;
        weight_stream_data = weights_mem[((co * MAX_CIN + ci) * 9) + k];
        weight_stream_valid = ((stall_cycle + valid_skew) % 5) != 2;
        @(posedge clk);
        stall_cycle++;

        if (weight_stream_valid && weight_stream_ready) begin
          word_idx++;
        end
      end

      @(negedge clk);
      weight_stream_valid = 1'b0;
      weight_stream_data = '0;
      @(posedge clk);
    end
  endtask

  task automatic feed_job(input int valid_skew);
    begin
      feed_activation(valid_skew);
      feed_bias(bias_l0_mem, HIDDEN_C, valid_skew + 1);
      feed_weights(weights_l0_mem, HIDDEN_C, INPUT_C, valid_skew + 2);
      feed_bias(bias_l1_mem, HIDDEN_C, valid_skew + 3);
      feed_weights(weights_l1_mem, HIDDEN_C, HIDDEN_C, valid_skew + 4);
      feed_bias(bias_l2_mem, OUTPUT_C, valid_skew + 5);
      feed_weights(weights_l2_mem, OUTPUT_C, HIDDEN_C, valid_skew + 6);
    end
  endtask

  task automatic collect_outputs(input string name, input logic expect_residual);
    int pixel;
    int channel;
    int expected_idx;
    logic signed [OUT_W-1:0] expected;
    begin
      output_count = 0;
      last_count = 0;

      while (output_count < (output_width * output_height * OUTPUT_C)) begin
        @(negedge clk);

        if (output_stream_valid && output_stream_ready) begin
          pixel = output_count / OUTPUT_C;
          channel = output_count % OUTPUT_C;
          expected_idx = (pixel * MAX_COUT) + channel;
          expected = expect_residual ? expected_residual_mem[expected_idx] :
                                      expected_no_residual_mem[expected_idx];

          if (output_stream_data !== expected) begin
            $display("[FAIL] %s: word=%0d pixel=%0d channel=%0d expected=%0d got=%0d",
                     name, output_count, pixel, channel, expected, output_stream_data);
            $finish;
          end

          if (output_stream_last) begin
            last_count++;
            if (output_count != ((output_width * output_height * OUTPUT_C) - 1)) begin
              $display("[FAIL] %s: early last at output word %0d", name, output_count);
              $finish;
            end
          end

          output_count++;
        end
      end

      if (last_count != 1) begin
        $display("[FAIL] %s: expected one last pulse, got %0d", name, last_count);
        $finish;
      end

      tests++;
    end
  endtask

  task automatic check_loaded_memories(input string name);
    int pixel_count;
    int idx;
    begin
      pixel_count = image_width * image_height;

      for (int p = 0; p < pixel_count; p++) begin
        for (int c = 0; c < INPUT_C; c++) begin
          idx = (p * MAX_CIN) + c;

          if (dut.input_tensor[idx] !== input_mem[idx]) begin
            $display("[FAIL] %s: loaded input idx=%0d expected=%0d got=%0d",
                     name, idx, input_mem[idx], dut.input_tensor[idx]);
            $finish;
          end
        end
      end

      for (int co = 0; co < HIDDEN_C; co++) begin
        if (dut.bias_l0[co] !== bias_l0_mem[co]) begin
          $display("[FAIL] %s: loaded bias_l0 co=%0d expected=%0d got=%0d",
                   name, co, bias_l0_mem[co], dut.bias_l0[co]);
          $finish;
        end

        if (dut.bias_l1[co] !== bias_l1_mem[co]) begin
          $display("[FAIL] %s: loaded bias_l1 co=%0d expected=%0d got=%0d",
                   name, co, bias_l1_mem[co], dut.bias_l1[co]);
          $finish;
        end

        for (int ci = 0; ci < INPUT_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            idx = ((co * MAX_CIN + ci) * 9) + k;

            if (dut.weights_l0[co][ci][k] !== weights_l0_mem[idx]) begin
              $display("[FAIL] %s: loaded weights_l0 co=%0d ci=%0d k=%0d expected=%0d got=%0d",
                       name, co, ci, k, weights_l0_mem[idx], dut.weights_l0[co][ci][k]);
              $finish;
            end
          end
        end

        for (int ci = 0; ci < HIDDEN_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            idx = ((co * MAX_CIN + ci) * 9) + k;

            if (dut.weights_l1[co][ci][k] !== weights_l1_mem[idx]) begin
              $display("[FAIL] %s: loaded weights_l1 co=%0d ci=%0d k=%0d expected=%0d got=%0d",
                       name, co, ci, k, weights_l1_mem[idx], dut.weights_l1[co][ci][k]);
              $finish;
            end
          end
        end
      end

      for (int co = 0; co < OUTPUT_C; co++) begin
        if (dut.bias_l2[co] !== bias_l2_mem[co]) begin
          $display("[FAIL] %s: loaded bias_l2 co=%0d expected=%0d got=%0d",
                   name, co, bias_l2_mem[co], dut.bias_l2[co]);
          $finish;
        end

        for (int ci = 0; ci < HIDDEN_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            idx = ((co * MAX_CIN + ci) * 9) + k;

            if (dut.weights_l2[co][ci][k] !== weights_l2_mem[idx]) begin
              $display("[FAIL] %s: loaded weights_l2 co=%0d ci=%0d k=%0d expected=%0d got=%0d",
                       name, co, ci, k, weights_l2_mem[idx], dut.weights_l2[co][ci][k]);
              $finish;
            end
          end
        end
      end

      tests++;
    end
  endtask

  task automatic run_streamed_job(
    input string name,
    input logic enable_residual,
    input logic expect_residual,
    input int valid_skew
  );
    int timeout;
    begin
      $display("[TEST] %s", name);

      final_residual_enable = enable_residual;
      start = 1'b1;
      @(posedge clk);
      start = 1'b0;

      feed_job(valid_skew);
      check_loaded_memories(name);
      collect_outputs(name, expect_residual);

      timeout = 0;
      while (!done && (timeout < 500000)) begin
        @(posedge clk);
        timeout++;
      end

      if (!done) begin
        $display("[FAIL] %s: timed out waiting for done", name);
        $finish;
      end

      if (busy || error) begin
        $display("[FAIL] %s: busy=%0b error=%0b at done", name, busy, error);
        $finish;
      end

      tests++;
      @(posedge clk);
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
    output_count = 0;
    last_count = 0;
    clear_arrays();
    clear_streams();

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    load_case("../../build/v2_golden/full_network_3layer");

    run_streamed_job("stream_loaded_python_golden_full_network_3layer_residual", 1'b1, 1'b1, 0);
    run_streamed_job("stream_loaded_python_golden_full_network_3layer_no_residual", 1'b0, 1'b0, 2);

    $display("[PASS] tb_v2_stream_loaded_full_network_golden_flow tests=%0d", tests);
    $finish;
  end

endmodule
