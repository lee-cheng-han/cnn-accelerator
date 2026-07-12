`timescale 1ns/1ps

module tb_layer_descriptors;

 logic [1:0] layer_index;
 logic [15:0] image_width;
 logic [15:0] image_height;
 logic valid;
 logic [31:0] input_base;
 logic [31:0] output_base;
 logic [31:0] weight_base;
 logic [31:0] bias_base;
 logic [15:0] input_width;
 logic [15:0] input_height;
 logic [7:0] input_channels;
 logic [7:0] output_channels;
 logic [1:0] kernel_size;
 logic [1:0] stride;
 logic [1:0] padding;
 logic bias_enable;
 logic relu_enable;
 logic quant_enable;
 logic [4:0] quant_shift;
 logic residual_enable;
 logic [31:0] residual_input_base;

 int tests;

 denoise_layer_descriptor_rom dut (
 .layer_index(layer_index),
 .image_width(image_width),
 .image_height(image_height),
 .valid(valid),
 .input_base(input_base),
 .output_base(output_base),
 .weight_base(weight_base),
 .bias_base(bias_base),
 .input_width(input_width),
 .input_height(input_height),
 .input_channels(input_channels),
 .output_channels(output_channels),
 .kernel_size(kernel_size),
 .stride(stride),
 .padding(padding),
 .bias_enable(bias_enable),
 .relu_enable(relu_enable),
 .quant_enable(quant_enable),
 .quant_shift(quant_shift),
 .residual_enable(residual_enable),
 .residual_input_base(residual_input_base)
 );

 task automatic check_layer(
 input int idx,
 input int exp_cin,
 input int exp_cout,
 input bit exp_relu,
 input bit exp_residual
 );
 begin
 layer_index = idx[1:0];
 #1;

 if (!valid) begin
 $display("[FAIL] layer %0d unexpectedly invalid", idx);
 $finish;
 end

 if ((input_width !== image_width) ||
 (input_height !== image_height) ||
 (kernel_size !== 2'd3) ||
 (stride !== 2'd1) ||
 (padding !== 2'd1) ||
 (input_channels !== exp_cin[7:0]) ||
 (output_channels !== exp_cout[7:0]) ||
 (bias_enable !== 1'b1) ||
 (relu_enable !== exp_relu) ||
 (quant_enable !== 1'b1) ||
 (residual_enable !== exp_residual)) begin
 $display("[FAIL] layer %0d descriptor mismatch", idx);
 $finish;
 end

 tests++;
 end
 endtask

 initial begin
 image_width = 16'd63;
 image_height = 16'd47;
 layer_index = '0;
 tests = 0;

 check_layer(0, 3, 16, 1, 0);
 check_layer(1, 16, 16, 1, 0);
 check_layer(2, 16, 3, 0, 1);

 layer_index = 2'd3;
 #1;
 if (valid) begin
 $display("[FAIL] layer 3 should be invalid");
 $finish;
 end
 tests++;

 $display("[PASS] tb_layer_descriptors tests=%0d", tests);
 $finish;
 end

endmodule
