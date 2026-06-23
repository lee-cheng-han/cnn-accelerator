`timescale 1ns/1ps

package cnn_accel_pkg;
  parameter int DATA_WIDTH = 8;
  parameter int WEIGHT_WIDTH = 8;
  parameter int ACC_WIDTH = 32;
  parameter int OUT_WIDTH = 8;
  parameter int BIAS_WIDTH = 32;

  parameter int KERNEL_SIZE = 3;
  parameter int KERNEL_TAPS = 9;
  parameter int NUM_INPUT_CHANNELS = 3;
  parameter int NUM_OUTPUT_CHANNELS = 4;

  parameter int MAX_IMG_WIDTH = 32;
  parameter int MAX_IMG_HEIGHT = 32;
  parameter int MAX_PIXELS = MAX_IMG_WIDTH * MAX_IMG_HEIGHT;

  parameter int CFG_ADDR_WIDTH = 16;
  parameter int CFG_DATA_WIDTH = 32;

  typedef logic signed [DATA_WIDTH-1:0]   data_t;
  typedef logic signed [WEIGHT_WIDTH-1:0] weight_t;
  typedef logic signed [ACC_WIDTH-1:0]    acc_t;
  typedef logic signed [OUT_WIDTH-1:0]    out_t;
  typedef logic signed [BIAS_WIDTH-1:0]   bias_t;
endpackage
