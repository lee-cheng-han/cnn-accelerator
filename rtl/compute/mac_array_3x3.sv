`timescale 1ns/1ps

module mac_array_3x3 #(
    parameter int DATA_WIDTH    = 8,
    parameter int WEIGHT_WIDTH  = 8,
    parameter int PRODUCT_WIDTH = DATA_WIDTH + WEIGHT_WIDTH,
    parameter int KERNEL_TAPS   = 9
)(
    input  logic signed [DATA_WIDTH-1:0]    window  [KERNEL_TAPS],
    input  logic signed [WEIGHT_WIDTH-1:0]  weights [KERNEL_TAPS],
    input  logic                            enable,
    output logic signed [PRODUCT_WIDTH-1:0] products[KERNEL_TAPS]
);

    always_comb begin
        for (int i = 0; i < KERNEL_TAPS; i++) begin
            if (enable) begin
                products[i] = $signed(window[i]) * $signed(weights[i]);
            end else begin
                products[i] = '0;
            end
        end
    end

endmodule

