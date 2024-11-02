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

reg [31:0] regs [0:`REG_COUNT-1]; //x0-x31
reg [31:0] pc;

assign pc_val = pc;
assign rs1 = regs[rs1_index];
assign rs2 = regs[rs2_index];

integer i;
always@(posedge clock or posedge reset)
begin
	if (reset == 1) begin
		for (i = 0; i < `REG_COUNT; i=i+1) regs[i] = 0;
		pc = 0;
	end
	else begin
		if (enable_write_pc) begin
			pc <= pc_next;
		end
		if (enable_write_rd) begin
			regs[rd_index] <= rd;
		end
	end
end

endmodule