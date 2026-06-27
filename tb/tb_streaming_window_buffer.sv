`timescale 1ns/1ps

module tb_streaming_window_buffer;

  localparam int DATA_WIDTH = 8;
  localparam int IC = 3;
  localparam int W = 5;
  localparam int H = 4;
  localparam int MAX_W = 8;

  logic clk;
  logic rst_n;
  logic clear;

  logic [15:0] image_width;
  logic [15:0] image_height;

  logic signed [DATA_WIDTH-1:0] pixel_data;
  logic pixel_valid;
  logic pixel_ready;

  logic window_valid;
  logic [15:0] window_x;
  logic [15:0] window_y;
  logic signed [DATA_WIDTH-1:0] window_data [IC][9];

  int errors;
  int windows_seen;

  streaming_window_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_INPUT_CHANNELS(IC),
    .MAX_IMG_WIDTH(MAX_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .image_width(image_width),
    .image_height(image_height),

    .pixel_data(pixel_data),
    .pixel_valid(pixel_valid),
    .pixel_ready(pixel_ready),

    .window_valid(window_valid),
    .window_x(window_x),
    .window_y(window_y),
    .window_data(window_data)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function automatic logic signed [DATA_WIDTH-1:0] pix(
    input int c,
    input int y,
    input int x
  );
    begin
      pix = logic'(c * 40 + y * 8 + x);
    end
  endfunction

  task automatic send_pixel(input logic signed [DATA_WIDTH-1:0] value);
    begin
      @(negedge clk);
      pixel_data  = value;
      pixel_valid = 1'b1;

      @(posedge clk);
      #1;

      @(negedge clk);
      pixel_valid = 1'b0;
      pixel_data  = '0;
    end
  endtask

  task automatic check_window;
    int base_x;
    int base_y;
    logic signed [DATA_WIDTH-1:0] exp [IC][9];

    begin
      if (window_valid) begin
        windows_seen++;

        base_x = window_x;
        base_y = window_y;

        for (int c = 0; c < IC; c++) begin
          exp[c][0] = pix(c, base_y + 0, base_x + 0);
          exp[c][1] = pix(c, base_y + 0, base_x + 1);
          exp[c][2] = pix(c, base_y + 0, base_x + 2);

          exp[c][3] = pix(c, base_y + 1, base_x + 0);
          exp[c][4] = pix(c, base_y + 1, base_x + 1);
          exp[c][5] = pix(c, base_y + 1, base_x + 2);

          exp[c][6] = pix(c, base_y + 2, base_x + 0);
          exp[c][7] = pix(c, base_y + 2, base_x + 1);
          exp[c][8] = pix(c, base_y + 2, base_x + 2);

          for (int k = 0; k < 9; k++) begin
            if (window_data[c][k] !== exp[c][k]) begin
              errors++;
              $error(
                "window mismatch at out=(%0d,%0d) c=%0d k=%0d got=%0d expected=%0d",
                window_x,
                window_y,
                c,
                k,
                window_data[c][k],
                exp[c][k]
              );
            end
          end
        end
      end
    end
  endtask

  always @(posedge clk) begin
    if (rst_n) begin
      #1;
      check_window();
    end
  end

  initial begin
    errors = 0;
    windows_seen = 0;

    image_width  = W;
    image_height = H;
    pixel_data   = '0;
    pixel_valid  = 1'b0;
    clear        = 1'b0;

    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    clear = 1'b1;
    @(posedge clk);
    #1;
    clear = 1'b0;

    // Stream order:
    // pixel (x,y), channel 0
    // pixel (x,y), channel 1
    // pixel (x,y), channel 2
    // then next x.
    for (int y = 0; y < H; y++) begin
      for (int x = 0; x < W; x++) begin
        for (int c = 0; c < IC; c++) begin
          send_pixel(pix(c, y, x));
        end
      end
    end

    repeat (10) @(posedge clk);

    if (windows_seen != ((W - 2) * (H - 2))) begin
      errors++;
      $error("windows_seen got=%0d expected=%0d", windows_seen, ((W - 2) * (H - 2)));
    end

    if (errors == 0) begin
      $display("[PASS] tb_streaming_window_buffer windows_seen=%0d", windows_seen);
    end else begin
      $fatal(1, "[FAIL] tb_streaming_window_buffer errors=%0d windows_seen=%0d", errors, windows_seen);
    end

    $finish;
  end

endmodule
