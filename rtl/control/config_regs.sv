`timescale 1ns/1ps

module config_regs #(
  parameter int CFG_ADDR_WIDTH      = 16,
  parameter int CFG_DATA_WIDTH      = 32,
  parameter int NUM_INPUT_CHANNELS  = 3,
  parameter int NUM_OUTPUT_CHANNELS = 4,
  parameter int KERNEL_TAPS         = 9,
  parameter int MAX_IMG_WIDTH       = 32,
  parameter int MAX_IMG_HEIGHT      = 32
)(
  input  logic clk,
  input  logic rst_n,

  input  logic cfg_we,
  input  logic [CFG_ADDR_WIDTH-1:0] cfg_addr,
  input  logic [CFG_DATA_WIDTH-1:0] cfg_wdata,
  output logic [CFG_DATA_WIDTH-1:0] cfg_rdata,

  input  logic done_status,
  input  logic busy_status,

  output logic start_pulse,
  output logic [15:0] image_width,
  output logic [15:0] image_height,

  output logic relu_enable,
  output logic bias_enable,
  output logic quant_enable,
  output logic [4:0] quant_shift,

  output logic signed [7:0]  weights[NUM_OUTPUT_CHANNELS][NUM_INPUT_CHANNELS][KERNEL_TAPS],
  output logic signed [31:0] bias[NUM_OUTPUT_CHANNELS]
);

  localparam logic [15:0] ADDR_CONTROL = 16'h0000;
  localparam logic [15:0] ADDR_STATUS  = 16'h0004;
  localparam logic [15:0] ADDR_WIDTH   = 16'h0008;
  localparam logic [15:0] ADDR_HEIGHT  = 16'h000C;
  localparam logic [15:0] ADDR_QUANT   = 16'h0010;

  localparam logic [15:0] ADDR_WEIGHT_BASE = 16'h0100;
  localparam logic [15:0] ADDR_BIAS_BASE   = 16'h0400;

  localparam int NUM_WEIGHTS  = NUM_OUTPUT_CHANNELS * NUM_INPUT_CHANNELS * KERNEL_TAPS;
  localparam int WEIGHT_BYTES = NUM_WEIGHTS * 4;
  localparam int BIAS_BYTES   = NUM_OUTPUT_CHANNELS * 4;

  integer oc;
  integer ic;
  integer k;

  logic weight_addr_hit;
  logic bias_addr_hit;

  logic [31:0] weight_idx;
  logic [31:0] bias_idx;

  logic [$clog2(NUM_OUTPUT_CHANNELS)-1:0] weight_oc;
  logic [$clog2(NUM_INPUT_CHANNELS)-1:0]  weight_ic;
  logic [$clog2(KERNEL_TAPS)-1:0]         weight_k;
  logic [$clog2(NUM_OUTPUT_CHANNELS)-1:0] bias_dec_idx;

  always_comb begin
    weight_addr_hit = 1'b0;
    bias_addr_hit   = 1'b0;

    weight_idx   = 32'd0;
    bias_idx     = 32'd0;

    weight_oc    = '0;
    weight_ic    = '0;
    weight_k     = '0;
    bias_dec_idx = '0;

    if (
      cfg_addr >= ADDR_WEIGHT_BASE &&
      cfg_addr <  ADDR_WEIGHT_BASE + WEIGHT_BYTES[15:0]
    ) begin
      weight_addr_hit = 1'b1;
      weight_idx = ({16'd0, cfg_addr} - {16'd0, ADDR_WEIGHT_BASE}) >> 2;

      weight_oc = $clog2(NUM_OUTPUT_CHANNELS)'(
        weight_idx / (NUM_INPUT_CHANNELS * KERNEL_TAPS)
      );

      weight_ic = $clog2(NUM_INPUT_CHANNELS)'(
        (weight_idx / KERNEL_TAPS) % NUM_INPUT_CHANNELS
      );

      weight_k = $clog2(KERNEL_TAPS)'(
        weight_idx % KERNEL_TAPS
      );
    end else if (
      cfg_addr >= ADDR_BIAS_BASE &&
      cfg_addr <  ADDR_BIAS_BASE + BIAS_BYTES[15:0]
    ) begin
      bias_addr_hit = 1'b1;
      bias_idx = ({16'd0, cfg_addr} - {16'd0, ADDR_BIAS_BASE}) >> 2;

      bias_dec_idx = $clog2(NUM_OUTPUT_CHANNELS)'(bias_idx);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      image_width  <= 16'd8;
      image_height <= 16'd8;

      relu_enable  <= 1'b1;
      bias_enable  <= 1'b1;
      quant_enable <= 1'b1;
      quant_shift  <= 5'd0;

      start_pulse <= 1'b0;

      for (oc = 0; oc < NUM_OUTPUT_CHANNELS; oc++) begin
        bias[oc] <= '0;

        for (ic = 0; ic < NUM_INPUT_CHANNELS; ic++) begin
          for (k = 0; k < KERNEL_TAPS; k++) begin
            weights[oc][ic][k] <= '0;
          end
        end
      end
    end else begin
      start_pulse <= 1'b0;

      if (cfg_we) begin
        unique case (cfg_addr)
          ADDR_CONTROL: begin
            start_pulse  <= cfg_wdata[0];
            relu_enable  <= cfg_wdata[1];
            bias_enable  <= cfg_wdata[2];
            quant_enable <= cfg_wdata[3];
          end

          ADDR_WIDTH: begin
            image_width <= cfg_wdata[15:0];
          end

          ADDR_HEIGHT: begin
            image_height <= cfg_wdata[15:0];
          end

          ADDR_QUANT: begin
            quant_shift <= cfg_wdata[4:0];
          end

          default: begin
            if (weight_addr_hit) begin
              weights[weight_oc][weight_ic][weight_k] <= $signed(cfg_wdata[7:0]);
            end else if (bias_addr_hit) begin
              bias[bias_dec_idx] <= $signed(cfg_wdata);
            end
          end
        endcase
      end
    end
  end

  always_comb begin
    cfg_rdata = '0;

    unique case (cfg_addr)
      ADDR_STATUS: begin
        cfg_rdata = {30'd0, done_status, busy_status};
      end

      ADDR_WIDTH: begin
        cfg_rdata = {16'd0, image_width};
      end

      ADDR_HEIGHT: begin
        cfg_rdata = {16'd0, image_height};
      end

      ADDR_QUANT: begin
        cfg_rdata = {27'd0, quant_shift};
      end

      default: begin
        cfg_rdata = '0;
      end
    endcase
  end

endmodule
