`timescale 1ns/1ps

module tb_tensor_load_controllers;

 localparam int PC = 4;
 localparam int PK = 8;
 localparam int MAX_PIXELS = 16;
 localparam int MAX_CIN = 16;
 localparam int MAX_COUT = 16;
 localparam int DATA_W = 8;

 logic clk;
 logic rst_n;

 logic act_start;
 logic [15:0] act_width;
 logic [15:0] act_height;
 logic [7:0] act_channels;
 logic act_stream_valid;
 logic act_stream_ready;
 logic signed [DATA_W-1:0] act_stream_data;
 logic act_write_enable;
 logic [31:0] act_write_pixel;
 logic [7:0] act_write_channel;
 logic signed [DATA_W-1:0] act_write_data;
 logic act_busy;
 logic act_done;
 logic act_error;
 logic [31:0] act_debug_pixel;
 logic [7:0] act_debug_channel;
 logic signed [DATA_W-1:0] act_debug_data;
 logic signed [DATA_W-1:0] act_lane_data [PC];

 logic weight_start;
 logic [7:0] weight_cout;
 logic [7:0] weight_cin;
 logic [1:0] weight_kernel_size;
 logic weight_stream_valid;
 logic weight_stream_ready;
 logic signed [DATA_W-1:0] weight_stream_data;
 logic weight_write_enable;
 logic [7:0] weight_write_oc;
 logic [7:0] weight_write_ic;
 logic [3:0] weight_write_k;
 logic signed [DATA_W-1:0] weight_write_data;
 logic weight_busy;
 logic weight_done;
 logic weight_error;
 logic [7:0] weight_debug_oc;
 logic [7:0] weight_debug_ic;
 logic [3:0] weight_debug_k;
 logic signed [DATA_W-1:0] weight_debug_data;
 logic signed [DATA_W-1:0] weight_mat [PK][PC];

 int tests;

 activation_tensor_load_controller #(
 .MAX_PIXELS(MAX_PIXELS),
 .MAX_C(MAX_CIN),
 .DATA_W(DATA_W)
 ) u_activation_tensor_load_controller (
 .clk(clk),
 .rst_n(rst_n),
 .start(act_start),
 .width(act_width),
 .height(act_height),
 .channels(act_channels),
 .stream_valid(act_stream_valid),
 .stream_ready(act_stream_ready),
 .stream_data(act_stream_data),
 .write_enable(act_write_enable),
 .write_pixel(act_write_pixel),
 .write_channel(act_write_channel),
 .write_data(act_write_data),
 .busy(act_busy),
 .done(act_done),
 .error(act_error)
 );

 activation_scratchpad #(
 .PC(PC),
 .MAX_PIXELS(MAX_PIXELS),
 .MAX_C(MAX_CIN),
 .DATA_W(DATA_W)
 ) u_activation_scratchpad (
 .clk(clk),
 .write_enable(act_write_enable),
 .write_pixel(act_write_pixel),
 .write_channel(act_write_channel),
 .write_data(act_write_data),
 .read_pixel('0),
 .read_c_base('0),
 .lane_mask('0),
 .lane_data(act_lane_data),
 .debug_read_pixel(act_debug_pixel),
 .debug_read_channel(act_debug_channel),
 .debug_read_data(act_debug_data)
 );

 weight_tensor_load_controller #(
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .DATA_W(DATA_W)
 ) u_weight_tensor_load_controller (
 .clk(clk),
 .rst_n(rst_n),
 .start(weight_start),
 .cout(weight_cout),
 .cin(weight_cin),
 .kernel_size(weight_kernel_size),
 .stream_valid(weight_stream_valid),
 .stream_ready(weight_stream_ready),
 .stream_data(weight_stream_data),
 .write_enable(weight_write_enable),
 .write_out_channel(weight_write_oc),
 .write_in_channel(weight_write_ic),
 .write_kernel_idx(weight_write_k),
 .write_data(weight_write_data),
 .busy(weight_busy),
 .done(weight_done),
 .error(weight_error)
 );

 weight_scratchpad #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .DATA_W(DATA_W)
 ) u_weight_scratchpad (
 .clk(clk),
 .write_enable(weight_write_enable),
 .write_out_channel(weight_write_oc),
 .write_in_channel(weight_write_ic),
 .write_kernel_idx(weight_write_k),
 .write_data(weight_write_data),
 .read_k_base('0),
 .read_c_base('0),
 .read_kernel_idx('0),
 .out_lane_mask('0),
 .in_lane_mask('0),
 .weight_mat(weight_mat),
 .debug_out_channel(weight_debug_oc),
 .debug_in_channel(weight_debug_ic),
 .debug_kernel_idx(weight_debug_k),
 .debug_read_data(weight_debug_data)
 );

 initial begin
 clk = 1'b0;
 forever #5 clk = ~clk;
 end

 function automatic logic signed [DATA_W-1:0] activation_value(input int pixel, input int channel);
 begin
 return $signed(DATA_W'((pixel * 7) + (channel * 3) - 11));
 end
 endfunction

 function automatic logic signed [DATA_W-1:0] weight_value(input int co, input int ci, input int k);
 begin
 return $signed(DATA_W'((co * 13) + (ci * 5) + k - 37));
 end
 endfunction

 task automatic pulse_start_activation;
 begin
 @(negedge clk);
 act_start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 act_start = 1'b0;
 end
 endtask

 task automatic pulse_start_weight;
 begin
 @(negedge clk);
 weight_start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 weight_start = 1'b0;
 end
 endtask

 task automatic send_activation(input logic signed [DATA_W-1:0] value, input int idle_cycles);
 begin
 repeat (idle_cycles) begin
 @(negedge clk);
 act_stream_valid = 1'b0;
 end

 while (!act_stream_ready) begin
 @(negedge clk);
 end

 act_stream_data = value;
 act_stream_valid = 1'b1;
 @(posedge clk);
 @(negedge clk);
 act_stream_valid = 1'b0;
 end
 endtask

 task automatic send_weight(input logic signed [DATA_W-1:0] value, input int idle_cycles);
 begin
 repeat (idle_cycles) begin
 @(negedge clk);
 weight_stream_valid = 1'b0;
 end

 while (!weight_stream_ready) begin
 @(negedge clk);
 end

 weight_stream_data = value;
 weight_stream_valid = 1'b1;
 @(posedge clk);
 @(negedge clk);
 weight_stream_valid = 1'b0;
 end
 endtask

 task automatic wait_activation_done(input string name);
 int timeout;
 begin
 timeout = 0;
 while (!act_done && (timeout < 10000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!act_done) begin
 $display("[FAIL] %s: activation loader timed out", name);
 $finish;
 end

 @(posedge clk);
 end
 endtask

 task automatic wait_weight_done(input string name);
 int timeout;
 begin
 timeout = 0;
 while (!weight_done && (timeout < 10000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!weight_done) begin
 $display("[FAIL] %s: weight loader timed out", name);
 $finish;
 end

 @(posedge clk);
 end
 endtask

 task automatic expect_activation(input int pixel, input int channel, input logic signed [DATA_W-1:0] expected);
 begin
 act_debug_pixel = pixel[31:0];
 act_debug_channel = channel[7:0];
 #1;

 if (act_debug_data !== expected) begin
 $display("[FAIL] activation pixel=%0d channel=%0d expected=%0d got=%0d",
 pixel, channel, expected, act_debug_data);
 $finish;
 end

 tests++;
 end
 endtask

 task automatic expect_weight(
 input int co,
 input int ci,
 input int k,
 input logic signed [DATA_W-1:0] expected
 );
 begin
 weight_debug_oc = co[7:0];
 weight_debug_ic = ci[7:0];
 weight_debug_k = k[3:0];
 #1;

 if (weight_debug_data !== expected) begin
 $display("[FAIL] weight co=%0d ci=%0d k=%0d expected=%0d got=%0d",
 co, ci, k, expected, weight_debug_data);
 $finish;
 end

 tests++;
 end
 endtask

 task automatic run_activation_load_case;
 begin
 act_width = 16'd2;
 act_height = 16'd2;
 act_channels = 8'd3;
 pulse_start_activation();

 for (int p = 0; p < 4; p++) begin
 for (int c = 0; c < 3; c++) begin
 send_activation(activation_value(p, c), (p + c) % 2);
 end
 end

 wait_activation_done("activation_load");

 if (act_error) begin
 $display("[FAIL] activation_load: unexpected error");
 $finish;
 end

 expect_activation(0, 0, activation_value(0, 0));
 expect_activation(1, 2, activation_value(1, 2));
 expect_activation(3, 1, activation_value(3, 1));
 end
 endtask

 task automatic run_rectangular_activation_load_case;
 begin
 act_width = 16'd3;
 act_height = 16'd2;
 act_channels = 8'd2;
 pulse_start_activation();

 for (int p = 0; p < 6; p++) begin
 for (int c = 0; c < 2; c++) begin
 send_activation(activation_value(p, c), (p + c) % 2);
 end
 end

 wait_activation_done("rectangular_activation_load");

 if (act_error) begin
 $display("[FAIL] rectangular_activation_load: unexpected error");
 $finish;
 end

 expect_activation(0, 0, activation_value(0, 0));
 expect_activation(2, 1, activation_value(2, 1));
 expect_activation(5, 1, activation_value(5, 1));
 end
 endtask

 task automatic run_weight_load_case;
 begin
 weight_cout = 8'd3;
 weight_cin = 8'd2;
 weight_kernel_size = 2'd3;
 pulse_start_weight();

 for (int co = 0; co < 3; co++) begin
 for (int ci = 0; ci < 2; ci++) begin
 for (int k = 0; k < 9; k++) begin
 send_weight(weight_value(co, ci, k), (co + ci + k) % 3);
 end
 end
 end

 wait_weight_done("weight_load");

 if (weight_error) begin
 $display("[FAIL] weight_load: unexpected error");
 $finish;
 end

 expect_weight(0, 0, 0, weight_value(0, 0, 0));
 expect_weight(1, 1, 8, weight_value(1, 1, 8));
 expect_weight(2, 0, 4, weight_value(2, 0, 4));
 end
 endtask

 task automatic run_invalid_config_cases;
 begin
 act_width = 16'd1;
 act_height = 16'd1;
 act_channels = 8'd17;
 pulse_start_activation();
 wait_activation_done("activation_invalid_config");

 if (!act_error || act_busy || act_stream_ready) begin
 $display("[FAIL] activation_invalid_config: expected error without load");
 $finish;
 end

 tests++;

 weight_cout = 8'd1;
 weight_cin = 8'd1;
 weight_kernel_size = 2'd2;
 pulse_start_weight();
 wait_weight_done("weight_invalid_config");

 if (!weight_error || weight_busy || weight_stream_ready) begin
 $display("[FAIL] weight_invalid_config: expected error without load");
 $finish;
 end

 tests++;
 end
 endtask

 initial begin
 rst_n = 1'b0;
 act_start = 1'b0;
 act_width = '0;
 act_height = '0;
 act_channels = '0;
 act_stream_valid = 1'b0;
 act_stream_data = '0;
 act_debug_pixel = '0;
 act_debug_channel = '0;

 weight_start = 1'b0;
 weight_cout = '0;
 weight_cin = '0;
 weight_kernel_size = '0;
 weight_stream_valid = 1'b0;
 weight_stream_data = '0;
 weight_debug_oc = '0;
 weight_debug_ic = '0;
 weight_debug_k = '0;
 tests = 0;

 repeat (3) @(posedge clk);
 rst_n = 1'b1;
 @(posedge clk);

 run_activation_load_case();
 run_rectangular_activation_load_case();
 run_weight_load_case();
 run_invalid_config_cases();

 $display("[PASS] tb_tensor_load_controllers tests=%0d", tests);
 $finish;
 end

endmodule
