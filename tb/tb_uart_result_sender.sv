`timescale 1ns/1ps

module tb_uart_result_sender;

  localparam int DATA_WIDTH = 8;

  logic clk;
  logic rst_n;
  logic clear;
  logic start;

  logic signed [DATA_WIDTH-1:0] buf_rd_data;
  logic buf_rd_valid;
  logic buf_rd_last;
  logic buf_rd_ready;

  logic [7:0] tx_data;
  logic tx_valid;
  logic tx_ready;

  logic busy;
  logic done;
  logic [31:0] bytes_sent;

  int errors;
  int checks;
  int done_count;

  logic [7:0] source_data_q [$];
  logic       source_last_q [$];

  logic [7:0] expected_tx_q [$];
  logic       expected_last_q [$];

  logic [7:0] current_data;
  logic       current_last;
  logic       current_valid;

  uart_result_sender #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .start(start),

    .buf_rd_data(buf_rd_data),
    .buf_rd_valid(buf_rd_valid),
    .buf_rd_last(buf_rd_last),
    .buf_rd_ready(buf_rd_ready),

    .tx_data(tx_data),
    .tx_valid(tx_valid),
    .tx_ready(tx_ready),

    .busy(busy),
    .done(done),
    .bytes_sent(bytes_sent)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  assign buf_rd_data  = current_data;
  assign buf_rd_last  = current_last;
  assign buf_rd_valid = current_valid;

  // Fake output_result_buffer model.
  always_ff @(posedge clk) begin
    if (!rst_n || clear) begin
      current_valid <= 1'b0;
      current_data  <= 8'd0;
      current_last  <= 1'b0;
    end else begin
      if (!current_valid && source_data_q.size() > 0) begin
        current_data  <= source_data_q[0];
        current_last  <= source_last_q[0];
        current_valid <= 1'b1;
      end else if (current_valid && buf_rd_ready) begin
        void'(source_data_q.pop_front());
        void'(source_last_q.pop_front());

        if (source_data_q.size() > 0) begin
          current_data  <= source_data_q[0];
          current_last  <= source_last_q[0];
          current_valid <= 1'b1;
        end else begin
          current_data  <= 8'd0;
          current_last  <= 1'b0;
          current_valid <= 1'b0;
        end
      end
    end
  end

  // TX scoreboard
  // Important: sample tx_valid/tx_ready/tx_data at the clock edge before
  // nonblocking assignments update the DUT outputs.
  always @(posedge clk) begin
    if (rst_n) begin
      if (tx_valid && tx_ready) begin
        logic [7:0] expected_data;

        checks++;

        if (expected_tx_q.size() == 0) begin
          errors++;
          $error("Unexpected tx_data=0x%02h", tx_data);
        end else begin
          expected_data = expected_tx_q.pop_front();

          if (tx_data !== expected_data) begin
            errors++;
            $error("tx_data mismatch got=0x%02h expected=0x%02h", tx_data, expected_data);
          end

          void'(expected_last_q.pop_front());
        end
      end

      #1;
      if (done) begin
        done_count++;
      end
    end
  end

  task automatic reset_dut;
    begin
      clear = 1'b0;
      start = 1'b0;
      tx_ready = 1'b0;

      source_data_q.delete();
      source_last_q.delete();
      expected_tx_q.delete();
      expected_last_q.delete();

      current_valid = 1'b0;
      current_data = 8'd0;
      current_last = 1'b0;

      done_count = 0;

      rst_n = 1'b0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (5) @(posedge clk);
    end
  endtask

  task automatic do_clear;
    begin
      @(negedge clk);
      clear = 1'b1;
      @(negedge clk);
      clear = 1'b0;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic load_packet(input int n);
    logic [7:0] value;
    begin
      source_data_q.delete();
      source_last_q.delete();
      expected_tx_q.delete();
      expected_last_q.delete();

      for (int i = 0; i < n; i++) begin
        value = 8'hA0 + i[7:0];

        source_data_q.push_back(value);
        source_last_q.push_back(i == n - 1);

        expected_tx_q.push_back(value);
        expected_last_q.push_back(i == n - 1);
      end
    end
  endtask

  task automatic pulse_start;
    begin
      @(negedge clk);
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic wait_done_or_timeout(input int max_cycles);
    int cycles;
    begin
      cycles = 0;

      while (!done && cycles < max_cycles) begin
        @(posedge clk);
        cycles++;
      end

      checks++;
      if (!done) begin
        errors++;
        $error("Timeout waiting for done");
      end

      repeat (3) @(posedge clk);
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

  task automatic test_ready_always;
    begin
      $display("[TEST] ready always");

      do_clear();
      load_packet(16);

      tx_ready = 1'b1;
      pulse_start();

      wait_done_or_timeout(200);

      check_int("bytes_sent ready always", bytes_sent, 16);
      check_int("done_count ready always", done_count, 1);
      check_int("expected_tx_q empty", expected_tx_q.size(), 0);
    end
  endtask

  task automatic test_with_stalls;
    begin
      $display("[TEST] TX stalls");

      do_clear();
      load_packet(24);

      pulse_start();

      for (int cycle = 0; cycle < 300; cycle++) begin
        @(negedge clk);

        // Repeating stall pattern.
        tx_ready = ((cycle % 5) != 0) && ((cycle % 7) != 0);

        if (done) begin
          break;
        end
      end

      wait_done_or_timeout(50);

      check_int("bytes_sent stalls", bytes_sent, 24);
      check_int("done_count stalls", done_count, 2);
      check_int("expected_tx_q empty stalls", expected_tx_q.size(), 0);
    end
  endtask

  task automatic test_single_byte;
    begin
      $display("[TEST] single byte packet");

      do_clear();
      load_packet(1);

      tx_ready = 1'b1;
      pulse_start();

      wait_done_or_timeout(50);

      check_int("bytes_sent single", bytes_sent, 1);
      check_int("done_count single", done_count, 3);
      check_int("expected_tx_q empty single", expected_tx_q.size(), 0);
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("UART RESULT SENDER TEST SUMMARY");
      $display("============================================================");
      $display("Checks run   : %0d", checks);
      $display("Done count   : %0d", done_count);
      $display("Bytes sent   : %0d", bytes_sent);
      $display("Total errors : %0d", errors);
      $display("Status       : %s", (errors == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;

    reset_dut();

    test_ready_always();
    test_with_stalls();
    test_single_byte();

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_uart_result_sender");
    end else begin
      $fatal(1, "[FAIL] tb_uart_result_sender errors=%0d", errors);
    end

    $finish;
  end

endmodule
