`timescale 1ns/1ps

module tb_output_store_controller;

 localparam int MAX_PIXELS = 16;
 localparam int MAX_COUT = 16;
 localparam int DATA_W = 8;

 logic clk;
 logic rst_n;
 logic start;
 logic [15:0] width;
 logic [15:0] height;
 logic [7:0] channels;
 logic signed [DATA_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT];
 logic stream_valid;
 logic stream_ready;
 logic signed [DATA_W-1:0] stream_data;
 logic stream_last;
 logic [31:0] stream_pixel;
 logic [7:0] stream_channel;
 logic busy;
 logic done;
 logic error;

 int tests;

 output_tensor_store_controller #(
 .MAX_PIXELS(MAX_PIXELS),
 .MAX_COUT(MAX_COUT),
 .DATA_W(DATA_W)
 ) dut (
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .width(width),
 .height(height),
 .channels(channels),
 .output_tensor(output_tensor),
 .stream_valid(stream_valid),
 .stream_ready(stream_ready),
 .stream_data(stream_data),
 .stream_last(stream_last),
 .stream_pixel(stream_pixel),
 .stream_channel(stream_channel),
 .busy(busy),
 .done(done),
 .error(error)
 );

 initial begin
 clk = 1'b0;
 forever #5 clk = ~clk;
 end

 function automatic logic signed [DATA_W-1:0] tensor_value(input int pixel, input int channel);
 begin
 return $signed(DATA_W'((pixel * 9) + (channel * 5) - 23));
 end
 endfunction

 task automatic clear_tensor;
 begin
 for (int i = 0; i < MAX_PIXELS*MAX_COUT; i++) begin
 output_tensor[i] = '0;
 end
 end
 endtask

 task automatic fill_tensor(input int pixel_count, input int channel_count);
 begin
 clear_tensor();

 for (int p = 0; p < pixel_count; p++) begin
 for (int c = 0; c < channel_count; c++) begin
 output_tensor[(p * MAX_COUT) + c] = tensor_value(p, c);
 end
 end
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

 task automatic wait_done(input string name);
 int timeout;
 begin
 timeout = 0;
 while (!done && (timeout < 10000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!done) begin
 $display("[FAIL] %s: timed out waiting for done", name);
 $finish;
 end

 @(posedge clk);
 end
 endtask

 task automatic check_stream_word(
 input string name,
 input int expected_index,
 input int total_words
 );
 int expected_pixel;
 int expected_channel;
 logic signed [DATA_W-1:0] expected_data;
 logic expected_last;
 begin
 expected_pixel = expected_index / channels;
 expected_channel = expected_index % channels;
 expected_data = tensor_value(expected_pixel, expected_channel);
 expected_last = (expected_index == (total_words - 1));

 if (stream_data !== expected_data) begin
 $display("[FAIL] %s: word=%0d expected_data=%0d got=%0d",
 name, expected_index, expected_data, stream_data);
 $finish;
 end

 if (stream_pixel !== expected_pixel[31:0]) begin
 $display("[FAIL] %s: word=%0d expected_pixel=%0d got=%0d",
 name, expected_index, expected_pixel, stream_pixel);
 $finish;
 end

 if (stream_channel !== expected_channel[7:0]) begin
 $display("[FAIL] %s: word=%0d expected_channel=%0d got=%0d",
 name, expected_index, expected_channel, stream_channel);
 $finish;
 end

 if (stream_last !== expected_last) begin
 $display("[FAIL] %s: word=%0d expected_last=%0d got=%0d",
 name, expected_index, expected_last, stream_last);
 $finish;
 end

 tests++;
 end
 endtask

 task automatic run_stream_case;
 int received;
 int cycle_count;
 int total_words;
 begin
 width = 16'd3;
 height = 16'd2;
 channels = 8'd4;
 fill_tensor(6, 4);

 pulse_start();

 received = 0;
 cycle_count = 0;
 total_words = width * height * channels;

 while (received < total_words) begin
 @(negedge clk);
 stream_ready = (cycle_count % 4) != 1;

 if (stream_valid && stream_ready) begin
 check_stream_word("stream_with_backpressure", received, total_words);
 received++;
 end

 @(posedge clk);
 cycle_count++;
 end

 stream_ready = 1'b0;
 wait_done("stream_with_backpressure");

 if (error || busy || stream_valid) begin
 $display("[FAIL] stream_with_backpressure: bad terminal flags error=%0d busy=%0d valid=%0d",
 error, busy, stream_valid);
 $finish;
 end

 tests++;
 end
 endtask

 task automatic run_zero_length_case;
 begin
 width = 16'd0;
 height = 16'd2;
 channels = 8'd4;
 pulse_start();
 wait_done("zero_length");

 if (error || busy || stream_valid) begin
 $display("[FAIL] zero_length: expected clean done without stream");
 $finish;
 end

 tests++;
 end
 endtask

 task automatic run_invalid_config_case;
 begin
 width = 16'd1;
 height = 16'd1;
 channels = 8'd17;
 pulse_start();
 wait_done("invalid_config");

 if (!error || busy || stream_valid) begin
 $display("[FAIL] invalid_config: expected error without stream");
 $finish;
 end

 tests++;
 end
 endtask

 initial begin
 rst_n = 1'b0;
 start = 1'b0;
 width = '0;
 height = '0;
 channels = '0;
 stream_ready = 1'b0;
 tests = 0;
 clear_tensor();

 repeat (3) @(posedge clk);
 rst_n = 1'b1;
 @(posedge clk);

 run_stream_case();
 run_zero_length_case();
 run_invalid_config_case();

 $display("[PASS] tb_output_store_controller tests=%0d", tests);
 $finish;
 end

endmodule
