::��������㥬 䠩� ��� ������
"E:\�஥���\RISC-V\iverilog\bin\iverilog.exe" -I ../core -o tmp_sim core_tb.v ../core/core.v ../core/registers.v ../core/alu.v

::ᨬ㫨�㥬
"E:\�஥���\RISC-V\iverilog\bin\vvp.exe" tmp_sim

::ᬮ�ਬ १����
::"E:\�஥���\RISC-V\iverilog\gtkwave\bin\gtkwave.exe" core_tb.vcd

pause