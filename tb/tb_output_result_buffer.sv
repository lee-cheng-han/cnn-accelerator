`timescale 1ns/1ps

module tb_output_result_buffer;

  localparam int DATA_WIDTH = 8;
  localparam int DEPTH = 64;

  logic clk;
  logic rst_n;
  logic clear;

  logic signed [DATA_WIDTH-1:0] wr_data;
  logic wr_valid;
  logic wr_last;
  logic wr_ready;

  logic signed [DATA_WIDTH-1:0] rd_data;
  logic rd_valid;
  logic rd_last;
  logic rd_ready;

  logic full;
  logic empty;
  logic done;

  logic [$clog2(DEPTH+1)-1:0] write_count;
  logic [$clog2(DEPTH+1)-1:0] read_count;
  logic [$clog2(DEPTH+1)-1:0] stored_count;

  int errors;
  int checks;

  logic signed [DATA_WIDTH-1:0] expected_data_q [$];
  logic expected_last_q [$];

  output_result_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .wr_data(wr_data),
    .wr_valid(wr_valid),
    .wr_last(wr_last),
    .wr_ready(wr_ready),

    .rd_data(rd_data),
    .rd_valid(rd_valid),
    .rd_last(rd_last),
    .rd_ready(rd_ready),

    .full(full),
    .empty(empty),
    .done(done),

    .write_count(write_count),
    .read_count(read_count),
    .stored_count(stored_count)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic reset_dut;
    begin
      clear = 1'b0;
      wr_data = '0;
      wr_valid = 1'b0;
      wr_last = 1'b0;
      rd_ready = 1'b0;

      expected_data_q.delete();
      expected_last_q.delete();

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

  task automatic push_item(input logic signed [7:0] data, input logic last);
    begin
      @(negedge clk);
      wr_data  = data;
      wr_last  = last;
      wr_valid = 1'b1;

      while (!wr_ready) begin
        @(posedge clk);
      end

      @(posedge clk);
      #1;

      expected_data_q.push_back(data);
      expected_last_q.push_back(last);

      @(negedge clk);
      wr_valid = 1'b0;
      wr_last  = 1'b0;
      wr_data  = '0;
    end
  endtask

  task automatic pop_item;
    logic signed [7:0] expected_data;
    logic expected_last;
    begin
      @(negedge clk);
      rd_ready = 1'b1;

      while (!rd_valid) begin
        @(posedge clk);
        #1;
      end

      expected_data = expected_data_q.pop_front();
      expected_last = expected_last_q.pop_front();

      checks++;
      if (rd_data !== expected_data) begin
        errors++;
        $error("rd_data got=%0d expected=%0d", rd_data, expected_data);
      end

      checks++;
      if (rd_last !== expected_last) begin
        errors++;
        $error("rd_last got=%0b expected=%0b", rd_last, expected_last);
      end

      @(posedge clk);
      #1;

      @(negedge clk);
      rd_ready = 1'b0;
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

  task automatic test_basic;
    begin
      $display("[TEST] basic write/read");

      do_clear();

      for (int i = 0; i < 10; i++) begin
        push_item(i[7:0], i == 9);
      end

      repeat (2) @(posedge clk);

      check_int("write_count", write_count, 10);
      check_int("stored_count", stored_count, 10);
      check_int("done", done, 1);

      for (int i = 0; i < 10; i++) begin
        pop_item();
      end

      repeat (3) @(posedge clk);

      check_int("read_count", read_count, 10);
      check_int("stored_count after read", stored_count, 0);
      check_int("empty", empty, 1);
      check_int("done after final read", done, 0);
    end
  endtask

  task automatic test_interleaved;
    logic signed [7:0] value;
    begin
      $display("[TEST] interleaved write/read");

      do_clear();

      for (int i = 0; i < 8; i++) begin
        value = 8'sd20 + i[7:0];
        push_item(value, 1'b0);
      end

      for (int i = 0; i < 4; i++) begin
        pop_item();
      end

      for (int i = 0; i < 8; i++) begin
        value = 8'sd40 + i[7:0];
        push_item(value, i == 7);
      end

      while (expected_data_q.size() > 0) begin
        pop_item();
      end

      repeat (3) @(posedge clk);
      check_int("empty interleaved", empty, 1);
    end
  endtask

  task automatic test_full;
    logic signed [7:0] value;
    begin
      $display("[TEST] full buffer");

      do_clear();

      for (int i = 0; i < DEPTH; i++) begin
        value = i[7:0];
        push_item(value, i == DEPTH - 1);
      end

      repeat (2) @(posedge clk);

      check_int("full", full, 1);
      check_int("stored_count full", stored_count, DEPTH);

      for (int i = 0; i < DEPTH; i++) begin
        pop_item();
      end

      repeat (3) @(posedge clk);

      check_int("empty after full drain", empty, 1);
      check_int("stored_count after full drain", stored_count, 0);
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("OUTPUT RESULT BUFFER TEST SUMMARY");
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

    reset_dut();

    test_basic();
    test_interleaved();
    test_full();

    print_summary();

    if (errors == 0) begin
      $display("[PASS] tb_output_result_buffer");
    end else begin
      $fatal(1, "[FAIL] tb_output_result_buffer errors=%0d", errors);
    end

    $finish;
  end

endmodule
