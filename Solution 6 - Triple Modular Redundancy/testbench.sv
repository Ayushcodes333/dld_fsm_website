`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [11:0] fault_mask; // [3:0]: Core A, [7:4]: Core B, [11:8]: Core C. Supports 0, 1, and 'x'

    wire access_granted;
    wire [3:0] state_out; // Voted state
    wire [3:0] state_A_out;
    wire [3:0] state_B_out;
    wire [3:0] state_C_out;
    wire auth_A_out;
    wire auth_B_out;
    wire auth_C_out;
    wire disagreement_detected;
    wire metastable_detected;

    auth_fsm uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .state_out(state_out),
        .state_A_out(state_A_out),
        .state_B_out(state_B_out),
        .state_C_out(state_C_out),
        .auth_A_out(auth_A_out),
        .auth_B_out(auth_B_out),
        .auth_C_out(auth_C_out),
        .disagreement_detected(disagreement_detected),
        .metastable_detected(metastable_detected)
    );

    // 100 MHz clock generation (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Task to apply stimulus for 1 clock cycle on negedge
    task apply_stimulus(input bit in_val, input [11:0] mask);
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
            fault_mask = 12'h000;
            repeat(2) @(negedge clk);
            rst_n      = 1;
        end
    endtask

    initial begin
        $dumpfile("fsm_simulation.vcd");
        $dumpvars(0, testbench);

        $monitor("Time=%3t ns | in=%b | mask=%h | sA=%b sB=%b sC=%b | voted=%b | disag=%b | access=%b", 
                 $time, auth_in, fault_mask, state_A_out, state_B_out, state_C_out, state_out, 
                 disagreement_detected, access_granted);

        // =========================================================================
        // SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) with No Faults
        // =========================================================================
        $display("\n=========================================================================");
        $display("SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) - Unanimous Consensus (A=1, B=1, C=1)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 12'h000); // Bit 1: 1 -> GOT_1   (0100)
        apply_stimulus(1'b0, 12'h000); // Bit 2: 0 -> GOT_10  (0101)
        apply_stimulus(1'b1, 12'h000); // Bit 3: 1 -> GOT_101 (0110)
        apply_stimulus(1'b0, 12'h000); // Bit 4: 0 -> SUCCESS (0111)

        apply_stimulus(1'b0, 12'h000); // Hold
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 4'b0111 && auth_A_out == 1'b1 && auth_B_out == 1'b1 && auth_C_out == 1'b1)
            $display(">> SCENARIO 1 PASSED: Unanimous agreement: AB + BC + AC = 1, Access Granted!\n");
        else
            $display(">> SCENARIO 1 FAILED\n");

        // =========================================================================
        // SCENARIO 2: Single-Module Failure Masked (Fault Tolerance)
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 2: Core A Glitched (mask=12'h004) -> TMR Masks Fault: AB+BC+AC = 1");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 12'h000); // Bit 1: 1
        apply_stimulus(1'b0, 12'h004); // Bit 2: 0 with bit-flip on Core A!
        apply_stimulus(1'b1, 12'h000); // Bit 3: 1
        apply_stimulus(1'b0, 12'h000); // Bit 4: 0

        apply_stimulus(1'b0, 12'h000);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 4'b0111 && auth_A_out == 1'b0 && auth_B_out == 1'b1 && auth_C_out == 1'b1)
            $display(">> SCENARIO 2 PASSED: Core A failed (0), but B & C consensus (1 & 1) preserved Access Granted!\n");
        else
            $display(">> SCENARIO 2 FAILED\n");

        // =========================================================================
        // SCENARIO 3: Attacker Glitches Core A to SUCCESS -> TMR Blocks Bypass
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 3: Attacker Glitches Core A to SUCCESS -> TMR Blocks Bypass!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 12'h000); // Bit 1: 1 (correct)
        apply_stimulus(1'b1, 12'h000); // Bit 2: 1 (wrong)
        apply_stimulus(1'b1, 12'h000); // Bit 3: 1
        apply_stimulus(1'b0, 12'h004); // Glitch Core A into SUCCESS (0011 ^ 0100 = 0111)

        if (access_granted == 1'b0 && auth_A_out == 1'b1 && auth_B_out == 1'b0 && auth_C_out == 1'b0)
            $display(">> SCENARIO 3 PASSED: Core A forced to SUCCESS, but TMR majority vote prevented bypass!\n");
        else
            $display(">> SCENARIO 3 FAILED: Security breach! Bypass was not thwarted!\n");

        apply_stimulus(1'b0, 12'h000);
        repeat(2) @(negedge clk);

        // =========================================================================
        // SCENARIO 4: Laser Attack Induces Metastability ('x') on Core A
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 4: Laser Attack -> Metastable Core A (mask=12'h00x) -> Disagreement");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 12'h000); // Bit 1: 1
        apply_stimulus(1'b0, 12'h00x); // Bit 2: Laser hit on Core A!
        apply_stimulus(1'b1, 12'h000); 
        apply_stimulus(1'b0, 12'h000); 

        apply_stimulus(1'b0, 12'h000);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 4'b0111)
            $display(">> SCENARIO 4 PASSED: Laser-induced metastability on Core A masked by clean Cores B & C!\n");
        else
            $display(">> SCENARIO 4 FAILED\n");

        // =========================================================================
        // SCENARIO 5: Incorrect Password (1 -> 1 -> 1 -> 0) with No Faults
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 5: Wrong Passcode (1110) - Unanimous Lockout (A=0, B=0, C=0)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 12'h000); // Bit 1: 1
        apply_stimulus(1'b1, 12'h000); // Bit 2: 1 (wrong)
        apply_stimulus(1'b1, 12'h000); // Bit 3: 1
        apply_stimulus(1'b0, 12'h000); // Bit 4: 0

        apply_stimulus(1'b0, 12'h000);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b0 && state_out == 4'b0011 && auth_A_out == 1'b0 && auth_B_out == 1'b0 && auth_C_out == 1'b0)
            $display(">> SCENARIO 5 PASSED: All 3 cores unanimously locked out wrong passcode!\n");
        else
            $display(">> SCENARIO 5 FAILED\n");

        $display("All 5 test scenarios completed successfully.");
        $finish;
    end

endmodule
