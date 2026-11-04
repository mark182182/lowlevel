.intel_syntax noprefix
.globl _start

# GNU assembler processes the macros while reading the source code, so we have to put these macro definitions on top
.macro log msg, len
# 1 write       eax 0x01        edi unsigned int fd         esi const char *buf     edx size_t count
# fd purpose   
# 0 stdin
# 1 stdout
# 2 stderr
    mov rax, 1 # write
    mov rdi, 1 # stdout
# lea calculates the memory address of \msg and sets it into RSI
# rip is the instruction pointer holding the address and [] means that we are accessing the absolute address of the label
# rip is used for relative addressing
    lea rsi, [rip+ \msg]
    mov rdx, \len
    syscall
.endm

.section .rodata

log_msg:
    .ascii "Starting\n"
log_msg_end:
# . represents the current assembly location, so at this location let's say in another example
# we are at 0x1004, since the . tracks the current address and log_msg is a label which has an address that can be retrieved by its name (log_msg)
# at 0x1000, so in the example . is 0x1004 and substracting log_msg (0x1000) yields the length at 4
    msg_len = .- log_msg

exit_msg:
    .ascii "Exiting\n"
    exit_msg_len = .- exit_msg

.section .text

_start:
    log log_msg, msg_len

# another way of calculating the length would be to get the start and end addresses and substract the start from the end to get the length (same as above)
    lea rsi, [rip+ log_msg]
    lea rbp, [rip+ log_msg_end]
    sub rbp, rsi

    cmp rbp, msg_len
# exit with error, if the two numbers are not equal
    jne exit_with_error

    mov rax, 60
    mov rdi, 64
    log exit_msg, exit_msg_len
    syscall

exit_with_error:
    mov rax, 60
    mov rdi, 1
    syscall
