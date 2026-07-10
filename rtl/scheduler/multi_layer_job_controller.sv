`timescale 1ns/1ps

module multi_layer_job_controller #(
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
  input  logic [2:0] layer_ready,

  input  logic signed [DATA_W-1:0] input_tensor [MAX_PIXELS*MAX_CIN],
  input  logic signed [DATA_W-1:0] weights_l0 [HIDDEN_C][INPUT_C][9],
  input  logic signed [DATA_W-1:0] weights_l1 [HIDDEN_C][HIDDEN_C][9],
  input  logic signed [DATA_W-1:0] weights_l2 [OUTPUT_C][HIDDEN_C][9],
  input  logic signed [BIAS_W-1:0] bias_l0 [HIDDEN_C],
  input  logic signed [BIAS_W-1:0] bias_l1 [HIDDEN_C],
  input  logic signed [BIAS_W-1:0] bias_l2 [OUTPUT_C],

  input  logic use_scratchpad_operands,
  input  logic scratch_input_write_enable,
  input  logic [ADDR_W-1:0] scratch_input_write_pixel,
  input  logic [COUNT_W-1:0] scratch_input_write_channel,
  input  logic signed [DATA_W-1:0] scratch_input_write_data,
  input  logic scratch_weight_write_enable,
  input  logic [1:0] scratch_weight_write_layer,
  input  logic [COUNT_W-1:0] scratch_weight_write_out_channel,
  input  logic [COUNT_W-1:0] scratch_weight_write_in_channel,
  input  logic [3:0] scratch_weight_write_kernel_idx,
  input  logic signed [DATA_W-1:0] scratch_weight_write_data,

  output logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT],
  output logic [1:0] active_layer,
  output logic activation_read_bank,
  output logic activation_write_bank,
  output logic waiting_for_layer,
  output logic busy,
  output logic done
);

  typedef enum logic [2:0] {
    S_IDLE,
    S_START_LAYER,
    S_WAIT_LAYER,
    S_STORE_LAYER,
    S_WRITE_SCRATCH,
    S_NEXT_LAYER,
    S_DONE
  } state_t;

  state_t state;

  logic [1:0] layer_index;
  logic scheduler_start;
  logic scheduler_done;
  logic current_layer_ready;
  logic descriptor_valid;
  logic [DIM_W-1:0] desc_input_width;
  logic [DIM_W-1:0] desc_input_height;
  logic [COUNT_W-1:0] desc_input_channels;
  logic [COUNT_W-1:0] desc_output_channels;
  logic [1:0] desc_kernel_size;
  logic [1:0] desc_stride;
  logic [1:0] desc_padding;
  logic desc_bias_enable;
  logic desc_relu_enable;
  logic desc_quant_enable;
  logic [4:0] desc_quant_shift;
  logic desc_residual_enable;

  logic signed [DATA_W-1:0] feature_bank0 [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] feature_bank1 [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] scheduler_activation [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] scheduler_weights_1x1 [MAX_COUT][MAX_CIN];
  logic signed [DATA_W-1:0] scheduler_weights_3x3 [MAX_COUT][MAX_CIN][9];
  logic signed [BIAS_W-1:0] scheduler_bias [MAX_COUT];
  logic signed [OUT_W-1:0] scheduler_output [MAX_PIXELS*MAX_COUT];
  logic [ADDR_W-1:0] scratch_activation_read_pixel;
  logic [COUNT_W-1:0] scratch_activation_read_c_base;
  logic [PC-1:0] scratch_activation_lane_mask;
  logic signed [DATA_W-1:0] scratch_activation_input_lane_data [PC];
  logic signed [DATA_W-1:0] scratch_activation_feature0_lane_data [PC];
  logic signed [DATA_W-1:0] scratch_activation_feature1_lane_data [PC];
  logic signed [DATA_W-1:0] scheduler_scratch_activation_lane_data [PC];
  logic [COUNT_W-1:0] scratch_weight_read_k_base;
  logic [COUNT_W-1:0] scratch_weight_read_c_base;
  logic [3:0] scratch_weight_read_kernel_idx;
  logic [PK-1:0] scratch_weight_out_lane_mask;
  logic [PC-1:0] scratch_weight_in_lane_mask;
  logic signed [DATA_W-1:0] scratch_weight_l0_mat_data [PK][PC];
  logic signed [DATA_W-1:0] scratch_weight_l1_mat_data [PK][PC];
  logic signed [DATA_W-1:0] scratch_weight_l2_mat_data [PK][PC];
  logic signed [DATA_W-1:0] scheduler_scratch_weight_mat_data [PK][PC];
  logic [ADDR_W-1:0] scratch_store_pixel;
  logic [COUNT_W-1:0] scratch_store_channel;
  logic [ADDR_W-1:0] scratch_store_pixel_count;
  logic scratch_store_valid;
  logic scratch_store_last;
  logic scratch_feature0_write_enable;
  logic scratch_feature1_write_enable;
  logic signed [DATA_W-1:0] scratch_feature_write_data;

  assign active_layer = layer_index;
  assign activation_read_bank = (layer_index == 2'd2);
  assign activation_write_bank = (layer_index == 2'd1);
  assign waiting_for_layer =
    (state == S_START_LAYER) && descriptor_valid && !current_layer_ready;
  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign scheduler_start =
    (state == S_START_LAYER) && descriptor_valid && current_layer_ready;
  assign scratch_store_pixel_count =
    ADDR_W'(image_width) * ADDR_W'(image_height);
  assign scratch_store_valid =
    use_scratchpad_operands &&
    (state == S_WRITE_SCRATCH) &&
    (layer_index != 2'd2) &&
    (scratch_store_pixel < scratch_store_pixel_count) &&
    (scratch_store_channel < desc_output_channels);
  assign scratch_store_last =
    scratch_store_valid &&
    (scratch_store_pixel == (scratch_store_pixel_count - ADDR_W'(1))) &&
    (scratch_store_channel == (desc_output_channels - COUNT_W'(1)));
  assign scratch_feature0_write_enable = scratch_store_valid && (layer_index == 2'd0);
  assign scratch_feature1_write_enable = scratch_store_valid && (layer_index == 2'd1);
  assign scratch_feature_write_data =
    scratch_store_valid ?
    DATA_W'(scheduler_output[(scratch_store_pixel * ADDR_W'(MAX_COUT)) +
                             ADDR_W'(scratch_store_channel)]) :
    '0;

  always_comb begin
    unique case (layer_index)
      2'd0: current_layer_ready = layer_ready[0];
      2'd1: current_layer_ready = layer_ready[1];
      2'd2: current_layer_ready = layer_ready[2];
      default: current_layer_ready = 1'b0;
    endcase
  end

  function automatic logic signed [OUT_W-1:0] sat8(input logic signed [ACC_W-1:0] value);
    begin
      if (value > 32'sd127) begin
        return 8'sd127;
      end else if (value < -32'sd128) begin
        return -8'sd128;
      end else begin
        return value[OUT_W-1:0];
      end
    end
  endfunction

  function automatic logic signed [OUT_W-1:0] residual_sub(
    input logic signed [DATA_W-1:0] base,
    input logic signed [OUT_W-1:0] predicted
  );
    logic signed [ACC_W-1:0] value;
    begin
      value = {{(ACC_W-DATA_W){base[DATA_W-1]}}, base} -
              {{(ACC_W-OUT_W){predicted[OUT_W-1]}}, predicted};
      return sat8(value);
    end
  endfunction

  denoise_layer_descriptor_rom #(
    .DIM_W(DIM_W),
    .CH_W(COUNT_W),
    .FINAL_RESIDUAL_ENABLE(1'b1)
  ) u_denoise_layer_descriptor_rom (
    .layer_index(layer_index),
    .image_width(image_width),
    .image_height(image_height),
    .valid(descriptor_valid),
    .input_base(),
    .output_base(),
    .weight_base(),
    .bias_base(),
    .input_width(desc_input_width),
    .input_height(desc_input_height),
    .input_channels(desc_input_channels),
    .output_channels(desc_output_channels),
    .kernel_size(desc_kernel_size),
    .stride(desc_stride),
    .padding(desc_padding),
    .bias_enable(desc_bias_enable),
    .relu_enable(desc_relu_enable),
    .quant_enable(desc_quant_enable),
    .quant_shift(desc_quant_shift),
    .residual_enable(desc_residual_enable),
    .residual_input_base()
  );

  always_comb begin
    for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
      unique case (layer_index)
        2'd0: scheduler_activation[i] = input_tensor[i];
        2'd1: scheduler_activation[i] = feature_bank0[i];
        2'd2: scheduler_activation[i] = feature_bank1[i];
        default: scheduler_activation[i] = '0;
      endcase
    end

    for (int co = 0; co < MAX_COUT; co++) begin
      unique case (layer_index)
        2'd0: scheduler_bias[co] = (co < HIDDEN_C) ? bias_l0[co] : '0;
        2'd1: scheduler_bias[co] = (co < HIDDEN_C) ? bias_l1[co] : '0;
        2'd2: scheduler_bias[co] = (co < OUTPUT_C) ? bias_l2[co] : '0;
        default: scheduler_bias[co] = '0;
      endcase

      for (int ci = 0; ci < MAX_CIN; ci++) begin
        scheduler_weights_1x1[co][ci] = '0;

        for (int k = 0; k < 9; k++) begin
          unique case (layer_index)
            2'd0: begin
              if ((co < HIDDEN_C) && (ci < INPUT_C)) begin
                scheduler_weights_3x3[co][ci][k] = weights_l0[co][ci][k];
              end else begin
                scheduler_weights_3x3[co][ci][k] = '0;
              end
            end

            2'd1: begin
              if ((co < HIDDEN_C) && (ci < HIDDEN_C)) begin
                scheduler_weights_3x3[co][ci][k] = weights_l1[co][ci][k];
              end else begin
                scheduler_weights_3x3[co][ci][k] = '0;
              end
            end

            2'd2: begin
              if ((co < OUTPUT_C) && (ci < HIDDEN_C)) begin
                scheduler_weights_3x3[co][ci][k] = weights_l2[co][ci][k];
              end else begin
                scheduler_weights_3x3[co][ci][k] = '0;
              end
            end

            default: begin
              scheduler_weights_3x3[co][ci][k] = '0;
            end
          endcase
        end
      end
    end

    for (int pc = 0; pc < PC; pc++) begin
      unique case (layer_index)
        2'd0: scheduler_scratch_activation_lane_data[pc] =
          scratch_activation_input_lane_data[pc];
        2'd1: scheduler_scratch_activation_lane_data[pc] =
          scratch_activation_feature0_lane_data[pc];
        2'd2: scheduler_scratch_activation_lane_data[pc] =
          scratch_activation_feature1_lane_data[pc];
        default: scheduler_scratch_activation_lane_data[pc] = '0;
      endcase
    end

    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        unique case (layer_index)
          2'd0: scheduler_scratch_weight_mat_data[pk][pc] =
            scratch_weight_l0_mat_data[pk][pc];
          2'd1: scheduler_scratch_weight_mat_data[pk][pc] =
            scratch_weight_l1_mat_data[pk][pc];
          2'd2: scheduler_scratch_weight_mat_data[pk][pc] =
            scratch_weight_l2_mat_data[pk][pc];
          default: scheduler_scratch_weight_mat_data[pk][pc] = '0;
        endcase
      end
    end
  end

  banked_activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_input_activation_scratchpad (
    .clk(clk),
    .write_enable(scratch_input_write_enable),
    .write_pixel(scratch_input_write_pixel),
    .write_channel(scratch_input_write_channel),
    .write_data(scratch_input_write_data),
    .read_pixel(scratch_activation_read_pixel),
    .read_c_base(scratch_activation_read_c_base),
    .lane_mask(scratch_activation_lane_mask),
    .lane_data(scratch_activation_input_lane_data),
    .debug_read_pixel('0),
    .debug_read_channel('0),
    .debug_read_data()
  );

  banked_activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_feature0_activation_scratchpad (
    .clk(clk),
    .write_enable(scratch_feature0_write_enable),
    .write_pixel(scratch_store_pixel),
    .write_channel(scratch_store_channel),
    .write_data(scratch_feature_write_data),
    .read_pixel(scratch_activation_read_pixel),
    .read_c_base(scratch_activation_read_c_base),
    .lane_mask(scratch_activation_lane_mask),
    .lane_data(scratch_activation_feature0_lane_data),
    .debug_read_pixel('0),
    .debug_read_channel('0),
    .debug_read_data()
  );

  banked_activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_feature1_activation_scratchpad (
    .clk(clk),
    .write_enable(scratch_feature1_write_enable),
    .write_pixel(scratch_store_pixel),
    .write_channel(scratch_store_channel),
    .write_data(scratch_feature_write_data),
    .read_pixel(scratch_activation_read_pixel),
    .read_c_base(scratch_activation_read_c_base),
    .lane_mask(scratch_activation_lane_mask),
    .lane_data(scratch_activation_feature1_lane_data),
    .debug_read_pixel('0),
    .debug_read_channel('0),
    .debug_read_data()
  );

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_weight_l0_scratchpad (
    .clk(clk),
    .write_enable(scratch_weight_write_enable && (scratch_weight_write_layer == 2'd0)),
    .write_out_channel(scratch_weight_write_out_channel),
    .write_in_channel(scratch_weight_write_in_channel),
    .write_kernel_idx(scratch_weight_write_kernel_idx),
    .write_data(scratch_weight_write_data),
    .read_k_base(scratch_weight_read_k_base),
    .read_c_base(scratch_weight_read_c_base),
    .read_kernel_idx(scratch_weight_read_kernel_idx),
    .out_lane_mask(scratch_weight_out_lane_mask),
    .in_lane_mask(scratch_weight_in_lane_mask),
    .weight_mat(scratch_weight_l0_mat_data),
    .debug_out_channel('0),
    .debug_in_channel('0),
    .debug_kernel_idx('0),
    .debug_read_data()
  );

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_weight_l1_scratchpad (
    .clk(clk),
    .write_enable(scratch_weight_write_enable && (scratch_weight_write_layer == 2'd1)),
    .write_out_channel(scratch_weight_write_out_channel),
    .write_in_channel(scratch_weight_write_in_channel),
    .write_kernel_idx(scratch_weight_write_kernel_idx),
    .write_data(scratch_weight_write_data),
    .read_k_base(scratch_weight_read_k_base),
    .read_c_base(scratch_weight_read_c_base),
    .read_kernel_idx(scratch_weight_read_kernel_idx),
    .out_lane_mask(scratch_weight_out_lane_mask),
    .in_lane_mask(scratch_weight_in_lane_mask),
    .weight_mat(scratch_weight_l1_mat_data),
    .debug_out_channel('0),
    .debug_in_channel('0),
    .debug_kernel_idx('0),
    .debug_read_data()
  );

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_weight_l2_scratchpad (
    .clk(clk),
    .write_enable(scratch_weight_write_enable && (scratch_weight_write_layer == 2'd2)),
    .write_out_channel(scratch_weight_write_out_channel),
    .write_in_channel(scratch_weight_write_in_channel),
    .write_kernel_idx(scratch_weight_write_kernel_idx),
    .write_data(scratch_weight_write_data),
    .read_k_base(scratch_weight_read_k_base),
    .read_c_base(scratch_weight_read_c_base),
    .read_kernel_idx(scratch_weight_read_kernel_idx),
    .out_lane_mask(scratch_weight_out_lane_mask),
    .in_lane_mask(scratch_weight_in_lane_mask),
    .weight_mat(scratch_weight_l2_mat_data),
    .debug_out_channel('0),
    .debug_in_channel('0),
    .debug_kernel_idx('0),
    .debug_read_data()
  );

  single_layer_scheduler #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_PIXELS),
    .DATA_W(DATA_W),
    .PROD_W(PROD_W),
    .ACC_W(ACC_W),
    .BIAS_W(BIAS_W),
    .OUT_W(OUT_W),
    .COUNT_W(COUNT_W),
    .DIM_W(DIM_W),
    .ADDR_W(ADDR_W)
  ) u_single_layer_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .start(scheduler_start),
    .input_width(desc_input_width),
    .input_height(desc_input_height),
    .output_width(image_width),
    .output_height(image_height),
    .kernel_size(desc_kernel_size),
    .stride(desc_stride),
    .padding(desc_padding),
    .cin(desc_input_channels),
    .cout(desc_output_channels),
    .bias_enable(desc_bias_enable),
    .relu_enable(desc_relu_enable),
    .quant_enable(desc_quant_enable),
    .quant_shift(desc_quant_shift),
    .activation(scheduler_activation),
    .weights_1x1(scheduler_weights_1x1),
    .weights_3x3(scheduler_weights_3x3),
    .bias(scheduler_bias),
    .use_scratchpad_operands(use_scratchpad_operands),
    .scratch_activation_read_pixel(scratch_activation_read_pixel),
    .scratch_activation_read_c_base(scratch_activation_read_c_base),
    .scratch_activation_lane_mask(scratch_activation_lane_mask),
    .scratch_activation_lane_data(scheduler_scratch_activation_lane_data),
    .scratch_weight_read_k_base(scratch_weight_read_k_base),
    .scratch_weight_read_c_base(scratch_weight_read_c_base),
    .scratch_weight_read_kernel_idx(scratch_weight_read_kernel_idx),
    .scratch_weight_out_lane_mask(scratch_weight_out_lane_mask),
    .scratch_weight_in_lane_mask(scratch_weight_in_lane_mask),
    .scratch_weight_mat_data(scheduler_scratch_weight_mat_data),
    .output_tensor(scheduler_output),
    .current_x(),
    .current_y(),
    .busy(),
    .done(scheduler_done)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      layer_index <= '0;
      scratch_store_pixel <= '0;
      scratch_store_channel <= '0;
      done <= 1'b0;

      for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
        feature_bank0[i] <= '0;
        feature_bank1[i] <= '0;
      end

      for (int i = 0; i < MAX_PIXELS*MAX_COUT; i++) begin
        output_tensor[i] <= '0;
      end
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            layer_index <= 2'd0;
            state <= ((image_width == '0) || (image_height == '0)) ? S_DONE : S_START_LAYER;
          end
        end

        S_START_LAYER: begin
          if (!descriptor_valid) begin
            state <= S_DONE;
          end else if (current_layer_ready) begin
            state <= S_WAIT_LAYER;
          end
        end

        S_WAIT_LAYER: begin
          if (scheduler_done) begin
            state <= S_STORE_LAYER;
          end
        end

        S_STORE_LAYER: begin
          for (int p = 0; p < MAX_PIXELS; p++) begin
            for (int c = 0; c < MAX_CIN; c++) begin
              if (layer_index == 2'd0) begin
                feature_bank0[(p * MAX_CIN) + c] <=
                  (c < HIDDEN_C) ? scheduler_output[(p * MAX_COUT) + c] : '0;
              end else if (layer_index == 2'd1) begin
                feature_bank1[(p * MAX_CIN) + c] <=
                  (c < HIDDEN_C) ? scheduler_output[(p * MAX_COUT) + c] : '0;
              end
            end

            for (int c = 0; c < MAX_COUT; c++) begin
              if (layer_index == 2'd2) begin
                if (c < OUTPUT_C) begin
                  if (desc_residual_enable && final_residual_enable) begin
                    output_tensor[(p * MAX_COUT) + c] <=
                      residual_sub(input_tensor[(p * MAX_CIN) + c],
                                   scheduler_output[(p * MAX_COUT) + c]);
                  end else begin
                    output_tensor[(p * MAX_COUT) + c] <= scheduler_output[(p * MAX_COUT) + c];
                  end
                end else begin
                  output_tensor[(p * MAX_COUT) + c] <= '0;
                end
              end
            end
          end

          scratch_store_pixel <= '0;
          scratch_store_channel <= '0;
          if (use_scratchpad_operands &&
              (layer_index != 2'd2) &&
              (scratch_store_pixel_count != '0) &&
              (desc_output_channels != '0)) begin
            state <= S_WRITE_SCRATCH;
          end else begin
            state <= S_NEXT_LAYER;
          end
        end

        S_WRITE_SCRATCH: begin
          if (scratch_store_last) begin
            scratch_store_pixel <= '0;
            scratch_store_channel <= '0;
            state <= S_NEXT_LAYER;
          end else if (scratch_store_valid) begin
            if (scratch_store_channel == (desc_output_channels - COUNT_W'(1))) begin
              scratch_store_channel <= '0;
              scratch_store_pixel <= scratch_store_pixel + ADDR_W'(1);
            end else begin
              scratch_store_channel <= scratch_store_channel + COUNT_W'(1);
            end
          end else begin
            state <= S_NEXT_LAYER;
          end
        end

        S_NEXT_LAYER: begin
          if (layer_index < 2'd2) begin
            layer_index <= layer_index + 2'd1;
            state <= S_START_LAYER;
          end else begin
            state <= S_DONE;
          end
        end

        S_DONE: begin
          done <= 1'b1;
          state <= S_IDLE;
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
