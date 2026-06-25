`timescale 1ns/1ps

module tb_cnn_accel_board_top_loopback;

  localparam int CLK_FREQ_HZ  = 10_000_000;
  localparam int BAUD_RATE    = 1_000_000;
  localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

  logic clk;
  logic rst_n;

  logic uart_rx;
  logic uart_tx;

  logic led_busy;
  logic led_done;
  logic led_error;

  int errors;
  int checks;
  int bytes_sent;
  int bytes_received;

  cnn_accel_board_top #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
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
    forever #5 clk = ~clk;
  end

  task automatic drive_uart_byte(input logic [7:0] value);
    begin
      uart_rx = 1'b1;
      repeat (CLKS_PER_BIT) @(posedge clk);

      // start bit
      uart_rx = 1'b0;
      repeat (CLKS_PER_BIT) @(posedge clk);

      // data bits LSB first
      for (int i = 0; i < 8; i++) begin
        uart_rx = value[i];
        repeat (CLKS_PER_BIT) @(posedge clk);
      end

      // stop bit
      uart_rx = 1'b1;
      repeat (CLKS_PER_BIT) @(posedge clk);

      bytes_sent++;
    end
  endtask

  task automatic read_uart_byte(output logic [7:0] value);
    int timeout;
    begin
      value = 8'd0;
      timeout = CLKS_PER_BIT * 200;

      // wait for start bit
      while (uart_tx !== 1'b0 && timeout > 0) begin
        @(posedge clk);
        #1;
        timeout--;
      end

      if (timeout == 0) begin
        errors++;
        checks++;
        $error("Timeout waiting for TX start bit");
      end else begin
        // sample middle of start bit
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
        #1;

        checks++;
        if (uart_tx !== 1'b0) begin
          errors++;
          $error("TX start bit mismatch got=%0b expected=0", uart_tx);
        end

        // sample data bits in the middle
        for (int i = 0; i < 8; i++) begin
          repeat (CLKS_PER_BIT) @(posedge clk);
          #1;
          value[i] = uart_tx;
        end

        // sample stop bit
        repeat (CLKS_PER_BIT) @(posedge clk);
        #1;

        checks++;
        if (uart_tx !== 1'b1) begin
          errors++;
          $error("TX stop bit mismatch got=%0b expected=1", uart_tx);
        end

        bytes_received++;
      end
    end
  endtask

  task automatic send_and_expect_echo(input logic [7:0] value);
    logic [7:0] got;
    begin
      fork
        drive_uart_byte(value);
        read_uart_byte(got);
      join

      checks++;
      if (got !== value) begin
        errors++;
        $error("Loopback mismatch got=0x%02h expected=0x%02h", got, value);
      end else begin
        $display("[CHECK PASS] echoed 0x%02h", value);
      end

      repeat (CLKS_PER_BIT * 3) @(posedge clk);
    end
  endtask


  // ------------------------------------------------------------
  // Protocol / sanity assertions
  // ------------------------------------------------------------

  // UART TX should be idle high after reset when not transmitting.
  property p_uart_tx_idle_high_after_reset;
    @(posedge clk) disable iff (!rst_n)
      (!dut.tx_busy && !dut.pending_valid) |-> (uart_tx == 1'b1);
  endproperty

  assert property (p_uart_tx_idle_high_after_reset)
    else begin
      errors++;
      $error("ASSERTION FAILED: uart_tx should be high when TX is idle");
    end

  // Error LED should only reflect RX framing error.
  property p_led_error_matches_framing_error;
    @(posedge clk) disable iff (!rst_n)
      led_error == dut.rx_framing_error;
  endproperty

  assert property (p_led_error_matches_framing_error)
    else begin
      errors++;
      $error("ASSERTION FAILED: led_error does not match rx_framing_error");
    end


  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("BOARD UART LOOPBACK TEST SUMMARY");
      $display("============================================================");
      $display("Bytes sent     : %0d", bytes_sent);
      $display("Bytes received : %0d", bytes_received);
      $display("Checks run     : %0d", checks);
      $display("Total errors   : %0d", errors);
      $display("Status         : %s", (errors == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;
    bytes_sent = 0;
    bytes_received = 0;

    uart_rx = 1'b1;

    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    checks++;
    if (uart_tx !== 1'b1) begin
      errors++;
      $error("UART TX should idle high");
    end

    send_and_expect_echo(8'h55);
    send_and_expect_echo(8'hA3);
    send_and_expect_echo(8'h00);
    send_and_expect_echo(8'hFF);
    send_and_expect_echo(8'h5A);

    repeat (100) @(posedge clk);

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_cnn_accel_board_top_loopback");
    end else begin
      $fatal(1, "[FAIL] tb_cnn_accel_board_top_loopback errors=%0d", errors);
    end

    $finish;
  end

endmodule
