module auth_fsm_core (
    input clk,
    input rst_n,
    input auth_in,
    input [3:0] fault_mask,
    output [3:0] state_out,
    output auth_out
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
    assign auth_out  = (state == SUCCESS);

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

            default: next_state = LOCKED;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= (next_state ^ fault_mask);
    end

endmodule

module auth_fsm (
    input clk,
    input rst_n,
    input auth_in,
    input [7:0] fault_mask,
    output reg access_granted,
    output [3:0] state_out,
    output [3:0] state_2_out,
    output mismatch_detected,
    output metastable_detected,
    output alarm_out
);

    wire [3:0] state_1, state_2;
    wire auth_1, auth_2;
    reg alarm;

    auth_fsm_core core_1 (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[3:0]),
        .state_out(state_1),
        .auth_out(auth_1)
    );

    auth_fsm_core core_2 (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[7:4]),
        .state_out(state_2),
        .auth_out(auth_2)
    );

    wire is_metastable = $isunknown({state_1, state_2});
    wire mismatch = (!is_metastable) && ((state_1 != state_2) || (auth_1 != auth_2));
    wire consensus_auth = auth_1 & auth_2;

    assign state_out           = state_1;
    assign state_2_out         = state_2;
    assign mismatch_detected   = mismatch;
    assign metastable_detected = is_metastable;
    assign alarm_out           = alarm;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alarm <= 1'b0;
        end else begin
            if (mismatch || is_metastable)
                alarm <= 1'b1;
        end
    end

    always @(*) begin
        if (!alarm && !is_metastable && consensus_auth)
            access_granted = 1'b1;
        else
            access_granted = 1'b0;
    end

endmodule
