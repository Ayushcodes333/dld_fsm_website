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
    input [11:0] fault_mask,
    output access_granted,
    output [3:0] state_out,
    output [3:0] state_A_out,
    output [3:0] state_B_out,
    output [3:0] state_C_out,
    output auth_A_out,
    output auth_B_out,
    output auth_C_out,
    output disagreement_detected,
    output metastable_detected
);

    wire [3:0] sA, sB, sC;
    wire aA, aB, aC;

    auth_fsm_core core_A (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[3:0]),
        .state_out(sA),
        .auth_out(aA)
    );

    auth_fsm_core core_B (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[7:4]),
        .state_out(sB),
        .auth_out(aB)
    );

    auth_fsm_core core_C (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[11:8]),
        .state_out(sC),
        .auth_out(aC)
    );

    wire [3:0] voted_state = (sA & sB) | (sB & sC) | (sA & sC);
    wire voted_auth = (aA & aB) | (aB & aC) | (aA & aC);

    wire disagreement  = !((sA == sB) && (sB == sC));
    wire is_metastable = $isunknown({sA, sB, sC});

    assign state_out              = voted_state;
    assign state_A_out            = sA;
    assign state_B_out            = sB;
    assign state_C_out            = sC;
    assign auth_A_out             = aA;
    assign auth_B_out             = aB;
    assign auth_C_out             = aC;
    assign disagreement_detected  = disagreement;
    assign metastable_detected    = is_metastable;
    assign access_granted         = voted_auth && (!is_metastable);

endmodule
