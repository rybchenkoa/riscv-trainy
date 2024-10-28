MEMORY
{
    MEM (rwx) : ORIGIN = 0x00000000, LENGTH = 65536
}
SECTIONS
{
    .text :
    {
        _text = .;
        *boot*.o(.text)
        *(.text*)
        _etext = .;
    } > MEM
    .data :
    {
        _data = .;
        *(.rodata*)
        *(.data*)
        _global = . + 0x800;
        *(.sbss*)
        *(.bss*)
        *(.sdata*)
        *(.*)
        _edata = .;
        . = ALIGN(4);
    } > MEM
   PROVIDE ( _stack = ORIGIN(MEM) + LENGTH(MEM) );
}
