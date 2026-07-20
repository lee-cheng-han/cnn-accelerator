`timescale 1ns/1ps

module tb_axi_stream_top;

 localparam int PC = 4;
 localparam int PK = 8;
 localparam int MAX_CIN = 16;
 localparam int MAX_COUT = 16;
 localparam int MAX_PIXELS = 8;
 localparam int INPUT_C = 3;
 localparam int HIDDEN_C = 16;
 localparam int OUTPUT_C = 3;
 localparam int IMAGE_W = 2;
 localparam int IMAGE_H = 2;
 localparam int PIXELS = IMAGE_W * IMAGE_H;

 logic clk;
 logic rst_n;
 logic start;
 logic clear;
 logic final_residual_enable;
 logic [15:0] image_width;
 logic [15:0] image_height;
 logic [31:0] s_axis_tdata;
 logic s_axis_tvalid;
 logic s_axis_tready;
 logic s_axis_tlast;
 logic [31:0] m_axis_tdata;
 logic m_axis_tvalid;
 logic m_axis_tready;
 logic m_axis_tlast;
 logic busy;
 logic done;
 logic error;
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

 int tests;
 int ready_cycle;

 cnn_image2image_axi_stream_top #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .MAX_PIXELS(MAX_PIXELS),
 .INPUT_C(INPUT_C),
 .HIDDEN_C(HIDDEN_C),
 .OUTPUT_C(OUTPUT_C)
 ) dut (
 .aclk(clk),
 .aresetn(rst_n),
 .start(start),
 .clear(clear),
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

 initial begin
 clk = 1'b0;
 forever #5 clk = ~clk;
 end

 always_ff @(posedge clk or negedge rst_n) begin
 if (!rst_n) begin
 ready_cycle <= 0;
 m_axis_tready <= 1'b0;
 end else begin
 ready_cycle <= ready_cycle + 1;
 m_axis_tready <= (ready_cycle % 4) != 1;
 end
 end

 function automatic logic signed [7:0] input_value(input int pixel, input int channel);
 begin
 return 8'((pixel * 7) + (channel * 2) + 1);
 end
 endfunction

 function automatic logic signed [7:0] weight_value(
 input int layer,
 input int co,
 input int ci,
 input int tap
 );
 begin
 unique case (layer)
 0: return ((co % INPUT_C) == ci && tap == 4) ? 8'sd1 : 8'sd0;
 1: return ((co == ci) && tap == 4) ? 8'sd32 : 8'sd0;
 2: return ((co == ci) && tap == 4) ? 8'sd2 : 8'sd0;
 default: return 8'sd0;
 endcase
 end
 endfunction

 task automatic pulse_start;
 begin
 @(negedge clk);
 start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 start = 1'b0;
 end
 endtask

 task automatic pulse_clear;
 begin
 @(negedge clk);
 clear = 1'b1;
 @(posedge clk);
 @(negedge clk);
 clear = 1'b0;
 @(posedge clk);
 end
 endtask

 task automatic send_beat(input logic [31:0] data, input logic last);
 logic transferred;
 begin
 @(negedge clk);
 s_axis_tdata = data;
 s_axis_tlast = last;
 s_axis_tvalid = 1'b1;
 transferred = 1'b0;

 while (!transferred) begin
 @(posedge clk);
 transferred = s_axis_tready;
 end

 @(negedge clk);
 s_axis_tvalid = 1'b0;
 s_axis_tlast = 1'b0;
 s_axis_tdata = '0;
 end
 endtask

 task automatic send_header(input int packet);
 begin
 send_beat({8'hA5, packet[7:0], 16'h0000}, 1'b0);
 end
 endtask

 task automatic send_activation_packet;
 int word;
 int pixel;
 int channel;
 begin
 send_header(0);
 for (word = 0; word < PIXELS * INPUT_C; word++) begin
 pixel = word / INPUT_C;
 channel = word % INPUT_C;
 send_beat({24'd0, input_value(pixel, channel)},
 word == (PIXELS * INPUT_C) - 1);
 end
 end
 endtask

 task automatic send_bias_packet(input int packet, input int count);
 begin
 send_header(packet);
 for (int word = 0; word < count; word++) begin
 send_beat(32'd0, word == count - 1);
 end
 end
 endtask

 task automatic send_weight_packet(
 input int packet,
 input int layer,
 input int cout,
 input int cin
 );
 int words;
 int co;
 int ci;
 int tap;
 begin
 words = cout * cin * 9;
 send_header(packet);

 for (int word = 0; word < words; word++) begin
 co = word / (cin * 9);
 ci = (word / 9) % cin;
 tap = word % 9;
 send_beat({24'd0, weight_value(layer, co, ci, tap)},
 word == words - 1);
 end
 end
 endtask

 task automatic send_identity_job;
 begin
 send_activation_packet();
 send_bias_packet(1, HIDDEN_C);
 send_weight_packet(2, 0, HIDDEN_C, INPUT_C);
 send_bias_packet(3, HIDDEN_C);
 send_weight_packet(4, 1, HIDDEN_C, HIDDEN_C);
 send_bias_packet(5, OUTPUT_C);
 send_weight_packet(6, 2, OUTPUT_C, HIDDEN_C);
 end
 endtask

 task automatic collect_and_check_output;
 int count;
 int timeout;
 int pixel;
 int channel;
 logic signed [7:0] expected;
 logic signed [31:0] expected_word;
 begin
 count = 0;
 timeout = 0;

 while ((count < PIXELS * OUTPUT_C) && (timeout < 100000)) begin
 @(negedge clk);
 timeout++;

 if (m_axis_tvalid && m_axis_tready) begin
 pixel = count / OUTPUT_C;
 channel = count % OUTPUT_C;
 expected = input_value(pixel, channel);
 expected_word = {{24{expected[7]}}, expected};

 if ($signed(m_axis_tdata) !== expected_word) begin
 $display("[FAIL] AXI output word=%0d expected=%0d got=%0d",
 count, expected, $signed(m_axis_tdata));
 $finish;
 end

 if (m_axis_tlast != (count == (PIXELS * OUTPUT_C) - 1)) begin
 $display("[FAIL] AXI output TLAST mismatch at word=%0d", count);
 $finish;
 end

 count++;
 end
 end

 if (count != PIXELS * OUTPUT_C) begin
 $display("[FAIL] AXI output timed out at word=%0d", count);
 $finish;
 end
 tests++;
 end
 endtask

 task automatic expect_error(input string name, input logic [7:0] expected_code);
 int timeout;
 begin
 timeout = 0;
 while (!error && (timeout < 100)) begin
 @(posedge clk);
 timeout++;
 end

 if (!error || (error_code != expected_code) || busy || s_axis_tready) begin
 $display("[FAIL] %s: error=%0b code=%02x busy=%0b ready=%0b",
 name, error, error_code, busy, s_axis_tready);
 $finish;
 end
 tests++;
 end
 endtask

 initial begin
 rst_n = 1'b0;
 start = 1'b0;
 clear = 1'b0;
 final_residual_enable = 1'b0;
 image_width = 16'(IMAGE_W);
 image_height = 16'(IMAGE_H);
 s_axis_tdata = '0;
 s_axis_tvalid = 1'b0;
 s_axis_tlast = 1'b0;
 tests = 0;

 repeat (4) @(posedge clk);
 rst_n = 1'b1;
 @(posedge clk);

 pulse_start();
 send_identity_job();
 collect_and_check_output();

 while (!done) begin
 @(posedge clk);
 end
 @(posedge clk);
 #1;

 if (error || busy || !prefetch_seen || (weight_layers_ready != 3'b111)) begin
 $display("[FAIL] valid AXI job status: error=%0b busy=%0b prefetch=%0b ready=%b",
 error, busy, prefetch_seen, weight_layers_ready);
 $finish;
 end
 tests++;

 if (perf_counting ||
 (perf_input_words != 32'd3222) ||
 (perf_output_words != 32'd12) ||
 (perf_job_cycles <= perf_packet_cycles) ||
 (perf_compute_cycles == 0) ||
 (perf_prefetch_cycles == 0) ||
 ((perf_layer0_cycles + perf_layer1_cycles + perf_layer2_cycles) !=
 perf_compute_cycles) ||
 (perf_output_stall_cycles == 0)) begin
 $display("[FAIL] performance counters job=%0d packet=%0d compute=%0d prefetch=%0d",
 perf_job_cycles, perf_packet_cycles, perf_compute_cycles,
 perf_prefetch_cycles);
 $display("[FAIL] layer=%0d/%0d/%0d input=%0d output=%0d output_stall=%0d counting=%0b",
 perf_layer0_cycles, perf_layer1_cycles, perf_layer2_cycles,
 perf_input_words, perf_output_words, perf_output_stall_cycles,
 perf_counting);
 $finish;
 end
 tests++;

 pulse_clear();
 pulse_start();
 send_header(1);
 expect_error("wrong_packet_order", 8'h04);

 pulse_clear();
 pulse_start();
 send_header(0);
 send_beat(32'h00000001, 1'b1);
 expect_error("early_tlast", 8'h06);

 pulse_clear();
 image_width = 16'd1;
 image_height = 16'd1;
 pulse_start();
 send_header(0);
 send_beat(32'h00000001, 1'b0);
 send_beat(32'h00000002, 1'b0);
 send_beat(32'h00000003, 1'b0);
 expect_error("missing_tlast", 8'h06);

 pulse_clear();
 image_width = 16'(MAX_PIXELS + 1);
 image_height = 16'd1;
 pulse_start();
 expect_error("invalid_dimensions", 8'h01);

 pulse_clear();
 image_width = 16'(IMAGE_W);
 image_height = 16'(IMAGE_H);
 pulse_start();
 pulse_start();
 expect_error("start_while_busy", 8'h02);

 $display("[PASS] tb_axi_stream_top tests=%0d", tests);
 $finish;
 end

endmodule
