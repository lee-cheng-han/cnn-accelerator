`timescale 1ns/1ps

module tb_uart_cmd_decoder;

  localparam int IC = 3;
  localparam int OC = 4;
  localparam int K  = 9;
  localparam int NUM_WEIGHTS = IC * OC * K;

  logic clk;
  logic rst_n;
  logic clear;

  logic [7:0] rx_data;
  logic rx_valid;

  logic ping_valid;
  logic read_request_valid;

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

  logic pixel_valid;
  logic signed [7:0] pixel_data;

  logic protocol_error;

  int errors;
  int checks;

  int ping_count;
  int cfg_count;
  int weight_count;
  int bias_count;
  int pixel_count;
  int read_count;
  int error_count;

  logic [7:0] expected_pixel_queue [$];
  logic [7:0] expected_weight_queue [$];
  logic signed [31:0] expected_bias_queue [$];

  int weights_done_count;
  int bias_done_count;

  uart_cmd_decoder #(
    .NUM_INPUT_CHANNELS(IC),
    .NUM_OUTPUT_CHANNELS(OC),
    .KERNEL_TAPS(K)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .rx_data(rx_data),
    .rx_valid(rx_valid),

    .ping_valid(ping_valid),
    .read_request_valid(read_request_valid),

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

    .pixel_valid(pixel_valid),
    .pixel_data(pixel_data),

    .protocol_error(protocol_error)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always @(posedge clk) begin
    if (rst_n) begin
      #1;

      if (ping_valid) ping_count++;
      if (cfg_valid) cfg_count++;

      if (weight_valid) begin
        logic [7:0] expected_weight;

        weight_count++;
        checks++;

        if (expected_weight_queue.size() == 0) begin
          errors++;
          $error("Unexpected weight_data=0x%02h index=%0d", weight_data, weight_index);
        end else begin
          expected_weight = expected_weight_queue.pop_front();

          if (weight_data !== expected_weight) begin
            errors++;
            $error("weight_data mismatch got=0x%02h expected=0x%02h index=%0d",
                   weight_data, expected_weight, weight_index);
          end
        end
      end

      if (weights_done) begin
        weights_done_count++;
      end

      if (bias_valid) begin
        logic signed [31:0] expected_bias;

        bias_count++;
        checks++;

        if (expected_bias_queue.size() == 0) begin
          errors++;
          $error("Unexpected bias_data=%0d index=%0d", bias_data, bias_index);
        end else begin
          expected_bias = expected_bias_queue.pop_front();

          if (bias_data !== expected_bias) begin
            errors++;
            $error("bias_data mismatch got=%0d expected=%0d index=%0d",
                   bias_data, expected_bias, bias_index);
          end
        end
      end

      if (bias_done) begin
        bias_done_count++;
      end

      if (pixel_valid) begin
        logic [7:0] expected_pixel;

        pixel_count++;
        checks++;

        if (expected_pixel_queue.size() == 0) begin
          errors++;
          $error("Unexpected pixel_data=0x%02h", pixel_data);
        end else begin
          expected_pixel = expected_pixel_queue.pop_front();

          if (pixel_data !== expected_pixel) begin
            errors++;
            $error("pixel_data mismatch got=0x%02h expected=0x%02h", pixel_data, expected_pixel);
          end
        end
      end

      if (read_request_valid) read_count++;
      if (protocol_error) error_count++;
    end
  end

  task automatic send_byte(input logic [7:0] value);
    begin
      @(negedge clk);
      rx_data = value;
      rx_valid = 1'b1;

      @(posedge clk);
      #1;

      @(negedge clk);
      rx_valid = 1'b0;
      rx_data = 8'd0;

      @(posedge clk);
      #1;
    end
  endtask

  task automatic check_equal_int(input string name, input int got, input int expected);
    begin
      checks++;
      if (got != expected) begin
        errors++;
        $error("%s got=%0d expected=%0d", name, got, expected);
      end
    end
  endtask

  task automatic check_equal_logic(input string name, input logic [31:0] got, input logic [31:0] expected);
    begin
      checks++;
      if (got !== expected) begin
        errors++;
        $error("%s got=0x%08h expected=0x%08h", name, got, expected);
      end
    end
  endtask

  task automatic reset_dut;
    begin
      rx_data = 8'd0;
      rx_valid = 1'b0;
      clear = 1'b0;

      ping_count = 0;
      cfg_count = 0;
      weight_count = 0;
      bias_count = 0;
      pixel_count = 0;
      read_count = 0;
      error_count = 0;
      expected_pixel_queue.delete();
      expected_weight_queue.delete();
      expected_bias_queue.delete();
      weights_done_count = 0;
      bias_done_count = 0;

      rst_n = 1'b0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic test_ping;
    begin
      $display("[TEST] ping");
      send_byte("P");
      check_equal_int("ping_count", ping_count, 1);
    end
  endtask

  task automatic test_config;
    begin
      $display("[TEST] config");

      send_byte("C");
      send_byte(8'd64); // width low
      send_byte(8'd0);  // width high
      send_byte(8'd32); // height low
      send_byte(8'd0);  // height high
      send_byte(8'd1);  // kernel 3x3
      send_byte(8'b0000_0111); // relu,bias,quant
      send_byte(8'd3);  // shift

      check_equal_int("cfg_count", cfg_count, 1);
      check_equal_logic("cfg_width", cfg_width, 32'd64);
      check_equal_logic("cfg_height", cfg_height, 32'd32);
      check_equal_int("cfg_kernel_mode", cfg_kernel_mode, 1);
      check_equal_int("cfg_relu_enable", cfg_relu_enable, 1);
      check_equal_int("cfg_bias_enable", cfg_bias_enable, 1);
      check_equal_int("cfg_quant_enable", cfg_quant_enable, 1);
      check_equal_int("cfg_quant_shift", cfg_quant_shift, 3);
    end
  endtask

  task automatic test_weights;
    logic [7:0] expected_weight;
    begin
      $display("[TEST] weights");

      send_byte("W");

      for (int i = 0; i < NUM_WEIGHTS; i++) begin
        expected_weight = i[7:0];
        expected_weight_queue.push_back(expected_weight);
        send_byte(expected_weight);
      end

      check_equal_int("weight_count", weight_count, NUM_WEIGHTS);
      check_equal_int("weights_done_count", weights_done_count, 1);
      check_equal_int("expected_weight_queue.size", expected_weight_queue.size(), 0);
    end
  endtask

  task automatic send_i32_le(input logic signed [31:0] value);
    begin
      send_byte(value[7:0]);
      send_byte(value[15:8]);
      send_byte(value[23:16]);
      send_byte(value[31:24]);
    end
  endtask

  task automatic test_bias;
    logic signed [31:0] vals [4];
    begin
      $display("[TEST] bias");

      vals[0] = 32'sd10;
      vals[1] = -32'sd20;
      vals[2] = 32'sd300;
      vals[3] = -32'sd400;

      send_byte("B");

      for (int i = 0; i < 4; i++) begin
        expected_bias_queue.push_back(vals[i]);
        send_i32_le(vals[i]);
      end

      check_equal_int("bias_count", bias_count, 4);
      check_equal_int("bias_done_count", bias_done_count, 1);
      check_equal_int("expected_bias_queue.size", expected_bias_queue.size(), 0);
    end
  endtask

  task automatic test_image_and_read;
    logic [7:0] expected_pixel;
    begin
      $display("[TEST] image stream and read request");

      send_byte("I");

      for (int i = 0; i < 20; i++) begin
        expected_pixel = 8'h80 + i[7:0];
        expected_pixel_queue.push_back(expected_pixel);
        send_byte(expected_pixel);
      end

      send_byte("R");

      check_equal_int("pixel_count", pixel_count, 20);
      check_equal_int("read_count", read_count, 1);
      check_equal_int("expected_pixel_queue.size", expected_pixel_queue.size(), 0);
    end
  endtask

  task automatic test_invalid_command;
    begin
      $display("[TEST] invalid command");

      send_byte(8'h00);
      check_equal_int("error_count", error_count, 1);
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("UART COMMAND DECODER TEST SUMMARY");
      $display("============================================================");
      $display("Checks run       : %0d", checks);
      $display("Ping count       : %0d", ping_count);
      $display("Config count     : %0d", cfg_count);
      $display("Weight count     : %0d", weight_count);
      $display("Weights done     : %0d", weights_done_count);
      $display("Bias count       : %0d", bias_count);
      $display("Bias done        : %0d", bias_done_count);
      $display("Pixel count      : %0d", pixel_count);
      $display("Read count       : %0d", read_count);
      $display("Protocol errors  : %0d", error_count);
      $display("Total errors     : %0d", errors);
      $display("Status           : %s", (errors == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;

    reset_dut();

    test_ping();
    test_config();
    test_weights();
    test_bias();
    test_image_and_read();
    test_invalid_command();

    repeat (10) @(posedge clk);

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_uart_cmd_decoder");
    end else begin
      $fatal(1, "[FAIL] tb_uart_cmd_decoder errors=%0d", errors);
    end

    $finish;
  end

endmodule
