`timescale 1ns/1ps
module axis_input_if #(
  parameter int DATA_WIDTH = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic enable,
  input  logic [DATA_WIDTH-1:0] s_axis_tdata,
  input  logic s_axis_tvalid,
  output logic s_axis_tready,
  input  logic s_axis_tlast,
  output logic [DATA_WIDTH-1:0] pixel_data,
  output logic pixel_valid,
  input  logic pixel_ready,
  output logic pixel_last
);
  assign s_axis_tready = enable && pixel_ready;
  assign pixel_valid = enable && s_axis_tvalid && s_axis_tready;
  assign pixel_data = s_axis_tdata;
  assign pixel_last = s_axis_tlast && pixel_valid;
endmodule
