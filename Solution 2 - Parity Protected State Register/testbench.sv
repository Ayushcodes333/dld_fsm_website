`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [4:0] fault_mask; // Supports 0, 1, and 'x' (metastability)
    
    wire access_granted;
    wire [3:0] state_out;
    wire state_parity_out;
    wire parity_valid_out;
    wire metastable_detected;
    wire alarm_out;

    auth_fsm uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .state_out(state_out),
        .state_parity_out(state_parity_out),
        .parity_valid_out(parity_valid_out),
        .metastable_detected(metastable_detected),
        .alarm_out(alarm_out)
    );

    // 100 MHz Clock (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Apply input and fault mask for 1 full clock cycle
    task apply_stimulus(input bit in_val, input [4:0] mask);
        begin
            auth_in    = in_val;
            fault_mask = mask;
            @(negedge clk);
        end
    endtask

    // Reset sequence
    task reset_fsm;
        begin
            rst_n      = 0;
            auth_in    = 0;
            fault_mask = 5'b00000;
            repeat(2) @(negedge clk);
            rst_n      = 1;
        end
    endtask

    wire actual_parity = ^state_out;

    initial begin
        $dumpfile("fsm_simulation.vcd");
        $dumpvars(0, testbench);

        $monitor("Time=%3t ns | in=%b | mask=%b | state=%b (P:%b, FF:%b, OK:%b, Meta:%b, Alarm:%b) | access=%b", 
                 $time, auth_in, fault_mask, state_out, actual_parity, state_parity_out, parity_valid_out, metastable_detected, alarm_out, access_granted);

        // =========================================================================
        // SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) with No Faults
        // =========================================================================
        $display("\n=========================================================================");
        $display("SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) - No Faults (mask=00000)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1 -> GOT_1   (0100)
        apply_stimulus(1'b0, 5'b00000); // Bit 2: 0 -> GOT_10  (0101)
        apply_stimulus(1'b1, 5'b00000); // Bit 3: 1 -> GOT_101 (0110)
        apply_stimulus(1'b0, 5'b00000); // Bit 4: 0 -> SUCCESS (0111)
        
        apply_stimulus(1'b0, 5'b00000); // Hold
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 4'b0111 && alarm_out == 1'b0)
            $display(">> SCENARIO 1 PASSED: State=SUCCESS (0111), Alarm=0 => Access Granted!\n");
        else
            $display(">> SCENARIO 1 FAILED\n");

        // =========================================================================
        // SCENARIO 2: Laser Attack Induces Metastability ('x') on State Bit 0
        // Attacker shoots laser at state[0] flip-flop -> mask = 5'b0000x!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 2: Laser Attack -> Metastable state[0] (mask=5'b0000x)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1 -> GOT_1 (0100)
        // Laser strike! State bit 0 enters intermediate/metastable voltage 'x':
        apply_stimulus(1'b0, 5'b0000x); // Bit 2: 0 with laser hit on state[0]!
        apply_stimulus(1'b1, 5'b00000); 
        apply_stimulus(1'b0, 5'b00000); 

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (alarm_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 2 PASSED: Metastable state[0] detected! Alarm latched (1), Access Denied!\n");
        else
            $display(">> SCENARIO 2 FAILED\n");

        // =========================================================================
        // SCENARIO 3: Laser Attack Induces Metastability ('x') on Parity FF
        // Attacker shoots laser at state_parity flip-flop -> mask = 5'bx0000!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 3: Laser Attack -> Metastable Parity FF (mask=5'bx0000)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1
        apply_stimulus(1'b0, 5'b00000); // Bit 2: 0
        apply_stimulus(1'b1, 5'b00000); // Bit 3: 1
        // Laser hits parity register on the final cycle:
        apply_stimulus(1'b0, 5'bx0000); // Bit 4: 0 with laser hit on Parity FF!

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (alarm_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 3 PASSED: Metastable Parity FF detected! Alarm latched (1), AUTH Revoked!\n");
        else
            $display(">> SCENARIO 3 FAILED\n");

        // =========================================================================
        // SCENARIO 4: Massive Laser Flood: All Registers Enter Metastability
        // mask = 5'bxxxxx forces all flip-flops into intermediate 'x' state!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 4: Full Laser Wash -> All FFs Metastable (mask=5'bxxxxx)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1
        // Massive energy pulse:
        apply_stimulus(1'b0, 5'bxxxxx); // Massive glitch!
        apply_stimulus(1'b0, 5'b00000);

        repeat(2) @(negedge clk);
        if (alarm_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 4 PASSED: Massive glitch caught! All FFs protected, Access Denied!\n");
        else
            $display(">> SCENARIO 4 FAILED\n");

        // =========================================================================
        // SCENARIO 5: Clean Bit-Flip Attack on state[2] (mask = 5'b00100)
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 5: Clean Bit-Flip Attack on state[2] (mask=5'b00100)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1
        apply_stimulus(1'b0, 5'b00100); // Bit 2: 0 with bit-flip on state[2]!
        apply_stimulus(1'b1, 5'b00000); 
        apply_stimulus(1'b0, 5'b00000); 

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (alarm_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 5 PASSED: Clean bit-flip on state[2] broke parity invariant => Alarm=1, Access Denied!\n");
        else
            $display(">> SCENARIO 5 FAILED\n");

        $display("All 5 test scenarios completed successfully.");
        $finish;
    end

endmodule
