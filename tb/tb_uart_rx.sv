`timescale 1ns/1ps

module tb_uart_rx;

  localparam int CLK_FREQ_HZ = 10_000_000;
  localparam int BAUD_RATE   = 1_000_000;
  localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

  logic clk;
  logic rst_n;

  logic rx;
  logic [7:0] data_out;
  logic data_valid;
  logic framing_error;

  int errors;
  int checks;
  int bytes_received;

  uart_rx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .rx(rx),
    .data_out(data_out),
    .data_valid(data_valid),
    .framing_error(framing_error)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic drive_uart_byte(input logic [7:0] value, input bit good_stop);
    begin
      rx = 1'b1;
      repeat (CLKS_PER_BIT) @(posedge clk);

      rx = 1'b0;
      repeat (CLKS_PER_BIT) @(posedge clk);

      for (int i = 0; i < 8; i++) begin
        rx = value[i];
        repeat (CLKS_PER_BIT) @(posedge clk);
      end

      rx = good_stop ? 1'b1 : 1'b0;
      repeat (CLKS_PER_BIT) @(posedge clk);

      rx = 1'b1;
      repeat (CLKS_PER_BIT * 2) @(posedge clk);
    end
  endtask

  task automatic expect_byte(input logic [7:0] expected);
    int timeout;
    bit seen;
    begin
      timeout = CLKS_PER_BIT * 20;
      seen = 1'b0;

      while (timeout > 0 && !seen) begin
        @(posedge clk);
        #1;

        if (data_valid) begin
          seen = 1'b1;
          bytes_received++;
          checks++;

          if (data_out !== expected) begin
            errors++;
            $error("RX byte mismatch got=0x%02h expected=0x%02h", data_out, expected);
          end
        end

        timeout--;
      end

      if (!seen) begin
        errors++;
        checks++;
        $error("RX timeout waiting for byte 0x%02h", expected);
      end
    end
  endtask

  task automatic expect_framing_error;
    int timeout;
    bit seen;
    begin
      timeout = CLKS_PER_BIT * 20;
      seen = 1'b0;

      while (timeout > 0 && !seen) begin
        @(posedge clk);
        #1;

        if (framing_error) begin
          seen = 1'b1;
          checks++;
        end

        timeout--;
      end

      if (!seen) begin
        errors++;
        checks++;
        $error("Expected framing error, but none occurred");
      end
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("UART RX TEST SUMMARY");
      $display("============================================================");
      $display("Checks run     : %0d", checks);
      $display("Bytes received : %0d", bytes_received);
      $display("Total errors   : %0d", errors);
      $display("Status         : %s", (errors == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;
    bytes_received = 0;

    rx = 1'b1;

    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    fork
      drive_uart_byte(8'h55, 1'b1);
      expect_byte(8'h55);
    join

    fork
      drive_uart_byte(8'hA3, 1'b1);
      expect_byte(8'hA3);
    join

    fork
      drive_uart_byte(8'h00, 1'b1);
      expect_byte(8'h00);
    join

    fork
      drive_uart_byte(8'hFF, 1'b1);
      expect_byte(8'hFF);
    join

    fork
      drive_uart_byte(8'h5A, 1'b0);
      expect_framing_error();
    join

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_uart_rx");
    end else begin
      $fatal(1, "[FAIL] tb_uart_rx errors=%0d", errors);
    end

    $finish;
  end

endmodule
