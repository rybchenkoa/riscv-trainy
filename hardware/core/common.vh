//доступные расширения

//embedded, 16 базовых регистров
`define __RV32E__

//аппаратное умножение и деление целых чисел
`define __MULTIPLY__

`ifdef    __ICARUS__
	`define  SIMULATION
`endif

`ifdef __RV32E__
    `define REG_COUNT 16 //для embedded число регистров меньше
`else
    `define REG_COUNT 32
`endif
