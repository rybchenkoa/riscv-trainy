//доступные расширения

//embedded, 16 базовых регистров
`define __RV32E__

//аппаратное умножение и деление целых чисел
`define __MULTIPLY__
//умножение и деление за один такт
//`define __FAST_MUL__
//`define __FAST_DIV__

`ifdef    __ICARUS__
	`define  SIMULATION
`endif

// размер кэша инструкций и данных
// в обоих случаях полезно иметь хотя бы 1 элемент
// для инструкций - чтобы не занимать постоянно шину памяти
// для данных - чтобы делать побайтовую обработку
`define CACHE_INSTRUCTIONS_SIZE 8
`define CACHE_DATA_SIZE 8

// количество регистров в ядре
//для embedded число регистров меньше
`ifdef __RV32E__
    `define REG_COUNT 16
`else
    `define REG_COUNT 32
`endif
