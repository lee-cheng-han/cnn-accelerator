`timescale 1ns/1ps

module tb_streaming_cnn_core;

  localparam int DATA_WIDTH = 8;
  localparam int WEIGHT_WIDTH = 8;
  localparam int ACC_WIDTH = 32;
  localparam int OUT_WIDTH = 8;
  localparam int BIAS_WIDTH = 32;
  localparam int IC = 3;
  localparam int OC = 4;
  localparam int K = 9;
  localparam int W = 5;
  localparam int H = 4;
  localparam int MAX_W = 8;

  logic clk;
  logic rst_n;
  logic clear;

  logic [15:0] image_width;
  logic [15:0] image_height;
  logic kernel_mode;

  logic signed [DATA_WIDTH-1:0] s_pixel_data;
  logic s_pixel_valid;
  logic s_pixel_ready;

  logic signed [WEIGHT_WIDTH-1:0] weights [OC][IC][K];
  logic signed [BIAS_WIDTH-1:0] bias [OC];

  logic relu_enable;
  logic bias_enable;
  logic quant_enable;
  logic [4:0] quant_shift;

  logic signed [OUT_WIDTH-1:0] m_axis_tdata;
  logic m_axis_tvalid;
  logic m_axis_tready;
  logic m_axis_tlast;

  logic [31:0] windows_seen;
  logic [31:0] outputs_seen;

  int errors;
  int total_errors;
  int cases_run;
  int cases_passed;
  int cases_failed;
  int tests_checked;

  int out_idx;
  int expected_total;
  logic signed [OUT_WIDTH-1:0] expected [0:511];

  streaming_cnn_core #(
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUT_WIDTH(OUT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .NUM_INPUT_CHANNELS(IC),
    .NUM_OUTPUT_CHANNELS(OC),
    .KERNEL_TAPS(K),
    .MAX_IMG_WIDTH(MAX_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .image_width(image_width),
    .image_height(image_height),
    .kernel_mode(kernel_mode),

    .s_pixel_data(s_pixel_data),
    .s_pixel_valid(s_pixel_valid),
    .s_pixel_ready(s_pixel_ready),

    .weights(weights),
    .bias(bias),

    .relu_enable(relu_enable),
    .bias_enable(bias_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),

    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),

    .windows_seen(windows_seen),
    .outputs_seen(outputs_seen)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function automatic logic signed [DATA_WIDTH-1:0] pix(
    input int c,
    input int y,
    input int x
  );
    begin
      pix = logic'(c * 20 + y * W + x);
    end
  endfunction

  function automatic logic signed [OUT_WIDTH-1:0] sat8(input logic signed [31:0] value);
    begin
      if (value > 32'sd127) begin
        sat8 = 8'sd127;
      end else if (value < -32'sd128) begin
        sat8 = -8'sd128;
      end else begin
        sat8 = value[7:0];
      end
    end
  endfunction

  task automatic init_weights;
    begin
      for (int oc = 0; oc < OC; oc++) begin
        bias[oc] = oc;

        for (int ic = 0; ic < IC; ic++) begin
          for (int k = 0; k < K; k++) begin
            if (oc == 0) begin
              weights[oc][ic][k] = 8'sd1;
            end else if (oc == 1) begin
              weights[oc][ic][k] = 8'sd0;
            end else if (oc == 2) begin
              weights[oc][ic][k] = -8'sd1;
            end else begin
              weights[oc][ic][k] = 8'sd2;
            end
          end
        end
      end
    end
  endtask

  task automatic build_expected(input bit mode_3x3);
    int idx;
    int out_w;
    int out_h;
    logic signed [31:0] acc;
    begin
      idx = 0;

      if (mode_3x3) begin
        out_w = W - 2;
        out_h = H - 2;
      end else begin
        out_w = W;
        out_h = H;
      end

      for (int y = 0; y < out_h; y++) begin
        for (int x = 0; x < out_w; x++) begin
          for (int oc = 0; oc < OC; oc++) begin
            acc = 0;

            for (int ic = 0; ic < IC; ic++) begin
              if (mode_3x3) begin
                acc += pix(ic, y + 0, x + 0) * weights[oc][ic][0];
                acc += pix(ic, y + 0, x + 1) * weights[oc][ic][1];
                acc += pix(ic, y + 0, x + 2) * weights[oc][ic][2];

                acc += pix(ic, y + 1, x + 0) * weights[oc][ic][3];
                acc += pix(ic, y + 1, x + 1) * weights[oc][ic][4];
                acc += pix(ic, y + 1, x + 2) * weights[oc][ic][5];

                acc += pix(ic, y + 2, x + 0) * weights[oc][ic][6];
                acc += pix(ic, y + 2, x + 1) * weights[oc][ic][7];
                acc += pix(ic, y + 2, x + 2) * weights[oc][ic][8];
              end else begin
                acc += pix(ic, y, x) * weights[oc][ic][0];
              end
            end

            if (bias_enable) begin
              acc += bias[oc];
            end

            if (relu_enable && acc < 0) begin
              acc = 0;
            end

            if (quant_enable) begin
              acc = acc >>> quant_shift;
            end

            expected[idx] = sat8(acc);
            idx++;
          end
        end
      end

      expected_total = idx;
    end
  endtask

  task automatic send_pixel(input logic signed [DATA_WIDTH-1:0] value);
    begin
      @(negedge clk);
      s_pixel_data  = value;
      s_pixel_valid = 1'b1;

      do begin
        @(posedge clk);
        #1;
      end while (!s_pixel_ready);

      @(negedge clk);
      s_pixel_valid = 1'b0;
      s_pixel_data  = '0;
    end
  endtask

  always @(posedge clk) begin
    if (rst_n) begin
      #1;

      if (m_axis_tvalid && m_axis_tready) begin
        tests_checked++;

        if (out_idx >= expected_total) begin
          errors++;
          $error("extra output[%0d] got=%0d", out_idx, m_axis_tdata);
        end else if (m_axis_tdata !== expected[out_idx]) begin
          errors++;
          $error(
            "output[%0d] mismatch got=%0d expected=%0d mode=%0d",
            out_idx,
            m_axis_tdata,
            expected[out_idx],
            kernel_mode
          );
        end

        if (out_idx == expected_total - 1) begin
          if (!m_axis_tlast) begin
            errors++;
            $error("missing tlast on final output");
          end
        end else begin
          if (m_axis_tlast) begin
            errors++;
            $error("early tlast at output[%0d]", out_idx);
          end
        end

        out_idx++;
      end
    end
  end

  task automatic run_case(input string name, input bit mode_3x3);
    int expected_windows;
    begin
      $display("============================================================");
      $display("[CASE] %s", name);
      $display("============================================================");

      errors = 0;
      out_idx = 0;
      expected_total = 0;
      cases_run++;

      image_width = W;
      image_height = H;
      kernel_mode = mode_3x3;

      s_pixel_data = '0;
      s_pixel_valid = 1'b0;
      m_axis_tready = 1'b1;

      relu_enable = 1'b0;
      bias_enable = 1'b1;
      quant_enable = 1'b1;
      quant_shift = 5'd3;

      init_weights();
      build_expected(mode_3x3);

      clear = 1'b0;
      rst_n = 1'b0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);

      clear = 1'b1;
      @(posedge clk);
      #1;
      clear = 1'b0;

      for (int y = 0; y < H; y++) begin
        for (int x = 0; x < W; x++) begin
          for (int c = 0; c < IC; c++) begin
            send_pixel(pix(c, y, x));
          end
        end
      end

      repeat (200) @(posedge clk);

      if (mode_3x3) begin
        expected_windows = (W - 2) * (H - 2);
      end else begin
        expected_windows = W * H;
      end

      tests_checked++;
      if (out_idx != expected_total) begin
        errors++;
        $error("%s outputs got=%0d expected=%0d", name, out_idx, expected_total);
      end

      tests_checked++;
      if (windows_seen != expected_windows) begin
        errors++;
        $error("%s windows_seen got=%0d expected=%0d", name, windows_seen, expected_windows);
      end

      tests_checked++;
      if (outputs_seen != expected_total) begin
        errors++;
        $error("%s outputs_seen got=%0d expected=%0d", name, outputs_seen, expected_total);
      end

      total_errors += errors;

      if (errors == 0) begin
        cases_passed++;
        $display("[CASE PASS] %s outputs=%0d windows=%0d", name, out_idx, windows_seen);
      end else begin
        cases_failed++;
        $display("[CASE FAIL] %s errors=%0d outputs=%0d windows=%0d", name, errors, out_idx, windows_seen);
      end
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("STREAMING CNN CORE TEST SUMMARY");
      $display("============================================================");
      $display("Cases run     : %0d", cases_run);
      $display("Cases passed  : %0d", cases_passed);
      $display("Cases failed  : %0d", cases_failed);
      $display("Checks run    : %0d", tests_checked);
      $display("Total errors  : %0d", total_errors);

      if (total_errors == 0 && cases_failed == 0) begin
        $display("Status        : PASS");
      end else begin
        $display("Status        : FAIL");
      end

      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    total_errors = 0;
    cases_run    = 0;
    cases_passed = 0;
    cases_failed = 0;
    tests_checked = 0;

    run_case("streaming_3x3", 1'b1);
    repeat (20) @(posedge clk);
    run_case("streaming_1x1", 1'b0);

    print_summary();

    if (total_errors != 0 || cases_failed != 0) begin
      $fatal(1, "tb_streaming_cnn_core FAILED: cases=%0d errors=%0d", cases_run, total_errors);
    end else begin
      $display("[PASS] tb_streaming_cnn_core");
    end

    $finish;
  end

endmodule
