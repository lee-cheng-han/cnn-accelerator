`timescale 1ns/1ps

module tb_cnn_accel_board_top_invalid;

  localparam int CLK_FREQ_HZ = 1_000_000;
  localparam int BAUD_RATE   = 100_000;
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
    forever #500 clk = ~clk;
  end

  task automatic reset_dut;
    begin
      uart_rx = 1'b1;

      rst_n = 1'b0;
      repeat (20) @(posedge clk);
      rst_n = 1'b1;
      repeat (20) @(posedge clk);
    end
  endtask

  task automatic uart_send_byte(input logic [7:0] data);
    begin
      uart_rx = 1'b0;
      repeat (CLKS_PER_BIT) @(posedge clk);

      for (int i = 0; i < 8; i++) begin
        uart_rx = data[i];
        repeat (CLKS_PER_BIT) @(posedge clk);
      end

      uart_rx = 1'b1;
      repeat (CLKS_PER_BIT) @(posedge clk);

      repeat (5) @(posedge clk);
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

  initial begin
    errors = 0;
    checks = 0;

    reset_dut();

    check_int("led_error initial", led_error, 0);

    $display("[TEST] send invalid command");
    uart_send_byte(8'h00);

    repeat (100) @(posedge clk);

    check_int("led_error after invalid command", led_error, 1);

    $display("");
    $display("============================================================");
    $display("CNN ACCEL BOARD TOP INVALID COMMAND TEST SUMMARY");
    $display("============================================================");
    $display("Checks run   : %0d", checks);
    $display("Total errors : %0d", errors);
    $display("LED error    : %0d", led_error);
    $display("Status       : %s", (errors == 0) ? "PASS" : "FAIL");
    $display("============================================================");
    $display("");

    if (errors == 0) begin
      $display("[PASS] tb_cnn_accel_board_top_invalid");
    end else begin
      $fatal(1, "[FAIL] tb_cnn_accel_board_top_invalid errors=%0d", errors);
    end

    $finish;
  end

endmodule
