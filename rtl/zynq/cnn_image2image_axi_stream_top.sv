`timescale 1ns/1ps

module cnn_image2image_axi_stream_top #(
 parameter int PC = 4,
 parameter int PK = 8,
 parameter int MAX_CIN = 16,
 parameter int MAX_COUT = 16,
 parameter int MAX_PIXELS = 64,
 parameter int INPUT_C = 3,
 parameter int HIDDEN_C = 16,
 parameter int OUTPUT_C = 3,
 parameter int DATA_W = 8,
 parameter int PROD_W = 16,
 parameter int ACC_W = 32,
 parameter int BIAS_W = 32,
 parameter int OUT_W = 8,
 parameter int COUNT_W = 8,
 parameter int DIM_W = 16,
 parameter int ADDR_W = 32
)(
 input logic aclk,
 input logic aresetn,

 input logic start,
 input logic clear,
 input logic final_residual_enable,
 input logic [DIM_W-1:0] image_width,
 input logic [DIM_W-1:0] image_height,

 input logic [31:0] s_axis_tdata,
 input logic s_axis_tvalid,
 output logic s_axis_tready,
 input logic s_axis_tlast,

 output logic [31:0] m_axis_tdata,
 output logic m_axis_tvalid,
 input logic m_axis_tready,
 output logic m_axis_tlast,

 output logic busy,
 output logic done,
 output logic error,
 output logic [7:0] error_code,
 output logic [3:0] phase,
 output logic [1:0] active_layer,
 output logic [2:0] weight_layers_ready,
 output logic prefetch_active,
 output logic prefetch_seen,
 output logic [2:0] input_packet_type,
 output logic [31:0] input_packet_words,

 output logic perf_counting,
 output logic [31:0] perf_job_cycles,
 output logic [31:0] perf_packet_cycles,
 output logic [31:0] perf_compute_cycles,
 output logic [31:0] perf_prefetch_cycles,
 output logic [31:0] perf_layer0_cycles,
 output logic [31:0] perf_layer1_cycles,
 output logic [31:0] perf_layer2_cycles,
 output logic [31:0] perf_input_words,
 output logic [31:0] perf_input_stall_cycles,
 output logic [31:0] perf_output_words,
 output logic [31:0] perf_output_stall_cycles
);

 logic router_start_accepted;
 logic router_busy;
 logic packets_done;
 logic router_error;
 logic [7:0] router_error_code;
 logic activation_stream_valid;
 logic activation_stream_ready;
 logic signed [DATA_W-1:0] activation_stream_data;
 logic bias_stream_valid;
 logic bias_stream_ready;
 logic signed [BIAS_W-1:0] bias_stream_data;
 logic weight_stream_valid;
 logic weight_stream_ready;
 logic signed [DATA_W-1:0] weight_stream_data;
 logic signed [OUT_W-1:0] output_stream_data;
 logic core_busy;
 logic core_done;
 logic core_error;
 logic core_reset_n;
 logic scheduler_compute_active;

 assign core_reset_n = aresetn && !clear && !router_error;
 assign busy =
 !error && !core_done && (router_busy || packets_done || core_busy);
 assign done = core_done && !error;
 assign error = router_error || core_error;
 assign error_code = router_error ? router_error_code :
 (core_error ? 8'h80 : 8'h00);

 assign m_axis_tdata = {{(32-OUT_W){output_stream_data[OUT_W-1]}},
 output_stream_data};

 tensor_packet_router #(
 .MAX_PIXELS(MAX_PIXELS),
 .INPUT_C(INPUT_C),
 .HIDDEN_C(HIDDEN_C),
 .OUTPUT_C(OUTPUT_C),
 .DATA_W(DATA_W),
 .BIAS_W(BIAS_W),
 .DIM_W(DIM_W)
 ) u_tensor_packet_router (
 .clk(aclk),
 .rst_n(aresetn),
 .start(start),
 .clear(clear),
 .job_done(core_done),
 .image_width(image_width),
 .image_height(image_height),
 .s_axis_tdata(s_axis_tdata),
 .s_axis_tvalid(s_axis_tvalid),
 .s_axis_tready(s_axis_tready),
 .s_axis_tlast(s_axis_tlast),
 .activation_stream_valid(activation_stream_valid),
 .activation_stream_ready(activation_stream_ready),
 .activation_stream_data(activation_stream_data),
 .bias_stream_valid(bias_stream_valid),
 .bias_stream_ready(bias_stream_ready),
 .bias_stream_data(bias_stream_data),
 .weight_stream_valid(weight_stream_valid),
 .weight_stream_ready(weight_stream_ready),
 .weight_stream_data(weight_stream_data),
 .start_accepted(router_start_accepted),
 .packet_busy(router_busy),
 .packets_done(packets_done),
 .packet_type(input_packet_type),
 .words_received(input_packet_words),
 .error(router_error),
 .error_code(router_error_code)
 );

 stream_loaded_multi_layer_job_controller #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .MAX_PIXELS(MAX_PIXELS),
 .INPUT_C(INPUT_C),
 .HIDDEN_C(HIDDEN_C),
 .OUTPUT_C(OUTPUT_C),
 .DATA_W(DATA_W),
 .PROD_W(PROD_W),
 .ACC_W(ACC_W),
 .BIAS_W(BIAS_W),
 .OUT_W(OUT_W),
 .COUNT_W(COUNT_W),
 .DIM_W(DIM_W),
 .ADDR_W(ADDR_W),
 .MIRROR_LOADED_WEIGHTS(0),
 .STREAM_INTERMEDIATE_OUTPUTS(1),
 .DIRECT_STREAM_FINAL_OUTPUTS(1)
 ) u_stream_loaded_multi_layer_job_controller (
 .clk(aclk),
 .rst_n(core_reset_n),
 .start(router_start_accepted),
 .final_residual_enable(final_residual_enable),
 .image_width(image_width),
 .image_height(image_height),
 .activation_stream_valid(activation_stream_valid),
 .activation_stream_ready(activation_stream_ready),
 .activation_stream_data(activation_stream_data),
 .bias_stream_valid(bias_stream_valid),
 .bias_stream_ready(bias_stream_ready),
 .bias_stream_data(bias_stream_data),
 .weight_stream_valid(weight_stream_valid),
 .weight_stream_ready(weight_stream_ready),
 .weight_stream_data(weight_stream_data),
 .output_stream_valid(m_axis_tvalid),
 .output_stream_ready(m_axis_tready),
 .output_stream_data(output_stream_data),
 .output_stream_last(m_axis_tlast),
 .phase(phase),
 .active_layer(active_layer),
 .weight_layers_ready(weight_layers_ready),
 .prefetch_active(prefetch_active),
 .prefetch_seen(prefetch_seen),
 .compute_active(scheduler_compute_active),
 .busy(core_busy),
 .done(core_done),
 .error(core_error)
 );

 performance_counters u_performance_counters (
 .clk(aclk),
 .rst_n(aresetn),
 .job_start(router_start_accepted),
 .job_done(core_done),
 .job_abort(router_error || core_error),
 .clear(clear),
 .packet_busy(router_busy),
 .compute_active(scheduler_compute_active),
 .prefetch_active(prefetch_active),
 .active_layer(active_layer),
 .input_valid(s_axis_tvalid),
 .input_ready(s_axis_tready),
 .output_valid(m_axis_tvalid),
 .output_ready(m_axis_tready),
 .counting(perf_counting),
 .job_cycles(perf_job_cycles),
 .packet_cycles(perf_packet_cycles),
 .compute_cycles(perf_compute_cycles),
 .prefetch_cycles(perf_prefetch_cycles),
 .layer0_cycles(perf_layer0_cycles),
 .layer1_cycles(perf_layer1_cycles),
 .layer2_cycles(perf_layer2_cycles),
 .input_words(perf_input_words),
 .input_stall_cycles(perf_input_stall_cycles),
 .output_words(perf_output_words),
 .output_stall_cycles(perf_output_stall_cycles)
 );

endmodule
