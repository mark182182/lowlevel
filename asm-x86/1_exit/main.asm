# NOTE: don't mix and match 32-bit and 64-bit registers, only stick with 64 or 32 depending on the system
.intel_syntax noprefix
.globl _start

_start:
    mov rax, 60 # this sets the exact syscall number, see e.g. https:#syscalls.w3challs.com/?arch=x86_64. Means 60 (or 0x3c) to call the exit function that has the int error_code parameter which should be set at edi
    mov rdi, 64 # this sets the error code based on the above (at edi for 32-bit or rdi for 64-bit)
    syscall # the actual syscall that is performed
