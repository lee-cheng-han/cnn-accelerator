`timescale 1ns/1ps

module axis_rgb_to_channels (
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  // AXI-Stream input from DMA.
  // One beat = one packed RGB pixel: 0x00BBGGRR.
  input  logic [31:0] s_axis_tdata,
  input  logic        s_axis_tvalid,
  output logic        s_axis_tready,
  input  logic        s_axis_tlast,

  // Channel stream output into streaming_cnn_core.
  // Emits R, then G, then B for each accepted pixel.
  output logic signed [7:0] m_pixel_data,
  output logic              m_pixel_valid,
  input  logic              m_pixel_ready,

  // Passes through the input TLAST after the B channel of the final pixel.
  output logic              m_pixel_last,

  output logic [31:0]       pixels_seen,
  output logic [31:0]       channels_seen
);

  typedef enum logic [1:0] {
    S_IDLE,
    S_SEND_R,
    S_SEND_G,
    S_SEND_B
  } state_t;

  state_t state;

  logic [31:0] pixel_q;
  logic        last_q;

  assign s_axis_tready = (state == S_IDLE);

  always_comb begin
    m_pixel_data  = 8'sd0;
    m_pixel_valid = 1'b0;
    m_pixel_last  = 1'b0;

    unique case (state)
      S_SEND_R: begin
        m_pixel_data  = pixel_q[7:0];
        m_pixel_valid = 1'b1;
      end

      S_SEND_G: begin
        m_pixel_data  = pixel_q[15:8];
        m_pixel_valid = 1'b1;
      end

      S_SEND_B: begin
        m_pixel_data  = pixel_q[23:16];
        m_pixel_valid = 1'b1;
        m_pixel_last  = last_q;
      end

      default: begin
        m_pixel_data  = 8'sd0;
        m_pixel_valid = 1'b0;
        m_pixel_last  = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= S_IDLE;
      pixel_q       <= 32'd0;
      last_q        <= 1'b0;
      pixels_seen   <= 32'd0;
      channels_seen <= 32'd0;
    end else if (clear) begin
      state         <= S_IDLE;
      pixel_q       <= 32'd0;
      last_q        <= 1'b0;
      pixels_seen   <= 32'd0;
      channels_seen <= 32'd0;
    end else begin
      unique case (state)
        S_IDLE: begin
          if (s_axis_tvalid && s_axis_tready) begin
            pixel_q     <= s_axis_tdata;
            last_q      <= s_axis_tlast;
            pixels_seen <= pixels_seen + 32'd1;
            state       <= S_SEND_R;
          end
        end

        S_SEND_R: begin
          if (m_pixel_valid && m_pixel_ready) begin
            channels_seen <= channels_seen + 32'd1;
            state         <= S_SEND_G;
          end
        end

        S_SEND_G: begin
          if (m_pixel_valid && m_pixel_ready) begin
            channels_seen <= channels_seen + 32'd1;
            state         <= S_SEND_B;
          end
        end

        S_SEND_B: begin
          if (m_pixel_valid && m_pixel_ready) begin
            channels_seen <= channels_seen + 32'd1;
            state         <= S_IDLE;
          end
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
