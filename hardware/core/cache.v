// кэш с ассоциативным хранилищем
`include "common.vh"

module RiscVCacheCommon
#(parameter SIZE = 8)
(
	input clock,
	input reset,
	
	output [31:0] memory_address, // обращение к памяти по заданному адресу
	output        memory_read,    // запрос на чтение памяти
	output        memory_write,   // запрос на запись в память
	input  [31:0] memory_in,      // прочитанные из ОЗУ данные
	output [31:0] memory_out,     // записываемые в ОЗУ данные
	input         memory_ready,   // запрос к памяти отработал
	input  [31:0] memory_address_requested, // значение по какому адресу возвращено
	
	input  [31:0] data_address, // обращение к кэшу по заданному адресу
	input  [1:0]  data_width,   // размер данных для записи
	input         data_read,    // запрос на чтение данных из кэша
	input         data_write,   // запрос на запись данных в кэш
	input  [31:0] data_in,      // записываемые в кэш данные
	output [31:0] data_out,     // прочитанные из кэша данные
	output        data_ready    // отработал ли запрос на обработку данных
);

// ответ памяти мультиплексируем с ответом кэша, чтобы не ждать лишний такт
// поэтому на выходе после регистров есть немного комбинаторики
//reg [31:0] data_out;
//reg        data_ready;
reg write_requested;     // запрос памяти на запись отправлен
reg read_requested;      // запрос памяти на чтение отправлен и нужен для чтения
reg cache_out_ready;     // ответ кэша получен
reg [31:0] cache_out;    // ответ кэша
reg [1:0] stage1_address_tail; // на сколько байт сдвинуть ответ

// хранилище данных кэша
reg [31:0]   cache_value   [0:SIZE-1];  // значения самой памяти
reg [31-2:0] cache_address [0:SIZE-1];  // виртуальные адреса
reg          cache_filled  [0:SIZE-1];  // значение есть в наличии

// ниже всё должно быть wire
reg          cache_address_equal[0:SIZE-1]; // совпал входной адрес ячейки
reg          cache_move_next    [1:SIZE-1]; // надо ли читать данные слева
reg          cache_hit;            // есть ли элемент с таким адресом
reg  [31:0]  cache_hit_value;      // значение элемента по запрошенному адресу
wire         cache_can_update;     // можно ли уже записать элемент наверх
wire [31:0]  cache_value_update;   // какое значение вписать

wire [31:0]  aligned_data_in;      // выровненное до нужного адреса входное значение
wire [31:0]  write_mask;           // какие биты перезаписать
wire         write_need_request;   // нужно ли перед записью запросить данные из памяти

integer i;

// находим положение нужного элемента и заливаем флаги
// это как бы шина адреса
always@(*) begin
	cache_hit = 0;
	cache_hit_value = 0;
	for(i = 0; i < SIZE; i = i + 1) begin
		cache_address_equal[i] = (cache_address[i] == data_address[31:2]) && cache_filled[i];
		if (i > 0) begin
			cache_move_next[i] = !cache_hit;
		end
		cache_hit = cache_hit | cache_address_equal[i];
		cache_hit_value = cache_hit_value | (cache_address_equal[i] ? cache_value[i] : 0);
	end
end

// когда появляются данные
// сдвигаем элементы до найденного
// и свежее пишем в начало списка
always@(posedge clock) begin
	if (cache_can_update) begin 
		for(i = 1; i < SIZE; i = i + 1) begin
			if (cache_move_next[i]) begin
				cache_value[i] <= cache_value[i-1];
				cache_address[i] <= cache_address[i-1];
			end
		end
		
		cache_value[0] <= cache_value_update;
		cache_address[0] <= data_address[31:2];
	end
	
	if (reset) begin
		for(i = 0; i < SIZE; i = i + 1) begin
			cache_filled[i] <= 0;
		end
	end
	else if (cache_can_update) begin
		for(i = 1; i < SIZE; i = i + 1) begin
			if (cache_move_next[i]) begin
				cache_filled[i] <= cache_filled[i-1];
			end
		end
		cache_filled[0] <= 1;
	end
end

// запись данных
// маска для записи некоторых байт (для чтения маска накладывается в ядре)
// TODO нужна проверка выхода за границы слова?
wire [1:0] address_tail = data_address[1:0];
wire [3:0] byte_enable = !data_write? 0 : 
                   data_width == 0 ? 4'b0001 << address_tail :
                   data_width == 1 ? 4'b0011 << address_tail :
                                  4'b1111;

assign aligned_data_in = data_in << address_tail * 8;
assign write_need_request = (byte_enable != 4'b1111);
assign write_mask = {{8{byte_enable[3]}}, {8{byte_enable[2]}}, {8{byte_enable[1]}}, {8{byte_enable[0]}}};

// работа с памятью
// если элемент не найден, запрашиваем из памяти
assign memory_address = {data_address[31:2], 2'b0};
wire memory_has_response = memory_ready && (memory_address_requested == memory_address); // наш запрос к памяти отработал
wire has_value = cache_hit || memory_has_response; // в наличии есть значение для чтения/модификации
assign memory_read = (!has_value) && (data_read || data_write && write_need_request);

// пока что пишем в память мгновенно, как только есть данные
assign memory_write = data_write && cache_can_update;
assign memory_out = cache_value_update;

// память может задержаться на несколько тактов
// обновлять можно только тогда, когда нужное значение есть в наличии
assign cache_can_update = (data_read || data_write) && has_value
						|| (data_write && !write_need_request);
wire [31:0] cache_value_read = cache_hit ? cache_hit_value : memory_in;
assign cache_value_update = (cache_value_read & ~write_mask) | (aligned_data_in & write_mask);

// пробрасываем ответ памяти напрямую ядру
wire data_write_ready = write_requested && memory_ready;
wire data_read_ready = read_requested && memory_ready || cache_out_ready;
assign data_ready = data_read_ready || data_write_ready;

// сдвигаем до нужного байта
wire [31:0] raw_data_out = read_requested && memory_ready ? memory_in : cache_out;
assign data_out = data_read_ready ? (raw_data_out >> stage1_address_tail * 8) : 32'hz;

// выдаём запрошенные данные
always@(posedge clock) begin
	read_requested <= reset ? 0 : data_read && memory_read;
	write_requested <= reset ? 0 : memory_write;
	cache_out_ready <= reset ? 0 : data_read && has_value;
	cache_out <= cache_value_read;
	stage1_address_tail <= address_tail;
end

endmodule
