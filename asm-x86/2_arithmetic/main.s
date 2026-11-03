.intel_syntax noprefix
.globl _start

_start:
    call _adder # need to invoke call for a given function
    mov eax, 60
    mov edi, ebx # retrieves the value from ebx that was calculated and sets into edi
    syscall

_adder:
# adds numbers from a 64-bit register (ebx) and 8-bit register (bl) I chose. this demonstrate that ebx and bl overlap and one way to add ebx to the value in bl is using movzx (or other conversions)
    mov ebx, 64
    mov bl, 64
    movzx ebp, bl # mixing 64-bit and 8-bit registers that use the overlapping portions of the same registers (e.g. rax, eax, eax, al would overlap), we DO NOT want that, so we are moving the value from bl into a register of the same with that the add operation is using (ebp in this case that can be added to ebx)
    add ebx, ebp # must have matching widths
    ret
