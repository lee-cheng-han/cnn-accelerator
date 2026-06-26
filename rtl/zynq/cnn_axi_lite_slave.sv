`timescale 1ns/1ps

module cnn_axi_lite_slave #(
  parameter int AXI_ADDR_WIDTH      = 12,
  parameter int AXI_DATA_WIDTH      = 32,
  parameter int NUM_INPUT_CHANNELS  = 3,
  parameter int NUM_OUTPUT_CHANNELS = 4,
  parameter int KERNEL_TAPS         = 9,
  parameter int DATA_WIDTH          = 8,
  parameter int WEIGHT_WIDTH        = 8,
  parameter int BIAS_WIDTH          = 32
)(
  input  logic                         s_axi_aclk,
  input  logic                         s_axi_aresetn,

  input  logic [AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
  input  logic                         s_axi_awvalid,
  output logic                         s_axi_awready,

  input  logic [AXI_DATA_WIDTH-1:0]     s_axi_wdata,
  input  logic [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
  input  logic                         s_axi_wvalid,
  output logic                         s_axi_wready,

  output logic [1:0]                   s_axi_bresp,
  output logic                         s_axi_bvalid,
  input  logic                         s_axi_bready,

  input  logic [AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
  input  logic                         s_axi_arvalid,
  output logic                         s_axi_arready,

  output logic [AXI_DATA_WIDTH-1:0]     s_axi_rdata,
  output logic [1:0]                   s_axi_rresp,
  output logic                         s_axi_rvalid,
  input  logic                         s_axi_rready,

  output logic                         start_pulse,
  output logic                         clear_pulse,

  output logic [15:0]                  image_width,
  output logic [15:0]                  image_height,
  output logic                         kernel_mode,
  output logic                         relu_enable,
  output logic                         bias_enable,
  output logic                         quant_enable,
  output logic [4:0]                   quant_shift,

  output logic                         weight_valid,
  output logic [7:0]                   weight_index,
  output logic signed [WEIGHT_WIDTH-1:0] weight_data,
  output logic                         bias_valid,
  output logic [1:0]                   bias_index,
  output logic signed [BIAS_WIDTH-1:0] bias_data,

  output logic                         pixel_valid,
  output logic [31:0]                  pixel_index,
  output logic signed [DATA_WIDTH-1:0] pixel_data,

  input  logic                         core_busy,
  input  logic                         core_done,
  input  logic                         result_valid,
  input  logic signed [DATA_WIDTH-1:0] result_data,
  input  logic                         result_last,
  output logic                         result_ready
);

  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CONTROL      = 12'h000;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STATUS       = 12'h004;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_WIDTH        = 12'h008;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_HEIGHT       = 12'h00C;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODE_FLAGS   = 12'h010;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PIXEL_IN     = 12'h020;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PIXEL_INDEX  = 12'h024;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_RESULT_DATA  = 12'h030;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_RESULT_STAT  = 12'h034;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_WEIGHT_BASE  = 12'h100;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_BIAS_BASE    = 12'h400;

  localparam int NUM_WEIGHTS = NUM_OUTPUT_CHANNELS * NUM_INPUT_CHANNELS * KERNEL_TAPS;

  logic [AXI_ADDR_WIDTH-1:0] awaddr_q;
  logic [AXI_DATA_WIDTH-1:0] wdata_q;
  logic [(AXI_DATA_WIDTH/8)-1:0] wstrb_q;
  logic aw_have;
  logic w_have;

  logic [31:0] control_reg;
  logic [31:0] status_reg;
  logic [31:0] mode_flags_reg;
  logic [31:0] result_status_reg;

  logic signed [WEIGHT_WIDTH-1:0] weight_mem [0:NUM_WEIGHTS-1];
  logic signed [BIAS_WIDTH-1:0]   bias_mem   [0:NUM_OUTPUT_CHANNELS-1];

  logic [7:0] wr_weight_idx_calc;
  logic [1:0] wr_bias_idx_calc;
  logic       result_read_fire;

  assign s_axi_bresp = 2'b00;
  assign s_axi_rresp = 2'b00;

  assign result_read_fire =
    (!s_axi_rvalid) &&
    s_axi_arvalid &&
    (s_axi_araddr == ADDR_RESULT_DATA);

  assign result_ready = result_read_fire && result_valid;

  assign status_reg = {
    27'd0,
    result_last,
    result_valid,
    core_done,
    core_busy,
    1'b0
  };

  assign result_status_reg = {
    30'd0,
    result_last,
    result_valid
  };

  always_comb begin
    wr_weight_idx_calc = 8'd0;
    if ((awaddr_q >= ADDR_WEIGHT_BASE) &&
        (awaddr_q < (ADDR_WEIGHT_BASE + (NUM_WEIGHTS * 4)))) begin
      wr_weight_idx_calc = (awaddr_q - ADDR_WEIGHT_BASE) >> 2;
    end
  end

  always_comb begin
    wr_bias_idx_calc = 2'd0;
    if ((awaddr_q >= ADDR_BIAS_BASE) &&
        (awaddr_q < (ADDR_BIAS_BASE + (NUM_OUTPUT_CHANNELS * 4)))) begin
      wr_bias_idx_calc = (awaddr_q - ADDR_BIAS_BASE) >> 2;
    end
  end

  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_awready <= 1'b0;
      s_axi_wready  <= 1'b0;
      s_axi_bvalid  <= 1'b0;
      aw_have       <= 1'b0;
      w_have        <= 1'b0;
      awaddr_q      <= '0;
      wdata_q       <= '0;
      wstrb_q       <= '0;

      control_reg   <= 32'd0;
      image_width   <= 16'd0;
      image_height  <= 16'd0;
      mode_flags_reg <= 32'd0;
      kernel_mode   <= 1'b0;
      relu_enable   <= 1'b0;
      bias_enable   <= 1'b0;
      quant_enable  <= 1'b0;
      quant_shift   <= 5'd0;

      start_pulse   <= 1'b0;
      clear_pulse   <= 1'b0;
      weight_valid  <= 1'b0;
      weight_index  <= 8'd0;
      weight_data   <= '0;
      bias_valid    <= 1'b0;
      bias_index    <= 2'd0;
      bias_data     <= '0;
      pixel_valid   <= 1'b0;
      pixel_index   <= 32'd0;
      pixel_data    <= '0;

      for (int i = 0; i < NUM_WEIGHTS; i++) begin
        weight_mem[i] <= '0;
      end

      for (int i = 0; i < NUM_OUTPUT_CHANNELS; i++) begin
        bias_mem[i] <= '0;
      end
    end else begin
      s_axi_awready <= 1'b0;
      s_axi_wready  <= 1'b0;

      start_pulse   <= 1'b0;
      clear_pulse   <= 1'b0;
      weight_valid  <= 1'b0;
      bias_valid    <= 1'b0;
      pixel_valid   <= 1'b0;

      if (!aw_have && s_axi_awvalid) begin
        s_axi_awready <= 1'b1;
        awaddr_q      <= s_axi_awaddr;
        aw_have       <= 1'b1;
      end

      if (!w_have && s_axi_wvalid) begin
        s_axi_wready <= 1'b1;
        wdata_q      <= s_axi_wdata;
        wstrb_q      <= s_axi_wstrb;
        w_have       <= 1'b1;
      end

      if (aw_have && w_have && !s_axi_bvalid) begin
        unique case (awaddr_q)
          ADDR_CONTROL: begin
            control_reg <= wdata_q;
            start_pulse <= wdata_q[0];
            clear_pulse <= wdata_q[1];
          end

          ADDR_WIDTH: begin
            image_width <= wdata_q[15:0];
          end

          ADDR_HEIGHT: begin
            image_height <= wdata_q[15:0];
          end

          ADDR_MODE_FLAGS: begin
            mode_flags_reg <= wdata_q;
            kernel_mode    <= wdata_q[0];
            relu_enable    <= wdata_q[1];
            bias_enable    <= wdata_q[2];
            quant_enable   <= wdata_q[3];
            quant_shift    <= wdata_q[12:8];
          end

          ADDR_PIXEL_IN: begin
            pixel_valid <= 1'b1;
            pixel_data  <= wdata_q[DATA_WIDTH-1:0];
          end

          ADDR_PIXEL_INDEX: begin
            pixel_index <= wdata_q;
          end

          default: begin
            if ((awaddr_q >= ADDR_WEIGHT_BASE) &&
                (awaddr_q < (ADDR_WEIGHT_BASE + (NUM_WEIGHTS * 4)))) begin
              weight_mem[wr_weight_idx_calc] <= wdata_q[WEIGHT_WIDTH-1:0];
              weight_valid <= 1'b1;
              weight_index <= wr_weight_idx_calc;
              weight_data  <= wdata_q[WEIGHT_WIDTH-1:0];
            end else if ((awaddr_q >= ADDR_BIAS_BASE) &&
                         (awaddr_q < (ADDR_BIAS_BASE + (NUM_OUTPUT_CHANNELS * 4)))) begin
              bias_mem[wr_bias_idx_calc] <= wdata_q;
              bias_valid <= 1'b1;
              bias_index <= wr_bias_idx_calc;
              bias_data  <= wdata_q;
            end
          end
        endcase

        aw_have      <= 1'b0;
        w_have       <= 1'b0;
        s_axi_bvalid <= 1'b1;
      end

      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end
    end
  end

  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_arready <= 1'b0;
      s_axi_rvalid  <= 1'b0;
      s_axi_rdata   <= 32'd0;
    end else begin
      s_axi_arready <= 1'b0;

      if (!s_axi_rvalid && s_axi_arvalid) begin
        s_axi_arready <= 1'b1;
        s_axi_rvalid  <= 1'b1;

        unique case (s_axi_araddr)
          ADDR_CONTROL: begin
            s_axi_rdata <= control_reg;
          end

          ADDR_STATUS: begin
            s_axi_rdata <= status_reg;
          end

          ADDR_WIDTH: begin
            s_axi_rdata <= {16'd0, image_width};
          end

          ADDR_HEIGHT: begin
            s_axi_rdata <= {16'd0, image_height};
          end

          ADDR_MODE_FLAGS: begin
            s_axi_rdata <= mode_flags_reg;
          end

          ADDR_PIXEL_INDEX: begin
            s_axi_rdata <= pixel_index;
          end

          ADDR_RESULT_DATA: begin
            s_axi_rdata  <= {{(32-DATA_WIDTH){result_data[DATA_WIDTH-1]}}, result_data};
          end

          ADDR_RESULT_STAT: begin
            s_axi_rdata <= result_status_reg;
          end

          default: begin
            if ((s_axi_araddr >= ADDR_WEIGHT_BASE) &&
                (s_axi_araddr < (ADDR_WEIGHT_BASE + (NUM_WEIGHTS * 4)))) begin
              s_axi_rdata <= {{(32-WEIGHT_WIDTH){weight_mem[(s_axi_araddr - ADDR_WEIGHT_BASE) >> 2][WEIGHT_WIDTH-1]}},
                              weight_mem[(s_axi_araddr - ADDR_WEIGHT_BASE) >> 2]};
            end else if ((s_axi_araddr >= ADDR_BIAS_BASE) &&
                         (s_axi_araddr < (ADDR_BIAS_BASE + (NUM_OUTPUT_CHANNELS * 4)))) begin
              s_axi_rdata <= bias_mem[(s_axi_araddr - ADDR_BIAS_BASE) >> 2];
            end else begin
              s_axi_rdata <= 32'hDEAD_BEEF;
            end
          end
        endcase
      end

      if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end
    end
  end

endmodule
