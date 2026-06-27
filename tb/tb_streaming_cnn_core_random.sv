`timescale 1ns/1ps

module tb_streaming_cnn_core_random;

  localparam int DATA_WIDTH = 8;
  localparam int WEIGHT_WIDTH = 8;
  localparam int ACC_WIDTH = 32;
  localparam int OUT_WIDTH = 8;
  localparam int BIAS_WIDTH = 32;
  localparam int IC = 3;
  localparam int OC = 4;
  localparam int K = 9;
  localparam int MAX_W = 8;

  localparam int NUM_CASES = 30;

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

  int seed;
  logic [31:0] prng_state;

  int errors;
  int total_errors;
  int cases_run;
  int cases_passed;
  int cases_failed;
  int checks_run;

  int out_idx;
  int expected_total;
  int expected_windows;

  logic signed [DATA_WIDTH-1:0] image [IC][MAX_W][MAX_W];
  logic signed [OUT_WIDTH-1:0] expected [0:4095];

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

  function automatic logic [31:0] next_rand;
    begin
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

  function automatic logic signed [7:0] rand_s8(input int lo, input int hi);
    begin
      rand_s8 = logic'(rand_range(lo, hi));
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

  task automatic randomize_case(input int case_id);
    begin
      kernel_mode = logic'(rand_range(0, 1));

      if (kernel_mode) begin
        image_width  = rand_range(3, MAX_W);
        image_height = rand_range(3, MAX_W);
      end else begin
        image_width  = rand_range(1, MAX_W);
        image_height = rand_range(1, MAX_W);
      end

      relu_enable  = logic'(rand_range(0, 1));
      bias_enable  = logic'(rand_range(0, 1));
      quant_enable = logic'(rand_range(0, 1));
      quant_shift  = rand_range(0, 4);

      for (int c = 0; c < IC; c++) begin
        for (int y = 0; y < MAX_W; y++) begin
          for (int x = 0; x < MAX_W; x++) begin
            image[c][y][x] = rand_s8(-8, 8);
          end
        end
      end

      for (int oc = 0; oc < OC; oc++) begin
        bias[oc] = rand_range(-32, 32);

        for (int ic = 0; ic < IC; ic++) begin
          for (int k = 0; k < K; k++) begin
            weights[oc][ic][k] = rand_s8(-4, 4);
          end
        end
      end

      $display(
        "[CASE %0d] mode=%s W=%0d H=%0d relu=%0b bias=%0b quant=%0b shift=%0d",
        case_id,
        kernel_mode ? "3x3" : "1x1",
        image_width,
        image_height,
        relu_enable,
        bias_enable,
        quant_enable,
        quant_shift
      );
    end
  endtask

  task automatic build_expected;
    int idx;
    int out_w;
    int out_h;
    logic signed [31:0] acc;
    begin
      idx = 0;

      if (kernel_mode) begin
        out_w = image_width - 2;
        out_h = image_height - 2;
      end else begin
        out_w = image_width;
        out_h = image_height;
      end

      expected_windows = out_w * out_h;

      for (int y = 0; y < out_h; y++) begin
        for (int x = 0; x < out_w; x++) begin
          for (int oc = 0; oc < OC; oc++) begin
            acc = 0;

            for (int ic = 0; ic < IC; ic++) begin
              if (kernel_mode) begin
                acc += image[ic][y + 0][x + 0] * weights[oc][ic][0];
                acc += image[ic][y + 0][x + 1] * weights[oc][ic][1];
                acc += image[ic][y + 0][x + 2] * weights[oc][ic][2];

                acc += image[ic][y + 1][x + 0] * weights[oc][ic][3];
                acc += image[ic][y + 1][x + 1] * weights[oc][ic][4];
                acc += image[ic][y + 1][x + 2] * weights[oc][ic][5];

                acc += image[ic][y + 2][x + 0] * weights[oc][ic][6];
                acc += image[ic][y + 2][x + 1] * weights[oc][ic][7];
                acc += image[ic][y + 2][x + 2] * weights[oc][ic][8];
              end else begin
                acc += image[ic][y][x] * weights[oc][ic][0];
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
    int gap;
    begin
      gap = rand_range(0, 3);
      repeat (gap) @(posedge clk);

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

      // Random output backpressure.
      if (m_axis_tvalid) begin
        m_axis_tready <= logic'(rand_range(0, 1));
      end else begin
        m_axis_tready <= 1'b1;
      end

      if (m_axis_tvalid && m_axis_tready) begin
        checks_run++;

        if (out_idx >= expected_total) begin
          errors++;
          $error("Extra output[%0d] got=%0d", out_idx, m_axis_tdata);
        end else if (m_axis_tdata !== expected[out_idx]) begin
          errors++;
          $error(
            "Output[%0d] mismatch got=%0d expected=%0d mode=%0b",
            out_idx,
            m_axis_tdata,
            expected[out_idx],
            kernel_mode
          );
        end

        if (out_idx == expected_total - 1) begin
          checks_run++;
          if (!m_axis_tlast) begin
            errors++;
            $error("Missing TLAST on final output");
          end
        end else begin
          checks_run++;
          if (m_axis_tlast) begin
            errors++;
            $error("Early TLAST at output[%0d]", out_idx);
          end
        end

        out_idx++;
      end
    end
  end

  task automatic run_one_case(input int case_id);
    begin
      errors = 0;
      out_idx = 0;
      expected_total = 0;
      expected_windows = 0;
      cases_run++;

      randomize_case(case_id);
      build_expected();

      s_pixel_data = '0;
      s_pixel_valid = 1'b0;
      m_axis_tready = 1'b1;

      rst_n = 1'b0;
      clear = 1'b0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);

      clear = 1'b1;
      @(posedge clk);
      #1;
      clear = 1'b0;

      for (int y = 0; y < image_height; y++) begin
        for (int x = 0; x < image_width; x++) begin
          for (int c = 0; c < IC; c++) begin
            send_pixel(image[c][y][x]);
          end
        end
      end

      wait (out_idx == expected_total);
      repeat (20) @(posedge clk);

      checks_run++;
      if (windows_seen != expected_windows) begin
        errors++;
        $error("windows_seen got=%0d expected=%0d", windows_seen, expected_windows);
      end

      checks_run++;
      if (outputs_seen != expected_total) begin
        errors++;
        $error("outputs_seen got=%0d expected=%0d", outputs_seen, expected_total);
      end

      total_errors += errors;

      if (errors == 0) begin
        cases_passed++;
        $display("[CASE PASS] %0d outputs=%0d windows=%0d", case_id, out_idx, windows_seen);
      end else begin
        cases_failed++;
        $display("[CASE FAIL] %0d errors=%0d outputs=%0d windows=%0d", case_id, errors, out_idx, windows_seen);
      end
    end
  endtask

  task automatic print_summary;
    begin
      $display("");
      $display("============================================================");
      $display("STREAMING CNN CORE RANDOM TEST SUMMARY");
      $display("============================================================");
      $display("Seed          : %0d", seed);
      $display("Cases run     : %0d", cases_run);
      $display("Cases passed  : %0d", cases_passed);
      $display("Cases failed  : %0d", cases_failed);
      $display("Checks run    : %0d", checks_run);
      $display("Total errors  : %0d", total_errors);
      $display("Status        : %s", (total_errors == 0 && cases_failed == 0) ? "PASS" : "FAIL");
      $display("============================================================");
      $display("");
    end
  endtask

  initial begin
    if (!$value$plusargs("ntb_random_seed=%d", seed)) begin
      seed = 12345;
    end

    prng_state = seed[31:0];

    total_errors = 0;
    cases_run = 0;
    cases_passed = 0;
    cases_failed = 0;
    checks_run = 0;

    s_pixel_data = '0;
    s_pixel_valid = 1'b0;
    m_axis_tready = 1'b1;
    clear = 1'b0;
    rst_n = 1'b0;

    for (int i = 0; i < NUM_CASES; i++) begin
      run_one_case(i);
      repeat (20) @(posedge clk);
    end

    print_summary();

    if (total_errors == 0 && cases_failed == 0) begin
      $display("[PASS] tb_streaming_cnn_core_random");
    end else begin
      $fatal(1, "[FAIL] tb_streaming_cnn_core_random errors=%0d", total_errors);
    end

    $finish;
  end

endmodule
