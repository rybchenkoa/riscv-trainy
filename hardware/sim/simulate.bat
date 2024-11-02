::компилируем файл для икаруса
"E:\проекты\RISC-V\iverilog\bin\iverilog.exe" -I ../core -o tmp_sim core_tb.v ../core/core.v ../core/registers.v ../core/alu.v

::симулируем
"E:\проекты\RISC-V\iverilog\bin\vvp.exe" tmp_sim

::смотрим результат
::"E:\проекты\RISC-V\iverilog\gtkwave\bin\gtkwave.exe" core_tb.vcd

pause