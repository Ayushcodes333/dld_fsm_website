`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [7:0] fault_mask; // [3:0]: Core 1, [7:4]: Core 2. Supports 0, 1, and 'x'

    wire access_granted;
    wire [3:0] state_out;
    wire [3:0] state_2_out;
    wire mismatch_detected;
    wire metastable_detected;
    wire alarm_out;

    auth_fsm uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .state_out(state_out),
        .state_2_out(state_2_out),
        .mismatch_detected(mismatch_detected),
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

        $monitor("Time=%3t ns | in=%b | mask=%h | s1=%b s2=%b | Mismatch:%b | Meta:%b | Alarm:%b | access=%b", 
                 $time, auth_in, fault_mask, state_out, state_2_out, 
                 mismatch_detected, metastable_detected, alarm_out, access_granted);

        // =========================================================================
        // SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) with No Faults
        // =========================================================================
        $display("\n=========================================================================");
        $display("SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) - Both Cores Agree (mask=00)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1 -> GOT_1   (0100)
        apply_stimulus(1'b0, 8'h00); // Bit 2: 0 -> GOT_10  (0101)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1 -> GOT_101 (0110)
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0 -> SUCCESS (0111)

        apply_stimulus(1'b0, 8'h00); // Hold
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 4'b0111 && state_2_out == 4'b0111 && alarm_out == 1'b0)
            $display(">> SCENARIO 1 PASSED: Dual consensus reached (1 & 1), Access Granted!\n");
        else
            $display(">> SCENARIO 1 FAILED\n");

        // =========================================================================
        // SCENARIO 2: Single Fault Injected into Core 1 during Traversal (state[2] flipped)
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 2: Single Fault Injected into Core 1 (mask=8'h04) -> Alarm Latched!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b0, 8'h04); // Bit 2: 0 with bit-flip on Core 1!
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (alarm_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 2 PASSED: Discrepancy between Core 1 and Core 2 detected, Alarm=1, Access Denied!\n");
        else
            $display(">> SCENARIO 2 FAILED\n");

        // =========================================================================
        // SCENARIO 3: Attacker Glitches Core 1 to SUCCESS -> AND Gate Blocks Bypass
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 3: Attacker Glitches Core 1 to SUCCESS -> AND Gate Blocks Bypass!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1 (correct)
        apply_stimulus(1'b1, 8'h00); // Bit 2: 1 (wrong bit -> both route to ERR_2)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h0D); // Glitch Core 1 only to SUCCESS!

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b0 && alarm_out == 1'b1)
            $display(">> SCENARIO 3 PASSED: Dual consensus AND gate thwarted single-core bypass attack!\n");
        else
            $display(">> SCENARIO 3 FAILED: Security breach! Bypass was not thwarted!\n");

        // =========================================================================
        // SCENARIO 4: Laser Attack Induces Metastability ('x') on Core 1
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 4: Laser Attack -> Metastable Core 1 (mask=8'h0x) -> Alarm=1");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b0, 8'h0x); // Bit 2: Laser hit on Core 1!
        apply_stimulus(1'b1, 8'h00); 
        apply_stimulus(1'b0, 8'h00); 

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (alarm_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 4 PASSED: Metastable state detected! Alarm=1, Access Denied!\n");
        else
            $display(">> SCENARIO 4 FAILED\n");

        // =========================================================================
        // SCENARIO 5: Incorrect Password (1 -> 1 -> 1 -> 0) with No Faults
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 5: Wrong Passcode (1110) - Both Cores Transition to LOCKED");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b1, 8'h00); // Bit 2: 1 (wrong)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b0 && state_out == 4'b0011 && state_2_out == 4'b0011)
            $display(">> SCENARIO 5 PASSED: Both cores consistently locked out wrong passcode!\n");
        else
            $display(">> SCENARIO 5 FAILED\n");

        $display("All 5 test scenarios completed successfully.");
        $finish;
    end

endmodule
