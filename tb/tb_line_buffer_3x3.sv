`timescale 1ns/1ps
module tb_line_buffer_3x3;
  localparam int DATA_WIDTH = 8;
  localparam int IMG_WIDTH = 5;
  localparam int IMG_HEIGHT = 5;
  localparam int EXPECTED_WINDOWS = (IMG_WIDTH-2) * (IMG_HEIGHT-2);

  logic clk = 1'b0;
  logic rst_n;
  logic pixel_valid;
  logic signed [DATA_WIDTH-1:0] pixel_in;
  logic window_valid;
  logic signed [DATA_WIDTH-1:0] taps[9];

  logic signed [DATA_WIDTH-1:0] image[IMG_HEIGHT][IMG_WIDTH];
  int tests, errors, windows_seen;

  always #5 clk = ~clk;

  line_buffer_3x3 #(
    .DATA_WIDTH(DATA_WIDTH),
    .IMG_WIDTH(IMG_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .pixel_valid(pixel_valid),
    .pixel_in(pixel_in),
    .window_valid(window_valid),
    .taps(taps)
  );

  task automatic reset_dut;
    begin
      rst_n = 1'b0;
      pixel_valid = 1'b0;
      pixel_in = '0;
      repeat (4) @(negedge clk);
      rst_n = 1'b1;
      repeat (2) @(negedge clk);
    end
  endtask

  task automatic check_window(input int row, input int col);
    logic signed [DATA_WIDTH-1:0] exp[9];
    begin
      exp[0] = image[row-2][col-2]; exp[1] = image[row-2][col-1]; exp[2] = image[row-2][col];
      exp[3] = image[row-1][col-2]; exp[4] = image[row-1][col-1]; exp[5] = image[row-1][col];
      exp[6] = image[row  ][col-2]; exp[7] = image[row  ][col-1]; exp[8] = image[row  ][col];
      for (int k = 0; k < 9; k++) begin
        tests++;
        if (taps[k] !== exp[k]) begin
          errors++;
          $error("window row=%0d col=%0d tap=%0d got=%0d expected=%0d", row, col, k, taps[k], exp[k]);
        end
      end
    end
  endtask

  task automatic drive_pixel(input int row, input int col, input bit insert_gap);
    begin
      if (insert_gap) begin
        @(negedge clk);
        pixel_valid = 1'b0;
        pixel_in = '0;
        @(posedge clk);
        #1;
        tests++;
        if (window_valid !== 1'b0) begin
          errors++;
          $error("window_valid asserted during invalid gap at row=%0d col=%0d", row, col);
        end
      end

      @(negedge clk);
      pixel_valid = 1'b1;
      pixel_in = image[row][col];
      @(posedge clk);
      #1;
      if (row >= 2 && col >= 2) begin
        tests++;
        if (window_valid !== 1'b1) begin
          errors++;
          $error("missing window_valid at row=%0d col=%0d", row, col);
        end else begin
          windows_seen++;
          check_window(row, col);
        end
      end else begin
        tests++;
        if (window_valid !== 1'b0) begin
          errors++;
          $error("early window_valid at row=%0d col=%0d", row, col);
        end
      end
    end
  endtask

  initial begin
    $dumpfile("tb_line_buffer_3x3.vcd");
    $dumpvars(0, tb_line_buffer_3x3);
    tests = 0;
    errors = 0;
    windows_seen = 0;

    for (int r = 0; r < IMG_HEIGHT; r++) begin
      for (int c = 0; c < IMG_WIDTH; c++) begin
        image[r][c] = r * IMG_WIDTH + c;
      end
    end

    reset_dut();

    for (int r = 0; r < IMG_HEIGHT; r++) begin
      for (int c = 0; c < IMG_WIDTH; c++) begin
        drive_pixel(r, c, ((r + c) % 4 == 0));
      end
    end

    @(negedge clk);
    pixel_valid = 1'b0;
    repeat (3) @(posedge clk);
    #1;
    tests++;
    if (window_valid !== 1'b0) begin
      errors++;
      $error("window_valid remained high after stream ended");
    end

    tests++;
    if (windows_seen != EXPECTED_WINDOWS) begin
      errors++;
      $error("window count mismatch: got=%0d expected=%0d", windows_seen, EXPECTED_WINDOWS);
    end

    if (errors != 0) $fatal(1, "tb_line_buffer_3x3 FAILED: tests=%0d errors=%0d", tests, errors);
    $display("PASS tb_line_buffer_3x3 tests=%0d windows=%0d", tests, windows_seen);
    $finish;
  end
endmodule
