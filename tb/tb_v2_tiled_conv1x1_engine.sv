`timescale 1ns/1ps

module tb_v2_tiled_conv1x1_engine;

  localparam int PC       = 4;
  localparam int PK       = 8;
  localparam int MAX_CIN  = 64;
  localparam int MAX_COUT = 64;
  localparam int DATA_W   = 8;
  localparam int ACC_W    = 32;
  localparam int OUT_W    = 8;

  logic clk;
  logic rst_n;
  logic start;
  logic [7:0] cin;
  logic [7:0] cout;
  logic bias_enable;
  logic relu_enable;
  logic quant_enable;
  logic [4:0] quant_shift;

  logic signed [DATA_W-1:0] activation [MAX_CIN];
  logic signed [DATA_W-1:0] weights [MAX_COUT][MAX_CIN];
  logic signed [ACC_W-1:0] bias [MAX_COUT];
  logic signed [OUT_W-1:0] output_data [MAX_COUT];
  logic busy;
  logic done;

  int tests;

  tiled_conv1x1_engine #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .BIAS_W(ACC_W),
    .OUT_W(OUT_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
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

  function automatic logic signed [OUT_W-1:0] expected_output(input int co);
    logic signed [ACC_W-1:0] acc;
    begin
      acc = '0;

      for (int ci = 0; ci < cin; ci++) begin
        acc += $signed(activation[ci]) * $signed(weights[co][ci]);
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
      for (int ci = 0; ci < MAX_CIN; ci++) begin
        activation[ci] = '0;
      end

      for (int co = 0; co < MAX_COUT; co++) begin
        bias[co] = '0;

        for (int ci = 0; ci < MAX_CIN; ci++) begin
          weights[co][ci] = '0;
        end
      end
    end
  endtask

  task automatic run_case(input string name, input int case_cin, input int case_cout);
    logic signed [OUT_W-1:0] expected [MAX_COUT];
    int timeout;
    begin
      cin = case_cin[7:0];
      cout = case_cout[7:0];

      for (int ci = 0; ci < MAX_CIN; ci++) begin
        activation[ci] = $signed(((ci * 7) + case_cin) % 17) - 8'sd8;
      end

      for (int co = 0; co < MAX_COUT; co++) begin
        bias[co] = (co % 5) - 2;

        for (int ci = 0; ci < MAX_CIN; ci++) begin
          weights[co][ci] = $signed(((co * 3) + (ci * 5) + 1) % 9) - 8'sd4;
        end
      end

      for (int co = 0; co < case_cout; co++) begin
        expected[co] = expected_output(co);
      end

      start = 1'b1;
      @(posedge clk);
      start = 1'b0;

      timeout = 0;
      while (!done && (timeout < 1000)) begin
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

    run_case("cin3_cout3_tail_both", 3, 3);
    run_case("cin7_cout13_tail_both", 7, 13);
    run_case("cin16_cout16_aligned", 16, 16);
    run_case("cin30_cout19_tail_both", 30, 19);

    relu_enable = 1'b0;
    quant_shift = 5'd0;
    run_case("cin15_cout31_no_relu_no_shift", 15, 31);

    $display("[PASS] tb_v2_tiled_conv1x1_engine tests=%0d", tests);
    $finish;
  end

endmodule
