// Minimal EL3 entry point for the reproducible KV260 validation firmware.
.section .text.boot
.global _start
_start:
    msr daifset, #15
    mrs x0, sctlr_el3
    bic x0, x0, #1
    bic x0, x0, #4
    bic x0, x0, #4096
    msr sctlr_el3, x0
    isb
    ldr x0, =0x200000
    mov sp, x0
    ldr x0, =__bss_start
    ldr x1, =__bss_end
1:  cmp x0,x1
    b.hs 2f
    str xzr,[x0],#8
    b 1b
2:  bl main
.global test_finished
test_finished:
    dsb sy
    b test_finished
