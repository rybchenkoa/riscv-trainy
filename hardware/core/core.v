// ядро risc-v процессора
`include "common.vh"

// базовый набор инструкций rv32i
`define opcode_load        7'b00000_11 //l**   rd,  rs1,imm     rd = m[rs1 + imm]; load bytes
`define opcode_store       7'b01000_11 //s**   rs1, rs2,imm     m[rs1 + imm] = rs2; store bytes
`define opcode_alu         7'b01100_11 //***   rd, rs1, rs2     rd = rs1 x rs2; arithmetical
`define opcode_alu_imm     7'b00100_11 //***   rd, rs1, imm     rd = rs1 x imm; arithmetical with immediate
`define opcode_load_upper  7'b01101_11 //lui   rd, imm          rd = imm << 12; load upper imm
`define opcode_add_upper   7'b00101_11 //auipc rd, imm          rd = pc + (imm << 12); add upper imm to PC
`define opcode_branch      7'b11000_11 //b**   rs1, rs2, imm   if () pc += imm
`define opcode_jal         7'b11011_11 //jal   rd,imm   jump and link, rd = PC+4; PC += imm
`define opcode_jalr        7'b11001_11 //jalr  rd,rs1,imm   jump and link reg, rd = PC+4; PC = rs1 + imm

module RiscVCore
(
	input clock,
	input reset,
	input irq,
	
	output [31:0] instruction_address,
	input  [31:0] instruction_data,
	
	output [31:0] data_address,
	output [1:0]  data_width,
	input  [31:0] data_in,
	output [31:0] data_out,
	output        data_read,
	output        data_write
);

//получаем из шины инструкцию
wire [31:0] instruction = instruction_data;

//расшифровываем код инструкции
wire[6:0] op_code = instruction[6:0]; //код операции
wire[4:0] op_rd = instruction[11:7]; //выходной регистр
wire[2:0] op_funct3 = instruction[14:12]; //подкод операции
wire[4:0] op_rs1 = instruction[19:15]; //регистр операнд 1
wire[4:0] op_rs2 = instruction[24:20]; //регистр операнд 2
wire[6:0] op_funct7 = instruction[31:25];
wire[31:0] op_immediate_i = {{20{instruction[31]}}, instruction[31:20]}; //встроенные данные инструкции I-типа
wire[31:0] op_immediate_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]}; //встроенные данные инструкции S-типа
wire[31:0] op_immediate_u = {instruction[31:12], 12'b0};
wire[31:0] op_immediate_b = {{20{instruction[31]}}, instruction[7], 
                             instruction[30:25], instruction[11:8], 1'b0};
wire[31:0] op_immediate_j = {{12{instruction[31]}}, instruction[19:12], 
                             instruction[20], instruction[30:21], 1'b0};

//выбираем сработавшую инструкцию
wire is_op_load = op_code == `opcode_load;
wire is_op_store = op_code == `opcode_store;
wire is_op_alu = op_code == `opcode_alu;
wire is_op_alu_imm = op_code == `opcode_alu_imm;
wire is_op_load_upper = op_code == `opcode_load_upper;
wire is_op_add_upper = op_code == `opcode_add_upper;
wire is_op_branch = op_code == `opcode_branch;
wire is_op_jal = op_code == `opcode_jal;
wire is_op_jalr = op_code == `opcode_jalr;

wire error_opcode = !(is_op_load || is_op_store ||
                    is_op_alu || is_op_alu_imm ||
                    is_op_load_upper || is_op_add_upper ||
                    is_op_branch || is_op_jal || is_op_jalr);

//регистры-аргументы
wire [31:0] reg_s1;
wire [31:0] reg_s2;
wire [31:0] pc = instruction_address;
wire signed [31:0] reg_s1_signed = reg_s1;
wire signed [31:0] reg_s2_signed = reg_s2;


//чтение памяти (lb, lh, lw, lbu, lhu), I-тип
assign data_read = is_op_load;
wire load_signed = ~op_funct3[2];
wire [31:0] rd_load = op_funct3[1:0] == 0 ? {{24{load_signed & data_in[7]}}, data_in[7:0]} : //0-byte
                      op_funct3[1:0] == 1 ? {{16{load_signed & data_in[15]}}, data_in[15:0]} : //1-half
                      data_in; //2-word

//запись памяти (sb, sh, sw), S-тип
assign data_write = is_op_store;
assign data_out = is_op_store ? reg_s2 : 0;

//общее для чтения и записи
wire [31:0] address_imm = data_read ? op_immediate_i : data_write ? op_immediate_s : 0;
assign data_address = (is_op_load || is_op_store) ? reg_s1 + address_imm : 0;
assign data_width = (is_op_load || is_op_store) ? op_funct3[1:0] : 'b11; //0-byte, 1-half, 2-word

//обработка арифметических операций
//(add, sub, xor, or, and, sll, srl, sra, slt, sltu)
//(mul, mulh, mulsu, mulu, div, divu, rem, remu)
wire [31:0] rd_alu;
wire is_alu_wait;
RiscVAlu alu(
				.clock(clock),
				.reset(reset),
				.is_op_alu(is_op_alu),
				.is_op_alu_imm(is_op_alu_imm),
				.op_funct3_in(op_funct3),
				.op_funct7(op_funct7),
				.reg_s1(reg_s1),
				.reg_s2(reg_s2),
				.imm(op_immediate_i),
				.rd_alu(rd_alu),
				.is_alu_wait(is_alu_wait)
			);

//обработка upper immediate
wire [31:0] rd_load_upper = op_immediate_u; //lui
wire [31:0] rd_add_upper = pc + op_immediate_u; //auipc

//обработка ветвлений
wire [31:0] pc_branch = pc + op_immediate_b;
wire branch_fired = op_funct3 == 0 && reg_s1 == reg_s2 || //beq
                    op_funct3 == 1 && reg_s1 != reg_s2 || //bne
                    op_funct3 == 4 && reg_s1_signed <  reg_s2_signed || //blt
                    op_funct3 == 5 && reg_s1_signed >= reg_s2_signed || //bge
                    op_funct3 == 6 && reg_s1 <  reg_s2 || //bltu
                    op_funct3 == 7 && reg_s1 >= reg_s2; //bgeu

//короткие и длинные переходы (jal, jalr)
wire [31:0] rd_jal = pc + 4;
wire [31:0] pc_jal = pc + op_immediate_j;
wire [31:0] pc_jalr = reg_s1 + op_immediate_i; //здесь действительно I-тип

//теперь комбинируем результат работы логики разных команд
wire [31:0] rd_result = is_op_load ? rd_load :
						is_op_alu || is_op_alu_imm ? rd_alu :
						is_op_load_upper ? rd_load_upper :
						is_op_add_upper ? rd_add_upper :
						is_op_jal || is_op_jalr ? rd_jal
						: 0;

wire [31:0] pc_next = (is_op_branch && branch_fired) ? pc_branch :
						is_op_jal ? pc_jal :
						is_op_jalr ? pc_jalr :
						pc + 4;
						
//на текущем такте инструкция ещё не готова
wire is_wait = is_alu_wait; 
//инструкция меняет регистр
wire write_rd_instruction = is_op_load || is_op_alu || is_op_alu_imm 
							|| is_op_load_upper || is_op_add_upper
							|| is_op_jal || is_op_jalr;

//инструкция меняет значение регистра
wire is_rd_changed = (!(is_wait || op_rd == 0)) && write_rd_instruction;

//набор регистров
RiscVRegs regs(
	.clock(clock),
	.reset(reset),
	
	.enable_write_pc(!is_wait),
	.pc_val(instruction_address), //запрашиваем из памяти новую инструкцию
	.pc_next(pc_next), //сохраняем в регистр адрес следующей инструкции

	.rs1_index(op_rs1), //читаем регистры-аргументы
	.rs2_index(op_rs2),
	.rs1(reg_s1),
	.rs2(reg_s2),
	
	.enable_write_rd(is_rd_changed), //пишем результат обработки операции
	.rd_index(op_rd),
	.rd(rd_result)
);

endmodule
