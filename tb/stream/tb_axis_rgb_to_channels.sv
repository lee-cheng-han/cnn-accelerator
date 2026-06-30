`timescale 1ns/1ps

module tb_axis_rgb_to_channels;

  logic clk;
  logic rst_n;
  logic clear;

  logic [31:0] s_axis_tdata;
  logic        s_axis_tvalid;
  logic        s_axis_tready;
  logic        s_axis_tlast;

  logic signed [7:0] m_pixel_data;
  logic              m_pixel_valid;
  logic              m_pixel_ready;
  logic              m_pixel_last;

  logic [31:0] pixels_seen;
  logic [31:0] channels_seen;

  int errors;
  int tests;

  axis_rgb_to_channels dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),

    .m_pixel_data(m_pixel_data),
    .m_pixel_valid(m_pixel_valid),
    .m_pixel_ready(m_pixel_ready),
    .m_pixel_last(m_pixel_last),

    .pixels_seen(pixels_seen),
    .channels_seen(channels_seen)
  );

  always #5 clk = ~clk;

  task automatic check_channel(
    input int expected_data,
    input bit expected_last
  );
    begin
      tests++;

      while (!m_pixel_valid) begin
        @(posedge clk);
      end

      if (m_pixel_data !== expected_data[7:0]) begin
        $display("[FAIL] channel data expected=%0d got=%0d",
                 expected_data, m_pixel_data);
        errors++;
      end

      if (m_pixel_last !== expected_last) begin
        $display("[FAIL] channel last expected=%0d got=%0d",
                 expected_last, m_pixel_last);
        errors++;
      end

      @(posedge clk);
    end
  endtask

  task automatic send_pixel(
    input logic [31:0] pixel,
    input logic        last
  );
    begin
      while (!s_axis_tready) begin
        @(posedge clk);
      end

      s_axis_tdata  <= pixel;
      s_axis_tvalid <= 1'b1;
      s_axis_tlast  <= last;

      @(posedge clk);

      s_axis_tvalid <= 1'b0;
      s_axis_tlast  <= 1'b0;
      s_axis_tdata  <= 32'd0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    clear = 1'b0;

    s_axis_tdata = 32'd0;
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;

    m_pixel_ready = 1'b1;

    errors = 0;
    tests = 0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    $display("[TEST] one packed RGB pixel");

    // 0x00BBGGRR = B=3, G=2, R=1
    send_pixel(32'h00030201, 1'b1);

    check_channel(1, 1'b0); // R
    check_channel(2, 1'b0); // G
    check_channel(3, 1'b1); // B, final channel carries TLAST

    repeat (3) @(posedge clk);

    if (pixels_seen !== 32'd1) begin
      $display("[FAIL] pixels_seen expected=1 got=%0d", pixels_seen);
      errors++;
    end

    if (channels_seen !== 32'd3) begin
      $display("[FAIL] channels_seen expected=3 got=%0d", channels_seen);
      errors++;
    end

    $display("[TEST] two packed RGB pixels");

    send_pixel(32'h00060504, 1'b0); // R=4 G=5 B=6
    check_channel(4, 1'b0);
    check_channel(5, 1'b0);
    check_channel(6, 1'b0);

    send_pixel(32'h00090807, 1'b1); // R=7 G=8 B=9
    check_channel(7, 1'b0);
    check_channel(8, 1'b0);
    check_channel(9, 1'b1);

    repeat (3) @(posedge clk);

    if (pixels_seen !== 32'd3) begin
      $display("[FAIL] pixels_seen expected=3 got=%0d", pixels_seen);
      errors++;
    end

    if (channels_seen !== 32'd9) begin
      $display("[FAIL] channels_seen expected=9 got=%0d", channels_seen);
      errors++;
    end

    if (errors == 0) begin
      $display("[PASS] tb_axis_rgb_to_channels tests=%0d", tests);
    end else begin
      $fatal(1, "[FAIL] tb_axis_rgb_to_channels errors=%0d tests=%0d",
             errors, tests);
    end

    $finish;
  end

endmodule
