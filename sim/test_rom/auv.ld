ENTRY(_start)

MEMORY
{
	ROM(rx)		: ORIGIN = 0x000000, LENGTH = 0x0400
	RAM(rw)		: ORIGIN = 0x010000, LENGTH = 0x0200
}

SECTIONS
{
	. = 0x0;
	
	.text : {
		#(.text)
	} > ROM
	
	.trap_vector ALIGN(64) : {
		#(.trap_vector)
	} > ROM
	
	.rodata : {
		#(.rodata)
	} > ROM
	
	.data_init : {
		#(.data)
	} > ROM
	
	.data : {
		#(.data)
	} > RAM
	
	.bss : {
		#(.bss)
	} > RAM
	
	. = 0x400;
}
