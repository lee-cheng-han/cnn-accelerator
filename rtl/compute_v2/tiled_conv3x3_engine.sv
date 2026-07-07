`timescale 1ns/1ps

module tiled_conv3x3_engine #(
  parameter int PC         = 4,
  parameter int PK         = 8,
  parameter int MAX_CIN    = 64,
  parameter int MAX_COUT   = 64,
  parameter int MAX_PIXELS = 4096,
  parameter int DATA_W     = 8,
  parameter int PROD_W     = 16,
  parameter int ACC_W      = 32,
  parameter int BIAS_W     = 32,
  parameter int OUT_W      = 8,
  parameter int COUNT_W    = 8,
  parameter int DIM_W      = 16,
  parameter int ADDR_W     = 32
)(
  input  logic clk,
  input  logic rst_n,

  input  logic start,
  input  logic [DIM_W-1:0] input_width,
  input  logic [DIM_W-1:0] input_height,
  input  logic [DIM_W-1:0] out_x,
  input  logic [DIM_W-1:0] out_y,
  input  logic [1:0] stride,
  input  logic [1:0] padding,
  input  logic [COUNT_W-1:0] cin,
  input  logic [COUNT_W-1:0] cout,

  input  logic bias_enable,
  input  logic relu_enable,
  input  logic quant_enable,
  input  logic [4:0] quant_shift,

  input  logic signed [DATA_W-1:0] activation [MAX_PIXELS*MAX_CIN],
  input  logic signed [DATA_W-1:0] weights [MAX_COUT][MAX_CIN][9],
  input  logic signed [BIAS_W-1:0] bias [MAX_COUT],

  output logic signed [OUT_W-1:0] output_data [MAX_COUT],
  output logic busy,
  output logic done
);

  typedef enum logic [2:0] {
    S_IDLE,
    S_CLEAR,
    S_ISSUE,
    S_WAIT_MAC,
    S_NEXT_C,
    S_NEXT_K,
    S_WRITE_TILE,
    S_DONE
  } state_t;

  state_t state;

  logic [COUNT_W-1:0] c_base;
  logic [COUNT_W-1:0] k_base;
  logic [3:0] kernel_idx;

  logic [1:0] kernel_x;
  logic [1:0] kernel_y;

  logic addr_valid;
  logic [ADDR_W-1:0] pixel_index;
  logic [ADDR_W-1:0] activation_base_addr;
  logic [PC-1:0] cin_lane_mask;
  logic [PK-1:0] cout_lane_mask;

  logic signed [DATA_W-1:0] mac_act_vec [PC];
  logic signed [DATA_W-1:0] mac_weight_mat [PK][PC];
  logic mac_valid_in;
  logic mac_valid_out;

  logic signed [ACC_W-1:0] dot_vec [PK];
  logic signed [ACC_W-1:0] psum_vec [PK];
  logic psum_clear;
  logic psum_accumulate;

  logic signed [BIAS_W-1:0] bias_vec [PK];
  logic signed [ACC_W-1:0] bias_acc_vec [PK];
  logic signed [ACC_W-1:0] relu_acc_vec [PK];
  logic signed [ACC_W-1:0] quant_acc_vec [PK];
  logic signed [OUT_W-1:0] post_out_vec [PK];

  always_comb begin
    kernel_y = kernel_idx / 4'd3;
    kernel_x = kernel_idx - (kernel_y * 2'd3);
  end

  tensor_address_gen #(
    .DIM_W(DIM_W),
    .ADDR_W(ADDR_W)
  ) u_tensor_address_gen (
    .input_width(input_width),
    .input_height(input_height),
    .out_x(out_x),
    .out_y(out_y),
    .kernel_x(kernel_x),
    .kernel_y(kernel_y),
    .stride(stride),
    .padding(padding),
    .valid(addr_valid),
    .pixel_index(pixel_index)
  );

  tail_mask_generator #(
    .LANES(PC),
    .COUNT_W(COUNT_W)
  ) u_cin_tail_mask (
    .base(c_base),
    .count(cin),
    .lane_mask(cin_lane_mask)
  );

  tail_mask_generator #(
    .LANES(PK),
    .COUNT_W(COUNT_W)
  ) u_cout_tail_mask (
    .base(k_base),
    .count(cout),
    .lane_mask(cout_lane_mask)
  );

  assign activation_base_addr = pixel_index * ADDR_W'(MAX_CIN);

  always_comb begin
    for (int pc = 0; pc < PC; pc++) begin
      if (addr_valid && cin_lane_mask[pc]) begin
        mac_act_vec[pc] = activation[activation_base_addr + ADDR_W'(c_base + COUNT_W'(pc))];
      end else begin
        mac_act_vec[pc] = '0;
      end
    end

    for (int pk = 0; pk < PK; pk++) begin
      if (cout_lane_mask[pk]) begin
        bias_vec[pk] = bias[k_base + COUNT_W'(pk)];
      end else begin
        bias_vec[pk] = '0;
      end

      for (int pc = 0; pc < PC; pc++) begin
        if (cout_lane_mask[pk] && cin_lane_mask[pc]) begin
          mac_weight_mat[pk][pc] =
            weights[k_base + COUNT_W'(pk)][c_base + COUNT_W'(pc)][kernel_idx];
        end else begin
          mac_weight_mat[pk][pc] = '0;
        end
      end
    end
  end

  parallel_mac_array #(
    .PC(PC),
    .PK(PK),
    .DATA_W(DATA_W),
    .PROD_W(PROD_W),
    .ACC_W(ACC_W)
  ) u_parallel_mac_array (
    .clk(clk),
    .rst_n(rst_n),
    .act_vec(mac_act_vec),
    .weight_mat(mac_weight_mat),
    .valid_in(mac_valid_in),
    .dot_vec(dot_vec),
    .valid_out(mac_valid_out)
  );

  psum_accumulator #(
    .PK(PK),
    .ACC_W(ACC_W)
  ) u_psum_accumulator (
    .clk(clk),
    .rst_n(rst_n),
    .clear(psum_clear),
    .accumulate(psum_accumulate),
    .lane_mask(cout_lane_mask),
    .add_vec(dot_vec),
    .psum_vec(psum_vec)
  );

  parallel_bias_add #(
    .PK(PK),
    .ACC_W(ACC_W),
    .BIAS_W(BIAS_W)
  ) u_parallel_bias_add (
    .psum_in(psum_vec),
    .bias_in(bias_vec),
    .bias_enable(bias_enable),
    .lane_mask(cout_lane_mask),
    .acc_out(bias_acc_vec)
  );

  parallel_relu #(
    .PK(PK),
    .ACC_W(ACC_W)
  ) u_parallel_relu (
    .acc_in(bias_acc_vec),
    .relu_enable(relu_enable),
    .lane_mask(cout_lane_mask),
    .acc_out(relu_acc_vec)
  );

  parallel_quantizer #(
    .PK(PK),
    .ACC_W(ACC_W)
  ) u_parallel_quantizer (
    .acc_in(relu_acc_vec),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),
    .lane_mask(cout_lane_mask),
    .acc_out(quant_acc_vec)
  );

  parallel_saturate #(
    .PK(PK),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) u_parallel_saturate (
    .acc_in(quant_acc_vec),
    .lane_mask(cout_lane_mask),
    .out_vec(post_out_vec)
  );

  assign mac_valid_in    = (state == S_ISSUE);
  assign psum_clear      = (state == S_CLEAR);
  assign psum_accumulate = (state == S_WAIT_MAC) && mac_valid_out;
  assign busy            = (state != S_IDLE) && (state != S_DONE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= S_IDLE;
      c_base     <= '0;
      k_base     <= '0;
      kernel_idx <= 4'd0;
      done       <= 1'b0;

      for (int co = 0; co < MAX_COUT; co++) begin
        output_data[co] <= '0;
      end
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            c_base     <= '0;
            k_base     <= '0;
            kernel_idx <= 4'd0;
            state      <= (cout == '0) ? S_DONE : S_CLEAR;
          end
        end

        S_CLEAR: begin
          c_base     <= '0;
          kernel_idx <= 4'd0;
          state      <= (cin == '0) ? S_WRITE_TILE : S_ISSUE;
        end

        S_ISSUE: begin
          state <= S_WAIT_MAC;
        end

        S_WAIT_MAC: begin
          if (mac_valid_out) begin
            state <= S_NEXT_C;
          end
        end

        S_NEXT_C: begin
          if ((c_base + COUNT_W'(PC)) < cin) begin
            c_base <= c_base + COUNT_W'(PC);
            state  <= S_ISSUE;
          end else begin
            state <= S_NEXT_K;
          end
        end

        S_NEXT_K: begin
          if (kernel_idx < 4'd8) begin
            kernel_idx <= kernel_idx + 4'd1;
            c_base     <= '0;
            state      <= S_ISSUE;
          end else begin
            state <= S_WRITE_TILE;
          end
        end

        S_WRITE_TILE: begin
          for (int pk = 0; pk < PK; pk++) begin
            if (cout_lane_mask[pk]) begin
              output_data[k_base + COUNT_W'(pk)] <= post_out_vec[pk];
            end
          end

          if ((k_base + COUNT_W'(PK)) < cout) begin
            k_base     <= k_base + COUNT_W'(PK);
            c_base     <= '0;
            kernel_idx <= 4'd0;
            state      <= S_CLEAR;
          end else begin
            state <= S_DONE;
          end
        end

        S_DONE: begin
          done  <= 1'b1;
          state <= S_IDLE;
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
