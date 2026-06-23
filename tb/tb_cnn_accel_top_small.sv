`timescale 1ns/1ps

import cnn_accel_pkg::*;

module tb_cnn_accel_top_small;

  localparam int MAX_H = 8;
  localparam int MAX_W = 8;
  localparam int IC = NUM_INPUT_CHANNELS;
  localparam int OC = NUM_OUTPUT_CHANNELS;
  localparam int MAX_OUT_TOTAL = (MAX_H - 2) * (MAX_W - 2) * OC;

  logic clk = 1'b0;
  logic rst_n;

  always #5 clk = ~clk;

  logic cfg_we;
  logic [15:0] cfg_addr;
  logic [31:0] cfg_wdata;
  logic [31:0] cfg_rdata;

  logic [7:0] s_axis_tdata;
  logic s_axis_tvalid;
  logic s_axis_tready;
  logic s_axis_tlast;

  logic [7:0] m_axis_tdata;
  logic m_axis_tvalid;
  logic m_axis_tready;
  logic m_axis_tlast;

  logic busy;
  logic done;

  logic [31:0] cycle_count;
  logic [31:0] input_pixel_count;
  logic [31:0] window_count;
  logic [31:0] mac_count;
  logic [31:0] output_count;
  logic [31:0] stall_count;
  logic [31:0] fifo_full_count;

  logic signed [7:0] input_mem [IC][MAX_H][MAX_W];
  logic signed [7:0] weight_mem[OC][IC][KERNEL_TAPS];
  logic signed [31:0] bias_mem[OC];
  logic signed [7:0] expected[MAX_OUT_TOTAL];

  int tests;
  int errors;
  int seed;

  int cov_relu_on;
  int cov_relu_off;
  int cov_quant_on;
  int cov_quant_off;
  int cov_shift_zero;
  int cov_shift_low;
  int cov_shift_high;
  int cov_cross[2][2];

  cnn_accel_top dut (
    .clk(clk),
    .rst_n(rst_n),

    .cfg_we(cfg_we),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .cfg_rdata(cfg_rdata),

    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),

    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),

    .busy(busy),
    .done(done),

    .cycle_count(cycle_count),
    .input_pixel_count(input_pixel_count),
    .window_count(window_count),
    .mac_count(mac_count),
    .output_count(output_count),
    .stall_count(stall_count),
    .fifo_full_count(fifo_full_count)
  );

  function automatic signed [7:0] sat8(input signed [31:0] x);
    begin
      if (x > 32'sd127) begin
        sat8 = 8'sd127;
      end else if (x < -32'sd128) begin
        sat8 = -8'sd128;
      end else begin
        sat8 = x[7:0];
      end
    end
  endfunction

  function automatic int rand_range(input int min_val, input int max_val);
    int r;
    begin
      r = $random(seed);

      if (r < 0) begin
        r = -r;
      end

      rand_range = min_val + (r % (max_val - min_val + 1));
    end
  endfunction

  task automatic cfg_write(input [15:0] addr, input [31:0] data);
    begin
      @(negedge clk);
      cfg_addr  = addr;
      cfg_wdata = data;
      cfg_we    = 1'b1;

      @(negedge clk);
      cfg_we    = 1'b0;
      cfg_addr  = '0;
      cfg_wdata = '0;
    end
  endtask

  task automatic reset_dut;
    begin
      @(negedge clk);

      rst_n = 1'b0;

      cfg_we = 1'b0;
      cfg_addr = '0;
      cfg_wdata = '0;

      s_axis_tdata = '0;
      s_axis_tvalid = 1'b0;
      s_axis_tlast = 1'b0;

      // Hold output interface during reset and input loading.
      // The collector will release this later.
      m_axis_tready = 1'b0;

      repeat (5) @(negedge clk);

      rst_n = 1'b1;

      repeat (2) @(negedge clk);
    end
  endtask

  task automatic init_scenario(input int scenario, input int h, input int w);
    begin
      for (int ic = 0; ic < IC; ic++) begin
        for (int r = 0; r < MAX_H; r++) begin
          for (int c = 0; c < MAX_W; c++) begin
            unique case (scenario)
              0: input_mem[ic][r][c] = $signed((ic + r + c) & 8'h7f);
              1: input_mem[ic][r][c] = 8'sd3;
              2: input_mem[ic][r][c] = 8'sd127;
              default: input_mem[ic][r][c] = rand_range(-16, 15);
            endcase
          end
        end
      end

      for (int oc = 0; oc < OC; oc++) begin
        unique case (scenario)
          0: bias_mem[oc] = oc;
          1: bias_mem[oc] = -32'sd5;
          2: bias_mem[oc] = 32'sd0;
          default: bias_mem[oc] = rand_range(-128, 127);
        endcase

        for (int ic = 0; ic < IC; ic++) begin
          for (int k = 0; k < KERNEL_TAPS; k++) begin
            unique case (scenario)
              0: begin
                if (oc == 0) begin
                  weight_mem[oc][ic][k] = 8'sd1;
                end else if (oc == 1) begin
                  weight_mem[oc][ic][k] = 8'sd0;
                end else if (oc == 2) begin
                  weight_mem[oc][ic][k] = -8'sd1;
                end else begin
                  weight_mem[oc][ic][k] = 8'sd1;
                end
              end

              1: weight_mem[oc][ic][k] = -8'sd2;
              2: weight_mem[oc][ic][k] = 8'sd127;
              default: weight_mem[oc][ic][k] = rand_range(-16, 15);
            endcase
          end
        end
      end
    end
  endtask

  task automatic compute_expected(
    input int h,
    input int w,
    input bit relu_en,
    input bit bias_en,
    input bit quant_en,
    input int qshift,
    output int total_outputs
  );
    int out_h;
    int out_w;
    int idx;
    logic signed [31:0] acc;

    begin
      out_h = h - 2;
      out_w = w - 2;
      total_outputs = out_h * out_w * OC;
      idx = 0;

      for (int r = 0; r < out_h; r++) begin
        for (int c = 0; c < out_w; c++) begin
          for (int oc = 0; oc < OC; oc++) begin
            acc = '0;

            for (int ic = 0; ic < IC; ic++) begin
              acc += input_mem[ic][r + 0][c + 0] * weight_mem[oc][ic][0];
              acc += input_mem[ic][r + 0][c + 1] * weight_mem[oc][ic][1];
              acc += input_mem[ic][r + 0][c + 2] * weight_mem[oc][ic][2];

              acc += input_mem[ic][r + 1][c + 0] * weight_mem[oc][ic][3];
              acc += input_mem[ic][r + 1][c + 1] * weight_mem[oc][ic][4];
              acc += input_mem[ic][r + 1][c + 2] * weight_mem[oc][ic][5];

              acc += input_mem[ic][r + 2][c + 0] * weight_mem[oc][ic][6];
              acc += input_mem[ic][r + 2][c + 1] * weight_mem[oc][ic][7];
              acc += input_mem[ic][r + 2][c + 2] * weight_mem[oc][ic][8];
            end

            if (bias_en) begin
              acc += bias_mem[oc];
            end

            if (relu_en && acc < 0) begin
              acc = '0;
            end

            if (quant_en) begin
              acc = acc >>> qshift;
            end

            expected[idx] = sat8(acc);
            idx++;
          end
        end
      end
    end
  endtask

  task automatic sample_manual_coverage(input bit relu_en, input bit quant_en, input int qshift);
    begin
      if (relu_en) begin
        cov_relu_on++;
      end else begin
        cov_relu_off++;
      end

      if (quant_en) begin
        cov_quant_on++;
      end else begin
        cov_quant_off++;
      end

      if (qshift == 0) begin
        cov_shift_zero++;
      end else if (qshift >= 1 && qshift <= 3) begin
        cov_shift_low++;
      end else if (qshift >= 4 && qshift <= 6) begin
        cov_shift_high++;
      end

      cov_cross[relu_en][quant_en]++;
    end
  endtask

  task automatic program_dut(
    input int h,
    input int w,
    input bit relu_en,
    input bit bias_en,
    input bit quant_en,
    input int qshift
  );
    logic [31:0] ctrl;

    begin
      cfg_write(16'h0008, w[31:0]);
      cfg_write(16'h000C, h[31:0]);
      cfg_write(16'h0010, qshift[31:0]);

      ctrl = {28'd0, quant_en, bias_en, relu_en, 1'b0};
      cfg_write(16'h0000, ctrl);

      for (int oc = 0; oc < OC; oc++) begin
        cfg_write(16'h0400 + oc * 4, bias_mem[oc]);

        for (int ic = 0; ic < IC; ic++) begin
          for (int k = 0; k < KERNEL_TAPS; k++) begin
            cfg_write(
              16'h0100 + (((oc * IC * KERNEL_TAPS) + (ic * KERNEL_TAPS) + k) * 4),
              {{24{weight_mem[oc][ic][k][7]}}, weight_mem[oc][ic][k]}
            );
          end
        end
      end

      sample_manual_coverage(relu_en, quant_en, qshift);
    end
  endtask

  task automatic start_dut(input bit relu_en, input bit bias_en, input bit quant_en);
    logic [31:0] ctrl;

    begin
      ctrl = {28'd0, quant_en, bias_en, relu_en, 1'b1};
      cfg_write(16'h0000, ctrl);

      repeat (2) @(negedge clk);

      $display(
        "[DEBUG] after start: busy=%0b done=%0b dut.loading=%0b dut.computing=%0b start_pulse=%0b s_axis_tready=%0b",
        busy,
        done,
        dut.loading,
        dut.computing,
        dut.start_pulse,
        s_axis_tready
      );
    end
  endtask

  task automatic send_one_pixel(
    input logic signed [7:0] pix,
    input bit last,
    input bit random_gaps
  );
    int ready_timeout;
    logic [31:0] prev_input_count;
    bit accepted;

    begin
      if (random_gaps && (rand_range(0, 2) == 0)) begin
        repeat (rand_range(1, 3)) @(negedge clk);
      end

      prev_input_count = input_pixel_count;
      accepted = 1'b0;

      @(negedge clk);
      s_axis_tdata  = pix;
      s_axis_tlast  = last;
      s_axis_tvalid = 1'b1;

      ready_timeout = 0;

      while (!accepted) begin
        @(posedge clk);
        #1;

        if (s_axis_tready === 1'b1) begin
          accepted = 1'b1;
        end

        if (input_pixel_count != prev_input_count) begin
          accepted = 1'b1;
        end

        ready_timeout++;

        if (ready_timeout > 1000) begin
          errors++;

          $error(
            "Timeout waiting for input accept. pix=%0d last=%0b busy=%0b done=%0b dut.loading=%0b dut.computing=%0b start_pulse=%0b s_axis_tvalid=%0b s_axis_tready=%0b input_pixel_count=%0d prev_input_count=%0d",
            pix,
            last,
            busy,
            done,
            dut.loading,
            dut.computing,
            dut.start_pulse,
            s_axis_tvalid,
            s_axis_tready,
            input_pixel_count,
            prev_input_count
          );

          $fatal(1);
        end
      end

      @(negedge clk);
      s_axis_tvalid = 1'b0;
      s_axis_tlast  = 1'b0;
    end
  endtask

  task automatic send_image(input int h, input int w, input bit random_gaps);
    bit is_last;

    begin
      $display("[SEND] sending image h=%0d w=%0d IC=%0d total_pixels=%0d", h, w, IC, h * w * IC);

      for (int ic = 0; ic < IC; ic++) begin
        for (int r = 0; r < h; r++) begin
          for (int c = 0; c < w; c++) begin
            is_last = (ic == IC - 1 && r == h - 1 && c == w - 1);
            send_one_pixel(input_mem[ic][r][c], is_last, random_gaps);
          end
        end
      end

      $display("[SEND] finished sending image");
    end
  endtask

    task automatic collect_and_check(input int total_outputs, input bit random_backpressure, input string name);
    int idx;
    int timeout;
    bit saw_last;

    logic sample_valid;
    logic sample_ready;
    logic signed [7:0] sample_data;
    logic sample_last;

    begin
      idx = 0;
      timeout = 0;
      saw_last = 1'b0;

      $display("[COLLECT] expecting %0d outputs", total_outputs);

      while (idx < total_outputs && timeout < 30000) begin
        @(negedge clk);

        if (random_backpressure) begin
          m_axis_tready = (rand_range(0, 3) != 0);
        end else begin
          m_axis_tready = 1'b1;
        end

        #1;

        // Sample the currently-held AXI output beat before the posedge
        // where ready/valid will accept it.
        sample_valid = m_axis_tvalid;
        sample_ready = m_axis_tready;
        sample_data  = $signed(m_axis_tdata);
        sample_last  = m_axis_tlast;

        @(posedge clk);

        if (sample_valid && sample_ready) begin
          tests++;

          if (sample_data !== expected[idx]) begin
            errors++;
            $error(
              "%s output[%0d] mismatch got=%0d expected=%0d",
              name,
              idx,
              sample_data,
              expected[idx]
            );
          end

          tests++;

          if (sample_last !== (idx == total_outputs - 1)) begin
            errors++;
            $error(
              "%s tlast mismatch at output[%0d]: got=%0b expected=%0b",
              name,
              idx,
              sample_last,
              (idx == total_outputs - 1)
            );
          end

          if (sample_last) begin
            saw_last = 1'b1;
          end

          idx++;
        end

        timeout++;
      end

      m_axis_tready = 1'b0;

      if (timeout >= 30000) begin
        errors++;
        $error(
          "%s timed out after collecting %0d/%0d outputs. busy=%0b done=%0b output_valid_en=%0b out_oc=%0d out_pixel_addr=%0d output_count=%0d",
          name,
          idx,
          total_outputs,
          busy,
          done,
          dut.output_valid_en,
          dut.out_oc,
          dut.out_pixel_addr,
          output_count
        );
        $fatal(1);
      end

      tests++;

      if (!saw_last) begin
        errors++;
        $error("%s never observed m_axis_tlast", name);
        $fatal(1);
      end

      $display("[COLLECT] collected %0d/%0d outputs", idx, total_outputs);
    end
  endtask

  task automatic wait_done(input string name);
    int timeout;

    begin
      timeout = 0;

      while (done !== 1'b1 && busy !== 1'b0 && timeout < 1000) begin
        @(posedge clk);
        timeout++;
      end

      tests++;

      if (timeout >= 1000) begin
        errors++;
        $error(
          "%s timed out waiting for done/busy-low. busy=%0b done=%0b output_count=%0d window_count=%0d mac_count=%0d",
          name,
          busy,
          done,
          output_count,
          window_count,
          mac_count
        );
        $fatal(1);
      end

      @(negedge clk);
    end
  endtask

  task automatic run_scenario(
    input string name,
    input int scenario,
    input int h,
    input int w,
    input bit relu_en,
    input bit bias_en,
    input bit quant_en,
    input int qshift,
    input bit gaps,
    input bit stalls
  );
    int total_outputs;
    int expected_input_count;
    int expected_window_count;
    int expected_mac_count;
    int errors_before;

    begin
      errors_before = errors;

      $display("============================================================");
      $display("[SCENARIO] %s", name);
      $display("============================================================");

      $display("[SCENARIO] reset DUT");
      reset_dut();

      $display("[SCENARIO] init inputs/weights/bias");
      init_scenario(scenario, h, w);

      $display("[SCENARIO] compute expected output");
      compute_expected(h, w, relu_en, bias_en, quant_en, qshift, total_outputs);

      $display("[SCENARIO] program DUT");
      program_dut(h, w, relu_en, bias_en, quant_en, qshift);

      $display("[SCENARIO] start DUT");
      m_axis_tready = 1'b0;
      start_dut(relu_en, bias_en, quant_en);

      $display("[SCENARIO] send image");
      send_image(h, w, gaps);

      // Keep output stalled until collector is active.
      repeat (2) @(negedge clk);

      $display("[SCENARIO] collect and check outputs");
      collect_and_check(total_outputs, stalls, name);

      $display("[SCENARIO] wait done");
      wait_done(name);

      expected_input_count  = h * w * IC;
      expected_window_count = (h - 2) * (w - 2);
      expected_mac_count    = expected_window_count * IC * OC * KERNEL_TAPS;

      tests++;

      if (input_pixel_count !== expected_input_count) begin
        errors++;
        $error(
          "%s input counter got=%0d expected=%0d",
          name,
          input_pixel_count,
          expected_input_count
        );
      end

      tests++;

      if (output_count !== total_outputs) begin
        errors++;
        $error(
          "%s output counter got=%0d expected=%0d",
          name,
          output_count,
          total_outputs
        );
      end

      tests++;

      if (window_count !== expected_window_count) begin
        errors++;
        $error(
          "%s window counter got=%0d expected=%0d",
          name,
          window_count,
          expected_window_count
        );
      end

      tests++;

      if (mac_count !== expected_mac_count) begin
        errors++;
        $error(
          "%s mac counter got=%0d expected=%0d",
          name,
          mac_count,
          expected_mac_count
        );
      end

      if (errors == errors_before) begin
        $display("[SCENARIO PASS] %s", name);
      end else begin
        $display("[SCENARIO FAIL] %s errors_added=%0d", name, errors - errors_before);
      end
    end
  endtask

  task automatic check_coverage;
    begin
      if (
        cov_relu_on == 0 ||
        cov_relu_off == 0 ||
        cov_quant_on == 0 ||
        cov_quant_off == 0 ||
        cov_shift_zero == 0 ||
        cov_shift_low == 0 ||
        cov_shift_high == 0 ||
        cov_cross[0][0] == 0 ||
        cov_cross[0][1] == 0 ||
        cov_cross[1][0] == 0 ||
        cov_cross[1][1] == 0
      ) begin
        errors++;

        $error(
          "Coverage miss: relu_on=%0d relu_off=%0d quant_on=%0d quant_off=%0d shift_zero=%0d shift_low=%0d shift_high=%0d cross00=%0d cross01=%0d cross10=%0d cross11=%0d",
          cov_relu_on,
          cov_relu_off,
          cov_quant_on,
          cov_quant_off,
          cov_shift_zero,
          cov_shift_low,
          cov_shift_high,
          cov_cross[0][0],
          cov_cross[0][1],
          cov_cross[1][0],
          cov_cross[1][1]
        );
      end else begin
        $display("[COVERAGE] config bins hit: relu on/off, quant on/off, shift zero/low/high, reluXquant cross");
      end
    end
  endtask

  initial begin
    $dumpfile("tb_cnn_accel_top_small.vcd");
    $dumpvars(0, tb_cnn_accel_top_small);

    if (!$value$plusargs("ntb_random_seed=%d", seed)) begin
      seed = 32'h6bad_c0df;
    end

    $display("[TB] ntb_random_seed=%0d", seed);

    tests = 0;
    errors = 0;

    cov_relu_on = 0;
    cov_relu_off = 0;
    cov_quant_on = 0;
    cov_quant_off = 0;
    cov_shift_zero = 0;
    cov_shift_low = 0;
    cov_shift_high = 0;

    cov_cross[0][0] = 0;
    cov_cross[0][1] = 0;
    cov_cross[1][0] = 0;
    cov_cross[1][1] = 0;

    rst_n = 1'b0;

    cfg_we = 1'b0;
    cfg_addr = '0;
    cfg_wdata = '0;

    s_axis_tdata = '0;
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;

    m_axis_tready = 1'b0;

    repeat (2) @(posedge clk);

    run_scenario(
      "directed_5x5_relu_bias_no_stalls",
      0,
      5,
      5,
      1'b1,
      1'b1,
      1'b1,
      0,
      1'b0,
      1'b0
    );

    run_scenario(
      "negative_relu_disabled_low_shift",
      1,
      5,
      5,
      1'b0,
      1'b1,
      1'b1,
      1,
      1'b1,
      1'b0
    );

    run_scenario(
      "small_backpressure_quant",
      3,
      5,
      6,
      1'b1,
      1'b1,
      1'b1,
      2,
      1'b1,
      1'b1
    );

    run_scenario(
      "small_no_relu_no_quant_high_shift",
      4,
      5,
      5,
      1'b0,
      1'b0,
      1'b0,
      5,
      1'b0,
      1'b1
    );

    run_scenario(
      "small_relu_no_quant_cross_coverage",
      5,
      5,
      5,
      1'b1,
      1'b0,
      1'b0,
      4,
      1'b0,
      1'b0
    );

    check_coverage();

    $display("============================================================");
    $display("tb_cnn_accel_top_small summary");
    $display("Tests run : %0d", tests);
    $display("Errors    : %0d", errors);
    $display("============================================================");

    if (errors != 0) begin
      $fatal(1, "tb_cnn_accel_top_small FAILED: tests=%0d errors=%0d", tests, errors);
    end else begin
      $display("[PASS] tb_cnn_accel_top_small tests=%0d", tests);
    end

    $finish;
  end

endmodule