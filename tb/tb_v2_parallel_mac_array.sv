`timescale 1ns/1ps

module tb_v2_parallel_mac_array;

  localparam int PC     = 4;
  localparam int PK     = 8;
  localparam int DATA_W = 8;
  localparam int PROD_W = 16;
  localparam int ACC_W  = 32;

  logic clk;
  logic rst_n;

  logic signed [DATA_W-1:0] act_vec [PC];
  logic signed [DATA_W-1:0] weight_mat [PK][PC];
  logic valid_in;

  logic signed [ACC_W-1:0] dot_vec [PK];
  logic valid_out;

  int tests;

  parallel_mac_array #(
    .PC(PC),
    .PK(PK),
    .DATA_W(DATA_W),
    .PROD_W(PROD_W),
    .ACC_W(ACC_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .act_vec(act_vec),
    .weight_mat(weight_mat),
    .valid_in(valid_in),
    .dot_vec(dot_vec),
    .valid_out(valid_out)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function automatic logic signed [ACC_W-1:0] expected_dot(input int pk_idx);
    logic signed [ACC_W-1:0] acc;
    begin
      acc = '0;

      for (int pc = 0; pc < PC; pc++) begin
        acc += $signed(act_vec[pc]) * $signed(weight_mat[pk_idx][pc]);
      end

      return acc;
    end
  endfunction

  task automatic drive_case(input string name);
    logic signed [ACC_W-1:0] expected [PK];
    begin
      for (int pk = 0; pk < PK; pk++) begin
        expected[pk] = expected_dot(pk);
      end

      valid_in = 1'b1;
      @(posedge clk);
      valid_in = 1'b0;

      @(posedge clk);

      if (!valid_out) begin
        $display("[FAIL] %s: valid_out was not asserted", name);
        $finish;
      end

      for (int pk = 0; pk < PK; pk++) begin
        if (dot_vec[pk] !== expected[pk]) begin
          $display("[FAIL] %s: dot_vec[%0d] expected=%0d got=%0d",
                   name, pk, expected[pk], dot_vec[pk]);
          $finish;
        end
      end

      tests++;
      @(posedge clk);
    end
  endtask

  initial begin
    rst_n    = 1'b0;
    valid_in = 1'b0;
    tests    = 0;

    for (int pc = 0; pc < PC; pc++) begin
      act_vec[pc] = '0;
    end

    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        weight_mat[pk][pc] = '0;
      end
    end

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    act_vec[0] = 8'sd1;
    act_vec[1] = -8'sd2;
    act_vec[2] = 8'sd3;
    act_vec[3] = -8'sd4;

    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        weight_mat[pk][pc] = $signed(pk + pc + 1);
      end
    end
    drive_case("directed_mixed_sign");

    act_vec[0] = 8'sd127;
    act_vec[1] = -8'sd128;
    act_vec[2] = 8'sd64;
    act_vec[3] = -8'sd63;

    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        weight_mat[pk][pc] = (pc[0]) ? -8'sd3 : 8'sd2;
      end
    end
    drive_case("directed_int8_edges");

    for (int t = 0; t < 50; t++) begin
      for (int pc = 0; pc < PC; pc++) begin
        act_vec[pc] = $signed($urandom_range(0, 255));
      end

      for (int pk = 0; pk < PK; pk++) begin
        for (int pc = 0; pc < PC; pc++) begin
          weight_mat[pk][pc] = $signed($urandom_range(0, 255));
        end
      end

      drive_case("random");
    end

    $display("[PASS] tb_v2_parallel_mac_array tests=%0d", tests);
    $finish;
  end

endmodule
