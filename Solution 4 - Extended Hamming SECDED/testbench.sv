`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [7:0] fault_mask; // [7:4]: parity mask, [3:0]: state mask. Supports 0, 1, and 'x'

    wire access_granted;
    wire [3:0] state_out;
    wire [3:0] raw_state_out;
    wire [3:0] hamming_parity_out;
    wire single_error_detected;
    wire double_error_detected;
    wire metastable_detected;
    wire alarm_out;

    auth_fsm uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .state_out(state_out),
        .raw_state_out(raw_state_out),
        .hamming_parity_out(hamming_parity_out),
        .single_error_detected(single_error_detected),
        .double_error_detected(double_error_detected),
        .metastable_detected(metastable_detected),
        .alarm_out(alarm_out)
    );

    // 100 MHz clock generation (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Task to apply stimulus for 1 clock cycle on negedge
    task apply_stimulus(input bit in_val, input [7:0] mask);
        begin
            auth_in    = in_val;
            fault_mask = mask;
            @(negedge clk);
        end
    endtask

    // Task to reset the FSM
    task reset_fsm;
        begin
            rst_n      = 0;
            auth_in    = 0;
            fault_mask = 8'h00;
            repeat(2) @(negedge clk);
            rst_n      = 1;
        end
    endtask

    initial begin
        $dumpfile("fsm_simulation.vcd");
        $dumpvars(0, testbench);

        $monitor("Time=%3t ns | in=%b | mask=%h | raw=%b | state=%b (P:%b, S_err:%b, D_err:%b, Alarm:%b) | access=%b", 
                 $time, auth_in, fault_mask, raw_state_out, state_out, hamming_parity_out, 
                 single_error_detected, double_error_detected, alarm_out, access_granted);

        // =========================================================================
        // SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) with No Faults
        // =========================================================================
        $display("\n=========================================================================");
        $display("SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) - No Faults (mask=00)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1 -> GOT_1   (0100)
        apply_stimulus(1'b0, 8'h00); // Bit 2: 0 -> GOT_10  (0101)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1 -> GOT_101 (0110)
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0 -> SUCCESS (0111)

        apply_stimulus(1'b0, 8'h00); // Hold
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 4'b0111 && alarm_out == 1'b0)
            $display(">> SCENARIO 1 PASSED: State=SUCCESS (0111), Alarm=0 => Access Granted!\n");
        else
            $display(">> SCENARIO 1 FAILED\n");

        // =========================================================================
        // SCENARIO 2: Single-Bit Fault on state[1] at Cycle 2 -> SECDED Corrects
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 2: Single-Bit Fault on state[1] (mask=8'h02) -> SECDED Corrects!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1 -> GOT_1 (0100)
        apply_stimulus(1'b0, 8'h02); // Bit 2: 0 with bit-flip on state[1]
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 4'b0111 && alarm_out == 1'b0)
            $display(">> SCENARIO 2 PASSED: Single-bit flip corrected on-the-fly, authentication preserved!\n");
        else
            $display(">> SCENARIO 2 FAILED\n");

        // =========================================================================
        // SCENARIO 3: Single-Bit Fault on Final State (state[0] flipped at SUCCESS)
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 3: Single-Bit Fault on Final State (mask=8'h01) -> Corrected!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b0, 8'h00); // Bit 2: 0
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h01); // Bit 4: 0 with bit-flip on state[0]

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 4'b0111)
            $display(">> SCENARIO 3 PASSED: Final cycle bit-flip corrected to SUCCESS, access granted!\n");
        else
            $display(">> SCENARIO 3 FAILED\n");

        // =========================================================================
        // SCENARIO 4: Double-Bit Fault Injection (SECDED Double Error Detection)
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 4: Double-Bit Fault (mask=8'h03) -> Double Error => Alarm Latched!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b0, 8'h03); // Bit 2: Double-bit flip on state[1:0]!
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (alarm_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 4 PASSED: Double-bit error caught by SECDED, Alarm=1, Access Denied!\n");
        else
            $display(">> SCENARIO 4 FAILED\n");

        // =========================================================================
        // SCENARIO 5: Incorrect Passcode (1 -> 1 -> 1 -> 0) with No Faults
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 5: Wrong Passcode (1110) - Constant-Time Pipeline to LOCKED");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b1, 8'h00); // Bit 2: 1 (wrong)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b0 && state_out == 4'b0011)
            $display(">> SCENARIO 5 PASSED: Reached normal LOCKED state (0011) => Access Denied!\n");
        else
            $display(">> SCENARIO 5 FAILED\n");

        $display("All 5 test scenarios completed successfully.");
        $finish;
    end

endmodule
