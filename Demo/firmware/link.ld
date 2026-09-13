/* Minimal DDR layout used by the KV260 validation firmware. */
ENTRY(_start)
SECTIONS {
 . = 0x100000;
 .text : { *(.text.boot) *(.text*) }
 .rodata : { *(.rodata*) }
 .data : { *(.data*) }
 . = ALIGN(8);
 __bss_start = .;
 .bss : { *(.bss*) *(COMMON) }
 . = ALIGN(8);
 __bss_end = .;
}
