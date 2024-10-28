	.globl  _start

_start:
	la   sp, _stack
	la   gp, _global
	call  main




