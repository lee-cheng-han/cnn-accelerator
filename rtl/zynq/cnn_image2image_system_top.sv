`timescale 1ns/1ps

module cnn_image2image_system_top #(
 parameter int PC = 4,
 parameter int PK = 8,
 parameter int MAX_CIN = 16,
 parameter int MAX_COUT = 16,
 parameter int MAX_PIXELS = 64,
 parameter int AXI_ADDR_WIDTH = 12,
 parameter int DIM_W = 16
)(
 input logic aclk,
 input logic aresetn,

 input logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
 input logic s_axi_awvalid,
 output logic s_axi_awready,
 input logic [31:0] s_axi_wdata,
 input logic [3:0] s_axi_wstrb,
 input logic s_axi_wvalid,
 output logic s_axi_wready,
 output logic [1:0] s_axi_bresp,
 output logic s_axi_bvalid,
 input logic s_axi_bready,
 input logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
 input logic s_axi_arvalid,
 output logic s_axi_arready,
 output logic [31:0] s_axi_rdata,
 output logic [1:0] s_axi_rresp,
 output logic s_axi_rvalid,
 input logic s_axi_rready,

 input logic [31:0] s_axis_tdata,
 input logic s_axis_tvalid,
 output logic s_axis_tready,
 input logic s_axis_tlast,
 output logic [31:0] m_axis_tdata,
 output logic m_axis_tvalid,
 input logic m_axis_tready,
 output logic m_axis_tlast,

 output logic irq,
 output logic busy,
 output logic done,
 output logic error
);

 logic start_pulse;
 logic clear_pulse;
 logic final_residual_enable;
 logic [DIM_W-1:0] image_width;
 logic [DIM_W-1:0] image_height;
 logic [7:0] error_code;
 logic [3:0] phase;
 logic [1:0] active_layer;
 logic [2:0] weight_layers_ready;
 logic prefetch_active;
 logic prefetch_seen;
 logic [2:0] input_packet_type;
 logic [31:0] input_packet_words;
 logic perf_counting;
 logic [31:0] perf_job_cycles;
 logic [31:0] perf_packet_cycles;
 logic [31:0] perf_compute_cycles;
 logic [31:0] perf_prefetch_cycles;
 logic [31:0] perf_layer0_cycles;
 logic [31:0] perf_layer1_cycles;
 logic [31:0] perf_layer2_cycles;
 logic [31:0] perf_input_words;
 logic [31:0] perf_input_stall_cycles;
 logic [31:0] perf_output_words;
 logic [31:0] perf_output_stall_cycles;

 cnn_axi_lite_slave #(
 .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
 .DIM_W(DIM_W)
 ) u_cnn_axi_lite_slave (
 .s_axi_aclk(aclk),
 .s_axi_aresetn(aresetn),
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
 .start_pulse(start_pulse),
 .clear_pulse(clear_pulse),
 .final_residual_enable(final_residual_enable),
 .image_width(image_width),
 .image_height(image_height),
 .irq(irq),
 .core_busy(busy),
 .core_done(done),
 .core_error(error),
 .core_error_code(error_code),
 .phase(phase),
 .active_layer(active_layer),
 .weight_layers_ready(weight_layers_ready),
 .prefetch_active(prefetch_active),
 .prefetch_seen(prefetch_seen),
 .input_packet_type(input_packet_type),
 .input_packet_words(input_packet_words),
 .perf_counting(perf_counting),
 .perf_job_cycles(perf_job_cycles),
 .perf_packet_cycles(perf_packet_cycles),
 .perf_compute_cycles(perf_compute_cycles),
 .perf_prefetch_cycles(perf_prefetch_cycles),
 .perf_layer0_cycles(perf_layer0_cycles),
 .perf_layer1_cycles(perf_layer1_cycles),
 .perf_layer2_cycles(perf_layer2_cycles),
 .perf_input_words(perf_input_words),
 .perf_input_stall_cycles(perf_input_stall_cycles),
 .perf_output_words(perf_output_words),
 .perf_output_stall_cycles(perf_output_stall_cycles)
 );

 cnn_image2image_axi_stream_top #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .MAX_PIXELS(MAX_PIXELS),
 .DIM_W(DIM_W)
 ) u_cnn_image2image_axi_stream_top (
 .aclk(aclk),
 .aresetn(aresetn),
 .start(start_pulse),
 .clear(clear_pulse),
 .final_residual_enable(final_residual_enable),
 .image_width(image_width),
 .image_height(image_height),
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
 .error(error),
 .error_code(error_code),
 .phase(phase),
 .active_layer(active_layer),
 .weight_layers_ready(weight_layers_ready),
 .prefetch_active(prefetch_active),
 .prefetch_seen(prefetch_seen),
 .input_packet_type(input_packet_type),
 .input_packet_words(input_packet_words),
 .perf_counting(perf_counting),
 .perf_job_cycles(perf_job_cycles),
 .perf_packet_cycles(perf_packet_cycles),
 .perf_compute_cycles(perf_compute_cycles),
 .perf_prefetch_cycles(perf_prefetch_cycles),
 .perf_layer0_cycles(perf_layer0_cycles),
 .perf_layer1_cycles(perf_layer1_cycles),
 .perf_layer2_cycles(perf_layer2_cycles),
 .perf_input_words(perf_input_words),
 .perf_input_stall_cycles(perf_input_stall_cycles),
 .perf_output_words(perf_output_words),
 .perf_output_stall_cycles(perf_output_stall_cycles)
 );

endmodule
