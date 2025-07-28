// шина с подключением кэша, процесора и памяти
`include "common.vh"

module RiscVBus
(
	input clock,
	input reset,
	
	output [31:0] memory_address, // обращение к памяти по заданному адресу
	output        memory_read,    // запрос на чтение памяти
	output        memory_write,   // запрос на запись в память
	input  [31:0] memory_in,      // прочитанные из ОЗУ данные
	output [31:0] memory_out,     // записываемые в ОЗУ данные
	input         memory_ready,   // запрос к памяти отработал
	input  [31:0] memory_address_requested, // запрос к какому адресу отработал
	
	input  [31:0] instruction_address, // процессор запрашивает инструкцию
	output [31:0] instruction_value,   // инструкция
	output        instruction_ready,   // запрос инструкции отработал
	
	input  [31:0] data_address, // обращение к памяти по заданному адресу
	input  [1:0]  data_width,   // размер данных для записи
	input         data_read,    // запрос на чтение данных из кэша
	input         data_write,   // запрос на запись данных в кэш
	input  [31:0] data_in,      // записываемые в кэш данные
	output [31:0] data_out,     // прочитанные из кэша данные
	output        data_ready    // отработал ли запрос на обработку данных
);

// кэш инструкций может запросить свои данные из памяти
wire [31:0] instruction_memory_address;
wire        instruction_memory_read;
wire        instruction_memory_ready;

// кэш данных обращается по другим адресам и т.п.
// memory_in общий
wire [31:0] data_memory_address;
wire        data_memory_read;
wire        data_memory_write;
wire [31:0] data_memory_out;
wire        data_memory_ready;

RiscVCacheCommon #(`CACHE_INSTRUCTIONS_SIZE)
instructions_cache(
	.clock(clock),
	.reset(reset),
	
	.memory_address(instruction_memory_address),
	.memory_read(instruction_memory_read),
	.memory_write(), // инструкции не пишем по шине инструкций
	.memory_in(memory_in),
	.memory_out(),
	.memory_ready(instruction_memory_ready),
	.memory_address_requested(memory_address_requested),
	
	.data_address(instruction_address),
	.data_width(2'b0),
	.data_read(1'b1),
	.data_write(1'b0),
	.data_in(0),
	.data_out(instruction_value),
	.data_ready(instruction_ready)
);

RiscVCacheCommon #(`CACHE_DATA_SIZE)
data_cache(
	.clock(clock),
	.reset(reset),
	
	.memory_address(data_memory_address),
	.memory_read(data_memory_read),
	.memory_write(data_memory_write),
	.memory_in(memory_in),
	.memory_out(data_memory_out),
	.memory_ready(data_memory_ready),
	.memory_address_requested(memory_address_requested),
	
	.data_address(data_address),
	.data_width(data_width),
	.data_read(data_read),
	.data_write(data_write),
	.data_in(data_in),
	.data_out(data_out),
	.data_ready(data_ready)
);

// инструкции читаем в первую очередь
// мультиплексируем входы памяти
wire instruction_need = instruction_memory_read;
assign memory_address = instruction_need ? instruction_memory_address : data_memory_address;
assign memory_read = instruction_need ? instruction_memory_read : data_memory_read;
assign memory_write = instruction_need ? 0 : data_memory_write;
assign memory_out = data_memory_out;

// ответ на следующем такте, так что запоминаем, кому отвечать
reg stage1_instruction_need;
always@(posedge clock) begin
	stage1_instruction_need <= reset ? 0 : instruction_need;
end

assign instruction_memory_ready = stage1_instruction_need && memory_ready;
assign data_memory_ready = !stage1_instruction_need && memory_ready;

endmodule
