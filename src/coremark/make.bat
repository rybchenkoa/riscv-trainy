set gcc_bin=E:\проекты\RISC-V\xpack-riscv-none-elf-gcc-12.2.0-3\bin\riscv-none-elf
set arch=rv32e
set abi=ilp32e

set COMPILER_FLAGS=\"compiler_flags\"
set ccflags=-march=%arch% -mabi=%abi% -ffreestanding -I "./src" -O2 -DPERFORMANCE_RUN=1 -DITERATIONS=1 -DCOMPILER_FLAGS=%COMPILER_FLAGS% 
set ldflags=-Tcore.ld -Map coremark.map -m elf32lriscv

rmdir /q /s build
del /q coremark.hex
del /q coremark.bin
del /q coremark.map
del /q coremark.o
del /q coremark.S
mkdir build

%gcc_bin%-gcc %ccflags% -c src/core_list_join.c -o build/core_list_join.o
%gcc_bin%-gcc %ccflags% -c src/core_main.c -o build/core_main.o
%gcc_bin%-gcc %ccflags% -c src/core_matrix.c -o build/core_matrix.o
%gcc_bin%-gcc %ccflags% -c src/core_state.c -o build/core_state.o
%gcc_bin%-gcc %ccflags% -c src/core_util.c -o build/core_util.o
%gcc_bin%-gcc %ccflags% -c src/core_portme.c -o build/core_portme.o
%gcc_bin%-gcc %ccflags% -c src/ee_printf.c -o build/ee_printf.o
%gcc_bin%-gcc %ccflags% -c mylib.c -o build/mylib.o
%gcc_bin%-gcc %ccflags% -c boot.s -o build/boot.o

%gcc_bin%-gcc %ccflags% -fverbose-asm -S src/core_state.c -o build/core_state.s
%gcc_bin%-gcc %ccflags% -fverbose-asm -S src/core_list_join.c -o build/core_list_join.s
%gcc_bin%-gcc %ccflags% -fverbose-asm -S mylib.c -o build/mylib.s

%gcc_bin%-ld %ldflags% -o coremark.o build/boot.o build/core_list_join.o build/core_main.o build/core_matrix.o build/core_state.o build/core_util.o build/core_portme.o build/ee_printf.o build/mylib.o

%gcc_bin%-objdump -D -S coremark.o > coremark.S
%gcc_bin%-objcopy -O binary --reverse-bytes=4 coremark.o coremark.bin

pause