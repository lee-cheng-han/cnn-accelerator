`timescale 1ns/1ps

module tb_cnn_system_core;

  localparam int DATA_WIDTH = 8;
  localparam int IC = 3;
  localparam int OC = 4;
  localparam int K  = 9;
  localparam int NUM_WEIGHTS = IC * OC * K;

  localparam int IMG_W = 4;
  localparam int IMG_H = 4;
  localparam int NUM_PIXELS = IMG_W * IMG_H * IC;
  localparam int NUM_OUTPUTS = IMG_W * IMG_H * OC;

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

  logic signed [7:0] pixel_data;
  logic pixel_valid;
  logic pixel_ready;

  logic read_request_valid;

  logic [7:0] tx_data;
  logic tx_valid;
  logic tx_ready;

  logic config_loaded;
  logic weights_loaded;
  logic bias_loaded;
  logic system_ready;

  logic result_buffer_full;
  logic result_buffer_empty;
  logic result_buffer_done;

  logic result_sender_busy;
  logic result_sender_done;

  logic [31:0] windows_seen;
  logic [31:0] outputs_seen;
  logic [31:0] result_bytes_written;
  logic [31:0] result_bytes_read;
  logic [31:0] result_bytes_stored;
  logic [31:0] result_bytes_sent;

  int errors;
  int checks;

  logic signed [7:0] image [IMG_W * IMG_H][IC];
  logic signed [7:0] expected_q [$];

  cnn_system_core #(
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_INPUT_CHANNELS(IC),
    .NUM_OUTPUT_CHANNELS(OC),
    .KERNEL_TAPS(K),
    .MAX_IMG_WIDTH(64),
    .RESULT_DEPTH(256)
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

    .pixel_data(pixel_data),
    .pixel_valid(pixel_valid),
    .pixel_ready(pixel_ready),

    .read_request_valid(read_request_valid),

    .tx_data(tx_data),
    .tx_valid(tx_valid),
    .tx_ready(tx_ready),

    .config_loaded(config_loaded),
    .weights_loaded(weights_loaded),
    .bias_loaded(bias_loaded),
    .system_ready(system_ready),

    .result_buffer_full(result_buffer_full),
    .result_buffer_empty(result_buffer_empty),
    .result_buffer_done(result_buffer_done),

    .result_sender_busy(result_sender_busy),
    .result_sender_done(result_sender_done),

    .windows_seen(windows_seen),
    .outputs_seen(outputs_seen),
    .result_bytes_written(result_bytes_written),
    .result_bytes_read(result_bytes_read),
    .result_bytes_stored(result_bytes_stored),
    .result_bytes_sent(result_bytes_sent)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic reset_dut;
    begin
      clear = 1'b0;

      cfg_valid = 1'b0;
      cfg_width = 16'd0;
      cfg_height = 16'd0;
      cfg_kernel_mode = 1'b0;
      cfg_relu_enable = 1'b0;
      cfg_bias_enable = 1'b0;
      cfg_quant_enable = 1'b0;
      cfg_quant_shift = 5'd0;

      weight_valid = 1'b0;
      weight_index = 8'd0;
      weight_data = 8'sd0;
      weights_done = 1'b0;

      bias_valid = 1'b0;
      bias_index = 2'd0;
      bias_data = 32'sd0;
      bias_done = 1'b0;

      pixel_data = 8'sd0;
      pixel_valid = 1'b0;

      read_request_valid = 1'b0;
      tx_ready = 1'b1;

      expected_q.delete();

      rst_n = 1'b0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (5) @(posedge clk);
    end
  endtask

  task automatic pulse_cfg;
    begin
      @(negedge clk);
      cfg_width = IMG_W;
      cfg_height = IMG_H;
      cfg_kernel_mode = 1'b0; // 1x1 mode
      cfg_relu_enable = 1'b0;
      cfg_bias_enable = 1'b0;
      cfg_quant_enable = 1'b0;
      cfg_quant_shift = 5'd0;
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

  task automatic pulse_weights_done;
    begin
      @(negedge clk);
      weights_done = 1'b1;
      @(negedge clk);
      weights_done = 1'b0;
    end
  endtask

  task automatic load_weights_identity_like;
    int idx;
    int oc;
    int ic;
    int tap;
    logic signed [7:0] w;
    begin
      $display("[TEST] load weights");

      for (int i = 0; i < NUM_WEIGHTS; i++) begin
        oc = i / (IC * K);
        ic = (i / K) % IC;
        tap = i % K;

        // 1x1 mode uses tap 0 only.
        // Output channels:
        // oc0 = ch0
        // oc1 = ch1
        // oc2 = ch2
        // oc3 = ch0 + ch1 + ch2
        w = 8'sd0;

        if (tap == 0) begin
          if (oc == 0 && ic == 0) w = 8'sd1;
          if (oc == 1 && ic == 1) w = 8'sd1;
          if (oc == 2 && ic == 2) w = 8'sd1;
          if (oc == 3) w = 8'sd1;
        end

        pulse_weight(i, w);
      end

      pulse_weights_done();
    end
  endtask

  task automatic init_image_and_expected;
    int p;
    logic signed [31:0] acc;
    logic signed [7:0] out_val;
    begin
      $display("[TEST] build golden model");

      expected_q.delete();

      for (int y = 0; y < IMG_H; y++) begin
        for (int x = 0; x < IMG_W; x++) begin
          p = y * IMG_W + x;

          image[p][0] = p + 1;
          image[p][1] = p + 2;
          image[p][2] = p + 3;

          // oc0
          expected_q.push_back(image[p][0]);

          // oc1
          expected_q.push_back(image[p][1]);

          // oc2
          expected_q.push_back(image[p][2]);

          // oc3
          acc = image[p][0] + image[p][1] + image[p][2];
          out_val = acc[7:0];
          expected_q.push_back(out_val);
        end
      end
    end
  endtask

  task automatic stream_image;
    int p;
    begin
      $display("[TEST] stream image");

      for (int y = 0; y < IMG_H; y++) begin
        for (int x = 0; x < IMG_W; x++) begin
          p = y * IMG_W + x;

          for (int ic = 0; ic < IC; ic++) begin
            @(negedge clk);
            pixel_data = image[p][ic];
            pixel_valid = 1'b1;

            while (!pixel_ready) begin
              @(posedge clk);
              #1;
            end

            @(posedge clk);
            #1;

            @(negedge clk);
            pixel_valid = 1'b0;
            pixel_data = 8'sd0;
          end
        end
      end
    end
  endtask

  task automatic wait_for_outputs;
    int cycles;
    begin
      cycles = 0;

      while ((result_bytes_written < NUM_OUTPUTS) && cycles < 2000) begin
        @(posedge clk);
        cycles++;
      end

      checks++;
      if (result_bytes_written != NUM_OUTPUTS) begin
        errors++;
        $error("Timeout waiting for outputs, got=%0d expected=%0d",
               result_bytes_written, NUM_OUTPUTS);
      end
    end
  endtask

  task automatic request_readback;
    begin
      $display("[TEST] readback");

      @(negedge clk);
      read_request_valid = 1'b1;
      @(negedge clk);
      read_request_valid = 1'b0;
    end
  endtask

  task automatic check_tx_output;
    int cycles;
    logic signed [7:0] expected;
    begin
      cycles = 0;
      tx_ready = 1'b1;

      while ((expected_q.size() > 0) && cycles < 3000) begin
        @(posedge clk);

        if (tx_valid && tx_ready) begin
          expected = expected_q.pop_front();

          checks++;
          if ($signed(tx_data) !== expected) begin
            errors++;
            $error("TX mismatch got=%0d expected=%0d", $signed(tx_data), expected);
          end
        end

        cycles++;
      end

      checks++;
      if (expected_q.size() != 0) begin
        errors++;
        $error("Readback incomplete, remaining=%0d", expected_q.size());
      end

      repeat (10) @(posedge clk);
    end
  endtask

  task automatic check_int(input string name, input int got, input int expected);
    begin
      checks++;
      if (got != expected) begin
        errors++;
        $error("%s got=%0d expected=%0d", name, got, expected);
      end
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("CNN SYSTEM CORE TEST SUMMARY");
      $display("============================================================");
      $display("Checks run            : %0d", checks);
      $display("Total errors          : %0d", errors);
      $display("System ready          : %0d", system_ready);
      $display("Windows seen          : %0d", windows_seen);
      $display("Outputs seen          : %0d", outputs_seen);
      $display("Result bytes written  : %0d", result_bytes_written);
      $display("Result bytes read     : %0d", result_bytes_read);
      $display("Result bytes sent     : %0d", result_bytes_sent);
      $display("Status                : %s", (errors == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;

    reset_dut();

    $display("[TEST] config");
    pulse_cfg();

    load_weights_identity_like();

    repeat (10) @(posedge clk);

    check_int("config_loaded", config_loaded, 1);
    check_int("weights_loaded", weights_loaded, 1);
    check_int("system_ready", system_ready, 1);

    init_image_and_expected();
    stream_image();

    wait_for_outputs();

    check_int("outputs_seen", outputs_seen, NUM_OUTPUTS);
    check_int("result_bytes_written", result_bytes_written, NUM_OUTPUTS);

    request_readback();
    check_tx_output();

    check_int("result_bytes_sent", result_bytes_sent, NUM_OUTPUTS);

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_cnn_system_core");
    end else begin
      $fatal(1, "[FAIL] tb_cnn_system_core errors=%0d", errors);
    end

    $finish;
  end

endmodule
