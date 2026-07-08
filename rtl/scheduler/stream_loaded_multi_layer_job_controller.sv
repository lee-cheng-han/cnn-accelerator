`timescale 1ns/1ps

module stream_loaded_multi_layer_job_controller #(
  parameter int PC          = 4,
  parameter int PK          = 8,
  parameter int MAX_CIN     = 16,
  parameter int MAX_COUT    = 16,
  parameter int MAX_PIXELS  = 64,
  parameter int INPUT_C     = 3,
  parameter int HIDDEN_C    = 16,
  parameter int OUTPUT_C    = 3,
  parameter int DATA_W      = 8,
  parameter int PROD_W      = 16,
  parameter int ACC_W       = 32,
  parameter int BIAS_W      = 32,
  parameter int OUT_W       = 8,
  parameter int COUNT_W     = 8,
  parameter int DIM_W       = 16,
  parameter int ADDR_W      = 32
)(
  input  logic clk,
  input  logic rst_n,

  input  logic start,
  input  logic final_residual_enable,
  input  logic [DIM_W-1:0] image_width,
  input  logic [DIM_W-1:0] image_height,

  input  logic activation_stream_valid,
  output logic activation_stream_ready,
  input  logic signed [DATA_W-1:0] activation_stream_data,

  input  logic bias_stream_valid,
  output logic bias_stream_ready,
  input  logic signed [BIAS_W-1:0] bias_stream_data,

  input  logic weight_stream_valid,
  output logic weight_stream_ready,
  input  logic signed [DATA_W-1:0] weight_stream_data,

  output logic output_stream_valid,
  input  logic output_stream_ready,
  output logic signed [OUT_W-1:0] output_stream_data,
  output logic output_stream_last,

  output logic [3:0] phase,
  output logic [1:0] active_layer,
  output logic busy,
  output logic done,
  output logic error
);

  typedef enum logic [3:0] {
    S_IDLE,
    S_START_ACT,
    S_LOAD_ACT,
    S_START_BIAS,
    S_LOAD_BIAS,
    S_START_WEIGHT,
    S_LOAD_WEIGHT,
    S_START_COMPUTE,
    S_WAIT_COMPUTE,
    S_START_STORE,
    S_STORE_OUTPUT,
    S_DONE
  } state_t;

  state_t state;
  logic [1:0] load_layer;
  logic act_loader_start;
  logic act_loader_done;
  logic act_loader_error;
  logic act_write_enable;
  logic [ADDR_W-1:0] act_write_pixel;
  logic [COUNT_W-1:0] act_write_channel;
  logic signed [DATA_W-1:0] act_write_data;
  logic weight_loader_start;
  logic weight_loader_done;
  logic weight_loader_error;
  logic weight_write_enable;
  logic [COUNT_W-1:0] weight_write_out_channel;
  logic [COUNT_W-1:0] weight_write_in_channel;
  logic [3:0] weight_write_kernel_idx;
  logic signed [DATA_W-1:0] weight_write_data;
  logic compute_start;
  logic compute_done;
  logic store_start;
  logic store_done;
  logic store_error;
  logic signed [DATA_W-1:0] input_tensor [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] weights_l0 [HIDDEN_C][INPUT_C][9];
  logic signed [DATA_W-1:0] weights_l1 [HIDDEN_C][HIDDEN_C][9];
  logic signed [DATA_W-1:0] weights_l2 [OUTPUT_C][HIDDEN_C][9];
  logic signed [BIAS_W-1:0] bias_l0 [HIDDEN_C];
  logic signed [BIAS_W-1:0] bias_l1 [HIDDEN_C];
  logic signed [BIAS_W-1:0] bias_l2 [OUTPUT_C];
  logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT];
  logic [COUNT_W-1:0] bias_index;
  logic [COUNT_W-1:0] bias_count;
  logic bias_transfer;
  logic last_bias;
  logic loaded_error;

  assign phase = state;
  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign act_loader_start = (state == S_START_ACT);
  assign weight_loader_start = (state == S_START_WEIGHT);
  assign compute_start = (state == S_START_COMPUTE);
  assign store_start = (state == S_START_STORE);
  assign bias_stream_ready = (state == S_LOAD_BIAS);
  assign bias_transfer = bias_stream_valid && bias_stream_ready;
  assign last_bias = bias_index == (bias_count - COUNT_W'(1));

  always_comb begin
    unique case (load_layer)
      2'd0: bias_count = COUNT_W'(HIDDEN_C);
      2'd1: bias_count = COUNT_W'(HIDDEN_C);
      2'd2: bias_count = COUNT_W'(OUTPUT_C);
      default: bias_count = '0;
    endcase
  end

  activation_tensor_load_controller #(
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_activation_tensor_load_controller (
    .clk(clk),
    .rst_n(rst_n),
    .start(act_loader_start),
    .width(image_width),
    .height(image_height),
    .channels(COUNT_W'(INPUT_C)),
    .stream_valid(activation_stream_valid),
    .stream_ready(activation_stream_ready),
    .stream_data(activation_stream_data),
    .write_enable(act_write_enable),
    .write_pixel(act_write_pixel),
    .write_channel(act_write_channel),
    .write_data(act_write_data),
    .busy(),
    .done(act_loader_done),
    .error(act_loader_error)
  );

  weight_tensor_load_controller #(
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W)
  ) u_weight_tensor_load_controller (
    .clk(clk),
    .rst_n(rst_n),
    .start(weight_loader_start),
    .cout((load_layer == 2'd2) ? COUNT_W'(OUTPUT_C) : COUNT_W'(HIDDEN_C)),
    .cin((load_layer == 2'd0) ? COUNT_W'(INPUT_C) : COUNT_W'(HIDDEN_C)),
    .kernel_size(2'd3),
    .stream_valid(weight_stream_valid),
    .stream_ready(weight_stream_ready),
    .stream_data(weight_stream_data),
    .write_enable(weight_write_enable),
    .write_out_channel(weight_write_out_channel),
    .write_in_channel(weight_write_in_channel),
    .write_kernel_idx(weight_write_kernel_idx),
    .write_data(weight_write_data),
    .busy(),
    .done(weight_loader_done),
    .error(weight_loader_error)
  );

  multi_layer_job_controller #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_PIXELS),
    .INPUT_C(INPUT_C),
    .HIDDEN_C(HIDDEN_C),
    .OUTPUT_C(OUTPUT_C),
    .DATA_W(DATA_W),
    .PROD_W(PROD_W),
    .ACC_W(ACC_W),
    .BIAS_W(BIAS_W),
    .OUT_W(OUT_W),
    .COUNT_W(COUNT_W),
    .DIM_W(DIM_W)
  ) u_multi_layer_job_controller (
    .clk(clk),
    .rst_n(rst_n),
    .start(compute_start),
    .final_residual_enable(final_residual_enable),
    .image_width(image_width),
    .image_height(image_height),
    .input_tensor(input_tensor),
    .weights_l0(weights_l0),
    .weights_l1(weights_l1),
    .weights_l2(weights_l2),
    .bias_l0(bias_l0),
    .bias_l1(bias_l1),
    .bias_l2(bias_l2),
    .output_tensor(output_tensor),
    .active_layer(active_layer),
    .busy(),
    .done(compute_done)
  );

  output_tensor_store_controller #(
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_COUT(MAX_COUT),
    .DATA_W(OUT_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_output_tensor_store_controller (
    .clk(clk),
    .rst_n(rst_n),
    .start(store_start),
    .width(image_width),
    .height(image_height),
    .channels(COUNT_W'(OUTPUT_C)),
    .output_tensor(output_tensor),
    .stream_valid(output_stream_valid),
    .stream_ready(output_stream_ready),
    .stream_data(output_stream_data),
    .stream_last(output_stream_last),
    .stream_pixel(),
    .stream_channel(),
    .busy(),
    .done(store_done),
    .error(store_error)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      load_layer <= '0;
      bias_index <= '0;
      done <= 1'b0;
      error <= 1'b0;
      loaded_error <= 1'b0;

      for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
        input_tensor[i] <= '0;
      end

      for (int co = 0; co < HIDDEN_C; co++) begin
        bias_l0[co] <= '0;
        bias_l1[co] <= '0;

        for (int ci = 0; ci < INPUT_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights_l0[co][ci][k] <= '0;
          end
        end

        for (int ci = 0; ci < HIDDEN_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights_l1[co][ci][k] <= '0;
          end
        end
      end

      for (int co = 0; co < OUTPUT_C; co++) begin
        bias_l2[co] <= '0;

        for (int ci = 0; ci < HIDDEN_C; ci++) begin
          for (int k = 0; k < 9; k++) begin
            weights_l2[co][ci][k] <= '0;
          end
        end
      end
    end else begin
      done <= 1'b0;

      if (act_write_enable) begin
        input_tensor[(act_write_pixel * ADDR_W'(MAX_CIN)) + ADDR_W'(act_write_channel)] <= act_write_data;
      end

      if (bias_transfer) begin
        unique case (load_layer)
          2'd0: bias_l0[bias_index] <= bias_stream_data;
          2'd1: bias_l1[bias_index] <= bias_stream_data;
          2'd2: bias_l2[bias_index] <= bias_stream_data;
          default: begin end
        endcase
      end

      if (weight_write_enable) begin
        unique case (load_layer)
          2'd0: begin
            if ((weight_write_out_channel < COUNT_W'(HIDDEN_C)) &&
                (weight_write_in_channel < COUNT_W'(INPUT_C))) begin
              weights_l0[weight_write_out_channel][weight_write_in_channel][weight_write_kernel_idx] <=
                weight_write_data;
            end
          end

          2'd1: begin
            if ((weight_write_out_channel < COUNT_W'(HIDDEN_C)) &&
                (weight_write_in_channel < COUNT_W'(HIDDEN_C))) begin
              weights_l1[weight_write_out_channel][weight_write_in_channel][weight_write_kernel_idx] <=
                weight_write_data;
            end
          end

          2'd2: begin
            if ((weight_write_out_channel < COUNT_W'(OUTPUT_C)) &&
                (weight_write_in_channel < COUNT_W'(HIDDEN_C))) begin
              weights_l2[weight_write_out_channel][weight_write_in_channel][weight_write_kernel_idx] <=
                weight_write_data;
            end
          end

          default: begin end
        endcase
      end

      case (state)
        S_IDLE: begin
          if (start) begin
            load_layer <= '0;
            bias_index <= '0;
            error <= 1'b0;
            loaded_error <= 1'b0;
            state <= S_START_ACT;
          end
        end

        S_START_ACT: begin
          state <= S_LOAD_ACT;
        end

        S_LOAD_ACT: begin
          if (act_loader_done) begin
            loaded_error <= act_loader_error;
            load_layer <= '0;
            bias_index <= '0;
            state <= act_loader_error ? S_DONE : S_START_BIAS;
          end
        end

        S_START_BIAS: begin
          bias_index <= '0;
          state <= (bias_count == '0) ? S_START_WEIGHT : S_LOAD_BIAS;
        end

        S_LOAD_BIAS: begin
          if (bias_transfer) begin
            if (last_bias) begin
              bias_index <= '0;
              state <= S_START_WEIGHT;
            end else begin
              bias_index <= bias_index + COUNT_W'(1);
            end
          end
        end

        S_START_WEIGHT: begin
          state <= S_LOAD_WEIGHT;
        end

        S_LOAD_WEIGHT: begin
          if (weight_loader_done) begin
            loaded_error <= weight_loader_error;

            if (weight_loader_error) begin
              state <= S_DONE;
            end else if (load_layer == 2'd2) begin
              state <= S_START_COMPUTE;
            end else begin
              load_layer <= load_layer + 2'd1;
              state <= S_START_BIAS;
            end
          end
        end

        S_START_COMPUTE: begin
          state <= S_WAIT_COMPUTE;
        end

        S_WAIT_COMPUTE: begin
          if (compute_done) begin
            state <= S_START_STORE;
          end
        end

        S_START_STORE: begin
          state <= S_STORE_OUTPUT;
        end

        S_STORE_OUTPUT: begin
          if (store_done) begin
            loaded_error <= store_error;
            state <= S_DONE;
          end
        end

        S_DONE: begin
          done <= 1'b1;
          error <= loaded_error;
          state <= S_IDLE;
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
