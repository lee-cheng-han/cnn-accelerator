`timescale 1ns/1ps

module tb_cnn_accel_board_top_compile;

  logic clk;
  logic rst_n;
  logic uart_rx;
  logic uart_tx;
  logic led_busy;
  logic led_done;
  logic led_error;

  cnn_accel_board_top #(
    .CLK_FREQ_HZ(100_000_000),
    .BAUD_RATE(115200),
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
    forever #5 clk = ~clk;
  end

  initial begin
    uart_rx = 1'b1;

    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (100) @(posedge clk);

    $display("[PASS] tb_cnn_accel_board_top_compile");
    $finish;
  end

endmodule
