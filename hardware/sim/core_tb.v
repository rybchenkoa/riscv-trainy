`include "common.vh"
`timescale 1ns / 1ns

`ifdef SIMULATION
	module core_tb;
	`define MEMORY_SIZE (2**16/4)
`else
	module core_tb(clock, reset, out);
	`define MEMORY_SIZE (2**14/4)
`endif

`ifdef SIMULATION
reg clock = 0;
reg reset = 1;
`else
input wire clock;
input wire reset;
`endif
output reg out;
reg [1:0] reset_counter = 2;
reg [7:0] rom_0 [0:`MEMORY_SIZE-1]; //память
reg [7:0] rom_1 [0:`MEMORY_SIZE-1]; //память
reg [7:0] rom_2 [0:`MEMORY_SIZE-1]; //память
reg [7:0] rom_3 [0:`MEMORY_SIZE-1]; //память
wire [31:0] i_addr;
reg [31:0] i_data;
wire [31:0] d_addr;
wire [31:0] d_data_in;
wire [31:0] d_data_out;
wire data_r;
wire data_w;
wire [1:0] d_width; //0-byte, 1-half, 2-word
wire [3:0] byte_mask;

reg [31:0] timer;
reg [31:0] timer_divider;

`ifdef SIMULATION
integer i, fdesc, fres;
reg [31:0] value;
initial while(1) #1 clock = !clock;
initial
begin
	$dumpfile("core_tb.vcd");
	$dumpvars();
	//$readmemh("code.hex", rom);
	fdesc = $fopen("code.bin", "rb");
	for (i = 0; i < `MEMORY_SIZE; i = i + 1) begin
		value = 0;
		fres = $fread(value, fdesc);
		{rom_3[i], rom_2[i], rom_1[i], rom_0[i]} = value;
	end
	$fclose(fdesc);
	#3000000
	$finish();
end

always@(posedge clock) begin
	reset_counter <= reset_counter == 0 ? 0 : reset_counter - 1;
	reset <= reset_counter != 0;
end
`endif

RiscVCore core0
(
	.clock(clock),
	.reset(reset),
	//.irq,
	
	.instruction_address(i_addr),
	.instruction_data(i_data),
	
	.data_address(d_addr),
	.data_width(d_width),
	.data_in(d_data_in),
	.data_out(d_data_out),
	.data_read(data_r),
	.data_write(data_w)
);

//шина инструкций всегда выровнена
always@(posedge clock) begin
	i_data <= {rom_3[i_addr[31:2]],
				rom_2[i_addr[31:2]],
				rom_1[i_addr[31:2]],
				rom_0[i_addr[31:2]]};
end

//теперь выравниваем данные
//делаем невыровненный доступ, точнее выровненный по байтам
reg [31:0] old_data;
reg [31:0] old_addr;
reg old_data_r;
always@(posedge clock) begin
	old_data <= (data_r || data_w) ? {rom_3[d_addr[31:2]],
										rom_2[d_addr[31:2]],
										rom_1[d_addr[31:2]],
										rom_0[d_addr[31:2]]
									}: 32'hz;
	old_addr <= d_addr;
	old_data_r <= data_r;
end

//вешаем на общую шину регистры и память
wire [1:0] old_addr_tail = old_addr[1:0];
assign d_data_in = !old_data_r ? 32'hz : old_addr == 32'h40000008 ? timer :
	old_addr < `MEMORY_SIZE * 4 ? (old_data >> (old_addr_tail * 8)) : 32'hz; //TODO data_read не нужен?

//для чтения данных маска накладывается в ядре, здесь только для записи
wire [1:0] addr_tail = d_addr[1:0];
assign byte_mask = !data_w? 0 : 
                   d_width == 0 ? 4'b0001 << addr_tail :
                   d_width == 1 ? 4'b0011 << addr_tail :
                                  4'b1111;

//раз для побайтового чтения надо делать побайтовый сдвиг
//то для полуслов дешевле не ограничивать выравниванием на два байта
//TODO нужна проверка выхода за границы слова?
wire [31:0] aligned_out = d_data_out << addr_tail * 8;

always@(posedge clock) begin
	if (byte_mask[3]) rom_3[d_addr[31:2]] <= aligned_out[31:24];
	if (byte_mask[2]) rom_2[d_addr[31:2]] <= aligned_out[23:16];
	if (byte_mask[1]) rom_1[d_addr[31:2]] <= aligned_out[15:8];
	if (byte_mask[0]) rom_0[d_addr[31:2]] <= aligned_out[7:0];
	
	if (data_w && d_addr == 32'h4000_0004) begin
		//отладочный вывод
		$write("%c", d_data_out);
	end
	else if (data_r && d_addr == 32'h40000008) begin
		; //таймер читать можно
	end
	else if ((data_r || data_w) && (d_addr < 8'hff || d_addr > `MEMORY_SIZE * 4)) begin
		//нулевые указатели и выход за границы приводит к прекращению работы
		$finish();
	end
	
	if(reset) begin
		timer = 0;
		timer_divider = 0;
	end else begin
		if (timer_divider == 100) begin
			timer <= timer + 1;
			timer_divider <= 0;
		end else begin
			timer_divider <= timer_divider + 1;
		end
	end
	out <= data_w; //TODO, добавить реальный вывод данных наружу
end
endmodule