`timescale 1ns/1ps

module tb_v2_tiled_conv3x3_engine;

  localparam int PC         = 4;
  localparam int PK         = 8;
  localparam int MAX_CIN    = 64;
  localparam int MAX_COUT   = 64;
  localparam int MAX_PIXELS = 256;
  localparam int DATA_W     = 8;
  localparam int ACC_W      = 32;
  localparam int OUT_W      = 8;

  logic clk;
  logic rst_n;
  logic start;
  logic [15:0] input_width;
  logic [15:0] input_height;
  logic [15:0] out_x;
  logic [15:0] out_y;
  logic [1:0] stride;
  logic [1:0] padding;
  logic [7:0] cin;
  logic [7:0] cout;
  logic bias_enable;
  logic relu_enable;
  logic quant_enable;
  logic [4:0] quant_shift;

  logic signed [DATA_W-1:0] activation [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] weights [MAX_COUT][MAX_CIN][9];
  logic signed [ACC_W-1:0] bias [MAX_COUT];
  logic signed [OUT_W-1:0] output_data [MAX_COUT];
  logic busy;
  logic done;

  int tests;

  tiled_conv3x3_engine #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_PIXELS),
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .BIAS_W(ACC_W),
    .OUT_W(OUT_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .input_width(input_width),
    .input_height(input_height),
    .out_x(out_x),
    .out_y(out_y),
    .stride(stride),
    .padding(padding),
    .cin(cin),
    .cout(cout),
    .bias_enable(bias_enable),
    .relu_enable(relu_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),
    .activation(activation),
    .weights(weights),
    .bias(bias),
    .output_data(output_data),
    .busy(busy),
    .done(done)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function automatic logic signed [OUT_W-1:0] sat8(input logic signed [ACC_W-1:0] value);
    begin
      if (value > 32'sd127) begin
        return 8'sd127;
      end else if (value < -32'sd128) begin
        return -8'sd128;
      end else begin
        return value[OUT_W-1:0];
      end
    end
  endfunction

  function automatic logic signed [DATA_W-1:0] activation_at(input int y, input int x, input int ci);
    int idx;
    begin
      if ((x < 0) || (y < 0) || (x >= input_width) || (y >= input_height)) begin
        return '0;
      end

      idx = ((y * input_width) + x) * MAX_CIN + ci;
      return activation[idx];
    end
  endfunction

  function automatic logic signed [OUT_W-1:0] expected_output(input int co);
    logic signed [ACC_W-1:0] acc;
    int in_x;
    int in_y;
    int k;
    begin
      acc = '0;

      for (int ky = 0; ky < 3; ky++) begin
        for (int kx = 0; kx < 3; kx++) begin
          in_x = (out_x * stride) + kx - padding;
          in_y = (out_y * stride) + ky - padding;
          k = ky * 3 + kx;

          for (int ci = 0; ci < cin; ci++) begin
            acc += $signed(activation_at(in_y, in_x, ci)) * $signed(weights[co][ci][k]);
          end
        end
      end

      if (bias_enable) begin
        acc += bias[co];
      end

      if (relu_enable && (acc < 0)) begin
        acc = '0;
      end

      if (quant_enable) begin
        acc = acc >>> quant_shift;
      end

      return sat8(acc);
    end
  endfunction

  task automatic clear_inputs;
    begin
      for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
        activation[i] = '0;
      end

      for (int co = 0; co < MAX_COUT; co++) begin
        bias[co] = '0;

        for (int ci = 0; ci < MAX_CIN; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights[co][ci][k] = '0;
          end
        end
      end
    end
  endtask

  task automatic fill_inputs(input int case_cin, input int case_cout);
    int idx;
    begin
      for (int y = 0; y < input_height; y++) begin
        for (int x = 0; x < input_width; x++) begin
          for (int ci = 0; ci < MAX_CIN; ci++) begin
            idx = ((y * input_width) + x) * MAX_CIN + ci;
            activation[idx] = $signed(((y * 5) + (x * 3) + (ci * 7) + case_cin) % 19) - 8'sd9;
          end
        end
      end

      for (int co = 0; co < MAX_COUT; co++) begin
        bias[co] = (co % 7) - 3;

        for (int ci = 0; ci < MAX_CIN; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights[co][ci][k] = $signed(((co * 2) + (ci * 3) + k + case_cout) % 11) - 8'sd5;
          end
        end
      end
    end
  endtask

  task automatic run_case(
    input string name,
    input int width,
    input int height,
    input int case_out_x,
    input int case_out_y,
    input int case_stride,
    input int case_padding,
    input int case_cin,
    input int case_cout
  );
    logic signed [OUT_W-1:0] expected [MAX_COUT];
    int timeout;
    begin
      input_width = width[15:0];
      input_height = height[15:0];
      out_x = case_out_x[15:0];
      out_y = case_out_y[15:0];
      stride = case_stride[1:0];
      padding = case_padding[1:0];
      cin = case_cin[7:0];
      cout = case_cout[7:0];

      fill_inputs(case_cin, case_cout);

      for (int co = 0; co < case_cout; co++) begin
        expected[co] = expected_output(co);
      end

      start = 1'b1;
      @(posedge clk);
      start = 1'b0;

      timeout = 0;
      while (!done && (timeout < 5000)) begin
        @(posedge clk);
        timeout++;
      end

      if (!done) begin
        $display("[FAIL] %s: timed out waiting for done", name);
        $finish;
      end

      for (int co = 0; co < case_cout; co++) begin
        if (output_data[co] !== expected[co]) begin
          $display("[FAIL] %s: output[%0d] expected=%0d got=%0d",
                   name, co, expected[co], output_data[co]);
          $finish;
        end
      end

      tests++;
      @(posedge clk);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    start = 1'b0;
    input_width = '0;
    input_height = '0;
    out_x = '0;
    out_y = '0;
    stride = 2'd1;
    padding = 2'd1;
    cin = '0;
    cout = '0;
    bias_enable = 1'b1;
    relu_enable = 1'b1;
    quant_enable = 1'b1;
    quant_shift = 5'd1;
    tests = 0;

    clear_inputs();

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    run_case("pad1_corner_cin3_cout3", 8, 8, 0, 0, 1, 1, 3, 3);
    run_case("pad1_center_cin7_cout13", 13, 11, 4, 5, 1, 1, 7, 13);
    run_case("pad0_center_cin16_cout16", 13, 11, 3, 4, 1, 0, 16, 16);
    run_case("stride2_pad1_cin15_cout19", 8, 8, 2, 1, 2, 1, 15, 19);

    relu_enable = 1'b0;
    quant_shift = 5'd0;
    run_case("no_relu_no_shift_cin30_cout31", 13, 11, 6, 4, 1, 1, 30, 31);

    $display("[PASS] tb_v2_tiled_conv3x3_engine tests=%0d", tests);
    $finish;
  end

endmodule
