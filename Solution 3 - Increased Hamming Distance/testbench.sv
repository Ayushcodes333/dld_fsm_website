`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [4:0] fault_mask;
    
    wire access_granted;
    wire [4:0] state_out;
    wire in_between_trap_out;

    auth_fsm uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .state_out(state_out),
        .in_between_trap_out(in_between_trap_out)
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

    initial begin
        $dumpfile("fsm_simulation.vcd");
        $dumpvars(0, testbench);

        $monitor("Time=%3t ns | in=%b | mask=%b | state=%b (In-Between Trap:%b) | access=%b", 
                 $time, auth_in, fault_mask, state_out, in_between_trap_out, access_granted);

        // =========================================================================
        // SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) with No Faults
        // =========================================================================
        $display("\n=========================================================================");
        $display("SCENARIO 1: Correct Password (1 -> 0 -> 1 -> 0) - No Faults (mask=00000)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1 -> GOT_1   (00011)
        apply_stimulus(1'b0, 5'b00000); // Bit 2: 0 -> GOT_10  (00101)
        apply_stimulus(1'b1, 5'b00000); // Bit 3: 1 -> GOT_101 (00110)
        apply_stimulus(1'b0, 5'b00000); // Bit 4: 0 -> SUCCESS (01001)
        
        apply_stimulus(1'b0, 5'b00000); // Hold & observe
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && state_out == 5'b01001)
            $display(">> SCENARIO 1 PASSED: Reached SUCCESS (01001) with d>=2 => Access Granted!\n");
        else
            $display(">> SCENARIO 1 FAILED\n");

        // =========================================================================
        // SCENARIO 2: Single-Bit Flip Attack on state[0] (mask=5'b00001)
        // Flips state from GOT_1 (00011) into In-Between state (00010)
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 2: Single-Bit Flip Attack on state[0] (mask=5'b00001)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1 -> GOT_1 (00011)
        // Inject single-bit flip on bit 0:
        apply_stimulus(1'b0, 5'b00001); // Bit 2: 0 with bit-flip on state[0]!
        apply_stimulus(1'b1, 5'b00000); 
        apply_stimulus(1'b0, 5'b00000); 

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (state_out == 5'b11110 && access_granted == 1'b0)
            $display(">> SCENARIO 2 PASSED: 1-bit flip landed in In-Between state => Trapped in TRAP_LOCKED (11110), Access Denied!\n");
        else
            $display(">> SCENARIO 2 FAILED\n");

        // =========================================================================
        // SCENARIO 3: Single-Bit Flip Attack on state[2] (mask=5'b00100)
        // Flips state from GOT_10 (00101) into In-Between state (00001)
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 3: Single-Bit Flip Attack on state[2] (mask=5'b00100)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1 -> GOT_1 (00011)
        apply_stimulus(1'b0, 5'b00000); // Bit 2: 0 -> GOT_10 (00101)
        // Inject single-bit flip on bit 2:
        apply_stimulus(1'b1, 5'b00100); // Bit 3: 1 with bit-flip on state[2]!
        apply_stimulus(1'b0, 5'b00000); 

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (state_out == 5'b11110 && access_granted == 1'b0)
            $display(">> SCENARIO 3 PASSED: 1-bit flip landed in In-Between state => Trapped in TRAP_LOCKED (11110), Access Denied!\n");
        else
            $display(">> SCENARIO 3 FAILED\n");

        // =========================================================================
        // SCENARIO 4: Attacker tries 1-bit glitch from ERR_3 (10001) towards SUCCESS (01001)
        // Hamming distance between ERR_3 and SUCCESS is 2 (bits 3 and 4 differ).
        // A single-bit flip cannot reach SUCCESS; it lands in an in-between state!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 4: 1-Bit Glitch Attack cannot bridge Hamming Distance to SUCCESS");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1
        apply_stimulus(1'b1, 5'b00000); // Bit 2: 1 (wrong) -> ERR_2 (01100)
        apply_stimulus(1'b1, 5'b00000); // Bit 3: 1 -> ERR_3 (10001)
        // Next state from ERR_3 is LOCKED (10010).
        // Attacker attempts a 1-bit flip on bit 1 (5'b00010) or bit 3 (5'b01000):
        apply_stimulus(1'b0, 5'b00010); // Glitch 1 bit

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (state_out != 5'b01001 && access_granted == 1'b0)
            $display(">> SCENARIO 4 PASSED: 1-bit glitch cannot reach SUCCESS (d=2). Trapped, Access Denied!\n");
        else
            $display(">> SCENARIO 4 FAILED\n");

        // =========================================================================
        // SCENARIO 5: Standard Incorrect Password (1 -> 1 -> 1 -> 0) with No Faults
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 5: Incorrect Password (1 -> 1 -> 1 -> 0) with No Faults");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 5'b00000); // Bit 1: 1 -> GOT_1 (00011)
        apply_stimulus(1'b1, 5'b00000); // Bit 2: 1 -> ERR_2 (01100)
        apply_stimulus(1'b1, 5'b00000); // Bit 3: 1 -> ERR_3 (10001)
        apply_stimulus(1'b0, 5'b00000); // Bit 4: 0 -> LOCKED (10010)

        apply_stimulus(1'b0, 5'b00000);
        repeat(2) @(negedge clk);
        if (state_out == 5'b10010 && access_granted == 1'b0)
            $display(">> SCENARIO 5 PASSED: Reached normal LOCKED state (10010) => Access Denied!\n");
        else
            $display(">> SCENARIO 5 FAILED\n");

        $display("All 5 test scenarios completed successfully.");
        $finish;
    end

endmodule
