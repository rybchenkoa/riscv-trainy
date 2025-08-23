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

// хранилище данных кэша
reg [31:0]   cache_value   [0:SIZE-1];  // значения самой памяти
reg [31-2:0] cache_address [0:SIZE-1];  // виртуальные адреса
reg          cache_filled  [0:SIZE-1];  // значение есть в наличии

// ниже всё должно быть wire
reg          cache_address_equal[0:SIZE-1]; // совпал входной адрес ячейки
reg          cache_move_next    [1:SIZE-1]; // надо ли читать данные сверху
reg          cache_hit;            // есть ли элемент с таким адресом
reg  [31:0]  cache_hit_value;      // значение элемента по запрошенному адресу
wire         cache_can_update;     // можно ли записать элемент наверх
wire [31:0]  cache_value_update;   // какое значение вписать

integer i;

// пробрасываем ответ памяти на первую позицию
reg [31:0]   temp_value   [0:SIZE-1];
reg          temp_filled  [0:SIZE-1];
wire [31:0] cache_value_0;
wire cache_filled_0;

always@(*) begin
	for(i = 0; i < SIZE; i = i + 1) begin
		temp_value[i] = cache_value[i];
		temp_filled[i] = cache_filled[i];
	end
	
	if (cache_can_update) begin
		temp_value[0] = cache_value_0;
		temp_filled[0] = cache_filled_0;
	end
end

// находим положение нужного элемента и заливаем флаги
// это как бы шина адреса
always@(*) begin
	cache_hit = 0;
	cache_hit_value = 0;
	for(i = 0; i < SIZE; i = i + 1) begin
		cache_address_equal[i] = (cache_address[i] == data_address[31:2]) && temp_filled[i];
		if (i > 0) begin
			cache_move_next[i] = !cache_hit;
		end
		cache_hit = cache_hit | cache_address_equal[i];
		cache_hit_value = cache_hit_value | (cache_address_equal[i] ? temp_value[i] : 0);
	end
end

// если к кэшу есть запрос, значит сверху в любом случае появится новое значение
// хотя возможно оно и будет взято из этого же регистра
// поэтому сдвигаем сразу до запрошенного адреса или до конца
wire cache_can_move = (data_read || data_write) && temp_filled[0];
wire cache_save_address = data_read || data_write;

// когда появляются данные, пишем их в начало списка
// или на новую позицию, если пришёл следующий запрос
always@(posedge clock) begin
	if (cache_can_move) begin 
		for(i = 1; i < SIZE; i = i + 1) begin
			if (cache_move_next[i]) begin
				cache_value[i] <= temp_value[i-1];
				cache_address[i] <= cache_address[i-1];
			end
		end
	end
	else if (cache_can_update) begin
		// если сдвига нет, а предыдущий результат есть, пишем в начало
		cache_value[0] <= temp_value[0];
	end
	
	if (cache_save_address) begin
		cache_address[0] <= data_address[31:2];
	end
	
	if (reset) begin
		for(i = 0; i < SIZE; i = i + 1) begin
			cache_filled[i] <= 0;
		end
	end
	else if (cache_can_move) begin
		for(i = 1; i < SIZE; i = i + 1) begin
			if (cache_move_next[i]) begin
				cache_filled[i] <= temp_filled[i-1];
			end
		end
		//даже если значение стояло на первом месте, переносим его в выходной регистр
		cache_filled[0] <= 0;
	end
	else if (cache_can_update) begin
		cache_filled[0] <= temp_filled[0];
	end
end

// подключили управление к хранилищу, теперь обрабатываем операции
//этап 0 ======================================
assign memory_address = `ONLY_SIM( !(memory_read || memory_write) ? 32'hz : ) 
						{data_address[31:2], 2'b0};

// декодируем инструкцию
// запись при первой попытке преобразуется в чтение, если меняем часть слова, которого нет в кэше
wire write_need_request;   // нужно ли перед записью запросить данные из памяти
wire write_to_read = data_write && !cache_hit && write_need_request;

// если нет значения - читаем
assign memory_read = !cache_hit && data_read || write_to_read;

// если есть значение и надо записать - пишем
assign memory_write = data_write && !write_to_read;
assign memory_out = cache_value_update;

// маска для записи некоторых байт (для чтения маска накладывается в ядре)
// TODO нужна проверка выхода за границы слова?
wire [1:0] address_tail = data_address[1:0];
wire [3:0] byte_enable = !data_write? 0 : 
                   data_width == 0 ? 4'b0001 << address_tail :
                   data_width == 1 ? 4'b0011 << address_tail :
                                  4'b1111;
wire [31:0] write_mask = {{8{byte_enable[3]}}, {8{byte_enable[2]}}, {8{byte_enable[1]}}, {8{byte_enable[0]}}};
// выровненное до нужного адреса входное значение
wire [31:0] aligned_data_in = data_in << address_tail * 8;
assign cache_value_update = (cache_hit_value & ~write_mask) | (aligned_data_in & write_mask);
assign write_need_request = (byte_enable != 4'b1111);

//этап 1 ======================================
// здесь надо обработать ответ памяти и кэша
reg stage1_is_read;
reg stage1_is_write;
reg stage1_hit;
reg [31:0] stage1_hit_value;
reg [1:0] stage1_address_tail; // на сколько байт сдвинуть ответ

always@(posedge clock) begin
	stage1_is_read <= reset ? 0 : data_read;
	stage1_is_write <= reset ? 0 : data_write;
	stage1_hit <= reset ? 0 : (cache_hit || data_write && !write_need_request);
	stage1_hit_value <= cache_value_update;
	stage1_address_tail <= address_tail;
end

// если процессор запрашивал чтение, то инструкция готова, если значение есть
wire stage1_read_ready = stage1_is_read && (memory_ready || stage1_hit);

// если запрашивали запись, достаточно получить подтверждение памяти
wire stage1_write_ready = stage1_is_write && memory_ready && stage1_hit;

// обе инструкции меняют значение на вершине
// само значение, как бы попавшее на вершину
wire [31:0] stage1_out_value = stage1_hit ? stage1_hit_value : memory_in;

// выдаём ответ процессору
assign data_ready = stage1_read_ready || stage1_write_ready;

// значение сдвигаем до нужного байта
assign data_out = `ONLY_SIM( !stage1_read_ready ? 32'hz : )
					(stage1_out_value >> stage1_address_tail * 8);

// пробрасываем значения назад
assign cache_filled_0 = stage1_hit || memory_ready;
assign cache_value_0 = stage1_out_value;
assign cache_can_update = stage1_is_read || stage1_is_write;

endmodule
