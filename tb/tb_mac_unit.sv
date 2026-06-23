`timescale 1ns/1ps

module tb_mac_unit;

    localparam int DATA_WIDTH   = 8;
    localparam int WEIGHT_WIDTH = 8;
    localparam int ACC_WIDTH    = 32;

    logic clk;

    logic enable;
    logic signed [DATA_WIDTH-1:0]   pixel;
    logic signed [WEIGHT_WIDTH-1:0] weight;
    logic signed [ACC_WIDTH-1:0]    acc_in;
    logic signed [ACC_WIDTH-1:0]    acc_out;

    int seed;
    int test_count;
    int pass_count;
    int fail_count;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .pixel(pixel),
        .weight(weight),
        .acc_in(acc_in),
        .enable(enable),
        .acc_out(acc_out)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // Waveform dump
    // ------------------------------------------------------------
    initial begin
        $dumpfile("tb_mac_unit.vcd");
        $dumpvars(0, tb_mac_unit);
    end

    // ------------------------------------------------------------
    // Vivado-compatible random helper
    // Uses $random instead of $urandom for XSim compatibility.
    // ------------------------------------------------------------
    function automatic int rand_range(input int min_val, input int max_val);
        int r;
        begin
            r = $random(seed);
            if (r < 0) begin
                r = -r;
            end
            rand_range = min_val + (r % (max_val - min_val + 1));
        end
    endfunction

    // ------------------------------------------------------------
    // Golden model
    // ------------------------------------------------------------
    function automatic signed [ACC_WIDTH-1:0] golden_mac(
        input logic en,
        input signed [DATA_WIDTH-1:0]   pix,
        input signed [WEIGHT_WIDTH-1:0] wt,
        input signed [ACC_WIDTH-1:0]    acc
    );
        begin
            if (en) begin
                golden_mac = acc + (pix * wt);
            end else begin
                golden_mac = acc;
            end
        end
    endfunction

    // ------------------------------------------------------------
    // Self-checking task
    // Drive on negedge, check after posedge.
    // ------------------------------------------------------------
    task automatic run_case(
        input string name,
        input logic en,
        input signed [DATA_WIDTH-1:0]   pix,
        input signed [WEIGHT_WIDTH-1:0] wt,
        input signed [ACC_WIDTH-1:0]    acc
    );
        logic signed [ACC_WIDTH-1:0] expected;

        begin
            expected = golden_mac(en, pix, wt, acc);

            @(negedge clk);
            enable = en;
            pixel  = pix;
            weight = wt;
            acc_in = acc;

            @(posedge clk);
            #1;

            test_count++;

            if (acc_out !== expected) begin
                fail_count++;
                $display("[FAIL] %s", name);
                $display("       enable   = %0d", en);
                $display("       pixel    = %0d", pix);
                $display("       weight   = %0d", wt);
                $display("       acc_in   = %0d", acc);
                $display("       expected = %0d", expected);
                $display("       got      = %0d", acc_out);
                $fatal(1);
            end else begin
                pass_count++;
                $display("[PASS] %s | pixel=%0d weight=%0d acc_in=%0d acc_out=%0d",
                         name, pix, wt, acc, acc_out);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        if (!$value$plusargs("ntb_random_seed=%d", seed)) begin
            seed = 12345;
        end

        $display("============================================================");
        $display("tb_mac_unit started");
        $display("SEED = %0d", seed);
        $display("============================================================");

        enable = 1'b0;
        pixel  = '0;
        weight = '0;
        acc_in = '0;

        repeat (3) @(posedge clk);

        // Directed tests
        run_case("zero multiply",              1'b1,  8'sd0,    8'sd0,    32'sd0);
        run_case("positive multiply",          1'b1,  8'sd3,    8'sd4,    32'sd0);
        run_case("positive multiply with acc", 1'b1,  8'sd3,    8'sd4,    32'sd10);
        run_case("negative pixel",             1'b1, -8'sd3,    8'sd4,    32'sd0);
        run_case("negative weight",            1'b1,  8'sd3,   -8'sd4,    32'sd0);
        run_case("both negative",              1'b1, -8'sd3,   -8'sd4,    32'sd0);
        run_case("negative accumulator",       1'b1,  8'sd5,    8'sd6,   -32'sd100);
        run_case("enable off passthrough",     1'b0,  8'sd5,    8'sd6,    32'sd1234);

        // INT8 edge cases
        run_case("max positive inputs",        1'b1,  8'sd127,  8'sd127,  32'sd0);
        run_case("min negative pixel",         1'b1, -8'sd128,  8'sd127,  32'sd0);
        run_case("min negative weight",        1'b1,  8'sd127, -8'sd128,  32'sd0);
        run_case("both min negative",          1'b1, -8'sd128, -8'sd128,  32'sd0);
        run_case("large positive acc",         1'b1,  8'sd10,   8'sd10,   32'sd100000);
        run_case("large negative acc",         1'b1,  8'sd10,   8'sd10,  -32'sd100000);

        // Randomized tests
        for (int i = 0; i < 1000; i++) begin
            run_case(
                $sformatf("random_%0d", i),
                rand_range(0, 1),
                rand_range(-128, 127),
                rand_range(-128, 127),
                rand_range(-100000, 100000)
            );
        end

        $display("============================================================");
        $display("tb_mac_unit summary");
        $display("Tests run : %0d", test_count);
        $display("Passed    : %0d", pass_count);
        $display("Failed    : %0d", fail_count);
        $display("============================================================");

        if (fail_count == 0) begin
            $display("[PASS] tb_mac_unit");
        end else begin
            $display("[FAIL] tb_mac_unit");
            $fatal(1);
        end

        $finish;
    end

endmodule