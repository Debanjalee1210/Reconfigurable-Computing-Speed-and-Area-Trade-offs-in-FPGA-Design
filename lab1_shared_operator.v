module lab1 #
(
	parameter WIDTHIN = 16,		// Input format is Q2.14 (2 integer bits + 14 fractional bits = 16 bits)
	parameter WIDTHOUT = 32,	// Intermediate/Output format is Q7.25 (7 integer bits + 25 fractional bits = 32 bits)
	// Taylor coefficients for the first five terms in Q2.14 format
	parameter [WIDTHIN-1:0] A0 = 16'b01_00000000000000, // a0 = 1
	parameter [WIDTHIN-1:0] A1 = 16'b01_00000000000000, // a1 = 1
	parameter [WIDTHIN-1:0] A2 = 16'b00_10000000000000, // a2 = 1/2
	parameter [WIDTHIN-1:0] A3 = 16'b00_00101010101010, // a3 = 1/6
	parameter [WIDTHIN-1:0] A4 = 16'b00_00001010101010, // a4 = 1/24
	parameter [WIDTHIN-1:0] A5 = 16'b00_00000010001000  // a5 = 1/120
)
(
	input clk,
	input reset,	
	
	input i_valid,
	input i_ready,
	output reg o_valid,
	output reg o_ready,
	
	input [WIDTHIN-1:0] i_x,
	output [WIDTHOUT-1:0] o_y
);

//Output value could overflow (32-bit output, and 16-bit inputs multiplied
//together repeatedly).  Don't worry about that -- assume that only the bottom
//32 bits are of interest, and keep them.
reg [WIDTHIN-1:0] x;	// Register to hold input X
reg [WIDTHOUT-1:0] y_out;	// Register to hold output Y

// Signals for computing the y output
wire [WIDTHOUT-1:0] mult_out;
wire [WIDTHOUT-1:0] add_out;
wire [WIDTHOUT-1:0] mult_in;
wire [WIDTHIN-1:0] add_in; 

//Mux Control signals
reg mul_ctrl;
reg [2:0] add_ctrl;

//Wires to control x and y movement into flops
reg ready_for_x;
reg ready_for_y;

//Ready and Valid input signals
reg input_valid;
reg enable;

//FSM States 
reg [2:0] current_state;
reg [2:0] next_state;

//State Definitions:
//000 : get_inp  : Stay in stage, move to stage1 if valid is 1, move i_x -> x, o_ready set to 1
//001 : stage1   : if stage is get_inp, and valid is 1, we go to this stage, set mul mux to A5, add to A4
//010 : stage2   : if stage is stage1 , set mul mux to loopback, add to a3
//011 : stage3   : if stage is stage2 , set mul mux to loopback, add to a2
//100 : stage4   : if stage is stage3 , set mul mux to loopback, add to a1
//101 : stage5   : if stage is stage4 , set mul mux to loopback, add to a0
//110 : send_out : if stage is stage5 , waiting for i_ready before sending it to get_inp, move y_out -> o_y, o_valid set to 1 

//Multiplexers to pick design
mux2 mux_mult(.sel(mul_ctrl), .a({5'b0, A5, 11'b0}), .b(y_out), .out(mult_in));
mux8 mux_add(.sel(add_ctrl), .a(A4), .b(A3), .c(A2), .d(A1), .e(A0), .f(16'b0), .g(16'b0), .h(16'b0), .out(add_in));

// compute y value
mult32x16 Mult1 (.i_dataa(mult_in), 	.i_datab(x), 	.o_res(mult_out));
addr32p16 Addr1 (.i_dataa(mult_out), 	.i_datab(add_in), 	.o_res(add_out));

//Set the next stage!
always @ (current_state or input_valid or enable) begin
	case(current_state)
		3'b000 : if(input_valid) begin
			next_state = 3'b001; //Start stage 1
		end else begin
			next_state = 3'b000; //stay in get_inp
		end
		3'b001: next_state = 3'b010; 	// Move to stage 2
		3'b010: next_state = 3'b011;	// Move to stage 3
		3'b011: next_state = 3'b100;	// Move to stage 4
		3'b100: next_state = 3'b101;	// Move to stage 5
		3'b101: next_state = 3'b110;	// Move to send_out
		3'b110: if(enable) begin 	
			next_state = 3'b000; //If reciever ready, move to get_inp
		end else begin
			next_state = 3'b110; //If reciever not ready, stay in send_out stage
		end
	endcase
end
always @ (*) begin 
	input_valid = i_valid;
	enable = i_ready;
end

// Set control fsm 
always @ (*) begin
	case(current_state)
		3'b000 : begin
			o_valid = 1'b0;
			o_ready = 1'b1;
			ready_for_x = 1'b1;
		end
		3'b001: begin
			mul_ctrl = 1'b0;
			add_ctrl = 3'b000;
			o_ready = 1'b0;
			o_valid = 1'b0;
			ready_for_y = 1'b1;
		end
		3'b010: begin
			mul_ctrl = 1'b1;
			add_ctrl = 3'b001;
			o_ready = 1'b0;
			o_valid = 1'b0;			
			ready_for_y = 1'b1;
		end 
		3'b011: begin
			mul_ctrl = 1'b1;
			add_ctrl = 3'b010;
			o_valid = 1'b0;			
			o_ready = 1'b0;
			ready_for_y = 1'b1;
		end 
		3'b100: begin
			mul_ctrl = 1'b1;
			add_ctrl = 3'b011;
			o_valid = 1'b0;
			o_ready = 1'b0;
			ready_for_y = 1'b1;
		end 
		3'b101: begin
			mul_ctrl = 1'b1;
			add_ctrl = 3'b100;
			o_ready = 1'b0;
			o_valid = 1'b0;			
			ready_for_y = 1'b1;
		end 
		3'b110: begin
			o_valid = 1'b1;
			o_ready = 1'b0;
		end
		default:begin
			o_valid = 1'b0;
			o_ready = 1'b0;
		
			ready_for_x = 1'b0;			// Controls x_reg
			ready_for_y = 1'b0;			// Controls y_reg
		
			mul_ctrl = 1'b0;				// Controls multiplier mux
			add_ctrl = 3'b000;				// Controls adder mux
		end
	endcase
end
	
//Register Control 
always @ (posedge clk or posedge reset) begin
	if (reset) begin
		x <= 0;
		y_out <= 0;
	end else if (ready_for_x) begin
		x <= i_x;
	end else if (ready_for_y) begin
		y_out <= add_out;
	end

end

//State Machine clock movement (Mealy)
always @ (posedge clk or posedge reset) begin
	if (reset) begin
		current_state <= 3'b000; //get_inp
	end else begin
		current_state <= next_state;
	end
end

assign o_y = y_out;
endmodule

/*******************************************************************************************/
//
// Multiplier module for all the remaining 32x16 multiplications
module mult32x16 (
	input  [31:0] i_dataa,
	input  [15:0] i_datab,
	output [31:0] o_res
);

reg [47:0] result;

always @ (*) begin
	result = i_dataa * i_datab;
end

// The result of Q7.25 x Q2.14 is in the Q9.39 format. Therefore we need to change it
// to the Q7.25 format specified in the assignment by selecting the appropriate bits
// (i.e. dropping the most-significant 2 bits and least-significant 14 bits).
assign o_res = result[45:14];

endmodule

/*******************************************************************************************/

// Adder module for all the 32b+16b addition operations 
module addr32p16 (
	input [31:0] i_dataa,
	input [15:0] i_datab,
	output [31:0] o_res
);

// The 16-bit Q2.14 input needs to be aligned with the 32-bit Q7.25 input by zero padding
assign o_res = i_dataa + {5'b00000, i_datab, 11'b00000000000};

endmodule

/*******************************************************************************************/
/*******************************************************************************************/

module mux2 (
	input sel,
	input [31:0] a,
	input [31:0] b,
	
	output reg [31:0] out
);
always @ (*) begin
	case (sel)
		1'b0: out = a;
		1'b1: out = b;
	endcase
end

endmodule

/*******************************************************************************************/

module mux8 (
	input [2:0] sel,
	input [15:0] a,
	input [15:0] b,
	input [15:0] c,
	input [15:0] d,
	input [15:0] e,
	input [15:0] f,
	input [15:0] g,
	input [15:0] h,
	
	output reg [15:0] out
);
always @ (*) begin
	case (sel[2:0])
		3'b000: out = a;
		3'b001: out = b;
		3'b010: out = c;
		3'b011: out = d;
		3'b100: out = e;
		3'b101: out = f;
		3'b110: out = g;
		3'b111: out = h;
	endcase
end

endmodule

/*******************************************************************************************/