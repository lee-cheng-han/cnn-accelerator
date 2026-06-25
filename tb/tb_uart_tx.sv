`timescale 1ns/1ps

module tb_uart_tx;

  localparam int CLK_FREQ_HZ = 10_000_000;
  localparam int BAUD_RATE   = 1_000_000;
  localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

  logic clk;
  logic rst_n;

  logic [7:0] data_in;
  logic data_valid;
  logic data_ready;

  logic tx;
  logic busy;

  int errors;
  int checks;

  uart_tx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .data_in(data_in),
    .data_valid(data_valid),
    .data_ready(data_ready),
    .tx(tx),
    .busy(busy)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic check_bit(input logic expected, input string name);
    begin
      repeat (CLKS_PER_BIT / 2) @(posedge clk);
      #1;
      checks++;

      if (tx !== expected) begin
        errors++;
        $error("%s mismatch got=%0b expected=%0b", name, tx, expected);
      end

      repeat (CLKS_PER_BIT - (CLKS_PER_BIT / 2)) @(posedge clk);
    end
  endtask

  task automatic send_and_check(input logic [7:0] value);
    begin
      @(negedge clk);
      data_in = value;
      data_valid = 1'b1;

      @(posedge clk);
      #1;

      @(negedge clk);
      data_valid = 1'b0;

      check_bit(1'b0, "start bit");

      for (int i = 0; i < 8; i++) begin
        check_bit(value[i], $sformatf("data bit %0d", i));
      end

      check_bit(1'b1, "stop bit");

      wait (data_ready);
      @(posedge clk);
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("UART TX TEST SUMMARY");
      $display("============================================================");
      $display("Checks run   : %0d", checks);
      $display("Total errors : %0d", errors);
      $display("Status       : %s", (errors == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;

    data_in = 8'd0;
    data_valid = 1'b0;

    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    checks++;
    if (tx !== 1'b1) begin
      errors++;
      $error("TX idle should be high");
    end

    send_and_check(8'h55);
    send_and_check(8'hA3);
    send_and_check(8'h00);
    send_and_check(8'hFF);

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_uart_tx");
    end else begin
      $fatal(1, "[FAIL] tb_uart_tx errors=%0d", errors);
    end

    $finish;
  end

endmodule
