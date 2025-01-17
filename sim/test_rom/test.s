#include "auv.h"

.section .text
.balign 4
.global _start

_start:
	la t0, .trap_vector
	csrw mtvec, t0
	li t0, 0b0000100010000000
	csrw mie, t0
	la s0, .data
	addi sp, s0, 256
	
main:
	mv t0, zero
mloop:
	sw t0, 0(s0)
	addi t0, t0, 1
	j mloop
	nop
	
_trap_service:
	csrr a0, mcause
	la t0, .data
	sw a0, 4(t0)
	wfi
	nop
	
	
.section .trap_vector, "ax"
.balign 64
.global _trap_vector

_trap_vector:
	j _trap_service
	nop
