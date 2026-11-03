.intel_syntax noprefix
.globl _start
_start:
    mov     eax, 60 # this sets the exact syscall number, see e.g. https:#syscalls.w3challs.com/?arch=x86_64. Means 60 (or 0x3c) to call the exit function that has the int error_code parameter which should be set at edi
    mov     edi, 128 # this sets the error code based on the above (at edi for 32-bit or rdi for 64-bit)
    syscall # the actual syscall that is performedF
