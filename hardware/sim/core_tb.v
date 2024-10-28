`timescale 1ns / 1ns

module core_tb;

`define MEMORY_SIZE (2**16/4)

reg clock = 0;
reg reset = 1;
reg [1:0] reset_counter = 2;
reg [31:0] rom [0:`MEMORY_SIZE-1]; //память
wire [31:0] i_addr;
wire [31:0] i_data;
wire [31:0] d_addr;
wire [31:0] d_data_in;
wire [31:0] d_data_out;
wire data_r;
wire data_w;
wire [1:0] d_width; //0-byte, 1-half, 2-word
wire [3:0] byte_mask;

reg [31:0] timer;
reg [31:0] timer_divider;

integer i, fdesc, fres;
initial while(1) #1 clock = !clock;
initial
begin
	$dumpfile("core_tb.vcd");
	$dumpvars();
	for (i = 0; i < `MEMORY_SIZE; i = i + 1)
		rom[i] = 32'b0;
	//$readmemh("code.hex", rom);
	fdesc = $fopen("code.bin", "rb");
	fres = $fread(rom, fdesc, 0, `MEMORY_SIZE);
	$fclose(fdesc);
	#3000000
	$finish();
end

always@(posedge clock) begin
	reset_counter <= reset_counter == 0 ? 0 : reset_counter - 1;
	reset <= reset_counter != 0;
end

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
assign i_data = rom[i_addr[31:2]];

//теперь выравниваем данные
//делаем невыровненный доступ, точнее выровненный по байтам
wire [31:0] old_data = rom[d_addr[31:2]];
wire [1:0] addr_tail = d_addr[1:0];

//вешаем на общую шину регистры и память
assign d_data_in = d_addr == 32'h40000008 ? timer :
	d_addr < `MEMORY_SIZE * 4 ? (old_data >> (addr_tail * 8)) : 0; //TODO data_read не нужен?

//для чтения данных маска накладывается в ядре, здесь только для записи
assign byte_mask = d_width == 0 ? 4'b0001 << addr_tail :
                   d_width == 1 ? 4'b0011 << addr_tail :
                                  4'b1111;

//раз для побайтового чтения надо делать побайтовый сдвиг
//то для полуслов дешевле не ограничивать выравниванием на два байта
//TODO нужна проверка выхода за границы слова?
wire [31:0] aligned_out = d_data_out << addr_tail * 8;

always@(posedge clock) begin
	if (data_w) begin
		rom[d_addr[31:2]] <= {byte_mask[3] ? aligned_out[31:24] : old_data[31:24],
							byte_mask[2] ? aligned_out[23:16] : old_data[23:16],
							byte_mask[1] ? aligned_out[15:8] : old_data[15:8],
							byte_mask[0] ? aligned_out[7:0] : old_data[7:0]};
	end
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
end
endmodule