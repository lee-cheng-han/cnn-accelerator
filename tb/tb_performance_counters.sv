`timescale 1ns/1ps

module tb_performance_counters;

 logic clk;
 logic rst_n;
 logic job_start;
 logic job_done;
 logic job_abort;
 logic clear;
 logic packet_busy;
 logic compute_active;
 logic prefetch_active;
 logic [1:0] active_layer;
 logic input_valid;
 logic input_ready;
 logic output_valid;
 logic output_ready;
 logic counting;
 logic [31:0] job_cycles;
 logic [31:0] packet_cycles;
 logic [31:0] compute_cycles;
 logic [31:0] prefetch_cycles;
 logic [31:0] layer0_cycles;
 logic [31:0] layer1_cycles;
 logic [31:0] layer2_cycles;
 logic [31:0] input_words;
 logic [31:0] input_stall_cycles;
 logic [31:0] output_words;
 logic [31:0] output_stall_cycles;

 int tests;

 performance_counters dut (
 .clk(clk),
 .rst_n(rst_n),
 .job_start(job_start),
 .job_done(job_done),
 .job_abort(job_abort),
 .clear(clear),
 .packet_busy(packet_busy),
 .compute_active(compute_active),
 .prefetch_active(prefetch_active),
 .active_layer(active_layer),
 .input_valid(input_valid),
 .input_ready(input_ready),
 .output_valid(output_valid),
 .output_ready(output_ready),
 .counting(counting),
 .job_cycles(job_cycles),
 .packet_cycles(packet_cycles),
 .compute_cycles(compute_cycles),
 .prefetch_cycles(prefetch_cycles),
 .layer0_cycles(layer0_cycles),
 .layer1_cycles(layer1_cycles),
 .layer2_cycles(layer2_cycles),
 .input_words(input_words),
 .input_stall_cycles(input_stall_cycles),
 .output_words(output_words),
 .output_stall_cycles(output_stall_cycles)
 );

 initial begin
 clk = 1'b0;
 forever #5 clk = ~clk;
 end

 task automatic drive_cycle(
 input logic next_packet_busy,
 input logic next_compute_active,
 input logic next_prefetch_active,
 input logic [1:0] next_layer,
 input logic next_input_valid,
 input logic next_input_ready,
 input logic next_output_valid,
 input logic next_output_ready,
 input logic next_done
 );
 begin
 @(negedge clk);
 packet_busy = next_packet_busy;
 compute_active = next_compute_active;
 prefetch_active = next_prefetch_active;
 active_layer = next_layer;
 input_valid = next_input_valid;
 input_ready = next_input_ready;
 output_valid = next_output_valid;
 output_ready = next_output_ready;
 job_done = next_done;
 @(posedge clk);
 end
 endtask

 task automatic expect_counter(
 input string name,
 input logic [31:0] actual,
 input logic [31:0] expected
 );
 begin
 if (actual !== expected) begin
 $display("[FAIL] %s expected=%0d got=%0d", name, expected, actual);
 $finish;
 end
 tests++;
 end
 endtask

 initial begin
 rst_n = 1'b0;
 job_start = 1'b0;
 job_done = 1'b0;
 job_abort = 1'b0;
 clear = 1'b0;
 packet_busy = 1'b0;
 compute_active = 1'b0;
 prefetch_active = 1'b0;
 active_layer = '0;
 input_valid = 1'b0;
 input_ready = 1'b0;
 output_valid = 1'b0;
 output_ready = 1'b0;
 tests = 0;

 repeat (3) @(posedge clk);
 rst_n = 1'b1;

 @(negedge clk);
 job_start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 job_start = 1'b0;

 drive_cycle(1, 0, 0, 0, 1, 1, 0, 0, 0);
 drive_cycle(1, 0, 0, 0, 1, 0, 0, 0, 0);
 drive_cycle(0, 1, 1, 0, 0, 0, 0, 0, 0);
 drive_cycle(0, 1, 0, 1, 0, 0, 1, 0, 0);
 drive_cycle(0, 1, 0, 2, 0, 0, 1, 1, 0);
 drive_cycle(0, 0, 0, 2, 0, 0, 0, 0, 1);
 #1;

 if (counting) begin
 $display("[FAIL] counters remained active after job_done");
 $finish;
 end
 tests++;

 expect_counter("job_cycles", job_cycles, 7);
 expect_counter("packet_cycles", packet_cycles, 2);
 expect_counter("compute_cycles", compute_cycles, 3);
 expect_counter("prefetch_cycles", prefetch_cycles, 1);
 expect_counter("layer0_cycles", layer0_cycles, 1);
 expect_counter("layer1_cycles", layer1_cycles, 1);
 expect_counter("layer2_cycles", layer2_cycles, 1);
 expect_counter("input_words", input_words, 1);
 expect_counter("input_stall_cycles", input_stall_cycles, 1);
 expect_counter("output_words", output_words, 1);
 expect_counter("output_stall_cycles", output_stall_cycles, 1);

 @(negedge clk);
 job_done = 1'b0;
 job_start = 1'b1;
 @(posedge clk);
 #1;
 expect_counter("new_job_clears_cycles", job_cycles, 0);

 @(negedge clk);
 job_start = 1'b0;
 clear = 1'b1;
 @(posedge clk);
 #1;
 if (counting) begin
 $display("[FAIL] clear did not stop counters");
 $finish;
 end
 tests++;

 $display("[PASS] tb_performance_counters tests=%0d", tests);
 $finish;
 end

endmodule
