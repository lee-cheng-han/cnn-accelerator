`timescale 1ns/1ps

module tb_uart_loopback_random;

  localparam int CLK_FREQ_HZ  = 10_000_000;
  localparam int BAUD_RATE    = 1_000_000;
  localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
  localparam int NUM_RANDOM_BYTES = 100;

  logic clk;
  logic rst_n;

  logic [7:0] tx_data_in;
  logic       tx_data_valid;
  logic       tx_data_ready;
  logic       tx_line;
  logic       tx_busy;

  logic [7:0] rx_data_out;
  logic       rx_data_valid;
  logic       rx_framing_error;

  int errors;
  int checks;
  int seed;
  int sent_count;
  int recv_count;

  logic [31:0] prng_state;

  logic [7:0] expected_queue [$];

  uart_tx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
  ) u_tx (
    .clk(clk),
    .rst_n(rst_n),
    .data_in(tx_data_in),
    .data_valid(tx_data_valid),
    .data_ready(tx_data_ready),
    .tx(tx_line),
    .busy(tx_busy)
  );

  uart_rx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
  ) u_rx (
    .clk(clk),
    .rst_n(rst_n),
    .rx(tx_line),
    .data_out(rx_data_out),
    .data_valid(rx_data_valid),
    .framing_error(rx_framing_error)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always @(posedge clk) begin
    if (rst_n) begin
      #1;

      if (rx_framing_error) begin
        errors++;
        $error("Unexpected RX framing error");
      end

      if (rx_data_valid) begin
        logic [7:0] expected;

        checks++;
        recv_count++;

        if (expected_queue.size() == 0) begin
          errors++;
          $error("Received unexpected byte 0x%02h", rx_data_out);
        end else begin
          expected = expected_queue.pop_front();

          if (rx_data_out !== expected) begin
            errors++;
            $error("UART loopback mismatch got=0x%02h expected=0x%02h", rx_data_out, expected);
          end
        end
      end
    end
  end


  function automatic logic [31:0] next_rand;
    begin
      // Simple LCG PRNG. Deterministic and XSim-friendly.
      prng_state = (prng_state * 32'd1664525) + 32'd1013904223;
      next_rand = prng_state;
    end
  endfunction

  function automatic int rand_range(input int lo, input int hi);
    logic [31:0] r;
    begin
      r = next_rand();
      rand_range = lo + int'(r % (hi - lo + 1));
    end
  endfunction


  task automatic send_byte(input logic [7:0] value);
    int gap_cycles;
    begin
      gap_cycles = rand_range(0, 20);
      repeat (gap_cycles) @(posedge clk);

      wait (tx_data_ready);
      @(negedge clk);
      tx_data_in    = value;
      tx_data_valid = 1'b1;

      @(posedge clk);
      #1;

      @(negedge clk);
      tx_data_valid = 1'b0;

      expected_queue.push_back(value);
      sent_count++;
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("UART RANDOM LOOPBACK TEST SUMMARY");
      $display("============================================================");
      $display("Seed           : %0d", seed);
      $display("Bytes sent     : %0d", sent_count);
      $display("Bytes received : %0d", recv_count);
      $display("Checks run     : %0d", checks);
      $display("Total errors   : %0d", errors);
      $display("Status         : %s", (errors == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    if (!$value$plusargs("ntb_random_seed=%d", seed)) begin
      seed = 12345;
    end

    prng_state = seed[31:0];

    errors = 0;
    checks = 0;
    sent_count = 0;
    recv_count = 0;

    tx_data_in = 8'd0;
    tx_data_valid = 1'b0;

    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    for (int i = 0; i < NUM_RANDOM_BYTES; i++) begin
      send_byte(logic'(rand_range(0, 255)));
    end

    wait (recv_count == NUM_RANDOM_BYTES);
    repeat (50) @(posedge clk);

    if (expected_queue.size() != 0) begin
      errors++;
      $error("Expected queue not empty, remaining=%0d", expected_queue.size());
    end

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_uart_loopback_random");
    end else begin
      $fatal(1, "[FAIL] tb_uart_loopback_random errors=%0d", errors);
    end

    $finish;
  end

endmodule
