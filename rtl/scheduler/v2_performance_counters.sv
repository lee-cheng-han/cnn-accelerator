`timescale 1ns/1ps

module v2_performance_counters (
  input  logic clk,
  input  logic rst_n,

  input  logic job_start,
  input  logic job_done,
  input  logic job_abort,
  input  logic clear,

  input  logic packet_busy,
  input  logic compute_active,
  input  logic prefetch_active,
  input  logic [1:0] active_layer,

  input  logic input_valid,
  input  logic input_ready,
  input  logic output_valid,
  input  logic output_ready,

  output logic counting,
  output logic [31:0] job_cycles,
  output logic [31:0] packet_cycles,
  output logic [31:0] compute_cycles,
  output logic [31:0] prefetch_cycles,
  output logic [31:0] layer0_cycles,
  output logic [31:0] layer1_cycles,
  output logic [31:0] layer2_cycles,
  output logic [31:0] input_words,
  output logic [31:0] input_stall_cycles,
  output logic [31:0] output_words,
  output logic [31:0] output_stall_cycles
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      counting <= 1'b0;
      job_cycles <= '0;
      packet_cycles <= '0;
      compute_cycles <= '0;
      prefetch_cycles <= '0;
      layer0_cycles <= '0;
      layer1_cycles <= '0;
      layer2_cycles <= '0;
      input_words <= '0;
      input_stall_cycles <= '0;
      output_words <= '0;
      output_stall_cycles <= '0;
    end else if (clear) begin
      counting <= 1'b0;
      job_cycles <= '0;
      packet_cycles <= '0;
      compute_cycles <= '0;
      prefetch_cycles <= '0;
      layer0_cycles <= '0;
      layer1_cycles <= '0;
      layer2_cycles <= '0;
      input_words <= '0;
      input_stall_cycles <= '0;
      output_words <= '0;
      output_stall_cycles <= '0;
    end else if (job_start) begin
      counting <= 1'b1;
      job_cycles <= '0;
      packet_cycles <= packet_busy ? 32'd1 : 32'd0;
      compute_cycles <= '0;
      prefetch_cycles <= prefetch_active ? 32'd1 : 32'd0;
      layer0_cycles <= '0;
      layer1_cycles <= '0;
      layer2_cycles <= '0;
      input_words <= (input_valid && input_ready) ? 32'd1 : 32'd0;
      input_stall_cycles <= (input_valid && !input_ready) ? 32'd1 : 32'd0;
      output_words <= (output_valid && output_ready) ? 32'd1 : 32'd0;
      output_stall_cycles <= (output_valid && !output_ready) ? 32'd1 : 32'd0;
    end else if (counting) begin
      job_cycles <= job_cycles + 32'd1;

      if (packet_busy) begin
        packet_cycles <= packet_cycles + 32'd1;
      end

      if (compute_active) begin
        compute_cycles <= compute_cycles + 32'd1;

        unique case (active_layer)
          2'd0: layer0_cycles <= layer0_cycles + 32'd1;
          2'd1: layer1_cycles <= layer1_cycles + 32'd1;
          2'd2: layer2_cycles <= layer2_cycles + 32'd1;
          default: begin end
        endcase
      end

      if (prefetch_active) begin
        prefetch_cycles <= prefetch_cycles + 32'd1;
      end

      if (input_valid && input_ready) begin
        input_words <= input_words + 32'd1;
      end else if (input_valid && !input_ready) begin
        input_stall_cycles <= input_stall_cycles + 32'd1;
      end

      if (output_valid && output_ready) begin
        output_words <= output_words + 32'd1;
      end else if (output_valid && !output_ready) begin
        output_stall_cycles <= output_stall_cycles + 32'd1;
      end

      if (job_done || job_abort) begin
        counting <= 1'b0;
      end
    end
  end

endmodule
