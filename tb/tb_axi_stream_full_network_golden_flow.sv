`timescale 1ns/1ps

module tb_axi_stream_full_network_golden_flow;

 localparam int PC = 4;
 localparam int PK = 8;
 localparam int MAX_CIN = 16;
 localparam int MAX_COUT = 16;
 localparam int MAX_PIXELS = 64;
 localparam int INPUT_C = 3;
 localparam int HIDDEN_C = 16;
 localparam int OUTPUT_C = 3;
 localparam int DATA_W = 8;
 localparam int BIAS_W = 32;
 localparam int OUT_W = 8;
 localparam int CFG_WORDS = 5;

 localparam int CFG_INPUT_WIDTH = 0;
 localparam int CFG_INPUT_HEIGHT = 1;
 localparam int CFG_OUTPUT_WIDTH = 2;
 localparam int CFG_OUTPUT_HEIGHT = 3;

 logic clk;
 logic rst_n;
 logic start;
 logic clear;
 logic final_residual_enable;
 logic [15:0] image_width;
 logic [15:0] image_height;
 logic [15:0] output_width;
 logic [15:0] output_height;
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

 logic [31:0] cfg_mem [CFG_WORDS];
 logic signed [DATA_W-1:0] input_mem [MAX_PIXELS*MAX_CIN];
 logic signed [DATA_W-1:0] weights_l0_mem [MAX_COUT*MAX_CIN*9];
 logic signed [DATA_W-1:0] weights_l1_mem [MAX_COUT*MAX_CIN*9];
 logic signed [DATA_W-1:0] weights_l2_mem [MAX_COUT*MAX_CIN*9];
 logic signed [BIAS_W-1:0] bias_l0_mem [MAX_COUT];
 logic signed [BIAS_W-1:0] bias_l1_mem [MAX_COUT];
 logic signed [BIAS_W-1:0] bias_l2_mem [MAX_COUT];
 logic signed [OUT_W-1:0] expected_residual_mem [MAX_PIXELS*MAX_COUT];
 logic signed [OUT_W-1:0] expected_no_residual_mem [MAX_PIXELS*MAX_COUT];

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
 .OUTPUT_C(OUTPUT_C),
 .DATA_W(DATA_W),
 .BIAS_W(BIAS_W),
 .OUT_W(OUT_W)
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
 m_axis_tready <= (ready_cycle % 7) != 3;
 end
 end

 function automatic string file_in_dir(input string dir, input string name);
 begin
 return {dir, "/", name};
 end
 endfunction

 task automatic clear_arrays;
 begin
 for (int i = 0; i < CFG_WORDS; i++) begin
 cfg_mem[i] = '0;
 end

 for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
 input_mem[i] = '0;
 end

 for (int i = 0; i < MAX_COUT*MAX_CIN*9; i++) begin
 weights_l0_mem[i] = '0;
 weights_l1_mem[i] = '0;
 weights_l2_mem[i] = '0;
 end

 for (int i = 0; i < MAX_COUT; i++) begin
 bias_l0_mem[i] = '0;
 bias_l1_mem[i] = '0;
 bias_l2_mem[i] = '0;
 end

 for (int i = 0; i < MAX_PIXELS*MAX_COUT; i++) begin
 expected_residual_mem[i] = '0;
 expected_no_residual_mem[i] = '0;
 end
 end
 endtask

 task automatic clear_streams;
 begin
 s_axis_tdata = '0;
 s_axis_tvalid = 1'b0;
 s_axis_tlast = 1'b0;
 end
 endtask

 task automatic load_case(input string case_dir);
 begin
 clear_arrays();

 $readmemh(file_in_dir(case_dir, "config.mem"), cfg_mem);
 $readmemh(file_in_dir(case_dir, "input.mem"), input_mem);
 $readmemh(file_in_dir(case_dir, "weights_l0.mem"), weights_l0_mem);
 $readmemh(file_in_dir(case_dir, "weights_l1.mem"), weights_l1_mem);
 $readmemh(file_in_dir(case_dir, "weights_l2.mem"), weights_l2_mem);
 $readmemh(file_in_dir(case_dir, "bias_l0.mem"), bias_l0_mem);
 $readmemh(file_in_dir(case_dir, "bias_l1.mem"), bias_l1_mem);
 $readmemh(file_in_dir(case_dir, "bias_l2.mem"), bias_l2_mem);
 $readmemh(file_in_dir(case_dir, "expected_residual.mem"), expected_residual_mem);
 $readmemh(file_in_dir(case_dir, "expected_no_residual.mem"), expected_no_residual_mem);

 image_width = cfg_mem[CFG_INPUT_WIDTH][15:0];
 image_height = cfg_mem[CFG_INPUT_HEIGHT][15:0];
 output_width = cfg_mem[CFG_OUTPUT_WIDTH][15:0];
 output_height = cfg_mem[CFG_OUTPUT_HEIGHT][15:0];
 end
 endtask

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

 task automatic send_beat(
 input logic [31:0] data,
 input logic last,
 input int valid_skew
 );
 logic transferred;
 begin
 for (int gap = 0; gap < (valid_skew % 3); gap++) begin
 @(negedge clk);
 s_axis_tdata = '0;
 s_axis_tlast = 1'b0;
 s_axis_tvalid = 1'b0;
 end

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

 task automatic send_header(input int packet, input int valid_skew);
 begin
 send_beat({8'hA5, packet[7:0], 16'h0000}, 1'b0, valid_skew);
 end
 endtask

 task automatic send_activation_packet(input int valid_skew);
 int word_idx;
 int pixel;
 int channel;
 begin
 send_header(0, valid_skew);

 for (word_idx = 0; word_idx < (image_width * image_height * INPUT_C); word_idx++) begin
 pixel = word_idx / INPUT_C;
 channel = word_idx % INPUT_C;
 send_beat({24'd0, input_mem[(pixel * MAX_CIN) + channel]},
 word_idx == ((image_width * image_height * INPUT_C) - 1),
 valid_skew + word_idx);
 end
 end
 endtask

 task automatic send_bias_packet(
 input int packet,
 input logic signed [BIAS_W-1:0] bias_mem [MAX_COUT],
 input int count,
 input int valid_skew
 );
 begin
 send_header(packet, valid_skew);

 for (int word_idx = 0; word_idx < count; word_idx++) begin
 send_beat(bias_mem[word_idx],
 word_idx == (count - 1),
 valid_skew + word_idx);
 end
 end
 endtask

 task automatic send_weight_packet(
 input int packet,
 input logic signed [DATA_W-1:0] weights_mem [MAX_COUT*MAX_CIN*9],
 input int cout,
 input int cin,
 input int valid_skew
 );
 int co;
 int ci;
 int tap;
 int words;
 begin
 words = cout * cin * 9;
 send_header(packet, valid_skew);

 for (int word_idx = 0; word_idx < words; word_idx++) begin
 co = word_idx / (cin * 9);
 ci = (word_idx / 9) % cin;
 tap = word_idx % 9;
 send_beat({24'd0, weights_mem[((co * MAX_CIN + ci) * 9) + tap]},
 word_idx == (words - 1),
 valid_skew + word_idx);
 end
 end
 endtask

 task automatic send_job(input int valid_skew);
 begin
 send_activation_packet(valid_skew);
 send_bias_packet(1, bias_l0_mem, HIDDEN_C, valid_skew + 1);
 send_weight_packet(2, weights_l0_mem, HIDDEN_C, INPUT_C, valid_skew + 2);
 send_bias_packet(3, bias_l1_mem, HIDDEN_C, valid_skew + 3);
 send_weight_packet(4, weights_l1_mem, HIDDEN_C, HIDDEN_C, valid_skew + 4);
 send_bias_packet(5, bias_l2_mem, OUTPUT_C, valid_skew + 5);
 send_weight_packet(6, weights_l2_mem, OUTPUT_C, HIDDEN_C, valid_skew + 6);
 end
 endtask

 task automatic collect_outputs(input string name, input logic expect_residual);
 int count;
 int timeout;
 int pixel;
 int channel;
 int expected_idx;
 logic signed [OUT_W-1:0] expected;
 logic signed [31:0] expected_word;
 int last_count;
 begin
 count = 0;
 timeout = 0;
 last_count = 0;

 while ((count < (output_width * output_height * OUTPUT_C)) &&
 (timeout < 500000)) begin
 @(negedge clk);
 timeout++;

 if (m_axis_tvalid && m_axis_tready) begin
 pixel = count / OUTPUT_C;
 channel = count % OUTPUT_C;
 expected_idx = (pixel * MAX_COUT) + channel;
 expected = expect_residual ? expected_residual_mem[expected_idx] :
 expected_no_residual_mem[expected_idx];
 expected_word = {{(32-OUT_W){expected[OUT_W-1]}}, expected};

 if ($signed(m_axis_tdata) !== expected_word) begin
 $display("[FAIL] %s: output word=%0d pixel=%0d channel=%0d expected=%0d got=%0d",
 name, count, pixel, channel, expected, $signed(m_axis_tdata));
 $finish;
 end

 if (m_axis_tlast) begin
 last_count++;
 if (count != ((output_width * output_height * OUTPUT_C) - 1)) begin
 $display("[FAIL] %s: early TLAST at output word %0d", name, count);
 $finish;
 end
 end

 count++;
 end
 end

 if (count != (output_width * output_height * OUTPUT_C)) begin
 $display("[FAIL] %s: output timed out at word %0d", name, count);
 $finish;
 end

 if (last_count != 1) begin
 $display("[FAIL] %s: expected one TLAST, got %0d", name, last_count);
 $finish;
 end

 tests++;
 end
 endtask

 task automatic wait_done_and_check(input string name);
 int timeout;
 begin
 timeout = 0;
 while (!done && (timeout < 500000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!done) begin
 $display("[FAIL] %s: timed out waiting for done", name);
 $finish;
 end

 @(posedge clk);
 #1;

 if (busy || error || (error_code != 8'h00) || !prefetch_seen ||
 (weight_layers_ready != 3'b111) || (perf_output_words != 32'(output_width * output_height * OUTPUT_C))) begin
 $display("[FAIL] %s: status busy=%0b error=%0b code=%02x prefetch=%0b layers=%b output_words=%0d",
 name, busy, error, error_code, prefetch_seen,
 weight_layers_ready, perf_output_words);
 $finish;
 end

 if ((perf_input_words == 0) || (perf_compute_cycles == 0) ||
 (perf_output_stall_cycles == 0) || perf_counting) begin
 $display("[FAIL] %s: perf input=%0d compute=%0d output_stall=%0d counting=%0b",
 name, perf_input_words, perf_compute_cycles,
 perf_output_stall_cycles, perf_counting);
 $finish;
 end

 tests++;
 end
 endtask

 task automatic run_axi_golden_job(
 input string name,
 input logic enable_residual,
 input logic expect_residual,
 input int valid_skew
 );
 begin
 $display("[TEST] %s", name);

 final_residual_enable = enable_residual;
 pulse_clear();
 pulse_start();

 fork
 send_job(valid_skew);
 collect_outputs(name, expect_residual);
 join

 wait_done_and_check(name);
 tests++;
 end
 endtask

 initial begin
 rst_n = 1'b0;
 start = 1'b0;
 clear = 1'b0;
 final_residual_enable = 1'b1;
 image_width = '0;
 image_height = '0;
 output_width = '0;
 output_height = '0;
 tests = 0;
 clear_arrays();
 clear_streams();

 repeat (4) @(posedge clk);
 rst_n = 1'b1;
 @(posedge clk);

 load_case("../../build/golden/full_network_3layer");

 run_axi_golden_job("axi_stream_python_golden_full_network_3layer_residual",
 1'b1, 1'b1, 0);
 run_axi_golden_job("axi_stream_python_golden_full_network_3layer_no_residual",
 1'b0, 1'b0, 2);

 $display("[PASS] tb_axi_stream_full_network_golden_flow tests=%0d", tests);
 $finish;
 end

endmodule
