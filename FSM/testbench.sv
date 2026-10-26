`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [3:0] fault_mask;
    
    wire access_granted;
    wire [3:0] state_out;

    auth_fsm uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .state_out(state_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("fsm_simulation.vcd");
        $dumpvars(0, testbench);

        rst_n = 0;
        auth_in = 0;
        fault_mask = 4'b0000;
        
        #15 rst_n = 1;

        #10 auth_in = 1; 
        #10 auth_in = 0; 
        #10 auth_in = 1; 
        #10 auth_in = 0; 
        #20;
        
        rst_n = 0; #10 rst_n = 1;

        #10 auth_in = 1; 
        #10 auth_in = 1; 
        #10 auth_in = 1; 
        #10 auth_in = 0; 
        #20;
        
        $finish;
    end

endmodule
