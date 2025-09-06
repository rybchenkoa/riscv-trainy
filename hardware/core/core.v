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
	input         instruction_ready,
	
	output [31:0] data_address,
	output [1:0]  data_width,
	input  [31:0] data_in,
	output [31:0] data_out,
	output        data_read,
	output        data_write,
	input         data_ready
);


// этап Fetch - получение инструкции ======================================
// на нулевом этапе выдаём адрес инструкции на шину и дальше вместе с инструкцией посылаем на первый этап
// запрашиваем со следующего адреса, и если не угадали, ставим флаг неактуальности

wire [31:0] pc;           // адрес текущей инструкции
wire [31:0] stage_e_pc_next; // адрес, вычисленный инструкцией
wire [31:0] stage_f_pc;   // адрес следующей инструкции
wire stage_f_jump;        // был ли в текущей инструкции переход
wire stage_f_jam_up;      // надо ли переходить к следующей инструкции

reg stage_f_pc_actual;          // инструкция запрошена по правильному адресу
reg stage_f_instruction_repeat; // инструкция многотактовая
reg [31:0] last_instruction;    // предыдущая инструкция
wire [31:0] instruction;

always@(posedge clock or posedge reset) begin
	stage_f_pc_actual <= reset ? 0 : !stage_f_jump;
	stage_f_instruction_repeat  <= reset ? 0 : stage_f_jam_up && !stage_f_jump;
	last_instruction <= reset ? 0 : instruction;
	//pc <= stage_f_pc; это делается в модуле регистров
end

// при переходе записываем новое значение в счётчик потока
assign stage_f_pc = stage_f_jump ? stage_e_pc_next : 
					stage_f_jam_up ? pc : pc + 4;

// при переходе перезапрашиваем по сохранённому адресу, иначе по следующему
assign instruction_address = stage_d_empty ? pc : pc + 4;

// получаем из шины инструкцию или повторяем предыдущее значение, если инструкция многотактовая
assign instruction = stage_d_empty ? 0 : stage_f_instruction_repeat ? last_instruction : instruction_data;


// этап Decode - декодирование ======================================
// инструкция уже в регистре, расшифровываем и запрашиваем аргументы

wire stage_d_jam_up; // следующий этап ещё не готов
wire stage_d_empty_regs; // для этапа не записаны регистры предыдущими инструкциями
wire stage_d_empty = !stage_f_pc_actual || !instruction_ready; // этап конвейера не получил инструкцию с предыдущего этапа
wire stage_d_pause = stage_d_empty || stage_d_empty_regs; // этапу пока нельзя работать
wire stage_d_wait = stage_d_pause || stage_d_jam_up;

// регистры, которые находятся в процессе изменения, но для них ещё нет значений
wire [`REG_COUNT-1:0] dirty_regs;

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
wire use_rs1 = type_r || type_i || type_s || type_b;
wire use_rs2 = type_r || type_s || type_b;

//инструкция меняет регистр
wire write_rd_instruction = op_rd != 0 &&
							(is_op_load || is_op_alu || is_op_alu_imm 
							|| is_op_load_upper || is_op_add_upper
							|| is_op_jal || is_op_jalr);

// остановить исполнение может только отсутствие регистров
assign stage_d_empty_regs = use_rs1 && dirty_regs[op_rs1] || use_rs2 && dirty_regs[op_rs2];
assign stage_f_jam_up = !stage_d_empty && stage_d_wait;

wire enable_write_pc = !stage_d_pause || stage_f_jump;


// этап Execute - исполнение инструкции ======================================
// считаем выходное значение

// флаги этапа конвейера
reg stage_e_empty;   // нечего обрабатывать
wire stage_e_jam_up; // некуда писать
wire stage_e_pause = stage_e_empty || stage_e_jam_up;
wire stage_e_wait;

// тип инструкции
reg stage_e_is_op_load;
reg stage_e_is_op_store;
reg stage_e_is_op_alu;
reg stage_e_is_op_alu_imm;
reg stage_e_is_op_load_upper;
reg stage_e_is_op_add_upper;
reg stage_e_is_op_branch;
reg stage_e_is_op_jal;
reg stage_e_is_op_jalr;
reg stage_e_is_op_multiply;

// уточнение инструкции
reg [2:0] stage_e_funct3;
reg [6:0] stage_e_funct7;

// аргументы инструкции
reg [31:0] stage_e_immediate;
reg [31:0] stage_e_rs1;
reg [31:0] stage_e_rs2;
reg [31:0] stage_e_pc; // адрес, с которого инструкция прочитана

// выходные данные инструкции
reg [4:0] stage_e_rd_index;
reg stage_e_is_write_rd;

always@(posedge clock or posedge reset) begin
	if (reset) begin
		stage_e_is_op_load       <= 0;
		stage_e_is_op_store      <= 0;
		stage_e_is_op_alu        <= 0;
		stage_e_is_op_alu_imm    <= 0;
		stage_e_is_op_load_upper <= 0;
		stage_e_is_op_add_upper  <= 0;
		stage_e_is_op_branch     <= 0;
		stage_e_is_op_jal        <= 0;
		stage_e_is_op_jalr       <= 0;
		stage_e_is_op_multiply   <= 0;
		
		stage_e_funct3           <= 0;
		stage_e_funct7           <= 0;
		
		stage_e_immediate        <= 0;
		stage_e_rs1              <= 0;
		stage_e_rs2              <= 0;
		stage_e_pc               <= 0;
		
		stage_e_rd_index         <= 0;
		stage_e_is_write_rd      <= 0;
		
		stage_e_empty            <= 1;
	end
	else if(!stage_e_wait) begin
		stage_e_is_op_load       <= is_op_load;
		stage_e_is_op_store      <= is_op_store;
		stage_e_is_op_alu        <= is_op_alu;
		stage_e_is_op_alu_imm    <= is_op_alu_imm;
		stage_e_is_op_load_upper <= is_op_load_upper;
		stage_e_is_op_add_upper  <= is_op_add_upper;
		stage_e_is_op_branch     <= is_op_branch;
		stage_e_is_op_jal        <= is_op_jal;
		stage_e_is_op_jalr       <= is_op_jalr;
		stage_e_is_op_multiply   <= is_op_multiply;
		
		stage_e_funct3           <= op_funct3;
		stage_e_funct7           <= op_funct7;
		
		stage_e_immediate        <= immediate;
		stage_e_rs1              <= reg_s1;
		stage_e_rs2              <= reg_s2;
		stage_e_pc               <= pc;
		
		stage_e_rd_index         <= op_rd;
		stage_e_is_write_rd      <= write_rd_instruction;
		
		stage_e_empty            <= stage_d_pause || stage_f_jump;
	end
end

//чтение памяти (lb, lh, lw, lbu, lhu), I-тип
wire stage_e_data_read = stage_e_is_op_load && !stage_e_pause;

//запись памяти (sb, sh, sw), S-тип
wire stage_e_data_write = stage_e_is_op_store && !stage_e_pause;
wire[31:0] stage_e_data_out = stage_e_rs2;

//общее для чтения и записи
wire[31:0] stage_e_address = `ONLY_SIM( !(stage_e_data_read || stage_e_data_write) ? 0 : )
							stage_e_rs1 + stage_e_immediate;
//wire[1:0] stage_e_data_width = op_funct3[1:0]; //0-byte, 1-half, 2-word

//обработка арифметических операций
//(add, sub, xor, or, and, sll, srl, sra, slt, sltu)
wire [31:0] rd_alu;
RiscVAlu alu(
				.clock(clock),
				.reset(reset),
				.is_op_alu(stage_e_is_op_alu),
				.is_op_alu_imm(stage_e_is_op_alu_imm),
				.op_funct3(stage_e_funct3),
				.op_funct7(stage_e_funct7),
				.reg_s1(stage_e_rs1),
				.reg_s2(stage_e_rs2),
				.imm(stage_e_immediate),
				.rd_alu(rd_alu)
			);

`ifdef __MULTIPLY__
//(mul, mulh, mulsu, mulu, div, divu, rem, remu)
wire [31:0] rd_mul;
wire is_mul_wait;
RiscVMul mul(
				.clock(clock),
				.reset(reset),
				.enabled(!stage_e_pause && stage_e_is_op_multiply),
				.op_funct3(stage_e_funct3),
				.reg_s1(stage_e_rs1),
				.reg_s2(stage_e_rs2),
				.rd(rd_mul),
				.is_wait(is_mul_wait)
			);
`endif

//обработка upper immediate
wire [31:0] rd_load_upper = stage_e_immediate; //lui
wire [31:0] rd_add_upper = stage_e_pc + stage_e_immediate; //auipc

//обработка ветвлений
wire [31:0] pc_branch = stage_e_pc + stage_e_immediate;
wire branch_fired = stage_e_funct3 == 0 && stage_e_rs1 == stage_e_rs2 || //beq
                    stage_e_funct3 == 1 && stage_e_rs1 != stage_e_rs2 || //bne
                    stage_e_funct3 == 4 && $signed(stage_e_rs1) <  $signed(stage_e_rs2) || //blt
                    stage_e_funct3 == 5 && $signed(stage_e_rs1) >= $signed(stage_e_rs2) || //bge
                    stage_e_funct3 == 6 && stage_e_rs1 <  stage_e_rs2 || //bltu
                    stage_e_funct3 == 7 && stage_e_rs1 >= stage_e_rs2; //bgeu

//короткие и длинные переходы (jal, jalr)
wire [31:0] rd_jal = stage_e_pc + 4;
wire [31:0] pc_jal = stage_e_pc + stage_e_immediate;
wire [31:0] pc_jalr = stage_e_rs1 + stage_e_immediate;

//теперь комбинируем результат работы логики разных команд
wire [31:0] stage_e_rd_value = /*stage_e_is_op_load ? rd_load :*/
`ifdef __MULTIPLY__
						stage_e_is_op_multiply ? rd_mul :
`endif
						stage_e_is_op_alu || stage_e_is_op_alu_imm ? rd_alu :
						stage_e_is_op_load_upper ? rd_load_upper :
						stage_e_is_op_add_upper ? rd_add_upper :
						stage_e_is_op_jal || stage_e_is_op_jalr ? rd_jal
						: 0;

wire stage_e_has_rd = !stage_e_empty && (stage_e_is_op_alu || stage_e_is_op_alu_imm
					|| stage_e_is_op_load_upper || stage_e_is_op_add_upper
					|| stage_e_is_op_jal || stage_e_is_op_jalr);

wire jump_activated = stage_e_is_op_branch && branch_fired || stage_e_is_op_jal || stage_e_is_op_jalr;

//на текущем такте инструкция ещё не готова
wire stage_e_working = 0
`ifdef __MULTIPLY__
							|| is_mul_wait
`endif
							;

// отработала ли инструкция
wire stage_e_not_ready = stage_e_pause || stage_e_working;

// запрещено ли переходить к следующей инструкции
assign stage_e_wait = !stage_e_empty && (stage_e_pause || stage_e_working);

assign stage_e_pc_next = stage_e_not_ready ? stage_e_pc :
						(stage_e_is_op_branch && branch_fired) ? pc_branch :
						stage_e_is_op_jal ? pc_jal :
						stage_e_is_op_jalr ? pc_jalr :
						stage_e_pc + 4;

assign stage_f_jump = !stage_e_pause && jump_activated;

// инструкция меняет значение регистра
wire stage_e_is_rd_changed = !stage_e_working && stage_e_is_write_rd;

// какой регистр пока не могут читать следующие инструкции
wire [`REG_COUNT-1:0] stage_e_dirty_regs = 
		stage_e_working && stage_e_is_write_rd || !stage_e_empty && stage_e_is_op_load ? 
			(1 << stage_e_rd_index) : 0;

wire stage_e_rs1_equal = (stage_e_rd_index == op_rs1);
wire stage_e_rs2_equal = (stage_e_rd_index == op_rs2);

wire stage_e_rs1_used = stage_e_has_rd && stage_e_rs1_equal;
wire stage_e_rs2_used = stage_e_has_rd && stage_e_rs2_equal;

// инструкции нужна обработка на следующих этапах
wire stage_e_need_next = stage_e_is_write_rd || stage_e_is_op_load || stage_e_is_op_store;

// притормаживаем предыдущий этап
assign stage_d_jam_up = stage_e_wait;


// этап Memory - доступ к памяти ======================================
// сохраняем рассчитанные значения с прошлого этапа и подаём их на вход памяти
// при условии, что предыдущий запрос отработал
// поэтому выбор данных и подача делается на следующем этапе

reg [2:0]  stage_m_funct3; // как расширить знак прочитанного значения
reg        stage_m_data_read;
reg        stage_m_data_write;
reg [31:0] stage_m_address;
reg [31:0] stage_m_data_out; // значение для записи в память
reg [31:0] stage_m_rd_value; // значение для записи в регистр-назначение, если операция не связана с памятью
reg [4:0]  stage_m_rd_index;
reg        stage_m_is_rd_changed;
reg        stage_m_empty; // ничего не делаем, потому что предыдущий этап ничего не передал
wire       stage_m_jam_up;  // ждём, потому что память занята предыдущим запросом
wire       stage_m_wait = stage_m_jam_up; // этот этап справляется за один такт, если только другие не тормозят

always@(posedge clock or posedge reset)
begin
	if (reset) begin

		stage_m_funct3 <= 0;
		stage_m_data_read <= 0;
		stage_m_data_write <= 0;
		stage_m_address <= 0;
		stage_m_data_out <= 0;
		stage_m_rd_value <= 0;
		stage_m_rd_index <= 0;
		stage_m_is_rd_changed <= 0;
		stage_m_empty <= 1;
	end
	else if (!stage_m_wait) begin
		stage_m_funct3     <= stage_e_funct3;
		stage_m_data_read  <= stage_e_data_read;
		stage_m_data_write <= stage_e_data_write;
		stage_m_address    <= stage_e_address;
		stage_m_data_out   <= stage_e_data_out;
		stage_m_rd_value   <= stage_e_rd_value;
		stage_m_rd_index   <= stage_e_rd_index;
		stage_m_is_rd_changed <= stage_e_is_rd_changed;
		stage_m_empty      <= stage_e_not_ready;
	end
end

// отработает ли полученный запрос точно за один раз
// если это просто сохранение регистра, то да
wire stage_m_no_retry = stage_m_empty || !(stage_m_data_read || stage_m_data_write);

// должен ли текущий этап сделать запись в rd
wire stage_m_has_rd = !stage_m_empty && stage_m_is_rd_changed && !stage_m_data_read;

// надо ли пробрасывать назад
wire stage_m_rs1_equal = (stage_m_rd_index == op_rs1);// && (type_r || type_i || type_s || type_b);
wire stage_m_rs2_equal = (stage_m_rd_index == op_rs2);// && (type_r || type_s || type_b);

wire stage_m_rs1_used = stage_m_has_rd && stage_m_rs1_equal;
wire stage_m_rs2_used = stage_m_has_rd && stage_m_rs2_equal;

// m этап в любом случае не может выдать данные, прочитанные из памяти
wire [`REG_COUNT-1:0] stage_m_dirty_regs = 
		!stage_m_empty && stage_m_data_read ? 
			(1 << stage_m_rd_index) : 0;

// если предыдущий этап что-то посчитал, а у нас занято - придётся подождать
assign stage_e_jam_up = stage_m_wait && stage_e_need_next;


// этап Write Back - запись регистра ======================================
// полученное из памяти или посчитанное значение записываем в регистр
// место изменения регистра только одно, чтобы не создавать лишний порт записи

reg [2:0]  stage_wb_funct3;
reg        stage_wb_data_read;
reg        stage_wb_data_write;
reg [31:0] stage_wb_address;
reg [31:0] stage_wb_data_out; // повтор записи в память, если на предыдущем этапе не сработало
reg [4:0]  stage_wb_rd_index;
reg        stage_wb_is_rd_changed;
reg        stage_wb_empty; // ничего не делаем, если предыдущий этап ничего не передал
wire       stage_wb_wait;  // ожидание ответа от памяти

always@(posedge clock or posedge reset)
begin
	if (reset) begin
		stage_wb_funct3 <= 0;
		stage_wb_data_read <= 0;
		stage_wb_data_write <= 0;
		stage_wb_address <= 0;
		stage_wb_data_out <= 0;
		stage_wb_rd_index <= 0;
		stage_wb_is_rd_changed <= 0;
		stage_wb_empty <= 1;
	end
	else if (!stage_wb_wait) begin
		stage_wb_funct3     <= stage_m_funct3;
		stage_wb_data_read  <= stage_m_data_read;
		stage_wb_data_write <= stage_m_data_write;
		stage_wb_address    <= stage_m_address;
		stage_wb_data_out   <= stage_m_data_out;
		stage_wb_rd_index   <= stage_m_rd_index;
		stage_wb_is_rd_changed <= stage_m_is_rd_changed;
		stage_wb_empty      <= stage_m_no_retry;
	end
end

// должен ли текущий этап сделать запись в rd
wire stage_wb_has_rd = !stage_wb_empty && stage_wb_is_rd_changed;

// если память не ответила, повторяем запрос
wire stage_wb_memory_wait = !stage_wb_empty && !data_ready;

// выбираем, от какого из этапов брать данные для запроса памяти
assign data_read    = stage_wb_memory_wait ? stage_wb_data_read   : stage_m_data_read;
assign data_write   = stage_wb_memory_wait ? stage_wb_data_write  : stage_m_data_write;
assign data_out     = stage_wb_memory_wait ? stage_wb_data_out    : stage_m_data_out;
assign data_address = stage_wb_memory_wait ? stage_wb_address     : stage_m_address;
assign data_width   = stage_wb_memory_wait ? stage_wb_funct3[1:0] : stage_m_funct3[1:0];

// получаем ответ из памяти
wire [1:0] data_width_read = stage_wb_has_rd ? stage_wb_funct3[1:0] : stage_m_funct3[1:0];
wire load_signed = ~(stage_wb_has_rd ? stage_wb_funct3[2] : stage_m_funct3[2]);

wire [31:0] rd_load = `ONLY_SIM( stage_wb_empty || !stage_wb_data_read || !data_ready ? 32'hz : )
                      data_width_read == 0 ? {{24{load_signed & data_in[7]}}, data_in[7:0]} : //0-byte
                      data_width_read == 1 ? {{16{load_signed & data_in[15]}}, data_in[15:0]} : //1-half
                      data_in; //2-word

// новое значение регистра пробрасываем на предыдущий этап, чтобы не ждать
wire stage_wb_rs1_equal = (stage_wb_rd_index == op_rs1);
wire stage_wb_rs2_equal = (stage_wb_rd_index == op_rs2);

wire stage_wb_rs1_used = stage_wb_has_rd && stage_wb_rs1_equal;
wire stage_wb_rs2_used = stage_wb_has_rd && stage_wb_rs2_equal;

wire [31:0] reg_s1_file;
wire [31:0] reg_s2_file;

assign reg_s1 = `ONLY_SIM( !use_rs1 ? 32'hz : )
				stage_e_rs1_used ? stage_e_rd_value :
				stage_m_rs1_used ? stage_m_rd_value :
				stage_wb_rs1_used ? rd_load :
				reg_s1_file;

assign reg_s2 = `ONLY_SIM( !use_rs2 ? 32'hz : )
				stage_e_rs2_used ? stage_e_rd_value :
				stage_m_rs2_used ? stage_m_rd_value :
				stage_wb_rs2_used ? rd_load :
				reg_s2_file;

// здесь можно сделать внеочередное выполнение следующей инструкции
// пока текущая инструкция читает память, записать следующее значение reg[op_rd] = rd
// но пока не будем так делать, иначе потом сложно будет обрабатывать прерывания
wire [31:0] selected_rd_value = stage_wb_has_rd ? rd_load : stage_m_rd_value;
wire [4:0]  selected_rd_index = stage_wb_has_rd ? stage_wb_rd_index : stage_m_rd_index;

// если две записи в регистр, то пишем в порядке очереди
assign stage_m_jam_up = stage_wb_wait || stage_wb_has_rd && stage_m_has_rd;
wire stage_wb_enable_write_rd = !stage_wb_wait && (stage_wb_has_rd || stage_m_has_rd);

// если не успели обработать память, просим подождать
assign stage_wb_wait = stage_wb_memory_wait;

// заполняем регистры, которые сейчас нельзя использовать
wire [`REG_COUNT-1:0] stage_wb_dirty_regs = 
		stage_wb_wait && stage_wb_has_rd ? 
			(1 << stage_wb_rd_index) : 0;

assign dirty_regs = stage_e_dirty_regs | stage_m_dirty_regs | stage_wb_dirty_regs;

//набор регистров
RiscVRegs regs(
	.clock(clock),
	.reset(reset),
	
	.enable_write_pc(enable_write_pc),
	.pc_val(pc), //текущий адрес инструкции
	.pc_next(stage_f_pc), //сохраняем в регистр адрес запрошенной инструкции

	.rs1_index(op_rs1), //читаем регистры-аргументы
	.rs2_index(op_rs2),
	.rs1(reg_s1_file),
	.rs2(reg_s2_file),
	
	.enable_write_rd(stage_wb_enable_write_rd), //пишем результат обработки операции
	.rd_index(selected_rd_index),
	.rd(selected_rd_value)
);

endmodule
