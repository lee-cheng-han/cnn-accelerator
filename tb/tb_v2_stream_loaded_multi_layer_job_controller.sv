`timescale 1ns/1ps

module tb_v2_stream_loaded_multi_layer_job_controller;

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
  localparam int IMAGE_W    = 4;
  localparam int IMAGE_H    = 3;
  localparam int PIXELS     = IMAGE_W * IMAGE_H;

  logic clk;
  logic rst_n;
  logic start;
  logic final_residual_enable;
  logic [15:0] image_width;
  logic [15:0] image_height;
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
      output_stream_ready <= (ready_cycle % 5) != 2;
    end
  end

  function automatic logic signed [DATA_W-1:0] input_value(input int pixel, input int channel);
    begin
      case (channel)
        0: return $signed(DATA_W'(((pixel * 3) + 1) % 29));
        1: return $signed(DATA_W'(((pixel * 5) + 2) % 31));
        2: return $signed(DATA_W'(((pixel * 7) + 3) % 37));
        default: return '0;
      endcase
    end
  endfunction

  function automatic logic signed [OUT_W-1:0] expected_value(
    input int pixel,
    input int channel,
    input logic expect_residual_zero
  );
    begin
      return expect_residual_zero ? '0 : input_value(pixel, channel);
    end
  endfunction

  function automatic logic signed [DATA_W-1:0] weight_value(
    input int layer,
    input int co,
    input int ci,
    input int k
  );
    begin
      unique case (layer)
        0: return ((co % INPUT_C) == ci && k == 4) ? 8'sd1 : 8'sd0;
        1: return ((co == ci) && k == 4) ? 8'sd1 : 8'sd0;
        2: return ((co == ci) && k == 4) ? 8'sd1 : 8'sd0;
        default: return 8'sd0;
      endcase
    end
  endfunction

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

  task automatic feed_activation(input int valid_skew);
    int word_idx;
    int stall_cycle;
    int pixel;
    int channel;
    begin
      word_idx = 0;
      stall_cycle = 0;

      while (word_idx < (PIXELS * INPUT_C)) begin
        @(negedge clk);
        pixel = word_idx / INPUT_C;
        channel = word_idx % INPUT_C;
        activation_stream_data = input_value(pixel, channel);
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

  task automatic feed_bias(input int count, input int valid_skew);
    int word_idx;
    int stall_cycle;
    begin
      word_idx = 0;
      stall_cycle = 0;

      while (word_idx < count) begin
        @(negedge clk);
        bias_stream_data = '0;
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
    input int layer,
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
        weight_stream_data = weight_value(layer, co, ci, k);
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
      feed_bias(HIDDEN_C, valid_skew + 1);
      feed_weights(0, HIDDEN_C, INPUT_C, valid_skew + 2);
      feed_bias(HIDDEN_C, valid_skew + 3);
      feed_weights(1, HIDDEN_C, HIDDEN_C, valid_skew + 4);
      feed_bias(OUTPUT_C, valid_skew + 5);
      feed_weights(2, OUTPUT_C, HIDDEN_C, valid_skew + 6);
    end
  endtask

  task automatic collect_outputs(input string name, input logic expect_residual_zero);
    int pixel;
    int channel;
    logic signed [OUT_W-1:0] expected;
    begin
      output_count = 0;
      last_count = 0;

      while (output_count < (PIXELS * OUTPUT_C)) begin
        @(negedge clk);

        if (output_stream_valid && output_stream_ready) begin
          pixel = output_count / OUTPUT_C;
          channel = output_count % OUTPUT_C;
          expected = expected_value(pixel, channel, expect_residual_zero);

          if (output_stream_data !== expected) begin
            $display("[FAIL] %s: word=%0d pixel=%0d channel=%0d expected=%0d got=%0d",
                     name, output_count, pixel, channel, expected, output_stream_data);
            $finish;
          end

          if (output_stream_last) begin
            last_count++;
            if (output_count != ((PIXELS * OUTPUT_C) - 1)) begin
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

  task automatic run_streamed_job(
    input string name,
    input logic enable_residual,
    input logic expect_residual_zero,
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
      collect_outputs(name, expect_residual_zero);

      timeout = 0;
      while (!done && (timeout < 400000)) begin
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
    image_width = IMAGE_W;
    image_height = IMAGE_H;
    tests = 0;
    output_count = 0;
    last_count = 0;
    clear_streams();

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    run_streamed_job("stream_loaded_identity_with_residual_subtract", 1'b1, 1'b1, 0);
    run_streamed_job("stream_loaded_identity_without_residual_subtract", 1'b0, 1'b0, 2);

    $display("[PASS] tb_v2_stream_loaded_multi_layer_job_controller tests=%0d", tests);
    $finish;
  end

endmodule
