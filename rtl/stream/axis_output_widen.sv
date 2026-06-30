`timescale 1ns/1ps

module axis_output_widen (
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  // 8-bit output stream from streaming_cnn_core.
  input  logic signed [7:0] s_data,
  input  logic              s_valid,
  output logic              s_ready,
  input  logic              s_last,

  // 32-bit AXI-Stream output to DMA.
  output logic [31:0]       m_axis_tdata,
  output logic              m_axis_tvalid,
  input  logic              m_axis_tready,
  output logic              m_axis_tlast,

  output logic [31:0]       outputs_seen
);

  logic        full;
  logic [31:0] data_q;
  logic        last_q;

  assign s_ready       = !full || (m_axis_tvalid && m_axis_tready);

  assign m_axis_tdata  = data_q;
  assign m_axis_tvalid = full;
  assign m_axis_tlast  = last_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      full         <= 1'b0;
      data_q       <= 32'd0;
      last_q       <= 1'b0;
      outputs_seen <= 32'd0;
    end else if (clear) begin
      full         <= 1'b0;
      data_q       <= 32'd0;
      last_q       <= 1'b0;
      outputs_seen <= 32'd0;
    end else begin
      if (m_axis_tvalid && m_axis_tready) begin
        full <= 1'b0;
      end

      if (s_valid && s_ready) begin
        data_q       <= {{24{s_data[7]}}, s_data};
        last_q       <= s_last;
        full         <= 1'b1;
        outputs_seen <= outputs_seen + 32'd1;
      end
    end
  end

endmodule
