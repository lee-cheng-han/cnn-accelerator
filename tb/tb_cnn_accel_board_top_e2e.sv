`timescale 1ns/1ps

module tb_cnn_accel_board_top_e2e;

  localparam int CLK_FREQ_HZ = 2_000_000;
  localparam int BAUD_RATE   = 100_000;
  localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

  localparam int IC = 3;
  localparam int OC = 4;
  localparam int K  = 9;

  localparam int IMG_W = 4;
  localparam int IMG_H = 4;
  localparam int NUM_WEIGHTS = IC * OC * K;
  localparam int NUM_IMAGE_BYTES = IMG_W * IMG_H * IC;
  localparam int NUM_OUTPUT_BYTES = IMG_W * IMG_H * OC;

  logic clk;
  logic rst_n;

  logic uart_rx;
  logic uart_tx;

  logic led_busy;
  logic led_done;
  logic led_error;

  int errors;
  int checks;

  logic signed [7:0] image [IMG_W * IMG_H][IC];
  logic [7:0] expected_q [$];
  logic [7:0] received_q [$];

  cnn_accel_board_top #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE),
    .RESULT_DEPTH(256)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),

    .uart_rx(uart_rx),
    .uart_tx(uart_tx),

    .led_busy(led_busy),
    .led_done(led_done),
    .led_error(led_error)
  );

  initial begin
    clk = 1'b0;
    forever #250 clk = ~clk; // 2 MHz clock
  end

  task automatic reset_dut;
    begin
      uart_rx = 1'b1;
      expected_q.delete();
      received_q.delete();

      rst_n = 1'b0;
      repeat (20) @(posedge clk);
      rst_n = 1'b1;
      repeat (20) @(posedge clk);
    end
  endtask

  task automatic uart_send_byte(input logic [7:0] data);
    begin
      // Start bit
      uart_rx = 1'b0;
      repeat (CLKS_PER_BIT) @(posedge clk);

      // Data bits, LSB first
      for (int i = 0; i < 8; i++) begin
        uart_rx = data[i];
        repeat (CLKS_PER_BIT) @(posedge clk);
      end

      // Stop bit
      uart_rx = 1'b1;
      repeat (CLKS_PER_BIT) @(posedge clk);

      // Gap between bytes
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic uart_recv_byte(output logic [7:0] data);
    begin
      data = 8'd0;

      // Wait for a real high-to-low start edge.
      // This is safer than entering while the line may already be low.
      @(negedge uart_tx);

      // Move to the center of bit 0: 1.5 bit-times after start edge.
      repeat (CLKS_PER_BIT + (CLKS_PER_BIT / 2)) @(posedge clk);

      // Sample data bits, LSB first, at bit centers.
      for (int i = 0; i < 8; i++) begin
        data[i] = uart_tx;
        repeat (CLKS_PER_BIT) @(posedge clk);
      end

      // Wait through the stop bit and settle in idle before next receive.
      wait (uart_tx === 1'b1);
      repeat (CLKS_PER_BIT / 2) @(posedge clk);
    end
  endtask

  task automatic send_u16_le(input logic [15:0] value);
    begin
      uart_send_byte(value[7:0]);
      uart_send_byte(value[15:8]);
    end
  endtask

  task automatic send_u32_le(input logic [31:0] value);
    begin
      uart_send_byte(value[7:0]);
      uart_send_byte(value[15:8]);
      uart_send_byte(value[23:16]);
      uart_send_byte(value[31:24]);
    end
  endtask

  task automatic send_config_1x1_no_bias;
    logic [7:0] flags;
    begin
      $display("[TEST] send config");

      flags = 8'b0000_0000; // ReLU=0, bias=0, quant=0

      uart_send_byte("C");
      send_u16_le(IMG_W[15:0]);
      send_u16_le(IMG_H[15:0]);
      uart_send_byte(8'd0);     // kernel_mode 0 = 1x1
      uart_send_byte(flags);
      uart_send_byte(8'd0);     // quant_shift
    end
  endtask

  task automatic send_weights_identity_like;
    int oc;
    int ic;
    int tap;
    logic signed [7:0] w;
    begin
      $display("[TEST] send weights");

      uart_send_byte("W");

      for (int i = 0; i < NUM_WEIGHTS; i++) begin
        oc  = i / (IC * K);
        ic  = (i / K) % IC;
        tap = i % K;

        w = 8'sd0;

        // 1x1 mode uses tap 0 only.
        // oc0 = ch0, oc1 = ch1, oc2 = ch2, oc3 = ch0+ch1+ch2.
        if (tap == 0) begin
          if (oc == 0 && ic == 0) w = 8'sd1;
          if (oc == 1 && ic == 1) w = 8'sd1;
          if (oc == 2 && ic == 2) w = 8'sd1;
          if (oc == 3) w = 8'sd1;
        end

        uart_send_byte(w[7:0]);
      end
    end
  endtask

  task automatic build_image_and_expected;
    int p;
    int acc;
    logic signed [7:0] out_val;
    begin
      $display("[TEST] build golden expected data");

      expected_q.delete();

      for (int y = 0; y < IMG_H; y++) begin
        for (int x = 0; x < IMG_W; x++) begin
          p = y * IMG_W + x;

          image[p][0] = p + 1;
          image[p][1] = p + 2;
          image[p][2] = p + 3;

          expected_q.push_back(image[p][0][7:0]);
          expected_q.push_back(image[p][1][7:0]);
          expected_q.push_back(image[p][2][7:0]);

          acc = image[p][0] + image[p][1] + image[p][2];
          out_val = acc[7:0];
          expected_q.push_back(out_val[7:0]);
        end
      end
    end
  endtask

  task automatic send_image;
    int p;
    begin
      $display("[TEST] send image");

      uart_send_byte("I");
      send_u32_le(NUM_IMAGE_BYTES);

      for (int y = 0; y < IMG_H; y++) begin
        for (int x = 0; x < IMG_W; x++) begin
          p = y * IMG_W + x;

          for (int ic = 0; ic < IC; ic++) begin
            uart_send_byte(image[p][ic][7:0]);
          end
        end
      end
    end
  endtask

  task automatic wait_for_internal_results;
    int cycles;
    begin
      cycles = 0;

      while ((dut.result_bytes_written < NUM_OUTPUT_BYTES) && cycles < 5000) begin
        @(posedge clk);
        cycles++;
      end

      checks++;
      if (dut.result_bytes_written != NUM_OUTPUT_BYTES) begin
        errors++;
        $error("Timeout waiting for internal results. got=%0d expected=%0d",
               dut.result_bytes_written, NUM_OUTPUT_BYTES);
      end else begin
        $display("[INFO] Internal result bytes written = %0d", dut.result_bytes_written);
      end
    end
  endtask

  task automatic request_readback;
    begin
      $display("[TEST] request readback");
      uart_send_byte("R");
    end
  endtask

  task automatic receive_and_check_results;
    logic [7:0] rx_byte;
    logic [7:0] expected;
    begin
      $display("[TEST] receive UART results");

      for (int i = 0; i < NUM_OUTPUT_BYTES; i++) begin
        uart_recv_byte(rx_byte);
        received_q.push_back(rx_byte);

        expected = expected_q.pop_front();

        checks++;
        if (rx_byte !== expected) begin
          errors++;
          $error("UART result mismatch index=%0d got=0x%02h expected=0x%02h",
                 i, rx_byte, expected);
        end
      end

      checks++;
      if (expected_q.size() != 0) begin
        errors++;
        $error("Expected queue not empty. remaining=%0d", expected_q.size());
      end
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
      $display("CNN ACCEL BOARD TOP E2E TEST SUMMARY");
      $display("============================================================");
      $display("Checks run           : %0d", checks);
      $display("Total errors         : %0d", errors);
      $display("Received bytes       : %0d", received_q.size());
      $display("System ready         : %0d", dut.system_ready);
      $display("Outputs seen         : %0d", dut.outputs_seen);
      $display("Result bytes written : %0d", dut.result_bytes_written);
      $display("Result bytes sent    : %0d", dut.result_bytes_sent);
      $display("LED error            : %0d", led_error);
      $display("Status               : %s", (errors == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;

    reset_dut();

    build_image_and_expected();

    send_config_1x1_no_bias();
    send_weights_identity_like();

    repeat (100) @(posedge clk);

    check_int("system_ready", dut.system_ready, 1);
    check_int("led_error before image", led_error, 0);

    send_image();

    wait_for_internal_results();

    // Start UART receiver first so it cannot miss the first TX start bit.
    fork
      begin
        receive_and_check_results();
      end

      begin
        repeat (20) @(posedge clk);
        request_readback();
      end
    join

    repeat (100) @(posedge clk);

    check_int("result_bytes_sent", dut.result_bytes_sent, NUM_OUTPUT_BYTES);
    check_int("led_error final", led_error, 0);

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_cnn_accel_board_top_e2e");
    end else begin
      $fatal(1, "[FAIL] tb_cnn_accel_board_top_e2e errors=%0d", errors);
    end

    $finish;
  end

endmodule
