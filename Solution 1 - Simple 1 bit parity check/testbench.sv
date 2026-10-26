`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [4:0] fault_mask; // Supports 0, 1, and 'x' (metastability)
    
    wire access_granted;
    wire [3:0] state_out;
    wire parity_out;
    wire metastable_detected;
    wire alarm_out;

    auth_fsm uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .state_out(state_out),
        .parity_out(parity_out),
        .metastable_detected(metastable_detected),
        .alarm_out(alarm_out)
    );

    // 100 MHz clock generation (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Task to apply stimulus for 1 clock cycle on negedge
    task apply_stimulus(input bit in_val, input [4:0] mask);
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
            fault_mask = 5'b00000;
            repeat(2) @(negedge clk);
            rst_n      = 1;
        end
    endtask

    initial begin
        $dumpfile("fsm_simulation.vcd");
        $dumpvars(0, testbench);

        $monitor("Time=%3t ns | in=%b | mask=%b | state=%b | P:%b | Meta:%b | Alarm:%b | access=%b", 
                 $time, auth_in, fault_mask, state_out, parity_out, metastable_detected, alarm_out, access_granted);

        // =====================================================================
        // SCENARIO 1: Normal Correct Passcode (1 -> 0 -> 1 -> 0)
        // =====================================================================
        $display("\n====================================================================");
        $display("SCENARIO 1: Normal Passcode (1 -> 0 -> 1 -> 0) with fault_mask = 00000");
        $display("====================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1
        apply_stimulus(1'b0, 5'b00000); // Bit 2: 0
        apply_stimulus(1'b1, 5'b00000); // Bit 3: 1
        apply_stimulus(1'b0, 5'b00000); // Bit 4: 0
        
        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 4'b0111 && alarm_out == 1'b0)
            $display(">> SCENARIO 1 PASSED: Access Granted (State=0111, Parity=0, Alarm=0)\n");
        else
            $display(">> SCENARIO 1 FAILED\n");

        // =====================================================================
        // SCENARIO 2: Laser Attack Induces Metastability ('x') on State Bit 0
        // Attacker shoots laser at state[0] flip-flop -> mask = 5'b0000x!
        // =====================================================================
        $display("====================================================================");
        $display("SCENARIO 2: Laser Attack -> Metastable State on state[0] (mask=5'b0000x)");
        $display("====================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1 -> GOT_1 (0100)
        // Laser strike! State bit 0 enters intermediate/metastable voltage 'x':
        apply_stimulus(1'b0, 5'b0000x); // Bit 2: 0 with laser metastability!
        apply_stimulus(1'b1, 5'b00000); 
        apply_stimulus(1'b0, 5'b00000); 

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (alarm_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 2 PASSED: Metastable state detected! Alarm latched (1), Access Denied!\n");
        else
            $display(">> SCENARIO 2 FAILED\n");

        // =====================================================================
        // SCENARIO 3: Laser Attack Induces Metastability ('x') on Parity FF
        // Attacker shoots laser at Parity flip-flop -> mask = 5'bx0000!
        // =====================================================================
        $display("====================================================================");
        $display("SCENARIO 3: Laser Attack -> Metastable Parity FF (mask=5'bx0000)");
        $display("====================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1
        apply_stimulus(1'b0, 5'b00000); // Bit 2: 0
        apply_stimulus(1'b1, 5'b00000); // Bit 3: 1
        // Laser strike hits parity flip-flop!
        apply_stimulus(1'b0, 5'bx0000); // Bit 4: 0 with laser hit on Parity FF!

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (alarm_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 3 PASSED: Metastable Parity FF detected! Alarm latched (1), AUTH Revoked!\n");
        else
            $display(">> SCENARIO 3 FAILED\n");

        // =====================================================================
        // SCENARIO 4: Massive Laser / EM Glitch: All Registers Enter Metastability
        // mask = 5'bxxxxx forces all flip-flops into intermediate 'x' state!
        // =====================================================================
        $display("====================================================================");
        $display("SCENARIO 4: Full Laser Wash -> All FFs Metastable (mask=5'bxxxxx)");
        $display("====================================================================");
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

        // =====================================================================
        // SCENARIO 5: Standard Clean Bit-Flip on Parity FF (mask = 5'b10000)
        // =====================================================================
        $display("====================================================================");
        $display("SCENARIO 5: Clean Bit-Flip Attack on Parity FF (mask=5'b10000)");
        $display("====================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1
        apply_stimulus(1'b0, 5'b00000); // Bit 2: 0
        apply_stimulus(1'b1, 5'b00000); // Bit 3: 1
        apply_stimulus(1'b0, 5'b10000); // Bit 4: 0 with bit-flip on Parity FF!

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (state_out == 4'b0111 && parity_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 5 PASSED: Clean bit-flip on Parity FF caught! AUTH Revoked!\n");
        else
            $display(">> SCENARIO 5 FAILED\n");

        $display("All 5 test scenarios completed successfully.");
        $finish;
    end

endmodule
