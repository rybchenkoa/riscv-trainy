module RiscVAlu
(
	input clock,
	input reset,
	
	input is_op_alu, //операция с двумя регистрами
	input is_op_alu_imm, //операция с регистром и константой
	input [2:0] op_funct3_in, //код операции
	input [6:0] op_funct7, //код операции
	input [31:0] reg_s1, //первый регистр-операнд
	input [31:0] reg_s2, //второй регистр-операнд
	input [31:0] imm, //константа-операнд
	output [31:0] rd_alu, //результат работы
	output is_alu_wait //надо ли ждать операцию до следующего такта
);

//немного стабилизации входов
wire [2:0] op_funct3_a = (is_op_alu || is_op_alu_imm) ? op_funct3_in : 3'b0;

//обработка (add, sub, xor, or, and, sll, srl, sra, slt, sltu)
//в случае лёгких инструкций вычисляем результат сразу
wire [31:0] alu_operand2 = is_op_alu ? reg_s2 : is_op_alu_imm ? imm : 0;
wire [31:0] rd_alu1 = op_funct3_a == 3'd0 ? (is_op_alu && op_funct7[5] ? reg_s1 - alu_operand2 : reg_s1 + alu_operand2) :
					  op_funct3_a == 3'd4 ? reg_s1 ^ alu_operand2 :
					  op_funct3_a == 3'd6 ? reg_s1 | alu_operand2 :
					  op_funct3_a == 3'd7 ? reg_s1 & alu_operand2 :
					  op_funct3_a == 3'd1 ? reg_s1 << alu_operand2[4:0] :
					  op_funct3_a == 3'd5 ? (op_funct7[5] ? $signed(reg_s1) >>> alu_operand2[4:0] : reg_s1 >> alu_operand2[4:0]) :
					  op_funct3_a == 3'd2 ? $signed(reg_s1) < $signed(alu_operand2) :
					  op_funct3_a == 3'd3 ? reg_s1 < alu_operand2 : //TODO для больших imm проверить
					  0; //невозможный результат

// РАСШИРЕНИЕ M
//обработка (mul, mulh, mulsu, mulu, div, divu, rem, remu)
//при умножении значения входных переменных могут меняться, поэтому запоминаем их локально
//инструкция запоминается снаружи, её надо сохранять не только для этого блока
//регистры используем для обоих операций
reg [31:0] x, y, r1, r2, r3;
//после начала работы не ориентируемся на входные значения
reg in_progress;
//считаем для беззнаковых, знак меняем в конце
reg muldiv_sign;
//для остатка от деления знак берётся из делимого
reg rem_sign;

//расшифровываем инструкцию
wire is_op_muldiv = is_op_alu && op_funct7[0];
wire [2:0] op_funct3 = is_op_muldiv ? op_funct3_in : 3'b0; //отдельная стабилизация для модуля M
wire is_op_multiply = !op_funct3[2];
wire is_op_mul_signed = !op_funct3[1]; //mul, mulh
//wire is_op_mul_low = op_funct3[1:0] == 0; //mul
wire is_op_mul_extend_sign = op_funct3[1:0] == 2; //musu //умножаем как беззнаковые, но сам знак надо расширить до 64 бит
wire is_op_div_signed = !op_funct3[0]; //div, rem
//wire is_op_remainder = op_funct3[2]; //rem, remu

//если хоть где-то ноль, результат можно выдать сразу
wire need_wait = is_op_muldiv && reg_s1 && reg_s2;

//инициализируем инструкцию
//перемножение {r3, r2} = {r1 = sign, x} * y
//деление {r3=q, r2=rem} = x / y , r1=msb - счётчик цикла, он же самый значимый бит
//для умножения со знаком достаточно убрать знак у короткого сомножителя
//но для деления надо убрать у обоих, поэтому делаем единообразно
wire need_restore_sign = is_op_multiply ? is_op_mul_signed : is_op_div_signed;
wire start_muldiv_sign = need_restore_sign ? reg_s1[31] ^ reg_s2[31] : 1'b0; // = sign(x) * sign(y)
wire rem_sign_start = need_restore_sign ? reg_s1[31] : 1'b0; // = sign(x)
wire [31:0] start_x = (need_restore_sign && $signed(reg_s1) < 0) ? -reg_s1 : reg_s1;
wire [31:0] start_y = (need_restore_sign && $signed(reg_s2) < 0) ? -reg_s2 : reg_s2;
wire [31:0] start_msb = start_x[31:24] != 8'b0 ? (1 << 31) : //легковесная подгонка начального счётчика цикла
						start_x[23:16] != 8'b0 ? (1 << 23) :
						start_x[15:8] != 8'b0 ? (1 << 15) :
						(1 << 7);
wire [31:0] start_r1 = !is_op_multiply ? start_msb :
						is_op_mul_extend_sign ? (reg_s1[31] ? -1 : 0) :
						0;

//обрабатываем в цикле
//умножение
wire [31:0] next_mul_y = (y >> 1); //поразрядное умножение
wire [63:0] current_mul_x = {r1, x}; //берём текущий x
wire [63:0] next_mul_x = current_mul_x << 1; //сдвигаем
wire [63:0] next_mul_val = {r3, r2} + (y[0] ? current_mul_x : 0); //и прибавляем к результату
wire mul_end = next_mul_y == 0; //условие окончания умножения

//деление в столбик
//y (делитель) не меняем
//x (делимое) не меняем
wire [31:0] current_msb = r1;
wire [31:0] current_rem = r2;
wire [31:0] current_div_val = r3;
wire [31:0] next_msb = (current_msb >> 1); // выбираем следующий разряд делимого
wire [31:0] next_rem_tmp = {current_rem[30:0], current_msb & x ? 1'b1 : 1'b0}; // приписываем к остатку
//если остаток больше или равен (то есть делится на делитель), то вычитаем
//конкретную цифру подбирать не надо, так как двоичная система
wire [31:0] div_remainder_delta = next_rem_tmp - y;
wire [31:0] next_rem_val = $signed(div_remainder_delta) >= 0 ? div_remainder_delta : next_rem_tmp;
wire [31:0] next_div_val = {current_div_val[30:0], ~div_remainder_delta[31]}; //приписываем разряд к частному
wire div_end = next_msb == 0;

//комбинируем значения для заполнения регистров
//в теории регистры можно переставить, сдвиг и условие выхода кажутся похожими
wire [31:0] next_x = is_op_multiply ? next_mul_x[31:0] : x;
wire [31:0] next_y = is_op_multiply ? next_mul_y : y;
wire [31:0] next_r1 = is_op_multiply ? next_mul_x[63:32] : next_msb;
wire [31:0] next_r2 = is_op_multiply ? next_mul_val[31:0] : next_rem_val;
wire [31:0] next_r3 = is_op_multiply ? next_mul_val[63:32] : next_div_val;
wire divmul_end = is_op_multiply ? mul_end : div_end; //блок умножения закончил вычислять
wire next_in_progress = in_progress && !divmul_end; //когда законил, выключаем регистр активности блока

wire [63:0] mul_result = muldiv_sign ? -next_mul_val : next_mul_val;
wire [31:0] div_result = muldiv_sign ? -next_div_val : next_div_val;
wire [31:0] rem_result = rem_sign ? -next_rem_val : next_rem_val;
wire [31:0] rd_mul = !in_progress ? 0 : //на нулевом такте всё равно может быть только ноль
					!divmul_end ? 0 : //пока процесс идёт, не качаем затворы
					op_funct3 == 3'd0 ? mul_result[31:0] : //mul
					op_funct3 == 3'd1 ? mul_result[63:32] : //mulh
					op_funct3 == 3'd2 ? mul_result[63:32] : //mulsu
					op_funct3 == 3'd3 ? mul_result[63:32] : //mulu
					op_funct3 == 3'd4 ? div_result : //div
					op_funct3 == 3'd5 ? div_result : //divu
					op_funct3 == 3'd6 ? rem_result : //rem
					/*op_funct3 == 7 ?*/ rem_result;  //remu

//когда нельзя переходить к следующей инструкции
assign is_alu_wait = !in_progress ? need_wait : !divmul_end;

wire divmul_active = need_wait || in_progress;
always@(posedge clock or posedge reset)
begin
	if (reset == 1) begin
		x <= 0;
		y <= 0;
		r1 <= 0;
		r2 <= 0;
		r3 <= 0;
		in_progress <= 0;
	end
	else if (divmul_active) begin
		if (!in_progress) begin // на нулевом такте просто запоминаем значения
			in_progress <= 1'b1;
			x <= start_x;
			y <= start_y;
			r1 <= start_r1; //расширение первого сомножителя знаком до 64 бит или счётчик цикла
			r2 <= 0; //младшие биты произведения или остаток
			r3 <= 0; //старшие биты произведения или частное
			muldiv_sign <= start_muldiv_sign; //надо ли в конце сменить знак
			rem_sign <= rem_sign_start;
		end
		else begin
			in_progress = next_in_progress;
			x <= next_x;
			y <= next_y;
			r1 <= next_r1;
			r2 <= next_r2;
			r3 <= next_r3;
		end
	end
end

//выдаём наружу результат
assign rd_alu = is_op_muldiv ? rd_mul :
					rd_alu1;

endmodule