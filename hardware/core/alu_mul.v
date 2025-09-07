`include "common.vh"

module RiscVMul
(
	input clock,
	input reset,
	input enabled,
	
	input [2:0] op_funct3, //код операции
	input [31:0] reg_s1, //первый регистр-операнд
	input [31:0] reg_s2, //второй регистр-операнд
	output [31:0] rd, //результат работы
	output is_wait //надо ли ждать операцию до следующего такта
);

// РАСШИРЕНИЕ M
//обработка (mul, mulh, mulhsu, mulu, div, divu, rem, remu)
//расшифровываем инструкцию
wire is_op_muldiv = enabled;
wire is_op_multiply = !op_funct3[2];
wire is_op_mul_signed = !op_funct3[1]; //mul, mulh
//wire is_op_mul_low = op_funct3[1:0] == 0; //mul
wire is_op_mul_signed_x = op_funct3[1:0] == 2; //mulhsu
wire is_op_div_signed = !op_funct3[0]; //div, rem
wire is_op_remainder = op_funct3[2:1] == 3; //rem, remu

//убираем знак у операндов
wire need_restore_sign_x = is_op_multiply ? is_op_mul_signed || is_op_mul_signed_x : is_op_div_signed;
wire need_restore_sign_y = is_op_multiply ? is_op_mul_signed : is_op_div_signed;
wire sign_x = need_restore_sign_x && reg_s1[31];
wire sign_y = need_restore_sign_y && reg_s2[31];

wire start_muldiv_sign = sign_x ^ sign_y; // = sign(x) * sign(y)
wire start_rem_sign = sign_x;
wire [31:0] start_x = sign_x ? -reg_s1 : reg_s1;
wire [31:0] start_y = sign_y ? -reg_s2 : reg_s2;

// ==========================================
// быстрое умножение
`ifdef __FAST_MUL__

wire [31:0] mul_1;
wire [31:0] mul_2;

assign {mul_2, mul_1} = start_x * start_y;

wire [63:0] mul_result = {mul_2, mul_1};
wire mul_sign = start_muldiv_sign;
wire is_mul_wait = 0;
wire is_mul_null = 0; // нули на входе

`endif // __FAST_MUL__

// ==========================================
// быстрое деление
`ifdef __FAST_DIV__

wire [31:0] quotient;
wire [31:0] remainder;

RiscVFastDiv fd(
		.x(start_x),
		.y(start_y),
		.quotient(quotient),
		.remainder(remainder)
	);

wire [31:0] div = quotient;
wire [31:0] rem = remainder;
wire div_sign = start_muldiv_sign;
wire rem_sign = start_rem_sign;
wire is_div_wait = 0;
wire is_div_null = 0;

`endif // __FAST_DIV__

`ifdef __FAST_MUL__
`ifdef __FAST_DIV__
`define NO_SLOW_MULDIV
`endif
`endif

// многотактное умножение и деление
`ifndef NO_SLOW_MULDIV
//при умножении значения входных переменных могут меняться, поэтому запоминаем их локально
//инструкция запоминается снаружи, её надо сохранять не только для этого блока
//регистры используем для обоих операций
reg [31:0] x, y;
//после начала работы не ориентируемся на входные значения
reg in_progress;
//считаем для беззнаковых, знак меняем в конце
reg muldiv_sign;
//для остатка от деления знак берётся из делимого
reg rem_sign;

//если хоть где-то ноль, результат можно выдать сразу
wire need_wait = is_op_muldiv && reg_s1 && reg_s2;
wire divmul_active = is_wait || in_progress;

// ==========================================
// поразрядное умножение
`ifndef __FAST_MUL__

// mul_val = mul_x * mul_y
reg [63:0] mul_x, mul_val;
reg [31:0] mul_y;

wire [63:0] start_mul_x = {32'b0, start_x};
wire [63:0] next_mul_val = mul_val + (mul_y[0] ? mul_x : 0);
wire [31:0] next_mul_y = mul_y >> 1;

always@(posedge clock)
begin
	if (divmul_active) begin
		mul_x   <= in_progress ? mul_x << 1   : start_mul_x;
		mul_y   <= in_progress ? mul_y >> 1   : start_y;
		mul_val <= in_progress ? next_mul_val : 0;
	end
end

wire [63:0] mul_result = next_mul_val;
wire mul_sign = muldiv_sign;
wire mul_end = next_mul_y == 0; //условие окончания умножения
wire is_mul_wait = !in_progress ? need_wait : !mul_end;
wire is_mul_null = !need_wait;

`else
wire mul_end = 1;
`endif // !__FAST_MUL__

// ==========================================
// деление в столбик
`ifndef __FAST_DIV__

// {quotient, remainder} = x / y , msb - счётчик цикла, он же самый значимый бит
reg [31:0] quotient, remainder, msb;
wire [31:0] start_msb = start_x[31:24] != 8'b0 ? (1 << 31) : //легковесная подгонка начального счётчика цикла
						start_x[23:16] != 8'b0 ? (1 << 23) :
						start_x[15:8] != 8'b0 ? (1 << 15) :
						(1 << 7);

wire [31:0] next_msb = msb >> 1; // выбираем следующий разряд делимого
wire [31:0] next_remainder_0 = {remainder[30:0], msb & x ? 1'b1 : 1'b0}; // приписываем к остатку
wire [31:0] remainder_delta = next_remainder_0 - y; // вычитаем делитель если набралось достаточно
wire [31:0] next_remainder = $signed(remainder_delta) >= 0 ? remainder_delta : next_remainder_0;
wire [31:0] next_quotient = {quotient[30:0], ~remainder_delta[31]}; //приписываем разряд к частному

always@(posedge clock)
begin
	if (divmul_active) begin
		quotient  <= in_progress ? next_quotient  : 0;
		remainder <= in_progress ? next_remainder : 0;
		msb       <= in_progress ? next_msb       : start_msb;
	end
end

wire [31:0] div = quotient;
wire [31:0] rem = remainder;
wire div_sign = muldiv_sign;
//wire rem_sign = rem_sign;

wire div_end = msb == 0;
wire is_div_wait = !in_progress ? need_wait : !div_end;
wire is_div_null = !need_wait;

`else
wire div_end = 1;
`endif // !__FAST_DIV__

//когда блок закончил вычислять, выключаем регистр активности блока
wire divmul_end = is_op_multiply ? mul_end : div_end;
wire next_in_progress = in_progress && !divmul_end;

always@(posedge clock or posedge reset)
begin
	if (reset) begin
		x <= 0;
		y <= 0;
		in_progress <= 0;
	end
	else if (divmul_active) begin
		if (!in_progress) begin // на нулевом такте просто запоминаем значения
			in_progress <= 1'b1;
			x <= start_x;
			y <= start_y;
			muldiv_sign <= start_muldiv_sign; //надо ли в конце сменить знак
			rem_sign <= start_rem_sign;
		end
		else begin
			in_progress <= next_in_progress;
		end
	end
end

`endif // !NO_SLOW_MULDIV

// делаем один сумматор на выходе
wire [63:0] rd_positive = is_op_multiply ? mul_result :
						is_op_remainder ? rem :
						div;

wire [63:0] rd_sign = is_op_multiply ? mul_sign :
						is_op_remainder ? rem_sign :
						div_sign;

wire [31:0] rd_1, rd2;
assign {rd_2, rd_1} = rd_sign ? -rd_positive : rd_positive;

wire is_null = is_op_multiply ? is_mul_null : is_div_null;

assign rd = is_null ? 0 :
	op_funct3 == 3'd0 ? rd_1 : // mul
	op_funct3 == 3'd1 ? rd_2 : // mulh
	op_funct3 == 3'd2 ? rd_2 : // mulhsu
	op_funct3 == 3'd3 ? rd_2 : // mulhu
	op_funct3 == 3'd4 ? rd_1 : // div
	op_funct3 == 3'd5 ? rd_1 : // divu
	op_funct3 == 3'd6 ? rd_1 : // rem
	/*op_funct3 == 7 ?*/ rd_1; // remu

//когда нельзя переходить к следующей инструкции
assign is_wait = is_op_multiply ? is_mul_wait : is_div_wait;

endmodule