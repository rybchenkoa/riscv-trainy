::��������㥬 䠩� ��� ������
"E:\�஥���\RISC-V\iverilog\bin\iverilog.exe" -I ../core -o tmp_sim ^
core_tb.v ^
../core/core.v ^
../core/registers.v ^
../core/alu.v ^
../core/alu_mul.v ^
../core/fast_div.v ^
../core/bus.v ^
../core/cache.v

::ᨬ㫨�㥬
"E:\�஥���\RISC-V\iverilog\bin\vvp.exe" tmp_sim

::ᬮ�ਬ १����
::"E:\�஥���\RISC-V\iverilog\gtkwave\bin\gtkwave.exe" core_tb.vcd

pause