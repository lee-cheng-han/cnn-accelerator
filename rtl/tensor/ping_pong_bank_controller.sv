`timescale 1ns/1ps

module ping_pong_bank_controller (
  input  logic clk,
  input  logic rst_n,

  input  logic load_start,
  input  logic load_done,
  input  logic compute_start,
  input  logic compute_done,
  input  logic clear_error,

  output logic load_ready,
  output logic compute_ready,
  output logic load_bank,
  output logic compute_bank,
  output logic [1:0] bank_valid,
  output logic load_active,
  output logic compute_active,
  output logic overlap_active,
  output logic error
);

  logic bank0_free;
  logic bank1_free;
  logic selected_load_bank;
  logic selected_compute_bank;

  assign bank0_free = !bank_valid[0] && !(compute_active && (compute_bank == 1'b0));
  assign bank1_free = !bank_valid[1] && !(compute_active && (compute_bank == 1'b1));
  assign load_ready = !load_active && (bank0_free || bank1_free);
  assign compute_ready = !compute_active && (bank_valid != 2'b00);
  assign selected_load_bank = bank0_free ? 1'b0 : 1'b1;
  assign selected_compute_bank = bank_valid[0] ? 1'b0 : 1'b1;
  assign overlap_active = load_active && compute_active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      load_bank <= 1'b0;
      compute_bank <= 1'b0;
      bank_valid <= 2'b00;
      load_active <= 1'b0;
      compute_active <= 1'b0;
      error <= 1'b0;
    end else begin
      if (clear_error) begin
        error <= 1'b0;
      end

      if (load_start) begin
        if (load_ready) begin
          load_bank <= selected_load_bank;
          load_active <= 1'b1;
        end else begin
          error <= 1'b1;
        end
      end

      if (load_done) begin
        if (load_active) begin
          bank_valid[load_bank] <= 1'b1;
          load_active <= 1'b0;
        end else begin
          error <= 1'b1;
        end
      end

      if (compute_start) begin
        if (compute_ready) begin
          compute_bank <= selected_compute_bank;
          compute_active <= 1'b1;
        end else begin
          error <= 1'b1;
        end
      end

      if (compute_done) begin
        if (compute_active) begin
          bank_valid[compute_bank] <= 1'b0;
          compute_active <= 1'b0;
        end else begin
          error <= 1'b1;
        end
      end
    end
  end

endmodule
