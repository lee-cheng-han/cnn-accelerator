`timescale 1ns/1ps

module uart_rx #(
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int BAUD_RATE   = 115200
)(
  input  logic clk,
  input  logic rst_n,

  input  logic rx,

  output logic [7:0] data_out,
  output logic       data_valid,
  output logic       framing_error
);

  localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
  localparam int CLK_CNT_W    = $clog2(CLKS_PER_BIT + 1);

  typedef enum logic [2:0] {
    S_IDLE,
    S_START,
    S_DATA,
    S_STOP
  } state_t;

  state_t state;

  logic [CLK_CNT_W-1:0] clk_count;
  logic [2:0] bit_index;
  logic [7:0] rx_shift;

  logic rx_q1;
  logic rx_q2;

  // Synchronize async UART RX input
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_q1 <= 1'b1;
      rx_q2 <= 1'b1;
    end else begin
      rx_q1 <= rx;
      rx_q2 <= rx_q1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= S_IDLE;
      clk_count     <= '0;
      bit_index     <= 3'd0;
      rx_shift      <= 8'd0;
      data_out      <= 8'd0;
      data_valid    <= 1'b0;
      framing_error <= 1'b0;
    end else begin
      data_valid    <= 1'b0;
      framing_error <= 1'b0;

      unique case (state)
        S_IDLE: begin
          clk_count <= '0;
          bit_index <= 3'd0;

          if (rx_q2 == 1'b0) begin
            state <= S_START;
          end
        end

        S_START: begin
          // Sample in the middle of the start bit
          if (clk_count == (CLKS_PER_BIT / 2) - 1) begin
            clk_count <= '0;

            if (rx_q2 == 1'b0) begin
              state <= S_DATA;
            end else begin
              state <= S_IDLE;
            end
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        S_DATA: begin
          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= '0;
            rx_shift[bit_index] <= rx_q2;

            if (bit_index == 3'd7) begin
              bit_index <= 3'd0;
              state <= S_STOP;
            end else begin
              bit_index <= bit_index + 1'b1;
            end
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        S_STOP: begin
          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= '0;

            if (rx_q2 == 1'b1) begin
              data_out   <= rx_shift;
              data_valid <= 1'b1;
            end else begin
              framing_error <= 1'b1;
            end

            state <= S_IDLE;
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
