module RiscVAlu
(
	input clock,
	input reset,
	
	input is_op_alu, //операция с двумя регистрами
	input is_op_alu_imm, //операция с регистром и константой
	input [2:0] op_funct3, //код операции
	input [6:0] op_funct7, //код операции
	input [31:0] reg_s1, //первый регистр-операнд
	input [31:0] reg_s2, //второй регистр-операнд
	input [31:0] imm, //константа-операнд
	output [31:0] rd_alu //результат работы
);

//обработка (add, sub, xor, or, and, sll, srl, sra, slt, sltu)
//в случае лёгких инструкций вычисляем результат сразу
wire [31:0] alu_operand2 = is_op_alu_imm ? imm : reg_s2;
assign rd_alu =       op_funct3 == 3'd0 ? (is_op_alu && op_funct7[5] ? reg_s1 - alu_operand2 : reg_s1 + alu_operand2) :
					  op_funct3 == 3'd4 ? reg_s1 ^ alu_operand2 :
					  op_funct3 == 3'd6 ? reg_s1 | alu_operand2 :
					  op_funct3 == 3'd7 ? reg_s1 & alu_operand2 :
					  op_funct3 == 3'd1 ? reg_s1 << alu_operand2[4:0] :
					  op_funct3 == 3'd5 ? (op_funct7[5] ? $signed(reg_s1) >>> alu_operand2[4:0] : reg_s1 >> alu_operand2[4:0]) :
					  op_funct3 == 3'd2 ? $signed(reg_s1) < $signed(alu_operand2) :
					  op_funct3 == 3'd3 ? reg_s1 < alu_operand2 : //TODO для больших imm проверить
					  0; //невозможный результат

endmodule