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

// процессор
wire [31:0] instruction_address;
wire [31:0] instruction_value;
wire        instruction_ready;
wire [31:0] core_data_address;
wire [1:0]  core_data_width;
wire [31:0] core_data_in;
wire [31:0] core_data_out;
wire        core_data_read;
wire        core_data_write;
wire        core_data_ready;

RiscVCore core0
(
	.clock(clock),
	.reset(reset),
	//.irq,
	
	.instruction_address(instruction_address),
	.instruction_data(instruction_value),
	.instruction_ready(instruction_ready),
	
	.data_address(core_data_address),
	.data_width(core_data_width),
	.data_in(core_data_in),
	.data_out(core_data_out),
	.data_read(core_data_read),
	.data_write(core_data_write),
	.data_ready(core_data_ready)
);

wire [31:0] memory_read_address;
wire [31:0] memory_write_address;
wire        memory_read;
wire        memory_write;
wire [31:0] memory_in;
reg  [31:0] memory_out;
wire        memory_read_ready;
wire        memory_write_ready;
reg [31:0]  memory_address_requested;

wire [31:0] bus_data_out;
wire        bus_data_read;
wire        bus_data_write;
wire        bus_data_ready;

// кэш процессора
RiscVBus bus0
(
	.clock(clock),
	.reset(reset),
	
	.memory_read_address(memory_read_address),
	.memory_write_address(memory_write_address),
	.memory_read(memory_read),
	.memory_write(memory_write),
	.memory_in(memory_out),
	.memory_out(memory_in),
	.memory_read_ready(memory_read_ready),
	.memory_write_ready(memory_write_ready),
	.memory_address_requested(memory_address_requested),
	
	.instruction_address(instruction_address),
	.instruction_value(instruction_value),
	.instruction_ready(instruction_ready),
	
	.data_address(core_data_address),
	.data_width(core_data_width),
	.data_read(bus_data_read),
	.data_write(bus_data_write),
	.data_in(core_data_out),
	.data_out(bus_data_out),
	.data_ready(bus_data_ready)
);

// оперативная память
always@(posedge clock) begin
	if (memory_read) begin
		memory_out <= {
			rom_3[memory_read_address[31:2]],
			rom_2[memory_read_address[31:2]],
			rom_1[memory_read_address[31:2]],
			rom_0[memory_read_address[31:2]]
		};
	end
	else begin
		memory_out <= 32'hz;
	end
	
	if (memory_write) begin
		{
			rom_3[memory_write_address[31:2]],
			rom_2[memory_write_address[31:2]],
			rom_1[memory_write_address[31:2]],
			rom_0[memory_write_address[31:2]]
		}
		<= memory_in;
	end
	
	if (memory_read || memory_write) begin
		memory_address_requested <= memory_read_address;
	end
end

assign memory_read_ready = 1;
assign memory_write_ready = 1;

//периферия
wire is_periph_write = (core_data_address == 32'h40000004);
wire is_periph_read = (core_data_address == 32'h40000008);
wire periph_used = is_periph_read || is_periph_write;
reg [31:0] periph_out;
reg periph_used_old;

always@(posedge clock) begin
	// процессор читает периферию как память
	// поэтому делаем задержку
	periph_used_old <= periph_used;
	periph_out <= core_data_address == 32'h40000008 ? timer : 32'hz;
	
	if (core_data_write && core_data_address == 32'h40000004) begin
		$write("%c", core_data_out); // отладочный вывод
	end
	
	// если читаем или пишем невалидный адрес и не из периферии
	if ((core_data_read || core_data_write) && 
		(core_data_address < 8'hff || core_data_address > `MEMORY_SIZE * 4) && 
		!periph_used)
	begin
		//нулевые указатели и выход за границы приводит к прекращению работы
		$finish();
	end
end

// подключение периферии и кэша к процессору
// вешаем на общую шину регистры и память
assign bus_data_read = periph_used ? 0 : core_data_read;
assign bus_data_write = periph_used ? 0 : core_data_write;
assign core_data_in = periph_used_old ? periph_out : bus_data_out;
assign core_data_ready = periph_used_old ? 1 : bus_data_ready;

always@(posedge clock) begin
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
	out <= bus_data_write; //TODO, добавить реальный вывод данных наружу
end
endmodule