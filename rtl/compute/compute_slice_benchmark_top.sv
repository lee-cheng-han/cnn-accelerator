`timescale 1ns/1ps

module compute_slice_benchmark_top #(
 parameter int PC = 4,
 parameter int PK = 8,
 parameter int DATA_W = 8,
 parameter int PROD_W = 16,
 parameter int ACC_W = 32,
 parameter int BIAS_W = 32,
 parameter int OUT_W = 8
)(
 input logic clk,
 input logic rst_n,

 input logic valid_in,
 input logic clear_accumulator,
 input logic bias_enable,
 input logic relu_enable,
 input logic quant_enable,
 input logic [4:0] quant_shift,
 input logic [PK-1:0] lane_mask,

 input logic [PC*DATA_W-1:0] activation_flat,
 input logic [PK*PC*DATA_W-1:0] weight_flat,
 input logic [PK*BIAS_W-1:0] bias_flat,

 output logic valid_out,
 output logic [PK*OUT_W-1:0] output_flat
);

 logic signed [DATA_W-1:0] activation [PC];
 logic signed [DATA_W-1:0] weights [PK][PC];
 logic signed [BIAS_W-1:0] bias [PK];
 logic signed [ACC_W-1:0] dot [PK];
 logic signed [ACC_W-1:0] psum [PK];
 logic signed [ACC_W-1:0] biased [PK];
 logic signed [ACC_W-1:0] relu [PK];
 logic signed [ACC_W-1:0] quantized [PK];
 logic signed [OUT_W-1:0] saturated [PK];
 logic mac_valid;

 always_comb begin
 for (int pc = 0; pc < PC; pc++) begin
 activation[pc] = activation_flat[(pc * DATA_W) +: DATA_W];
 end

 for (int pk = 0; pk < PK; pk++) begin
 bias[pk] = bias_flat[(pk * BIAS_W) +: BIAS_W];
 output_flat[(pk * OUT_W) +: OUT_W] = saturated[pk];

 for (int pc = 0; pc < PC; pc++) begin
 weights[pk][pc] =
 weight_flat[((pk * PC + pc) * DATA_W) +: DATA_W];
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
 .act_vec(activation),
 .weight_mat(weights),
 .valid_in(valid_in),
 .dot_vec(dot),
 .valid_out(mac_valid)
 );

 psum_accumulator #(
 .PK(PK),
 .ACC_W(ACC_W)
 ) u_psum_accumulator (
 .clk(clk),
 .rst_n(rst_n),
 .clear(clear_accumulator),
 .accumulate(mac_valid),
 .lane_mask(lane_mask),
 .add_vec(dot),
 .psum_vec(psum)
 );

 parallel_bias_add #(
 .PK(PK),
 .ACC_W(ACC_W),
 .BIAS_W(BIAS_W)
 ) u_parallel_bias_add (
 .psum_in(psum),
 .bias_in(bias),
 .bias_enable(bias_enable),
 .lane_mask(lane_mask),
 .acc_out(biased)
 );

 parallel_relu #(
 .PK(PK),
 .ACC_W(ACC_W)
 ) u_parallel_relu (
 .acc_in(biased),
 .relu_enable(relu_enable),
 .lane_mask(lane_mask),
 .acc_out(relu)
 );

 parallel_quantizer #(
 .PK(PK),
 .ACC_W(ACC_W)
 ) u_parallel_quantizer (
 .acc_in(relu),
 .quant_enable(quant_enable),
 .quant_shift(quant_shift),
 .lane_mask(lane_mask),
 .acc_out(quantized)
 );

 parallel_saturate #(
 .PK(PK),
 .ACC_W(ACC_W),
 .OUT_W(OUT_W)
 ) u_parallel_saturate (
 .acc_in(quantized),
 .lane_mask(lane_mask),
 .out_vec(saturated)
 );

 assign valid_out = mac_valid;

endmodule
