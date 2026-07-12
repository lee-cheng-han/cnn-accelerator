`timescale 1ns/1ps

module tb_multi_layer_job_controller;

 localparam int PC = 4;
 localparam int PK = 8;
 localparam int MAX_CIN = 16;
 localparam int MAX_COUT = 16;
 localparam int MAX_PIXELS = 64;
 localparam int INPUT_C = 3;
 localparam int HIDDEN_C = 16;
 localparam int OUTPUT_C = 3;
 localparam int DATA_W = 8;
 localparam int ACC_W = 32;
 localparam int OUT_W = 8;

 logic clk;
 logic rst_n;
 logic start;
 logic final_residual_enable;
 logic [15:0] image_width;
 logic [15:0] image_height;
 logic signed [DATA_W-1:0] input_tensor [MAX_PIXELS*MAX_CIN];
 logic signed [DATA_W-1:0] weights_l0 [HIDDEN_C][INPUT_C][9];
 logic signed [DATA_W-1:0] weights_l1 [HIDDEN_C][HIDDEN_C][9];
 logic signed [DATA_W-1:0] weights_l2 [OUTPUT_C][HIDDEN_C][9];
 logic signed [ACC_W-1:0] bias_l0 [HIDDEN_C];
 logic signed [ACC_W-1:0] bias_l1 [HIDDEN_C];
 logic signed [ACC_W-1:0] bias_l2 [OUTPUT_C];
 logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT];
 logic [1:0] active_layer;
 logic [2:0] layer_ready;
 logic activation_read_bank;
 logic activation_write_bank;
 logic waiting_for_layer;
 logic busy;
 logic done;

 int tests;

 multi_layer_job_controller #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .MAX_PIXELS(MAX_PIXELS),
 .INPUT_C(INPUT_C),
 .HIDDEN_C(HIDDEN_C),
 .OUTPUT_C(OUTPUT_C),
 .DATA_W(DATA_W),
 .ACC_W(ACC_W),
 .BIAS_W(ACC_W),
 .OUT_W(OUT_W)
 ) dut (
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .final_residual_enable(final_residual_enable),
 .image_width(image_width),
 .image_height(image_height),
 .layer_ready(layer_ready),
 .input_tensor(input_tensor),
 .weights_l0(weights_l0),
 .weights_l1(weights_l1),
 .weights_l2(weights_l2),
 .bias_l0(bias_l0),
 .bias_l1(bias_l1),
 .bias_l2(bias_l2),
 .use_scratchpad_operands(1'b0),
 .scratch_input_write_enable(1'b0),
 .scratch_input_write_pixel('0),
 .scratch_input_write_channel('0),
 .scratch_input_write_data('0),
 .scratch_weight_write_enable(1'b0),
 .scratch_weight_write_layer('0),
 .scratch_weight_write_out_channel('0),
 .scratch_weight_write_in_channel('0),
 .scratch_weight_write_kernel_idx('0),
 .scratch_weight_write_data('0),
 .output_tensor(output_tensor),
 .output_pixel_valid(),
 .output_pixel_ready(1'b1),
 .output_pixel_index(),
 .output_pixel_channels(),
 .output_pixel_data(),
 .output_pixel_last(),
 .active_layer(active_layer),
 .activation_read_bank(activation_read_bank),
 .activation_write_bank(activation_write_bank),
 .waiting_for_layer(waiting_for_layer),
 .busy(busy),
 .done(done)
 );

 initial begin
 clk = 1'b0;
 forever #5 clk = ~clk;
 end

 function automatic logic signed [DATA_W-1:0] input_value(input int pixel, input int channel);
 begin
 case (channel)
 0: return $signed(DATA_W'(((pixel * 3) + 1) % 29));
 1: return $signed(DATA_W'(((pixel * 5) + 2) % 31));
 2: return $signed(DATA_W'(((pixel * 7) + 3) % 37));
 default: return '0;
 endcase
 end
 endfunction

 task automatic clear_inputs;
 begin
 for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
 input_tensor[i] = '0;
 end

 for (int co = 0; co < HIDDEN_C; co++) begin
 bias_l0[co] = '0;
 bias_l1[co] = '0;

 for (int ci = 0; ci < INPUT_C; ci++) begin
 for (int k = 0; k < 9; k++) begin
 weights_l0[co][ci][k] = '0;
 end
 end

 for (int ci = 0; ci < HIDDEN_C; ci++) begin
 for (int k = 0; k < 9; k++) begin
 weights_l1[co][ci][k] = '0;
 end
 end
 end

 for (int co = 0; co < OUTPUT_C; co++) begin
 bias_l2[co] = '0;

 for (int ci = 0; ci < HIDDEN_C; ci++) begin
 for (int k = 0; k < 9; k++) begin
 weights_l2[co][ci][k] = '0;
 end
 end
 end
 end
 endtask

 task automatic load_identity_denoiser;
 int pixel_count;
 begin
 pixel_count = image_width * image_height;

 for (int p = 0; p < pixel_count; p++) begin
 for (int c = 0; c < MAX_CIN; c++) begin
 input_tensor[(p * MAX_CIN) + c] = input_value(p, c);
 end
 end

 for (int co = 0; co < HIDDEN_C; co++) begin
 weights_l0[co][co % INPUT_C][4] = 8'sd1;
 weights_l1[co][co][4] = 8'sd1;
 end

 for (int co = 0; co < OUTPUT_C; co++) begin
 weights_l2[co][co][4] = 8'sd1;
 end
 end
 endtask

 task automatic run_job(input string name, input logic enable_residual);
 int timeout;
 begin
 final_residual_enable = enable_residual;
 start = 1'b1;
 @(posedge clk);
 start = 1'b0;

 timeout = 0;
 while (!done && (timeout < 200000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!done) begin
 $display("[FAIL] %s: timed out waiting for done", name);
 $finish;
 end

 if (busy) begin
 $display("[FAIL] %s: busy stayed high with done", name);
 $finish;
 end

 tests++;
 @(posedge clk);
 end
 endtask

 task automatic check_outputs(input string name, input logic expect_residual_zero);
 int pixel_count;
 logic signed [OUT_W-1:0] expected;
 begin
 pixel_count = image_width * image_height;

 for (int p = 0; p < pixel_count; p++) begin
 for (int c = 0; c < OUTPUT_C; c++) begin
 expected = expect_residual_zero ? '0 : input_tensor[(p * MAX_CIN) + c];

 if (output_tensor[(p * MAX_COUT) + c] !== expected) begin
 $display("[FAIL] %s: pixel=%0d channel=%0d expected=%0d got=%0d",
 name, p, c, expected, output_tensor[(p * MAX_COUT) + c]);
 $finish;
 end
 end

 for (int c = OUTPUT_C; c < MAX_COUT; c++) begin
 if (output_tensor[(p * MAX_COUT) + c] !== '0) begin
 $display("[FAIL] %s: pixel=%0d unused channel=%0d expected=0 got=%0d",
 name, p, c, output_tensor[(p * MAX_COUT) + c]);
 $finish;
 end
 end
 end
 end
 endtask

 task automatic run_gated_job;
 int timeout;
 begin
 final_residual_enable = 1'b0;
 layer_ready = 3'b001;
 start = 1'b1;
 @(posedge clk);
 start = 1'b0;

 timeout = 0;
 while (!(waiting_for_layer && (active_layer == 2'd1)) && (timeout < 100000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!waiting_for_layer || activation_read_bank || !activation_write_bank) begin
 $display("[FAIL] gated_prefetch: layer 1 did not wait on feature bank 0");
 $finish;
 end
 tests++;

 repeat (5) @(posedge clk);
 if (done) begin
 $display("[FAIL] gated_prefetch: job completed before layer 1 became ready");
 $finish;
 end

 layer_ready[1] = 1'b1;
 timeout = 0;
 while (!(waiting_for_layer && (active_layer == 2'd2)) && (timeout < 100000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!waiting_for_layer || !activation_read_bank || activation_write_bank) begin
 $display("[FAIL] gated_prefetch: layer 2 did not wait on feature bank 1");
 $finish;
 end
 tests++;

 layer_ready[2] = 1'b1;
 timeout = 0;
 while (!done && (timeout < 100000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!done) begin
 $display("[FAIL] gated_prefetch: timed out after releasing layer 2");
 $finish;
 end

 check_outputs("gated_prefetch", 1'b0);
 tests++;
 @(posedge clk);
 end
 endtask

 initial begin
 rst_n = 1'b0;
 start = 1'b0;
 final_residual_enable = 1'b1;
 layer_ready = 3'b111;
 image_width = 16'd4;
 image_height = 16'd3;
 tests = 0;

 clear_inputs();

 repeat (3) @(posedge clk);
 rst_n = 1'b1;
 @(posedge clk);

 load_identity_denoiser();

 run_job("three_layer_identity_with_residual_subtract", 1'b1);
 check_outputs("three_layer_identity_with_residual_subtract", 1'b1);

 run_job("three_layer_identity_without_residual_subtract", 1'b0);
 check_outputs("three_layer_identity_without_residual_subtract", 1'b0);

 run_gated_job();

 image_width = '0;
 image_height = '0;
 layer_ready = 3'b111;
 run_job("zero_sized_job", 1'b1);

 $display("[PASS] tb_multi_layer_job_controller tests=%0d", tests);
 $finish;
 end

endmodule
