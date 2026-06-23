`timescale 1ns/1ps

module axis_output_if #(
  parameter int DATA_WIDTH = 8
)(
  input  logic clk,
  input  logic rst_n,

  input  logic [DATA_WIDTH-1:0] data_in,
  input  logic data_valid,
  output logic data_ready,
  input  logic data_last,

  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic m_axis_tvalid,
  input  logic m_axis_tready,
  output logic m_axis_tlast
);

  /*
    Registered AXI-stream output stage.

    data_ready means:
      "This output stage can accept a new internal data beat."

    It is high when:
      1. the output register is empty, or
      2. the current output beat is being accepted by downstream.

    This prevents m_axis_tdata/m_axis_tlast from changing immediately
    when the controller increments out_count.
  */

  assign data_ready = (!m_axis_tvalid) || m_axis_tready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_tdata  <= '0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast  <= 1'b0;
    end else begin
      if (data_ready) begin
        m_axis_tvalid <= data_valid;

        if (data_valid) begin
          m_axis_tdata <= data_in;
          m_axis_tlast <= data_last;
        end else begin
          m_axis_tdata <= '0;
          m_axis_tlast <= 1'b0;
        end
      end
    end
  end

endmodule

