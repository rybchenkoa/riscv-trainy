module RiscVFastDiv
(
	input [31:0] x, //на входе и на выходе неотрицательные числа
	input [31:0] y,
	output [31:0] quotient,  // частное
	output [31:0] remainder  // остаток
);

wire [31:0] divisible;    // делимое, смещённое на столько же разрядов что и делитель
wire [31:0] divisible2;   // та часть делимого, которая вылезла за границы при смещении
wire [31:0] divider;      // делитель с 1 в старшем разряде
reg [31:0] quotient_out; // частное
reg [31:0] remainder_out;// остаток

// [   divisible2] [divisible]
// [divider      ] [000000000]

// алгоритм основан на том факте, что 100 - 10 = 10, в свою очередь 10 - 1 = 1, ну а 1 как-нибудь можно обнулить
reg [31:0] quotient_bit;
reg [31:0] quotient_carry;
reg [32:0] remainder_bit;
reg [31:0] remainder_carry;
reg [31:0] divisible_bit;
reg [1:0] out_place;

reg [2:0] next_place;
reg [32:0] addition;
reg [32:0] carry_addition;
reg [32:0] remainder_bit_2;
reg [31:0] remainder_carry_2;

reg [1:0] next_place_2;
reg [32:0] addition_2;
reg [32:0] carry_addition_2;

reg [1:0] correction;

reg [2:0] end_digit;
reg [32:0] addition_3;
reg [32:0] carry_addition_3;
reg [32:0] remainder_bit_3;

reg [32:0] remainder_sum;
reg [32:0] remainder_diff;

always @(*)
begin
	quotient_bit = 0; // в частном на старте пусто
	quotient_carry = 0;
	remainder_bit = divisible2; //эти биты остатка автоматически задвинуты на старте и точно меньше делителя
	remainder_carry = 0;      //это биты переноса остатка, т.е. бит = 1, когда разряд = 2 или 3
	divisible_bit = divisible;

	repeat(32) begin
		// вдвигаем очередной бит делимого в остаток
		remainder_bit = remainder_bit << 1;
		remainder_carry = remainder_carry << 1;
		remainder_bit[0] = divisible_bit[31];
		divisible_bit = divisible_bit << 1;
		
		//reg [1:0] out_place; // что запишем в разряд частного
		
		// итерация для установления старшего бита (2) разряда в 0
		//берём очередной разряд делителя с учётом остатка с прошлого раза в remainder_bit[32]
		next_place = remainder_bit[32:31] + remainder_carry[31:30];
		//reg [32:0] addition;
		if (next_place[2]) begin
			addition = (-divider) << 1; //1[xx]
			out_place = 2;
		end
		else if (next_place[1]) begin
			addition = -divider; //1[1x]
			out_place = 1;
		end
		else begin
			addition = 0;
			out_place = 0;
		end
		//делаем сложение с распространением переноса только на 1 шаг
		carry_addition = remainder_carry << 1;
		remainder_bit_2 = remainder_bit ^ carry_addition ^ addition;
		remainder_carry_2 = (remainder_bit & carry_addition) | (remainder_bit & addition) | (carry_addition & addition);
		
		// теперь устанавливаем младший бит (1) разряда в 0
		next_place_2 = remainder_bit_2[32:31] + remainder_carry_2[31:30];
		//reg [32:0] addition_2;
		if (next_place_2[1]) begin
			addition_2 = -divider;  // [1x]
			out_place = out_place + 1;
		end
		else begin
			addition_2 = 0;
			out_place = out_place + 0;
		end
		
		// ещё раз продвигаем перенос
		// в старшем бите(32) должно получиться 0
		carry_addition_2 = remainder_carry_2 << 1;
		remainder_bit = remainder_bit_2 ^ carry_addition_2 ^ addition_2;
		remainder_carry = (remainder_bit_2 & carry_addition_2) | (remainder_bit_2 & addition_2) | (carry_addition_2 & addition_2);
		
		// добавляем очередной разряд в частное
		quotient_bit = (quotient_bit << 1);
		quotient_carry = (quotient_carry << 1);
		quotient_bit[0] = out_place[0];
		quotient_carry[0] = out_place[1];
	end
	
	correction = 0;
	//теперь делаем ещё одно продвижение переноса
	//так как в худшем случае переносы могут добавить 1 бит остатка
	//и для этого смотрим 2 последних разряда
	end_digit = remainder_bit[32:30] + remainder_carry[31:29];
	addition_3 = 0;
	carry_addition_3 = 0;
	remainder_bit_3 = 0;
	if (end_digit > divider[31:30]) begin
		correction = 1;
		addition_3 = -divider;
		carry_addition_3 = remainder_carry << 1;
		remainder_bit_3 = remainder_bit;
		remainder_bit = remainder_bit_3 ^ carry_addition_3 ^ addition_3;
		remainder_carry = (remainder_bit_3 & carry_addition_3) | (remainder_bit_3 & addition_3) | (carry_addition_3 & addition_3);
	end
	
	// в конце складываем и при необходимости округляем на 1
	remainder_sum = remainder_bit + (remainder_carry << 1);
	remainder_diff = remainder_sum - divider;
	if ($signed(remainder_diff) >= 0) begin
		correction = correction + 1;
		remainder_sum = remainder_diff;
	end
	
	// выдаём результат
	remainder_out = remainder_sum;
	quotient_out = quotient_bit + (quotient_carry << 1) + correction;
end

function [4:0] clz(input [31:0] value);
reg [4:0] result;
reg [15:0] v16;
reg [7:0] v8;
reg [3:0] v4;
reg [1:0] v2;
begin
	result[4] = value[31:16] == 0? 1 : 0;
	v16 = result[4]? value[15:0] : value[31:16];
	
	result[3] = v16[15:8] == 0? 1 : 0;
	v8 = result[3]? v16[7:0] : v16[15:8];
	
	result[2] = v8[7:4] == 0? 1 : 0;
	v4 = result[2]? v8[3:0] : v8[7:4];
	
	result[1] = v4[3:2] == 0? 1 : 0;
	v2 = result[1]? v4[1:0] : v4[3:2];
	
	result[0] = v2[1] == 0? 1 : 0;
	clz = result;
end
endfunction

//теперь присоединяем входы и выходы к блоку деления
wire [4:0] offset = clz(y);
assign divider = y << offset;
assign {divisible2, divisible} = x << offset;
assign remainder = remainder_out >> offset;
assign quotient = quotient_out;

endmodule
