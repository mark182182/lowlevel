.intel_syntax noprefix
.global _start

# every macro and label should be prefixed with UT_ or ut_

.section .rodata
start_msg:
    .ascii "Starting\n"
    start_msg_len = .- start_msg

.macro UT_LOG msg, len
    mov rax, 1 # write
    mov rdi, 1 # stdout
    lea rsi, [rip+ \msg]
    mov rdx, \len
    syscall
.endm

.section .text

ut_log_start:
    UT_LOG start_msg, start_msg_len
    ret
