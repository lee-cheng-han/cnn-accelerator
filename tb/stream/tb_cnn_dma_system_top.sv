`timescale 1ns/1ps

module tb_cnn_dma_system_top;

  localparam int AXI_ADDR_WIDTH = 12;
  localparam int AXI_DATA_WIDTH = 32;

  localparam logic [11:0] REG_CONTROL     = 12'h000;
  localparam logic [11:0] REG_WIDTH       = 12'h008;
  localparam logic [11:0] REG_HEIGHT      = 12'h00C;
  localparam logic [11:0] REG_MODE_FLAGS  = 12'h010;
  localparam logic [11:0] REG_WEIGHT_BASE = 12'h100;
  localparam logic [11:0] REG_BIAS_BASE   = 12'h400;

  localparam int NUM_INPUT_CHANNELS  = 3;
  localparam int NUM_OUTPUT_CHANNELS = 4;
  localparam int KERNEL_TAPS         = 9;
  localparam int NUM_WEIGHTS         = NUM_INPUT_CHANNELS * NUM_OUTPUT_CHANNELS * KERNEL_TAPS;

  logic clk;
  logic rst_n;

  logic [AXI_ADDR_WIDTH-1:0]     s_axi_awaddr;
  logic                         s_axi_awvalid;
  logic                         s_axi_awready;

  logic [AXI_DATA_WIDTH-1:0]     s_axi_wdata;
  logic [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb;
  logic                         s_axi_wvalid;
  logic                         s_axi_wready;

  logic [1:0]                   s_axi_bresp;
  logic                         s_axi_bvalid;
  logic                         s_axi_bready;

  logic [AXI_ADDR_WIDTH-1:0]     s_axi_araddr;
  logic                         s_axi_arvalid;
  logic                         s_axi_arready;

  logic [AXI_DATA_WIDTH-1:0]     s_axi_rdata;
  logic [1:0]                   s_axi_rresp;
  logic                         s_axi_rvalid;
  logic                         s_axi_rready;

  logic [31:0]                  s_axis_tdata;
  logic                         s_axis_tvalid;
  logic                         s_axis_tready;
  logic                         s_axis_tlast;

  logic [31:0]                  m_axis_tdata;
  logic                         m_axis_tvalid;
  logic                         m_axis_tready;
  logic                         m_axis_tlast;

  int errors;
  int tests;

  int out_count;
  int expected_count;

  int expected_3x3 [0:15];
  int expected_1x1 [0:63];

  cnn_dma_system_top dut (
    .s_axi_aclk(clk),
    .s_axi_aresetn(rst_n),

    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),

    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),

    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),

    .s_axi_araddr(s_axi_araddr),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),

    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),

    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),

    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast)
  );

  always #5 clk = ~clk;

  function automatic int pixel_r(input int x, input int y);
    return x + 1;
  endfunction

  function automatic int pixel_g(input int x, input int y);
    return y + 1;
  endfunction

  function automatic int pixel_b(input int x, input int y);
    return x + y + 1;
  endfunction

  function automatic logic [31:0] pack_rgb(input int r, input int g, input int b);
    return {8'd0, b[7:0], g[7:0], r[7:0]};
  endfunction

  task automatic axi_write(
    input logic [11:0] addr,
    input logic [31:0] data
  );
    begin
      @(posedge clk);
      s_axi_awaddr  <= addr;
      s_axi_awvalid <= 1'b1;
      s_axi_wdata   <= data;
      s_axi_wstrb   <= 4'hf;
      s_axi_wvalid  <= 1'b1;
      s_axi_bready  <= 1'b1;

      wait (s_axi_awready && s_axi_wready);
      @(posedge clk);

      s_axi_awvalid <= 1'b0;
      s_axi_wvalid  <= 1'b0;
      s_axi_awaddr  <= '0;
      s_axi_wdata   <= '0;

      wait (s_axi_bvalid);
      @(posedge clk);
      s_axi_bready <= 1'b0;
    end
  endtask

  task automatic clear_accel();
    begin
      axi_write(REG_CONTROL, 32'h2);
      repeat (10) @(posedge clk);
    end
  endtask

  task automatic load_identity_weights(input bit kernel_mode);
    int active_tap;
    int idx;
    begin
      active_tap = kernel_mode ? 4 : 0;

      for (int i = 0; i < NUM_WEIGHTS; i++) begin
        axi_write(REG_WEIGHT_BASE + (i * 4), 32'd0);
      end

      idx = (((0 * NUM_INPUT_CHANNELS) + 0) * KERNEL_TAPS) + active_tap;
      axi_write(REG_WEIGHT_BASE + (idx * 4), 32'd1);

      idx = (((1 * NUM_INPUT_CHANNELS) + 1) * KERNEL_TAPS) + active_tap;
      axi_write(REG_WEIGHT_BASE + (idx * 4), 32'd1);

      idx = (((2 * NUM_INPUT_CHANNELS) + 2) * KERNEL_TAPS) + active_tap;
      axi_write(REG_WEIGHT_BASE + (idx * 4), 32'd1);

      idx = (((3 * NUM_INPUT_CHANNELS) + 0) * KERNEL_TAPS) + active_tap;
      axi_write(REG_WEIGHT_BASE + (idx * 4), 32'd1);

      idx = (((3 * NUM_INPUT_CHANNELS) + 1) * KERNEL_TAPS) + active_tap;
      axi_write(REG_WEIGHT_BASE + (idx * 4), 32'd1);

      idx = (((3 * NUM_INPUT_CHANNELS) + 2) * KERNEL_TAPS) + active_tap;
      axi_write(REG_WEIGHT_BASE + (idx * 4), 32'd1);
    end
  endtask

  task automatic load_zero_biases();
    begin
      for (int oc = 0; oc < NUM_OUTPUT_CHANNELS; oc++) begin
        axi_write(REG_BIAS_BASE + (oc * 4), 32'd0);
      end


    end
  endtask

  task automatic send_pixel(
    input logic [31:0] pixel,
    input bit last
  );
    begin
      // AXI-Stream rule:
      // Hold TVALID and TDATA stable until TVALID && TREADY is observed.
      @(negedge clk);
      s_axis_tdata  <= pixel;
      s_axis_tvalid <= 1'b1;
      s_axis_tlast  <= last;

      do begin
        @(posedge clk);
      end while (!s_axis_tready);

      @(negedge clk);
      s_axis_tvalid <= 1'b0;
      s_axis_tlast  <= 1'b0;
      s_axis_tdata  <= 32'd0;
    end
  endtask

  task automatic send_4x4_image();
    int r;
    int g;
    int b;
    bit last;
    begin
      for (int y = 0; y < 4; y++) begin
        for (int x = 0; x < 4; x++) begin
          r = pixel_r(x, y);
          g = pixel_g(x, y);
          b = pixel_b(x, y);
          last = (x == 3) && (y == 3);
          send_pixel(pack_rgb(r, g, b), last);
        end
      end
    end
  endtask

  task automatic collect_outputs_3x3();
    int timeout;
    begin
      out_count = 0;
      timeout = 0;

      while (out_count < 16 && timeout < 20000) begin
        @(posedge clk);
        timeout++;

        if (m_axis_tvalid && m_axis_tready) begin
          tests++;

          if ($signed(m_axis_tdata) !== expected_3x3[out_count]) begin
            $display("[FAIL] 3x3 output[%0d] expected=%0d got=%0d",
                     out_count, expected_3x3[out_count], $signed(m_axis_tdata));
            errors++;
          end

          if ((out_count == 15) && !m_axis_tlast) begin
            $display("[FAIL] 3x3 final output missing TLAST");
            errors++;
          end

          if ((out_count != 15) && m_axis_tlast) begin
            $display("[FAIL] 3x3 early TLAST at output[%0d]", out_count);
            errors++;
          end

          out_count++;
        end
      end

      if (out_count != 16) begin
        $display("[FAIL] 3x3 timeout: got %0d / 16 outputs", out_count);
        $display("debug 3x3: input_pixels=%0d input_channels=%0d windows_seen=%0d core_outputs=%0d dma_outputs=%0d",
                 dut.input_pixels_seen, dut.input_channels_seen, dut.windows_seen,
                 dut.core_outputs_seen, dut.dma_outputs_seen);
        $display("debug 3x3: total_windows=%0d window_index=%0d kernel_mode=%0d",
                 dut.u_streaming_core.total_windows,
                 dut.u_streaming_core.window_index,
                 dut.cfg_kernel_mode);
        errors++;
      end
    end
  endtask

  task automatic collect_outputs_1x1();
    int timeout;
    begin
      out_count = 0;
      timeout = 0;

      while (out_count < 64 && timeout < 20000) begin
        @(posedge clk);
        timeout++;

        if (m_axis_tvalid && m_axis_tready) begin
          tests++;

          if ($signed(m_axis_tdata) !== expected_1x1[out_count]) begin
            $display("[FAIL] 1x1 output[%0d] expected=%0d got=%0d",
                     out_count, expected_1x1[out_count], $signed(m_axis_tdata));
            errors++;
          end

          if ((out_count == 63) && !m_axis_tlast) begin
            $display("[FAIL] 1x1 final output missing TLAST");
            errors++;
          end

          if ((out_count != 63) && m_axis_tlast) begin
            $display("[FAIL] 1x1 early TLAST at output[%0d]", out_count);
            errors++;
          end

          out_count++;
        end
      end

      if (out_count != 64) begin
        $display("[FAIL] 1x1 timeout: got %0d / 64 outputs", out_count);
        $display("debug 1x1: input_pixels=%0d input_channels=%0d windows_seen=%0d core_outputs=%0d dma_outputs=%0d",
                 dut.input_pixels_seen, dut.input_channels_seen, dut.windows_seen,
                 dut.core_outputs_seen, dut.dma_outputs_seen);
        $display("debug 1x1: total_windows=%0d window_index=%0d kernel_mode=%0d",
                 dut.u_streaming_core.total_windows,
                 dut.u_streaming_core.window_index,
                 dut.cfg_kernel_mode);
        errors++;
      end
    end
  endtask

  task automatic init_expected();
    int idx;
    int r;
    int g;
    int b;
    begin
      expected_3x3[0]  = 2;
      expected_3x3[1]  = 2;
      expected_3x3[2]  = 3;
      expected_3x3[3]  = 7;
      expected_3x3[4]  = 3;
      expected_3x3[5]  = 2;
      expected_3x3[6]  = 4;
      expected_3x3[7]  = 9;
      expected_3x3[8]  = 2;
      expected_3x3[9]  = 3;
      expected_3x3[10] = 4;
      expected_3x3[11] = 9;
      expected_3x3[12] = 3;
      expected_3x3[13] = 3;
      expected_3x3[14] = 5;
      expected_3x3[15] = 11;

      idx = 0;
      for (int y = 0; y < 4; y++) begin
        for (int x = 0; x < 4; x++) begin
          r = pixel_r(x, y);
          g = pixel_g(x, y);
          b = pixel_b(x, y);

          expected_1x1[idx++] = r;
          expected_1x1[idx++] = g;
          expected_1x1[idx++] = b;
          expected_1x1[idx++] = r + g + b;
        end
      end
    end
  endtask

  task automatic run_case(input bit kernel_mode);
    begin
      clear_accel();

      axi_write(REG_WIDTH,  32'd4);
      axi_write(REG_HEIGHT, 32'd4);

      // bit 0 = kernel_mode, bit 1 = ReLU enable.
      axi_write(REG_MODE_FLAGS, {30'd0, 1'b1, kernel_mode});

      load_identity_weights(kernel_mode);
      load_zero_biases();

      axi_write(REG_CONTROL, 32'h1);

      // Give cnn_config_loader and streaming_cnn_core time to latch
      // width/height/kernel_mode/weights before pixels arrive.
      repeat (20) @(posedge clk);

      fork
        begin
          send_4x4_image();
        end

        begin
          if (kernel_mode) begin
            collect_outputs_3x3();
          end else begin
            collect_outputs_1x1();
          end
        end
      join

      repeat (20) @(posedge clk);
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;

    s_axi_awaddr = '0;
    s_axi_awvalid = 1'b0;
    s_axi_wdata = '0;
    s_axi_wstrb = 4'h0;
    s_axi_wvalid = 1'b0;
    s_axi_bready = 1'b0;

    s_axi_araddr = '0;
    s_axi_arvalid = 1'b0;
    s_axi_rready = 1'b0;

    s_axis_tdata = 32'd0;
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;

    m_axis_tready = 1'b1;

    errors = 0;
    tests = 0;

    init_expected();

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    $display("[TEST] DMA top 3x3 mode");
    run_case(1'b1);

    $display("[TEST] DMA top 1x1 mode");
    run_case(1'b0);

    if (errors == 0) begin
      $display("[PASS] tb_cnn_dma_system_top tests=%0d", tests);
    end else begin
      $fatal(1, "[FAIL] tb_cnn_dma_system_top errors=%0d tests=%0d",
             errors, tests);
    end

    $finish;
  end

endmodule
