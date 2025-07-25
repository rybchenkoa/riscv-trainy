`define CACHE_INSTRUCTIONS_SIZE 8
`define CACHE_DATA_SIZE 8

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
	output reg[31:0] data_out,     // прочитанные из кэша данные
	output        data_ready    // отработал ли запрос на обработку данных
);

//reg [31:0] data_out;
// при чтении значение известно сразу, а при записи ответ от памяти приходит через регистр, поэтому мультиплексируем
//reg        data_ready;
reg data_read_ready; // запрос на чтение обработан
reg write_requested; // запрос на запись отправлен

reg [31:0]   cache_value   [0:SIZE-1];  // значения самой памяти
reg [31-2:0] cache_address [0:SIZE-1];  // виртуальные адреса
reg          cache_filled  [0:SIZE-1];  // значение есть в наличии

// ниже всё должно быть wire
reg  [0:SIZE-1]        cache_address_equal; // совпал входной адрес ячейки
reg  [1:SIZE-1]        cache_move_next    ; // надо ли читать данные слева
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
assign memory_read = (!has_value) && (data_read || write_need_request);

// пока что пишем в память мгновенно, как только есть данные
assign memory_write = data_write && cache_can_update;
assign memory_out = cache_value_update;

// память может задержаться на несколько тактов
// обновлять можно только тогда, когда нужное значение есть в наличии
assign cache_can_update = (data_read || data_write) && has_value
						|| (data_write && !write_need_request);
wire [31:0] cache_value_read = cache_hit ? cache_hit_value : memory_in;
assign cache_value_update = (cache_value_read & ~write_mask) | (aligned_data_in & write_mask);

wire [31:0] aligned_data_out = cache_value_read >> address_tail * 8;

wire data_write_ready = write_requested && memory_ready;
assign data_ready = data_read_ready || data_write_ready;

// выдаём запрошенные данные
always@(posedge clock) begin
	write_requested <= reset ? 0 : memory_write;
	data_read_ready <= reset ? 0 : data_read && has_value;
	data_out <= reset ? 32'hz : data_read && has_value ? aligned_data_out : 32'hz;
end

endmodule
