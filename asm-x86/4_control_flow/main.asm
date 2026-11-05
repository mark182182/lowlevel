.intel_syntax noprefix
# expose _start symbol to other object files during linking
.global _start

.include "../util.asm"

.section .rodata
x:      .byte 8  # 8-bit
y:      .word 16 # 16-bit
z:      .long 32 # 32-bit
w:      .quad 64 # 64-bit

nums:   .quad x, y, z, w

.section .text
_start:
    call ut_log_start

# TODO: remove the given number from the array (x, y, z, w) based on what is provided by the user

    mov rax, 60
    mov rdi, rsi
    syscall
