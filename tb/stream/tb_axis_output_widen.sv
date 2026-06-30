`timescale 1ns/1ps

module tb_axis_output_widen;

  logic clk;
  logic rst_n;
  logic clear;

  logic signed [7:0] s_data;
  logic              s_valid;
  logic              s_ready;
  logic              s_last;

  logic [31:0]       m_axis_tdata;
  logic              m_axis_tvalid;
  logic              m_axis_tready;
  logic              m_axis_tlast;

  logic [31:0]       outputs_seen;

  int errors;
  int tests;

  axis_output_widen dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .s_data(s_data),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_last(s_last),

    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),

    .outputs_seen(outputs_seen)
  );

  always #5 clk = ~clk;

  task automatic send_output(
    input int value,
    input bit last
  );
    begin
      while (!s_ready) begin
        @(posedge clk);
      end

      s_data  <= value[7:0];
      s_valid <= 1'b1;
      s_last  <= last;

      @(posedge clk);

      s_valid <= 1'b0;
      s_last  <= 1'b0;
      s_data  <= 8'sd0;
    end
  endtask

  task automatic check_axis_output(
    input logic [31:0] expected_data,
    input bit          expected_last
  );
    begin
      tests++;

      while (!m_axis_tvalid) begin
        @(posedge clk);
      end

      if (m_axis_tdata !== expected_data) begin
        $display("[FAIL] tdata expected=0x%08x got=0x%08x",
                 expected_data, m_axis_tdata);
        errors++;
      end

      if (m_axis_tlast !== expected_last) begin
        $display("[FAIL] tlast expected=%0d got=%0d",
                 expected_last, m_axis_tlast);
        errors++;
      end

      @(posedge clk);
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    clear = 1'b0;

    s_data = 8'sd0;
    s_valid = 1'b0;
    s_last = 1'b0;

    m_axis_tready = 1'b1;

    errors = 0;
    tests = 0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    $display("[TEST] positive value");
    send_output(7, 1'b0);
    check_axis_output(32'h00000007, 1'b0);

    $display("[TEST] negative value sign extension");
    send_output(-1, 1'b0);
    check_axis_output(32'hffffffff, 1'b0);

    $display("[TEST] last output");
    send_output(11, 1'b1);
    check_axis_output(32'h0000000b, 1'b1);

    repeat (3) @(posedge clk);

    if (outputs_seen !== 32'd3) begin
      $display("[FAIL] outputs_seen expected=3 got=%0d", outputs_seen);
      errors++;
    end

    if (errors == 0) begin
      $display("[PASS] tb_axis_output_widen tests=%0d", tests);
    end else begin
      $fatal(1, "[FAIL] tb_axis_output_widen errors=%0d tests=%0d",
             errors, tests);
    end

    $finish;
  end

endmodule
