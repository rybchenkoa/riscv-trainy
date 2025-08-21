// регистры процессора
`include "common.vh"

module RiscVRegs
(
	input clock,
	input reset,

	input enable_write_pc,
	input [31:0] pc_next,
	output [31:0] pc_val,

	input [4:0] rs1_index,
	input [4:0] rs2_index,
	output [31:0] rs1,
	output [31:0] rs2,

	input enable_write_rd,
	input [4:0] rd_index,
	input [31:0] rd
);

reg [31:0] regs [1:`REG_COUNT-1]; //x0-x31
reg [31:0] pc;

assign pc_val = pc;
assign rs1 = rs1_index == 0 ? 0 : regs[rs1_index];
assign rs2 = rs2_index == 0 ? 0 : regs[rs2_index];

`ifdef SIMULATION
integer i;
initial begin
	for (i = 1; i < `REG_COUNT; i = i + 1) begin
		regs[i] = 0;
	end
end

wire [31:0] ra = regs[1];
wire [31:0] sp = regs[2];
wire [31:0] gp = regs[3];
wire [31:0] tp = regs[4];
wire [31:0] t0 = regs[5];
wire [31:0] t1 = regs[6];
wire [31:0] t2 = regs[7];
wire [31:0] s0_fp = regs[8];
wire [31:0] s1 = regs[9];
wire [31:0] a0 = regs[10];
wire [31:0] a1 = regs[11];
wire [31:0] a2 = regs[12];
wire [31:0] a3 = regs[13];
wire [31:0] a4 = regs[14];
wire [31:0] a5 = regs[15];
`endif

always@(posedge clock or posedge reset)
begin
	if (reset == 1) begin
		pc = 0;
	end
	else begin
		if (enable_write_pc) begin
			pc <= pc_next;
		end
	end
end

always@(posedge clock)
begin
	//regs[enable_write_rd ? 0 : rd_index] <= rd; //так более красиво, но занимает больше места
	if (enable_write_rd) begin
		regs[rd_index] <= rd;
	end
end

endmodule