module auth_fsm (
    input clk,
    input rst_n,
    input auth_in,
    input [3:0] fault_mask,
    output reg access_granted,
    output [3:0] state_out
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
        if (!rst_n)
            state <= IDLE;
        else
            state <= (next_state ^ fault_mask);
    end

    always @(*) begin
        if (state == SUCCESS)
            access_granted = 1'b1;
        else
            access_granted = 1'b0;
    end

endmodule
