`timescale 1ns / 1ps

module testbench;
    reg clk, rst_n, auth_in;
    reg [3:0] fault_mask;
    wire access_granted, dmr_err, parity_err, tmr_err, ecc_err, ecc_corr, ecc_unc, attack_detected;
    wire [2:0] tmr_faulty;
    wire [3:0] state_out, voted_state, ecc_pos, ecc_state;

    integer s, m, pass = 0, fail = 0, false_alarms = 0;
    integer n_faults = 0, dmr_hits = 0, par_hits = 0, tmr_hits = 0, ecc_hits = 0, any_hits = 0;
    integer tmr_fix = 0, ecc_fix = 0, ecc_unc_n = 0;

    secure_fsm_top dut (.clk(clk), .rst_n(rst_n), .auth_in(auth_in), .fault_mask(fault_mask),
        .access_granted(access_granted), .state_out(state_out),
        .dmr_err(dmr_err), .parity_err(parity_err),
        .tmr_err(tmr_err), .tmr_faulty(tmr_faulty), .voted_state(voted_state),
        .ecc_err(ecc_err), .ecc_corr(ecc_corr), .ecc_unc(ecc_unc),
        .ecc_pos(ecc_pos), .ecc_state(ecc_state), .attack_detected(attack_detected));

    initial begin clk = 0; forever #5 clk = ~clk; end

    function integer wt(input [3:0] x);
        wt = x[0] + x[1] + x[2] + x[3];
    endfunction

    task reset_fsm;
        begin rst_n = 0; auth_in = 0; fault_mask = 0; @(posedge clk); #1; rst_n = 1; end
    endtask

    task step(input pin_bit, input [3:0] mask);
        begin auth_in = pin_bit; fault_mask = mask; @(posedge clk); #1; fault_mask = 0; end
    endtask

    task goto_state(input integer idx);
        begin
            reset_fsm();
            case (idx)
                1: step(1,0);                                   
                2: begin step(1,0); step(0,0); end              
                3: begin step(1,0); step(0,0); step(1,0); end   
                4: begin step(1,0); step(0,0); step(1,0); step(0,0); end // SUCCESS
                5: step(0,0);                                   
                6: begin step(0,0); step(0,0); end              
                7: begin step(0,0); step(0,0); step(0,0); end   
                8: begin step(0,0); step(0,0); step(0,0); step(0,0); end // LOCKED
                default: ;                                      // IDLE
            endcase
        end
    endtask

    task check_clean(input [255:0] name);
        begin
            if (attack_detected) begin
                false_alarms = false_alarms + 1; fail = fail + 1;
                $display("  FAIL %0s: false alarm (state=%b)", name, state_out);
            end else pass = pass + 1;
        end
    endtask

    task check_fault(input [3:0] mask);
        reg [3:0] exp;
        reg ok;
        begin
            exp = state_out ^ mask;
            n_faults = n_faults + 1;
            if (dmr_err)    dmr_hits = dmr_hits + 1;
            if (parity_err) par_hits = par_hits + 1;
            if (tmr_err)    tmr_hits = tmr_hits + 1;
            if (ecc_err)    ecc_hits = ecc_hits + 1;
            if (attack_detected) any_hits = any_hits + 1;
            if (voted_state === exp) tmr_fix = tmr_fix + 1;
            if (ecc_state === exp)   ecc_fix = ecc_fix + 1;
            if (ecc_unc)             ecc_unc_n = ecc_unc_n + 1;

            ok = (dmr_err === 1'b1) && (parity_err === ^mask)
              && (tmr_err === 1'b1) && (tmr_faulty === 3'b001) && (voted_state === exp)
              && (ecc_err === 1'b1);
            if (wt(mask) == 1)
                ok = ok && (ecc_corr === 1'b1) && (ecc_unc === 1'b0) && (ecc_pos === mask) && (ecc_state === exp);
            else
                ok = ok && (ecc_corr === 1'b0) && (ecc_unc === 1'b1) && (ecc_pos === 4'b0000);

            if (ok) pass = pass + 1;
            else begin
                fail = fail + 1;
                $display("  FAIL mask=%b state=%b exp=%b | dmr=%b par=%b tmr=%b/%b/%b ecc=%b corr=%b unc=%b pos=%b",
                         mask, state_out, exp, dmr_err, parity_err, tmr_err, tmr_faulty, voted_state,
                         ecc_err, ecc_corr, ecc_unc, ecc_pos);
            end
        end
    endtask

    initial begin
        $dumpfile("detect.vcd"); $dumpvars(0, testbench);

        $display("=== [1] Fault-free runs: expect NO detection ===");
        reset_fsm(); check_clean("reset");
        step(1,0); check_clean("GOT_1");  step(0,0); check_clean("GOT_10");
        step(1,0); check_clean("GOT_101"); step(0,0); check_clean("SUCCESS");
        $display("  correct PIN : state=%b access=%b", state_out, access_granted);
        reset_fsm();
        repeat (5) begin step(0,0); check_clean("wrong PIN"); end
        $display("  wrong PIN   : state=%b access=%b", state_out, access_granted);

        $display("=== [2] All 15 masks injected from IDLE ===");
        $display("  mask  state | DMR PAR TMR(copy) ECC  class        located  corrected");
        for (m = 1; m < 16; m = m + 1) begin
            goto_state(0); step(1, m[3:0]); check_fault(m[3:0]);
            $display("  %b  %b  |  %b   %b   %b(%b)    %b    %-11s  %b     %b",
                     m[3:0], state_out, dmr_err, parity_err, tmr_err, tmr_faulty, ecc_err,
                     ecc_corr ? "1-bit fixed" : "uncorrect.", ecc_pos, ecc_state);
        end

        $display("=== [3] All 15 masks from every state (9 states x 15) ===");
        for (s = 0; s < 9; s = s + 1)
            for (m = 1; m < 16; m = m + 1) begin
                goto_state(s); check_clean("pre-fault");
                step(1, m[3:0]); check_fault(m[3:0]);
            end
        $display("  done: %0d faults injected so far", n_faults);

        $display("=== [4] Bypass: LOCKED + mask 0100 -> SUCCESS ===");
        goto_state(8); check_clean("LOCKED");
        step(0, 4'b0100); check_fault(4'b0100);
        $display("  attacked: state=%b access=%b | ECC corrected=%b TMR voted=%b",
                 state_out, access_granted, ecc_state, voted_state);

        $display("=== [5] Even-weight bypass: ERR_1 path + mask 1111 -> SUCCESS ===");
        goto_state(0); step(0, 4'b1111); check_fault(4'b1111);
        $display("  attacked: state=%b access=%b | PAR=%b DMR=%b ECC_unc=%b TMR voted=%b",
                 state_out, access_granted, parity_err, dmr_err, ecc_unc, voted_state);

        $display("=== [6] Monte Carlo Randomized Stress Test (50 Iterations) ===");
        for (s = 0; s < 50; s = s + 1) begin
            goto_state($urandom_range(0, 8)); 
            m = $urandom_range(1, 15);
            step($urandom_range(0, 1), m[3:0]);
            check_fault(m[3:0]);
        end
      
        $display("\n=== SUMMARY ===");
        $display("  checks pass/fail     : %0d / %0d", pass, fail);
        $display("  false alarms         : %0d", false_alarms);
        $display("  faults injected      : %0d", n_faults);
        $display("  DMR detected         : %0d", dmr_hits);
        $display("  Parity detected      : %0d", par_hits);
        $display("  TMR detected         : %0d  (state corrected by vote: %0d)", tmr_hits, tmr_fix);
        $display("  ECC(8,4) detected    : %0d  (corrected+located: %0d, uncorrectable: %0d)", ecc_hits, ecc_fix, ecc_unc_n);
        $display("  Combined detected    : %0d", any_hits);
        $finish;
    end
endmodule
