`timescale 1ns/1ps

module uart_tx #(
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int BAUD_RATE   = 115200
)(
  input  logic clk,
  input  logic rst_n,

  input  logic [7:0] data_in,
  input  logic       data_valid,
  output logic       data_ready,

  output logic tx,
  output logic busy
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
  logic [7:0] tx_shift;

  assign data_ready = (state == S_IDLE);
  assign busy       = (state != S_IDLE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= S_IDLE;
      clk_count <= '0;
      bit_index <= 3'd0;
      tx_shift  <= 8'd0;
      tx        <= 1'b1;
    end else begin
      unique case (state)
        S_IDLE: begin
          tx        <= 1'b1;
          clk_count <= '0;
          bit_index <= 3'd0;

          if (data_valid) begin
            tx_shift <= data_in;
            state    <= S_START;
          end
        end

        S_START: begin
          tx <= 1'b0;

          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= '0;
            state <= S_DATA;
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        S_DATA: begin
          tx <= tx_shift[bit_index];

          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= '0;

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
          tx <= 1'b1;

          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= '0;
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
