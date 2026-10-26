`timescale 1ns / 1ps

module auth_fsm (
    input clk,
    input rst_n,
    input auth_in,
    input [3:0] fault_mask,
    output reg access_granted,
    output [3:0] state_out,
    output reg parity_q,           
    output reg [3:0] ecc_q         
);
    parameter IDLE    = 4'b0000;
    parameter GOT_1   = 4'b0100;
    parameter GOT_10  = 4'b0101;
    parameter GOT_101 = 4'b0110;
    parameter SUCCESS = 4'b0111;
    parameter ERR_1   = 4'b1000;
    parameter ERR_2   = 4'b1001;
    parameter ERR_3   = 4'b1010;
    parameter LOCKED  = 4'b0011;

    reg [3:0] state, next_state;
    assign state_out = state;

    function [3:0] enc(input [3:0] d);
        reg p1, p2, p4;
        begin
            p1 = d[0] ^ d[1] ^ d[3];
            p2 = d[0] ^ d[2] ^ d[3];
            p4 = d[1] ^ d[2] ^ d[3];
            enc = {^{d, p1, p2, p4}, p4, p2, p1};
        end
    endfunction

    always @(*) begin
        case (state)
            IDLE:    next_state = (auth_in)  ? GOT_1   : ERR_1;
            GOT_1:   next_state = (!auth_in) ? GOT_10  : ERR_2;
            GOT_10:  next_state = (auth_in)  ? GOT_101 : ERR_3;
            GOT_101: next_state = (!auth_in) ? SUCCESS : LOCKED;
            ERR_1:   next_state = ERR_2;
            ERR_2:   next_state = ERR_3;
            ERR_3:   next_state = LOCKED;
            SUCCESS: next_state = SUCCESS;
            LOCKED:  next_state = LOCKED;
            default: next_state = IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            parity_q <= 1'b0;                 
            ecc_q    <= 4'b0000;              
        end else begin
            state    <= next_state ^ fault_mask;
            parity_q <= ^next_state;
            ecc_q    <= enc(next_state);
        end
    end

    always @(*) access_granted = (state == SUCCESS);
endmodule

module dmr_detector (
    input  [3:0] state_a,
    input  [3:0] state_b,
    output       dmr_err
);
    assign dmr_err = (state_a != state_b);
endmodule

module parity_detector (
    input  [3:0] state_out,
    input        parity_q,
    output       parity_err
);
    assign parity_err = (^state_out) ^ parity_q;
endmodule

module tmr_voter (
    input  [3:0] a, b, c,
    output [3:0] voted,
    output       tmr_err,
    output [2:0] faulty
);
    assign voted   = (a & b) | (a & c) | (b & c);
    assign tmr_err = (a != b) | (a != c) | (b != c);
    assign faulty  = {c != voted, b != voted, a != voted};
endmodule

module ecc_detector (
    input  [3:0] state_out,
    input  [3:0] ecc_q,
    output       ecc_err,
    output       ecc_corr,
    output       ecc_unc,
    output [3:0] ecc_pos,
    output [3:0] ecc_state
);
    wire p1 = state_out[0] ^ state_out[1] ^ state_out[3];
    wire p2 = state_out[0] ^ state_out[2] ^ state_out[3];
    wire p4 = state_out[1] ^ state_out[2] ^ state_out[3];
    wire [2:0] syn = {p4, p2, p1} ^ ecc_q[2:0];         
    wire overall   = (^state_out) ^ (^ecc_q[2:0]) ^ ecc_q[3];  

    reg [3:0] pos;
    always @(*) case (syn)
        3'd3: pos = 4'b0001;
        3'd5: pos = 4'b0010;
        3'd6: pos = 4'b0100;
        3'd7: pos = 4'b1000;
        default: pos = 4'b0000;
    endcase

    assign ecc_err   = (syn != 3'd0) | overall;
    assign ecc_corr  = overall & (pos != 4'b0000);        
    assign ecc_unc   = ecc_err & ~ecc_corr;               
    assign ecc_pos   = ecc_corr ? pos : 4'b0000;
    assign ecc_state = state_out ^ ecc_pos;
endmodule

module secure_fsm_top (
    input clk,
    input rst_n,
    input auth_in,
    input [3:0] fault_mask,
    output access_granted,
    output [3:0] state_out,
    output dmr_err,
    output parity_err,
    output tmr_err,
    output [2:0] tmr_faulty,
    output [3:0] voted_state,
    output ecc_err,
    output ecc_corr,
    output ecc_unc,
    output [3:0] ecc_pos,
    output [3:0] ecc_state,
    output attack_detected
);
    wire [3:0] state_b, state_c, ecc_a;
    wire       parity_a;

    auth_fsm fsm_a (.clk(clk), .rst_n(rst_n), .auth_in(auth_in),
                    .fault_mask(fault_mask), .access_granted(access_granted),
                    .state_out(state_out), .parity_q(parity_a), .ecc_q(ecc_a));

    auth_fsm fsm_b (.clk(clk), .rst_n(rst_n), .auth_in(auth_in),
                    .fault_mask(4'b0000), .access_granted(),
                    .state_out(state_b), .parity_q(), .ecc_q());

    auth_fsm fsm_c (.clk(clk), .rst_n(rst_n), .auth_in(auth_in),
                    .fault_mask(4'b0000), .access_granted(),
                    .state_out(state_c), .parity_q(), .ecc_q());

    dmr_detector    u_dmr (.state_a(state_out), .state_b(state_b), .dmr_err(dmr_err));
    parity_detector u_par (.state_out(state_out), .parity_q(parity_a), .parity_err(parity_err));
    tmr_voter       u_tmr (.a(state_out), .b(state_b), .c(state_c),
                           .voted(voted_state), .tmr_err(tmr_err), .faulty(tmr_faulty));
    ecc_detector    u_ecc (.state_out(state_out), .ecc_q(ecc_a), .ecc_err(ecc_err),
                           .ecc_corr(ecc_corr), .ecc_unc(ecc_unc),
                           .ecc_pos(ecc_pos), .ecc_state(ecc_state));

    assign attack_detected = dmr_err | parity_err | tmr_err | ecc_err;
endmodule
