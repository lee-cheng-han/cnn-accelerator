`timescale 1ns/1ps

module tensor_packet_router #(
 parameter int MAX_PIXELS = 64,
 parameter int INPUT_C = 3,
 parameter int HIDDEN_C = 16,
 parameter int OUTPUT_C = 3,
 parameter int DATA_W = 8,
 parameter int BIAS_W = 32,
 parameter int DIM_W = 16
)(
 input logic clk,
 input logic rst_n,

 input logic start,
 input logic clear,
 input logic job_done,
 input logic [DIM_W-1:0] image_width,
 input logic [DIM_W-1:0] image_height,

 input logic [31:0] s_axis_tdata,
 input logic s_axis_tvalid,
 output logic s_axis_tready,
 input logic s_axis_tlast,

 output logic activation_stream_valid,
 input logic activation_stream_ready,
 output logic signed [DATA_W-1:0] activation_stream_data,

 output logic bias_stream_valid,
 input logic bias_stream_ready,
 output logic signed [BIAS_W-1:0] bias_stream_data,

 output logic weight_stream_valid,
 input logic weight_stream_ready,
 output logic signed [DATA_W-1:0] weight_stream_data,

 output logic start_accepted,
 output logic packet_busy,
 output logic packets_done,
 output logic [2:0] packet_type,
 output logic [31:0] words_received,
 output logic error,
 output logic [7:0] error_code
);

 localparam logic [7:0] HEADER_MAGIC = 8'hA5;

 localparam logic [7:0] ERR_NONE = 8'h00;
 localparam logic [7:0] ERR_CONFIG = 8'h01;
 localparam logic [7:0] ERR_START_BUSY = 8'h02;
 localparam logic [7:0] ERR_HEADER_MAGIC = 8'h03;
 localparam logic [7:0] ERR_PACKET_ORDER = 8'h04;
 localparam logic [7:0] ERR_HEADER_FORMAT = 8'h05;
 localparam logic [7:0] ERR_PACKET_LENGTH = 8'h06;

 typedef enum logic [2:0] {
 S_IDLE,
 S_CONFIG,
 S_HEADER,
 S_PAYLOAD,
 S_COMPLETE,
 S_ERROR
 } state_t;

 state_t state;
 logic [2:0] expected_type;
 logic [31:0] expected_words_q;
 logic [31:0] pixel_count_calc;
 logic [31:0] pixel_count_q;
 logic config_dims_valid_q;
 logic payload_ready;
 logic payload_transfer;
 logic expected_last;

 function automatic logic [31:0] words_for_type(
 input logic [2:0] type_id,
 input logic [31:0] pixel_count
 );
 unique case (type_id)
 3'd0: words_for_type = pixel_count * INPUT_C;
 3'd1: words_for_type = HIDDEN_C;
 3'd2: words_for_type = HIDDEN_C * INPUT_C * 9;
 3'd3: words_for_type = HIDDEN_C;
 3'd4: words_for_type = HIDDEN_C * HIDDEN_C * 9;
 3'd5: words_for_type = OUTPUT_C;
 3'd6: words_for_type = OUTPUT_C * HIDDEN_C * 9;
 default: words_for_type = '0;
 endcase
 endfunction

 assign pixel_count_calc = image_width * image_height;

 always_comb begin
 unique case (expected_type)
 3'd0: payload_ready = activation_stream_ready;
 3'd1, 3'd3, 3'd5: payload_ready = bias_stream_ready;
 3'd2, 3'd4, 3'd6: payload_ready = weight_stream_ready;
 default: payload_ready = 1'b0;
 endcase
 end

 assign s_axis_tready =
 (state == S_HEADER) ||
 ((state == S_PAYLOAD) && payload_ready);
 assign payload_transfer =
 (state == S_PAYLOAD) && s_axis_tvalid && s_axis_tready;
 assign expected_last = words_received == (expected_words_q - 32'd1);

 assign activation_stream_valid =
 (state == S_PAYLOAD) && (expected_type == 3'd0) && s_axis_tvalid;
 assign bias_stream_valid =
 (state == S_PAYLOAD) &&
 ((expected_type == 3'd1) || (expected_type == 3'd3) ||
 (expected_type == 3'd5)) &&
 s_axis_tvalid;
 assign weight_stream_valid =
 (state == S_PAYLOAD) &&
 ((expected_type == 3'd2) || (expected_type == 3'd4) ||
 (expected_type == 3'd6)) &&
 s_axis_tvalid;

 assign activation_stream_data = s_axis_tdata[DATA_W-1:0];
 assign bias_stream_data = s_axis_tdata[BIAS_W-1:0];
 assign weight_stream_data = s_axis_tdata[DATA_W-1:0];

 assign packet_busy = (state == S_HEADER) || (state == S_PAYLOAD);
 assign packets_done = (state == S_COMPLETE);
 assign packet_type = expected_type;

 always_ff @(posedge clk or negedge rst_n) begin
 if (!rst_n) begin
 state <= S_IDLE;
 expected_type <= '0;
 expected_words_q <= '0;
 pixel_count_q <= '0;
 config_dims_valid_q <= 1'b0;
 words_received <= '0;
 start_accepted <= 1'b0;
 error <= 1'b0;
 error_code <= ERR_NONE;
 end else begin
 start_accepted <= 1'b0;

 if (clear) begin
 state <= S_IDLE;
 expected_type <= '0;
 expected_words_q <= '0;
 pixel_count_q <= '0;
 config_dims_valid_q <= 1'b0;
 words_received <= '0;
 error <= 1'b0;
 error_code <= ERR_NONE;
 end else begin
 if (start && (state != S_IDLE)) begin
 state <= S_ERROR;
 error <= 1'b1;
 error_code <= ERR_START_BUSY;
 end else begin
 unique case (state)
 S_IDLE: begin
 if (start) begin
 expected_type <= 3'd0;
 pixel_count_q <= pixel_count_calc;
 config_dims_valid_q <= (image_width != '0) &&
 (image_height != '0);
 words_received <= '0;
 state <= S_CONFIG;
 end
 end

 S_CONFIG: begin
 expected_words_q <= words_for_type(3'd0, pixel_count_q);

 if (config_dims_valid_q && (pixel_count_q <= MAX_PIXELS)) begin
 start_accepted <= 1'b1;
 state <= S_HEADER;
 end else begin
 error <= 1'b1;
 error_code <= ERR_CONFIG;
 state <= S_ERROR;
 end
 end

 S_HEADER: begin
 if (s_axis_tvalid && s_axis_tready) begin
 if (s_axis_tdata[31:24] != HEADER_MAGIC) begin
 error <= 1'b1;
 error_code <= ERR_HEADER_MAGIC;
 state <= S_ERROR;
 end else if (s_axis_tdata[23:16] != {5'd0, expected_type}) begin
 error <= 1'b1;
 error_code <= ERR_PACKET_ORDER;
 state <= S_ERROR;
 end else if ((s_axis_tdata[15:0] != 16'd0) || s_axis_tlast) begin
 error <= 1'b1;
 error_code <= ERR_HEADER_FORMAT;
 state <= S_ERROR;
 end else begin
 words_received <= '0;
 state <= S_PAYLOAD;
 end
 end
 end

 S_PAYLOAD: begin
 if (payload_transfer) begin
 if (s_axis_tlast != expected_last) begin
 error <= 1'b1;
 error_code <= ERR_PACKET_LENGTH;
 state <= S_ERROR;
 end else if (expected_last) begin
 words_received <= '0;

 if (expected_type == 3'd6) begin
 state <= S_COMPLETE;
 end else begin
 expected_type <= expected_type + 3'd1;
 expected_words_q <= words_for_type(expected_type + 3'd1,
 pixel_count_q);
 state <= S_HEADER;
 end
 end else begin
 words_received <= words_received + 32'd1;
 end
 end
 end

 S_COMPLETE: begin
 if (job_done) begin
 state <= S_IDLE;
 end
 end

 S_ERROR: begin
 state <= S_ERROR;
 end

 default: begin
 state <= S_ERROR;
 error <= 1'b1;
 error_code <= ERR_HEADER_FORMAT;
 end
 endcase
 end
 end
 end
 end

endmodule
