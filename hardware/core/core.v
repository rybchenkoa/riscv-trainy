// ядро risc-v процессора

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

`ifdef __RV32E__
    `define REG_COUNT 16 //для embedded число регистров меньше
`else
    `define REG_COUNT 32
`endif

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

//базовый набор регистров
reg [31:0] regs [0:`REG_COUNT-1]; //x0-x31
reg [31:0] pc;

//достаём из pc адрес инструкции и посылаем в шину
assign instruction_address = pc;

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

//получаем регистры из адресов
//wire [31:0] reg_d = regs[op_rd];
wire [31:0] reg_s1 = regs[op_rs1];
wire [31:0] reg_s2 = regs[op_rs2];
wire signed [31:0] reg_s1_signed = reg_s1;
wire signed [31:0] reg_s2_signed = reg_s2;


//чтение памяти (lb, lh, lw, lbu, lhu), I-тип
assign data_read = is_op_load;
wire load_signed = ~op_funct3[2];
wire [31:0] load_data = op_funct3[1:0] == 0 ? {{24{load_signed & data_in[7]}}, data_in[7:0]} : //0-byte
                        op_funct3[1:0] == 1 ? {{16{load_signed & data_in[15]}}, data_in[15:0]} : //1-half
                        data_in; //2-word

//запись памяти (sb, sh, sw), S-тип
assign data_write = is_op_store;
assign data_out = is_op_store ? reg_s2 : 0;

//общее для чтения и записи
wire [31:0] address_imm = data_read ? op_immediate_i : data_write ? op_immediate_s : 0;
assign data_address = (is_op_load || is_op_store) ? reg_s1 + address_imm : 0;
assign data_width = (is_op_load || is_op_store) ? op_funct3[1:0] : 'b11; //0-byte, 1-half, 2-word

//обработка арифметических операций (add, sub, xor, or, and, sll, srl, sra, slt, sltu)
wire [31:0] alu_operand2 = is_op_alu ? reg_s2 : is_op_alu_imm ? op_immediate_i : 0;
wire [31:0] alu_result = op_funct3 == 0 ? (is_op_alu && op_funct7[5] ? reg_s1 - alu_operand2 : reg_s1 + alu_operand2) :
                         op_funct3 == 4 ? reg_s1 ^ alu_operand2 :
                         op_funct3 == 6 ? reg_s1 | alu_operand2 :
                         op_funct3 == 7 ? reg_s1 & alu_operand2 :
                         op_funct3 == 1 ? reg_s1 << alu_operand2[4:0] :
                         op_funct3 == 5 ? (op_funct7[5] ? reg_s1_signed >>> alu_operand2[4:0] : reg_s1 >> alu_operand2[4:0]) :
                         op_funct3 == 2 ? reg_s1_signed < $signed(alu_operand2) :
                         op_funct3 == 3 ? reg_s1 < alu_operand2 : //TODO для больших imm проверить
                         0; //невозможный результат

//обработка upper immediate
wire [31:0] load_upper_result = op_immediate_u; //lui
wire [31:0] add_upper_result = pc + op_immediate_u; //auipc

//обработка ветвлений
wire [31:0] branch_pc = pc + op_immediate_b;
wire branch_fired = op_funct3 == 0 && reg_s1 == reg_s2 || //beq
                    op_funct3 == 1 && reg_s1 != reg_s2 || //bne
                    op_funct3 == 4 && reg_s1_signed <  reg_s2_signed || //blt
                    op_funct3 == 5 && reg_s1_signed >= reg_s2_signed || //bge
                    op_funct3 == 6 && reg_s1 <  reg_s2 || //bltu
                    op_funct3 == 7 && reg_s1 >= reg_s2; //bgeu

//короткие и длинные переходы (jal, jalr)
wire [31:0] jal_result = pc + 4;
wire [31:0] jal_pc = pc + op_immediate_j;
wire [31:0] jalr_pc = reg_s1 + op_immediate_i; //здесь действительно I-тип

//теперь комбинируем результат работы логики разных команд
integer i;
always@(posedge clock or posedge reset)
begin
	if (reset == 1) begin
		for (i = 0; i < `REG_COUNT; i=i+1) regs[i] = 0;
		pc = 0;
	end else begin
		regs[op_rd] <= op_rd == 0 ? 0 : //x0 = 0
					   is_op_load ? load_data :
					   is_op_alu || is_op_alu_imm ? alu_result :
					   is_op_load_upper ? load_upper_result :
					   is_op_add_upper ? add_upper_result :
					   is_op_jal || is_op_jalr ? jal_result :
					   regs[op_rd];

		pc <= (is_op_branch && branch_fired) ? branch_pc :
			  is_op_jal ? jal_pc :
			  is_op_jalr ? jalr_pc :
			  pc + 4;
	end
end
endmodule
