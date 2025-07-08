// ядро risc-v процессора
`include "common.vh"

// базовый набор инструкций rv32i
`define opcode_load        7'b00000_11 //I //l**   rd,  rs1,imm     rd = m[rs1 + imm]; load bytes
`define opcode_store       7'b01000_11 //S //s**   rs1, rs2,imm     m[rs1 + imm] = rs2; store bytes
`define opcode_alu         7'b01100_11 //R //***   rd, rs1, rs2     rd = rs1 x rs2; arithmetical
`define opcode_alu_imm     7'b00100_11 //I //***   rd, rs1, imm     rd = rs1 x imm; arithmetical with immediate
`define opcode_load_upper  7'b01101_11 //U //lui   rd, imm          rd = imm << 12; load upper imm
`define opcode_add_upper   7'b00101_11 //U //auipc rd, imm          rd = pc + (imm << 12); add upper imm to PC
`define opcode_branch      7'b11000_11 //B //b**   rs1, rs2, imm    if (rs1 x rs2) pc += imm
`define opcode_jal         7'b11011_11 //J //jal   rd,imm   jump and link, rd = PC+4; PC += imm
`define opcode_jalr        7'b11001_11 //I //jalr  rd,rs1,imm   jump and link reg, rd = PC+4; PC = rs1 + imm

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

//этап 0 ======================================

//на нулевом этапе выдаём адрес инструкции на шину и дальше вместе с инструкцией посылаем на первый этап
wire [31:0] stage0_pc;
assign instruction_address = stage0_pc;

//этап 1 ======================================

//инструкция уже в регистре, обрабатываем
wire stage1_jam_up; //стадия остановлена следующей стадией
reg stage1_empty; //стадия конвейера не получила инструкцию с предыдущего этапа
wire stage1_pause = stage1_empty || stage1_jam_up; //стадии пока нельзя работать
//сохраняем адрес инструкции с предыдущего этапа
wire [31:0] pc; //pc <= stage0_pc

always@(posedge clock or posedge reset)
begin
	if (reset == 1) begin
		stage1_empty <= 1;
	end
	else begin
		stage1_empty <= 0;
	end
end

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
wire is_op_multiply = is_op_alu && op_funct7[0];

wire error_opcode = !(is_op_load || is_op_store ||
                    is_op_alu || is_op_alu_imm ||
                    is_op_load_upper || is_op_add_upper ||
                    is_op_branch || is_op_jal || is_op_jalr);

//какой формат у инструкции
wire type_r = is_op_alu;
wire type_i = is_op_alu_imm || is_op_load || is_op_jalr;
wire type_s = is_op_store;
wire type_b = is_op_branch;
wire type_u = is_op_load_upper || is_op_add_upper;
wire type_j = is_op_jal;

//мультиплексируем константы
wire [31:0] immediate = type_i ? op_immediate_i :
				type_s ? op_immediate_s :
				type_b ? op_immediate_b :
				type_j ? op_immediate_j :
				type_u ? op_immediate_u :
				0;

//регистры-аргументы
wire [31:0] reg_s1;
wire [31:0] reg_s2;
wire signed [31:0] reg_s1_signed = reg_s1;
wire signed [31:0] reg_s2_signed = reg_s2;


//чтение памяти (lb, lh, lw, lbu, lhu), I-тип
assign data_read = is_op_load && !stage1_pause;

//запись памяти (sb, sh, sw), S-тип
assign data_write = is_op_store && !stage1_pause;
assign data_out = reg_s2;

//общее для чтения и записи
assign data_address = (is_op_load || is_op_store) ? reg_s1 + immediate : 32'hz;
assign data_width = op_funct3[1:0]; //0-byte, 1-half, 2-word

//обработка арифметических операций
//(add, sub, xor, or, and, sll, srl, sra, slt, sltu)
wire [31:0] rd_alu;
RiscVAlu alu(
				.clock(clock),
				.reset(reset),
				.is_op_alu(is_op_alu),
				.is_op_alu_imm(is_op_alu_imm),
				.op_funct3(op_funct3),
				.op_funct7(op_funct7),
				.reg_s1(reg_s1),
				.reg_s2(reg_s2),
				.imm(immediate),
				.rd_alu(rd_alu)
			);

`ifdef __MULTIPLY__
//(mul, mulh, mulsu, mulu, div, divu, rem, remu)
wire [31:0] rd_mul;
wire is_mul_wait;
RiscVMul mul(
				.clock(clock),
				.reset(reset),
				.enabled(!stage1_pause && is_op_multiply),
				.op_funct3(op_funct3),
				.reg_s1(reg_s1),
				.reg_s2(reg_s2),
				.rd_mul(rd_mul),
				.is_mul_wait(is_mul_wait)
			);
`endif

//обработка upper immediate
wire [31:0] rd_load_upper = immediate; //lui
wire [31:0] rd_add_upper = pc + immediate; //auipc

//обработка ветвлений
wire [31:0] pc_branch = pc + immediate;
wire branch_fired = op_funct3 == 0 && reg_s1 == reg_s2 || //beq
                    op_funct3 == 1 && reg_s1 != reg_s2 || //bne
                    op_funct3 == 4 && reg_s1_signed <  reg_s2_signed || //blt
                    op_funct3 == 5 && reg_s1_signed >= reg_s2_signed || //bge
                    op_funct3 == 6 && reg_s1 <  reg_s2 || //bltu
                    op_funct3 == 7 && reg_s1 >= reg_s2; //bgeu

//короткие и длинные переходы (jal, jalr)
wire [31:0] rd_jal = pc + 4;
wire [31:0] pc_jal = pc + immediate;
wire [31:0] pc_jalr = reg_s1 + immediate;

//теперь комбинируем результат работы логики разных команд
wire [31:0] stage1_rd = /*is_op_load ? rd_load :*/
`ifdef __MULTIPLY__
						is_op_multiply ? rd_mul :
`endif
						is_op_alu || is_op_alu_imm ? rd_alu :
						is_op_load_upper ? rd_load_upper :
						is_op_add_upper ? rd_add_upper :
						is_op_jal || is_op_jalr ? rd_jal
						: 0;

//на текущем такте инструкция ещё не готова
wire stage1_working = 0
`ifdef __MULTIPLY__
							|| is_mul_wait
`endif
							;
//запрещено ли переходить к следующей инструкции
wire stage1_wait = stage1_pause || stage1_working;

assign stage0_pc = stage1_wait ? pc :
						(is_op_branch && branch_fired) ? pc_branch :
						is_op_jal ? pc_jal :
						is_op_jalr ? pc_jalr :
						pc + 4;

//инструкция меняет регистр
wire write_rd_instruction = is_op_load || is_op_alu || is_op_alu_imm 
							|| is_op_load_upper || is_op_add_upper
							|| is_op_jal || is_op_jalr;

//инструкция меняет значение регистра
wire is_rd_changed = (!(stage1_working || op_rd == 0)) && write_rd_instruction;

//этап 2 ======================================
//полученное из памяти значение записываем в регистр
//место изменения регистра только одно, чтобы не возникало лишних задержек
reg [2:0] stage2_funct3;
reg stage2_is_op_load;
reg [31:0] stage2_rd;
reg[4:0] stage2_op_rd;
reg stage2_is_rd_changed;
reg stage2_empty; //ничего не делаем, потому что предыдущая стадия ничего не передала

always@(posedge clock or posedge reset)
begin
	if (reset) begin
		stage2_funct3 <= 0;
		stage2_is_op_load <= 0;
		stage2_rd <= 0;
		stage2_op_rd <= 0;
		stage2_is_rd_changed <= 0;
		stage2_empty <= 0;
	end
	else begin
		stage2_funct3 <= op_funct3;
		stage2_is_op_load <= is_op_load;
		stage2_rd <= stage1_rd;
		stage2_op_rd <= op_rd;
		stage2_is_rd_changed <= is_rd_changed;
		stage2_empty <= stage1_wait;
	end
end

wire load_signed = ~stage2_funct3[2];
wire [31:0] rd_load = stage2_funct3[1:0] == 0 ? {{24{load_signed & data_in[7]}}, data_in[7:0]} : //0-byte
                      stage2_funct3[1:0] == 1 ? {{16{load_signed & data_in[15]}}, data_in[15:0]} : //1-half
                      data_in; //2-word

wire [31:0] stage2_rd_result = stage2_is_op_load ? rd_load : stage2_rd;

//если пишем регистр, просим подождать предыдущие стадии
wire stage2_rs1_equal = (stage2_op_rd == op_rs1) && (type_r || type_i || type_s || type_b);
wire stage2_rs2_equal = (stage2_op_rd == op_rs2) && (type_r || type_s || type_b);
//пока что память отвечает мгновенно
assign stage1_jam_up = 0;

wire [31:0] reg_s1_file;
wire [31:0] reg_s2_file;

assign reg_s1 = (stage2_is_rd_changed && stage2_rs1_equal) ? stage2_rd_result : reg_s1_file;
assign reg_s2 = (stage2_is_rd_changed && stage2_rs2_equal) ? stage2_rd_result : reg_s2_file;

//набор регистров
RiscVRegs regs(
	.clock(clock),
	.reset(reset),
	
	.enable_write_pc(!stage1_wait),
	.pc_val(pc), //текущий адрес инструкции
	.pc_next(stage0_pc), //сохраняем в регистр адрес следующей инструкции

	.rs1_index(op_rs1), //читаем регистры-аргументы
	.rs2_index(op_rs2),
	.rs1(reg_s1_file),
	.rs2(reg_s2_file),
	
	.enable_write_rd(stage2_is_rd_changed && !stage2_empty), //пишем результат обработки операции
	.rd_index(stage2_op_rd),
	.rd(stage2_rd_result)
);

endmodule
