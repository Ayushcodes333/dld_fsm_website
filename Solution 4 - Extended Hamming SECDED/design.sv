module auth_fsm (
    input clk,
    input rst_n,
    input auth_in,
    input [7:0] fault_mask,
    output reg access_granted,
    output [3:0] state_out,
    output [3:0] raw_state_out,
    output [3:0] hamming_parity_out,
    output single_error_detected,
    output double_error_detected,
    output metastable_detected,
    output alarm_out
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
    reg [3:0] hamming_parity;
    reg alarm;

    wire is_metastable = $isunknown({hamming_parity, state});

    wire np1 = next_state[0] ^ next_state[1] ^ next_state[3];
    wire np2 = next_state[0] ^ next_state[2] ^ next_state[3];
    wire np3 = next_state[1] ^ next_state[2] ^ next_state[3];
    wire np0 = np1 ^ np2 ^ np3 ^ next_state[0] ^ next_state[1] ^ next_state[2] ^ next_state[3];
    wire [3:0] next_parity = {np0, np3, np2, np1};

    wire s1 = hamming_parity[0] ^ state[0] ^ state[1] ^ state[3];
    wire s2 = hamming_parity[1] ^ state[0] ^ state[2] ^ state[3];
    wire s3 = hamming_parity[2] ^ state[1] ^ state[2] ^ state[3];
    wire [2:0] syndrome = {s3, s2, s1};

    wire overall_parity = hamming_parity[3] ^ hamming_parity[2] ^ hamming_parity[1] ^ hamming_parity[0] ^
                          state[3] ^ state[2] ^ state[1] ^ state[0];

    wire s_err = (!is_metastable) && (overall_parity == 1'b1);
    wire d_err = (!is_metastable) && (syndrome != 3'b000) && (overall_parity == 1'b0);

    reg [3:0] corrected_state;
    always @(*) begin
        corrected_state = state;
        if (s_err) begin
            case (syndrome)
                3'd3: corrected_state[0] = ~state[0];
                3'd5: corrected_state[1] = ~state[1];
                3'd6: corrected_state[2] = ~state[2];
                3'd7: corrected_state[3] = ~state[3];
                default: corrected_state = state;
            endcase
        end
    end

    reg is_valid_state;
    always @(*) begin
        case (corrected_state)
            IDLE, GOT_1, GOT_10, GOT_101, SUCCESS,
            ERR_1, ERR_2, ERR_3, LOCKED: is_valid_state = 1'b1;
            default:                      is_valid_state = 1'b0;
        endcase
    end
    wire corrupted_state = (!is_metastable) && (!is_valid_state);

    assign state_out              = corrected_state;
    assign raw_state_out          = state;
    assign hamming_parity_out     = hamming_parity;
    assign single_error_detected  = s_err;
    assign double_error_detected  = d_err;
    assign metastable_detected    = is_metastable;
    assign alarm_out              = alarm;

    always @(*) begin
        if (alarm || is_metastable) begin
            next_state = LOCKED;
        end else begin
            case (corrected_state)
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
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            hamming_parity <= 4'b0000;
            alarm          <= 1'b0;
        end else begin
            state          <= (next_state ^ fault_mask[3:0]);
            hamming_parity <= (next_parity ^ fault_mask[7:4]);

            if (d_err || corrupted_state || is_metastable)
                alarm <= 1'b1;
        end
    end

    always @(*) begin
        if (!alarm && !is_metastable && !d_err && !corrupted_state && (corrected_state == SUCCESS))
            access_granted = 1'b1;
        else
            access_granted = 1'b0;
    end

endmodule
