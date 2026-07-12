`timescale 1ns/1ps

module tb_tensor_address_gen;

 logic [15:0] input_width;
 logic [15:0] input_height;
 logic [15:0] out_x;
 logic [15:0] out_y;
 logic [1:0] kernel_x;
 logic [1:0] kernel_y;
 logic [1:0] stride;
 logic [1:0] padding;
 logic valid;
 logic [31:0] pixel_index;

 tensor_address_gen dut (
 .input_width(input_width),
 .input_height(input_height),
 .out_x(out_x),
 .out_y(out_y),
 .kernel_x(kernel_x),
 .kernel_y(kernel_y),
 .stride(stride),
 .padding(padding),
 .valid(valid),
 .pixel_index(pixel_index)
 );

 task automatic check_case(
 input string name,
 input int iw,
 input int ih,
 input int ox,
 input int oy,
 input int kx,
 input int ky,
 input int st,
 input int pad,
 input bit exp_valid,
 input int exp_index
 );
 begin
 input_width = iw[15:0];
 input_height = ih[15:0];
 out_x = ox[15:0];
 out_y = oy[15:0];
 kernel_x = kx[1:0];
 kernel_y = ky[1:0];
 stride = st[1:0];
 padding = pad[1:0];
 #1;

 if (valid !== exp_valid) begin
 $display("[FAIL] %s: valid expected=%0d got=%0d", name, exp_valid, valid);
 $finish;
 end

 if (valid && (pixel_index !== exp_index[31:0])) begin
 $display("[FAIL] %s: pixel_index expected=%0d got=%0d", name, exp_index, pixel_index);
 $finish;
 end
 end
 endtask

 initial begin
 check_case("pad1_top_left_invalid", 8, 8, 0, 0, 0, 0, 1, 1, 0, 0);
 check_case("pad1_top_left_center", 8, 8, 0, 0, 1, 1, 1, 1, 1, 0);
 check_case("pad1_inner_bottom_right_kernel", 8, 8, 2, 3, 2, 2, 1, 1, 1, 35);
 check_case("stride2_valid", 8, 8, 3, 2, 0, 1, 2, 0, 1, 46);
 check_case("stride2_right_oob", 8, 8, 4, 0, 2, 0, 2, 0, 0, 0);

 $display("[PASS] tb_tensor_address_gen");
 $finish;
 end

endmodule
