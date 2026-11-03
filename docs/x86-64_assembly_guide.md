# x86-64 assembly, step by step

Linux, GNU `as`, Intel syntax. Complete programs were run and the outputs and exit codes quoted are what I got, but only on that one setup. Short fragments (the `if`/`for` templates, the `div` example) are patterns, not run on their own.

## 0. Setup

Build and run, no libc:

```sh
as prog.s -o prog.o && ld prog.o -o prog && ./prog; echo $?
```

`$?` is the exit status (0-255). Early on it is your only output channel. Debugging: `gdb ./prog` then `layout asm`, `stepi`, `info registers`; `objdump -d -M intel prog`; `strace ./prog`.

A minimal gdb session (break at a function, inspect the stack on entry):

```sh
gdb -q ./prog
(gdb) set disassembly-flavor intel
(gdb) break fact
(gdb) run
(gdb) info registers rdi          # first argument
(gdb) p/x $rsp                    # stack pointer at function entry
(gdb) x/2gx $rsp                  # [rsp] = return address, then what was above it
(gdb) x/i $pc                     # the instruction about to run
(gdb) stepi                       # one instruction
(gdb) continue
```

On Program 6 below, this shows `rdi = 5`, an `rsp` whose last hex digit is `8` (8 mod 16, as chapter 6 says), and a return address at `[rsp]` that points back into `_start`. Breaking on a label works because `ld` keeps it as a symbol.

Every file starts with:

```x86asm
.intel_syntax noprefix
```

## 1. The machine in six lines

- The CPU keeps working data in registers (few, fast). Memory is a big array of bytes addressed by number.
- x86 is little-endian: the lowest byte of a value sits at the lowest address.
- `rip` holds the address of the next instruction. Jumps change it.
- `rflags` holds flag bits that arithmetic and compare instructions set. Conditional jumps read them.
- The stack is a region of memory. `rsp` points at its top. It grows toward lower addresses.
- Instructions look like `op dest, src`. At most one operand may be memory.

## 2. Registers

| 64-bit     | 32           | 16           | 8 (low)      | What it is used for                                                                                     |
| ---------- | ------------ | ------------ | ------------ | ------------------------------------------------------------------------------------------------------- |
| `rax`      | `eax`        | `ax`         | `al`         | return value, syscall number, implicit in `mul`/`div`                                                   |
| `rbx`      | `ebx`        | `bx`         | `bl`         | general; callee-saved                                                                                   |
| `rcx`      | `ecx`        | `cx`         | `cl`         | 4th argument, shift count, `rep` counter; destroyed by `syscall`                                        |
| `rdx`      | `edx`        | `dx`         | `dl`         | 3rd argument; high half in `mul`/`div`                                                                  |
| `rsi`      | `esi`        | `si`         | `sil`        | 2nd argument; source of `rep movs`                                                                      |
| `rdi`      | `edi`        | `di`         | `dil`        | 1st argument; destination of `rep movs`                                                                 |
| `rbp`      | `ebp`        | `bp`         | `bpl`        | general; callee-saved; frame pointer by convention                                                      |
| `rsp`      | `esp`        | `sp`         | `spl`        | stack pointer. Do not use as general purpose                                                            |
| `r8`-`r15` | `r8d`-`r15d` | `r8w`-`r15w` | `r8b`-`r15b` | `r8`, `r9` = args 5, 6; `r10` = 4th syscall arg; `r11` destroyed by `syscall`; `r12`-`r15` callee-saved |

Two rules you must know:

- Writing a **32-bit** register zeroes the upper 32 bits. So `mov eax, 1` sets all of `rax` to 1, and `xor eax, eax` zeroes all of `rax`.
- Writing an **8-bit or 16-bit** register leaves the rest of the register unchanged.

Calling convention (System V, used by Linux): function arguments go in `rdi, rsi, rdx, rcx, r8, r9`; return value in `rax`. System calls use `rdi, rsi, rdx, r10, r8, r9`. The 4th argument differs (`r10`, not `rcx`) because `syscall` overwrites `rcx`.

### Program 1: exit with a chosen status

```x86asm
.intel_syntax noprefix
.globl _start
.text
_start:
    mov  eax, 60            # syscall number: exit
    mov  edi, 42            # argument 1: status
    syscall
```

Runs, prints nothing, `echo $?` shows `42`. `.globl _start` exports the entry symbol so the linker finds it. `.text` starts the code section.

### Program 2: see the two write rules

```x86asm
_start:
    mov  rdi, -1            # all 64 bits set
    mov  edi, 7             # 32-bit write: upper half becomes zero
    shr  rdi, 32            # shift the upper half down: now 0
    mov  eax, 60
    syscall
```

Exit status `0`. Change `mov edi, 7` to `mov dil, 7`: the upper bits survive, `rdi >> 32` is `0xFFFFFFFF`, and the status (low 8 bits) is `255`.

## 3. Memory and data

Data directives, each emits bytes at the current position:

| Directive                             | Emits                                                  |
| ------------------------------------- | ------------------------------------------------------ |
| `.byte` / `.word` / `.long` / `.quad` | 1 / 2 / 4 / 8 byte integers                            |
| `.ascii "hi"` / `.asciz "hi"`         | the bytes / the bytes plus a trailing 0                |
| `.fill n, size, value`                | `n` repetitions                                        |
| `.skip n`                             | `n` zero bytes (in `.bss`, takes no space in the file) |
| `.balign n`                           | pad to an `n`-byte boundary                            |

Sections: `.text` code, `.rodata` read-only data, `.data` writable initialized data, `.bss` writable zero-initialized data. A label (`name:`) is the address of whatever comes next.

Memory operands:

```x86asm
[rax]                    # memory at the address in rax
[rax + 8]                # base + displacement
[rsi + rcx*8]            # base + index*scale, scale is 1, 2, 4 or 8
[rip + label]            # address of a label, relative to the current instruction
```

Rules: use `lea rsi, [rip + label]` to get an address. `lea` computes the address without touching memory. When no register tells the size, you must say it: `mov dword ptr [rdi], 0`, `cmp byte ptr [rsi], 10`. Sizes: `byte`, `word`, `dword` (4), `qword` (8).

### Program 3: sum an array

```x86asm
.intel_syntax noprefix
.globl _start
.section .rodata
nums:   .quad 10, 20, 30, 40, 50
.text
_start:
    lea  rsi, [rip + nums]      # rsi = address of the array
    xor  eax, eax               # sum = 0
    xor  ecx, ecx               # i = 0
.Lloop:
    add  rax, [rsi + rcx*8]     # sum += nums[i]   (8 bytes per element)
    inc  rcx
    cmp  rcx, 5
    jb   .Lloop                 # while (i < 5)
    mov  rdi, rax               # status = sum
    mov  eax, 60
    syscall
```

Exit status `150`. `.L`-prefixed labels are local: they don't appear in the symbol table.

### Program 4: loads of different widths

```x86asm
.section .rodata
x:  .long -2
w:  .quad 0x1122334455667788
.text
_start:
    movsxd rax, dword ptr [rip + x]   # sign-extend 32 -> 64: rax = -2
    movzx  ecx, byte ptr [rip + w]    # zero-extend 8 -> 32: lowest byte
    add    rax, rcx                   # 0x88 - 2 = 134
    mov    rdi, rax
    mov    eax, 60
    syscall
```

Status `134`. It proves little-endian: the byte at the lowest address of `w` is `0x88`, the _last_ digits you wrote. `movsx`/`movsxd` widen signed values, `movzx` widens unsigned ones. Pick by whether the value is signed.

Bulk copy with the string instructions (direction flag is clear by ABI):

```x86asm
    lea  rsi, [rip + src]
    lea  rdi, [rip + dst]
    mov  ecx, 6
    rep  movsb                  # copy rcx bytes from [rsi] to [rdi]
```

### Structs and arrays

A struct is fields at fixed byte offsets. For `struct P { int32 x, y, hp; }` (12 bytes), `x` is at offset 0, `y` at 4, `hp` at 8, and element `i` starts at `base + i*12`. An index scale can only be 1, 2, 4 or 8, so compute the stride yourself (`lea rdx, [rcx + rcx*2]` is `i*3`) and use the scale for the field size.

```x86asm
.section .rodata
.balign 4
parts:  .long 1,2,10,  3,4,20,  5,6,30,  7,8,40      # four struct P
hp_soa: .long 10, 20, 30, 40                          # the same hp fields, stored separately
.text
_start:
    lea  rsi, [rip + parts]
    xor  eax, eax
    xor  ecx, ecx
.Laos:
    lea  rdx, [rcx + rcx*2]         # rdx = i*3
    add  eax, [rsi + rdx*4 + 8]     # parts[i].hp = base + (i*3)*4 + 8
    inc  ecx
    cmp  ecx, 4
    jb   .Laos
    mov  r8d, eax                   # AoS sum = 100
    lea  rsi, [rip + hp_soa]
    xor  eax, eax
    xor  ecx, ecx
.Lsoa:
    add  eax, [rsi + rcx*4]         # contiguous: one scaled index, no stride arithmetic
    inc  ecx
    cmp  ecx, 4
    jb   .Lsoa
    sub  eax, r8d                   # 0 if both layouts agree
    mov  edi, eax
    mov  eax, 60
    syscall
```

Exit status `0`. The two loops show why layout matters. Array-of-structs (AoS) reads `hp` every 12 bytes and pulls `x` and `y` through the cache with it. Struct-of-arrays (SoA) reads only the field you use, contiguously, which is also what SIMD loads want. Which one wins depends on what the loop touches, so measure.

## 4. Arithmetic and flags

| Instruction                 | Effect                                                                                               |
| --------------------------- | ---------------------------------------------------------------------------------------------------- |
| `add a, b` / `sub a, b`     | `a += b` / `a -= b`                                                                                  |
| `inc a` / `dec a` / `neg a` | `+1`, `-1`, two's-complement negate. `inc`/`dec` leave CF unchanged                                  |
| `imul a, b`                 | `a *= b`, signed, result truncated to 64 bits                                                        |
| `mul b`                     | `rdx:rax = rax * b`, unsigned, full 128-bit result                                                   |
| `div b`                     | `rax = rdx:rax / b`, `rdx = remainder`, unsigned. **Set `rdx` first**                                |
| `idiv b`                    | same, signed. Sign-extend `rax` into `rdx` with `cqo` first                                          |
| `and` `or` `xor` `not`      | bitwise                                                                                              |
| `shl` `shr` `sar`           | shift left / logical right (zero fill) / arithmetic right (sign fill). Count is an immediate or `cl` |
| `cmp a, b`                  | sets flags as `a - b` would, discards the result                                                     |
| `test a, b`                 | sets flags as `a & b` would, discards the result                                                     |

`div`/`idiv` by zero, or a quotient too big for `rax`, raises SIGFPE. Example: 100 / 7:

```x86asm
    mov  rax, 100
    xor  edx, edx           # rdx must be 0, because div divides rdx:rax
    mov  ecx, 7
    div  rcx                # rax = 14, rdx = 2
```

Flags (set by arithmetic, `cmp`, `test`; `mov`, `lea`, `jmp` never touch them):

| Flag | Set when                                               |
| ---- | ------------------------------------------------------ |
| ZF   | result was 0                                           |
| SF   | top bit of the result is 1                             |
| CF   | unsigned overflow (carry or borrow out of the top bit) |
| OF   | signed overflow                                        |

Conditional jumps read flags. After `cmp a, b`:

| `a ? b` | signed | unsigned |
| ------- | ------ | -------- |
| `<`     | `jl`   | `jb`     |
| `<=`    | `jle`  | `jbe`    |
| `>`     | `jg`   | `ja`     |
| `>=`    | `jge`  | `jae`    |
| `==`    | `je`   | `je`     |
| `!=`    | `jne`  | `jne`    |

Same bits, two interpretations: `-1` is `0xFFFFFFFFFFFFFFFF`, which is less than 0 signed and the largest value unsigned. You choose the interpretation by choosing the jump. Related: `setcc r8` stores 0/1 from a condition (`sete dl`), `cmovcc a, b` copies `b` into `a` only if the condition holds (`cmovg`, `cmovb`, ...).

### Program 5: signed vs unsigned, side by side

```x86asm
.intel_syntax noprefix
.globl _start
.section .rodata
vals:   .quad 5, -3, 7, -1, 2
.text
_start:
    lea  rsi, [rip + vals]
    xor  ecx, ecx           # i
    xor  r8d, r8d           # count of vals > 0, signed
    xor  r9d, r9d           # count of vals > 0, unsigned
.Lloop:
    mov  rax, [rsi + rcx*8]
    cmp  rax, 0
    jle  .Lskip_s           # signed: skip if rax <= 0
    inc  r8
.Lskip_s:
    cmp  rax, 0
    jbe  .Lskip_u           # unsigned: skip only if rax == 0
    inc  r9
.Lskip_u:
    inc  rcx
    cmp  rcx, 5
    jb   .Lloop
    lea  rdi, [r8 + r8*4]   # r8 * 5
    lea  rdi, [r9 + rdi*2]  # r9 + r8 * 10
    mov  eax, 60
    syscall
```

Status `35`: signed count 3 (5, 7, 2), unsigned count 5 (`-3` and `-1` are huge unsigned numbers). The two `lea` lines compute `r8*10 + r9` using only address arithmetic.

### Bit instructions and multiword arithmetic

| Instruction                 | Result                                                                   |
| --------------------------- | ------------------------------------------------------------------------ |
| `popcnt r, s`               | number of 1 bits                                                         |
| `tzcnt r, s` / `lzcnt r, s` | trailing / leading zero count; 64 for a zero input                       |
| `bsf r, s` / `bsr r, s`     | index of the lowest / highest set bit; destination undefined if `s` is 0 |
| `bt a, n`                   | copy bit `n` of `a` into CF                                              |
| `adc a, b` / `sbb a, b`     | `a + b + CF` / `a - b - CF`, for multiword arithmetic                    |

`popcnt`, `tzcnt` and `lzcnt` are not in the original x86-64 baseline (they need the POPCNT, BMI1 and LZCNT features; nearly all CPUs of the last decade have them). On a CPU without BMI1 the `tzcnt` encoding silently executes as `bsf`, which differs on a zero input.

```x86asm
    mov  rax, 0xF0F0
    popcnt rbx, rax                 # 8
    mov  rax, 0x50
    tzcnt rcx, rax                  # 4  (0x50 = 0b1010000)
    bsr  rdx, rax                   # 6
    xor  eax, eax
    tzcnt rsi, rax                  # 64: tzcnt of zero is defined
```

A 128-bit add: the carry out of the low halves goes into the high halves.

```x86asm
    add  rax, rcx                   # low halves; CF set on unsigned overflow
    adc  rdx, rsi                   # high halves + CF
```

Both fragments were run inside small programs (exit statuses 82 and 1 as expected).

## 5. Control flow patterns

C `if (a > b) { body }` (signed):

```x86asm
    cmp  rax, rbx
    jle  .Lskip             # jump on the opposite condition
    ...body...
.Lskip:
```

C `for (i = 0; i < n; i++)` with the test at the bottom (one jump per iteration):

```x86asm
    xor  ecx, ecx
    test rsi, rsi           # guard: skip the loop if n == 0
    jz   .Lend
.Lloop:
    ...body...
    inc  rcx
    cmp  rcx, rsi
    jb   .Lloop
.Lend:
```

Count-down loops are cheaper: `dec rsi` already sets ZF, so `dec rsi` / `jnz .Lloop` needs no `cmp`. If you do this, the loop body must see `n >= 1` (hence the guard).

### Jump tables (switch)

A dense `switch` becomes a table of code addresses and one indirect jump:

```x86asm
.section .rodata
.balign 8
table:  .quad .Lc0, .Lc1, .Lc2
.text
# select(i): switch (i) { case 0: 10; case 1: 20; case 2: 30; default: 99 }
select:
    cmp  rdi, 2
    ja   .Ldef                      # one unsigned compare also rejects negative i
    lea  rcx, [rip + table]
    jmp  [rcx + rdi*8]              # indirect jump through the table
.Lc0: mov eax, 10
    ret
.Lc1: mov eax, 20
    ret
.Lc2: mov eax, 30
    ret
.Ldef: mov eax, 99
    ret
```

`select(1)` returns 20 and `select(-5)` returns 99 (I ran both). Absolute 64-bit addresses in the table work for a plain static executable. Position-independent code stores 32-bit offsets from the table instead. For very few cases a compare chain is usually as good as a table, so measure before assuming.

## 6. The stack and functions

- `push x`: `rsp -= 8`, store `x` at `[rsp]`. `pop x`: load, `rsp += 8`.
- `call f`: push the address of the next instruction, jump to `f`. `ret`: pop an address into `rip`.
- **Caller-saved** (a call may destroy them): `rax rcx rdx rsi rdi r8-r11`, all `xmm`. **Callee-saved** (a function must restore them before returning): `rbx rbp r12-r15`, and `rsp` itself.
- **Alignment:** `rsp` must be a multiple of 16 at the moment of a `call`. At function entry it is 8 modulo 16 (the return address was just pushed). One `push` or `sub rsp, 8` realigns it. `_start` is not called, and `rsp` is a multiple of 16 on entry there (I checked).
- A leaf function (calls nothing) that uses only caller-saved registers needs no stack work at all.

### Program 6: recursive factorial

```x86asm
.intel_syntax noprefix
.globl _start
.text
# u64 fact(u64 n)      n in rdi, result in rax
fact:
    cmp  rdi, 1
    ja   .Lrec
    mov  eax, 1
    ret
.Lrec:
    push rbx                # we want rbx, and it is callee-saved: save it
    mov  rbx, rdi           # keep n across the call
    dec  rdi
    call fact               # rax = fact(n-1)
    imul rax, rbx           # rax = n * fact(n-1)
    pop  rbx                # restore, in reverse order of the pushes
    ret

_start:
    mov  edi, 5
    call fact
    mov  rdi, rax           # 120
    mov  eax, 60
    syscall
```

Status `120`. Alignment check inside `fact`: entry is 8 mod 16, after `push rbx` it is 0 mod 16, so the recursive `call` is aligned. Step through it with `gdb` and watch `rsp` and the return addresses on the stack (`x/6gx $rsp`).

### Locals and stack arguments

A function with local variables, or with more than six integer arguments, uses the stack. With a frame pointer, locals sit below `rbp`, and stack arguments sit above the saved `rbp` and the return address:

```x86asm
.intel_syntax noprefix
.globl _start
.text
# long f7(a..f in rdi,rsi,rdx,rcx,r8,r9; g on the stack) = a+b+c+d+e+f+g
f7:
    push rbp
    mov  rbp, rsp
    sub  rsp, 16                    # locals; rsp: entry 8, after push 0, after sub 0 (mod 16)
    lea  rax, [rdi + rsi]
    add  rax, rdx
    add  rax, rcx
    add  rax, r8
    add  rax, r9
    mov  [rbp - 8], rax             # a local variable
    mov  rax, [rbp + 16]            # [rbp] = saved rbp, [rbp+8] = return address, [rbp+16] = 7th arg
    add  rax, [rbp - 8]
    mov  rsp, rbp                   # drop the locals
    pop  rbp
    ret

_start:
    mov  edi, 1
    mov  esi, 2
    mov  edx, 3
    mov  ecx, 4
    mov  r8d, 5
    mov  r9d, 6
    sub  rsp, 8                     # padding: the pushed argument must not leave rsp misaligned
    push 7                          # 7th argument
    call f7
    add  rsp, 16                    # remove argument and padding
    mov  rdi, rax                   # 28
    mov  eax, 60
    syscall
```

Status `28`. Arguments beyond the sixth are pushed right to left and the caller removes them. `rsp` must be 16-aligned at the `call`, so an odd number of pushed arguments needs 8 bytes of padding. A leaf function may also use the 128 bytes below `rsp` (the red zone) without moving `rsp`, because signal delivery skips that area. A function that makes calls must not rely on it.

## 7. System calls and I/O

`syscall` hands control to the kernel. Number in `rax`, arguments in `rdi, rsi, rdx, r10, r8, r9`. The result comes back in `rax`; a value from `-4095` to `-1` is `-errno`. The kernel destroys `rcx` and `r11`.

| Call                    | `rax` | `rdi`  | `rsi`       | `rdx` |
| ----------------------- | ----- | ------ | ----------- | ----- |
| `read(fd, buf, count)`  | 0     | fd     | buf address | count |
| `write(fd, buf, count)` | 1     | fd     | buf address | count |
| `exit(status)`          | 60    | status |             |       |

File descriptors: 0 stdin, 1 stdout, 2 stderr. `read` returns the number of bytes read, 0 at end of input, and may return fewer bytes than asked for (often, on pipes). The `print_u64` function in the capstone shows `write` in use and a `div`-based number-to-text conversion.

### Virtual memory: mmap, mprotect, page faults, and /proc

What "memory" means to your program:

- Every address you use is **virtual**. The CPU's MMU translates each load and store through page tables that the kernel maintains, in fixed-size pages (4096 bytes on x86-64; `getconf PAGESIZE` tells you).
- A load or store does **not** call the OS. It just uses the address. If the page is not mapped, or the access breaks the page's permissions, the CPU raises a _page fault_ and the kernel decides: either it fixes things up (for example by supplying a zeroed page the first time you touch fresh anonymous memory), or it kills the process with SIGSEGV. A shell reports that as status 139, which is 128 + 11.
- To get memory, change its permissions, or give it back, you ask the kernel with system calls. After that, reading and writing it is ordinary `mov`.
- Your own process's layout is visible in `/proc/self/maps`. Kernel memory is not accessible from user mode at all, and another process's memory is reachable only through mechanisms that need permission (`/proc/<pid>/mem`, `ptrace`, `process_vm_readv`).

| Call                                    | `rax` | `rdi`                         | `rsi`  | `rdx` | `r10` | `r8`          | `r9`   |
| --------------------------------------- | ----- | ----------------------------- | ------ | ----- | ----- | ------------- | ------ |
| `mmap(addr, len, prot, flags, fd, off)` | 9     | addr (0: kernel chooses)      | length | prot  | flags | fd (-1: none) | offset |
| `munmap(addr, len)`                     | 11    | addr                          | length |       |       |               |        |
| `mprotect(addr, len, prot)`             | 10    | addr                          | length | prot  |       |               |        |
| `brk(addr)`                             | 12    | new break (0: just report it) |        |       |       |               |        |

Constants: `PROT_NONE` 0, `PROT_READ` 1, `PROT_WRITE` 2, `PROT_EXEC` 4 (add them). `MAP_PRIVATE` 0x02 and `MAP_ANONYMOUS` 0x20 together are `0x22`: memory not backed by any file, zero-filled. Addresses and lengths for `mprotect` and `munmap` must be multiples of the page size. A raw system call returns the address or `-errno`. There is no libc-style `MAP_FAILED` value of -1 here, so test with `cmp rax, -4096` / `ja`.

### Program 7: get a page, use it, give it back

```x86asm
.intel_syntax noprefix
.globl _start
.text
_start:
    mov  eax, 9                     # mmap
    xor  edi, edi                   # addr = 0: let the kernel choose
    mov  esi, 4096                  # length
    mov  edx, 3                     # PROT_READ | PROT_WRITE
    mov  r10d, 0x22                 # MAP_PRIVATE | MAP_ANONYMOUS
    mov  r8, -1                     # fd = -1 (no file)
    xor  r9d, r9d                   # offset = 0
    syscall
    cmp  rax, -4096
    ja   .Lfail                     # unsigned compare: rax in [-4095, -1] means -errno
    mov  rbx, rax                   # rbx = base address of the new page
    mov  qword ptr [rbx], 40        # ordinary stores: no system call involved
    mov  qword ptr [rbx + 4088], 2  # last 8 bytes of the page
    mov  r12, [rbx]
    add  r12, [rbx + 4088]          # 40 + 2
    mov  eax, 11                    # munmap
    mov  rdi, rbx
    mov  esi, 4096
    syscall
    test rax, rax
    jnz  .Lfail
    mov  rdi, r12                   # status 42
    jmp  .Lexit
.Lfail:
    mov  edi, 99
.Lexit:
    mov  eax, 60
    syscall
```

Exit status `42`. The kernel typically allocates the physical page on first touch rather than at `mmap` time (I did not measure that here). After `munmap`, any access to that range faults.

### Program 8: a guard page

Map two pages, then remove all permissions from the second one with `mprotect`. This is the guard-page buffer your plan's tests use to catch over-reads: put the buffer so it ends exactly where the guard page begins.

```x86asm
_start:
    mov  eax, 9                     # mmap two pages
    xor  edi, edi
    mov  esi, 8192
    mov  edx, 3                     # read+write
    mov  r10d, 0x22
    mov  r8, -1
    xor  r9d, r9d
    syscall
    cmp  rax, -4096
    ja   .Lfail
    mov  rbx, rax
    mov  eax, 10                    # mprotect(base + 4096, 4096, PROT_NONE)
    lea  rdi, [rbx + 4096]
    mov  esi, 4096
    xor  edx, edx                   # PROT_NONE
    syscall
    test rax, rax
    jnz  .Lfail
    mov  byte ptr [rbx + 4095], 7   # last byte of the first page: fine
    movzx r12d, byte ptr [rbx + 4095]
    mov  byte ptr [rbx + 4096], 1   # first byte of the guard page: page fault -> SIGSEGV
    mov  edi, r12d                  # never reached
    jmp  .Lexit
.Lfail:
    mov  edi, 99
.Lexit:
    mov  eax, 60
    syscall
```

The shell prints `Segmentation fault` and `echo $?` shows `139`. Remove the last store and the program exits normally with status 7. In `gdb` the fault stops on the faulting instruction, and `info registers rip` tells you which one.

### Program 9: look at your own address space

Open `/proc/self/maps`, read it, and write it to stdout. `openat` is call 257 (`AT_FDCWD` is -100, `O_RDONLY` is 0); `close` is 3.

```x86asm
.intel_syntax noprefix
.globl _start
.section .rodata
path:   .asciz "/proc/self/maps"
.bss
buf:    .skip 4096
.text
_start:
    mov  eax, 257                   # openat(AT_FDCWD, path, O_RDONLY)
    mov  rdi, -100
    lea  rsi, [rip + path]
    xor  edx, edx
    syscall
    test rax, rax
    js   .Lfail
    mov  rbx, rax                   # fd
.Lloop:
    xor  eax, eax                   # read(fd, buf, 4096)
    mov  rdi, rbx
    lea  rsi, [rip + buf]
    mov  edx, 4096
    syscall
    test rax, rax
    js   .Lfail
    jz   .Ldone
    mov  rdx, rax                   # write(1, buf, n)
    mov  eax, 1
    mov  edi, 1
    lea  rsi, [rip + buf]
    syscall
    jmp  .Lloop
.Ldone:
    mov  eax, 3                     # close(fd)
    mov  rdi, rbx
    syscall
    xor  edi, edi
    jmp  .Lexit
.Lfail:
    mov  edi, 1
.Lexit:
    mov  eax, 60
    syscall
```

Output on my machine (this program is a static, non-PIE executable):

```sh
00400000-00401000 r--p 00000000 fe:00 573566    /tmp/g/v3
00401000-00402000 r-xp 00001000 fe:00 573566    /tmp/g/v3
00402000-00403000 r--p 00002000 fe:00 573566    /tmp/g/v3
00403000-00404000 rw-p 00000000 00:00 0
7f0d9a107000-7f0d9a10b000 r--p 00000000 00:00 0  [vvar]
7f0d9a10b000-7f0d9a10d000 r--p 00000000 00:00 0  [vvar_vclock]
7f0d9a10d000-7f0d9a10f000 r-xp 00000000 00:00 0  [vdso]
7fff88bd4000-7fff88bf5000 rw-p 00000000 00:00 0  [stack]
ffffffffff600000-ffffffffff601000 --xp 00000000 00:00 0  [vsyscall]
```

(I trimmed the column padding.) Reading it: the first column is the address range, the second the permissions (`r`, `w`, `x`, and `p` for private), then the file offset, device, inode and name. The first three lines are the executable itself: ELF headers, then code (`r-xp`), then read-only data. The `rw-p` page with no name is the `.bss`. `[stack]` is your stack, and `[vdso]` and `[vvar]` are kernel-provided pages. Stack and vdso addresses change on every run (address-space randomization), and the exact set of special lines depends on the kernel. Run it on your machine and compare it with what you expect from the section layout: where is the stack relative to your code, and which regions are writable and which executable?

Every `mmap` you make appears here as a new line. Add the Program 7 code before the read loop (and skip the `munmap`) and you will see a new 4 KiB `rw-p` region.

### Program 10: reading and writing memory through the kernel

`/proc/self/mem` is a file whose "offsets" are your virtual addresses. Reading or writing it with `pread64` (call 17) and `pwrite64` (call 18) makes the kernel read or write that address for you. The kernel does this on behalf of debuggers and similar tools, which is why it can write into a page your own `mov` could not:

```x86asm
.intel_syntax noprefix
.globl _start
.section .rodata
path:   .asciz "/proc/self/mem"
.balign 8
secret: .quad 41                    # read-only data
.bss
tmp:    .skip 8
.text
_start:
    mov  eax, 257                   # openat(AT_FDCWD, "/proc/self/mem", O_RDWR)
    mov  rdi, -100
    lea  rsi, [rip + path]
    mov  edx, 2                     # O_RDWR
    syscall
    test rax, rax
    js   .Lfail
    mov  rbx, rax                   # fd
    mov  eax, 17                    # pread64(fd, tmp, 8, offset = virtual address of secret)
    mov  rdi, rbx
    lea  rsi, [rip + tmp]
    mov  edx, 8
    lea  r10, [rip + secret]        # the "file offset" is just the virtual address
    syscall
    cmp  rax, 8
    jne  .Lfail
    mov  r12, [rip + tmp]           # 41, read through the kernel
    mov  qword ptr [rip + tmp], 1   # new value to write into the read-only page
    mov  eax, 18                    # pwrite64(fd, tmp, 8, address of secret)
    mov  rdi, rbx
    lea  rsi, [rip + tmp]
    mov  edx, 8
    lea  r10, [rip + secret]
    syscall
    cmp  rax, 8
    jne  .Lfail
    add  r12, [rip + secret]        # an ordinary load now sees 1: 41 + 1 = 42
    mov  rdi, r12
    jmp  .Lexit
.Lfail:
    mov  edi, 99
.Lexit:
    mov  eax, 60
    syscall
```

Exit status `42` on my machine: the program modified its own read-only data. Opening the memory of **another** process works the same way with `/proc/<pid>/mem`, but needs permission: the same user plus the system's `ptrace` policy, or root. Some hardened systems refuse even the self case, so a failure here is not a bug in your assembly.

### Program 11: the program break (`brk`)

`brk` is the older interface: the kernel keeps one "program break", the end of the heap, and you move it. Most allocators use `mmap` for large blocks and `brk` for small ones. For memory of your own, `mmap` is simpler.

```x86asm
.intel_syntax noprefix
.globl _start
.text
_start:
    mov  eax, 12                    # brk(0): returns the current program break
    xor  edi, edi
    syscall
    mov  rbx, rax
    lea  rdi, [rbx + 4096]          # ask for one more page
    mov  eax, 12
    syscall
    cmp  rax, rbx
    jbe  .Lfail                     # unchanged or smaller: failed
    mov  qword ptr [rbx], 42        # the new page [old break, old break + 4096) is writable
    mov  rdi, [rbx]
    jmp  .Lexit
.Lfail:
    mov  edi, 99
.Lexit:
    mov  eax, 60
    syscall
```

Exit status `42`.

### Program 12: locking a mapping with `mseal`

Page permissions are not final: `mprotect` can make a read-only page writable again, `munmap` can remove it, and `mmap` with `MAP_FIXED` can replace it. That is what an attacker with a memory-write bug uses to turn your data into code or to remove a guard page. `mseal` closes that door. It is system call **462**, the same number on x86-64 and AArch64, and was added in Linux 6.10, so check `uname -r` (an older kernel returns `-ENOSYS`, which is `-38`).

`mseal(addr, len, flags)`:

- `flags` must be 0. `addr` must be page-aligned. `len` is rounded up to whole pages. The whole range must be mapped.
- After it succeeds, the kernel refuses to change those mappings: `munmap`, `mremap`, `mprotect`, and `mmap` with `MAP_FIXED` over them fail with `-EPERM` (which is `-1`), and so do some destructive `madvise` calls. It cannot be undone. The seal lasts until the process exits.
- Sealing does **not** change the current permissions. A sealed read-write page stays writable. To make something immutable, set its permissions first and then seal it, as the program does.
- It protects the mapping (its range and permissions), not the contents of a writable page.

```x86asm
.intel_syntax noprefix
.globl _start
.text
_start:
    mov  eax, 9                     # mmap one read/write page
    xor  edi, edi
    mov  esi, 4096
    mov  edx, 3                     # PROT_READ | PROT_WRITE
    mov  r10d, 0x22                 # MAP_PRIVATE | MAP_ANONYMOUS
    mov  r8, -1
    xor  r9d, r9d
    syscall
    cmp  rax, -4096
    ja   .Lfail
    mov  rbx, rax                   # rbx = page address
    mov  qword ptr [rbx], 42        # put data in it
    mov  eax, 10                    # mprotect(page, 4096, PROT_READ): make it read-only
    mov  rdi, rbx
    mov  esi, 4096
    mov  edx, 1
    syscall
    test rax, rax
    jnz  .Lfail

    mov  eax, 462                   # mseal(page, 4096, 0)
    mov  rdi, rbx
    mov  esi, 4096
    xor  edx, edx
    syscall
    test rax, rax
    jnz  .Lnoseal                   # e.g. -ENOSYS on a kernel older than 6.10

    xor  r13d, r13d                 # r13 = bitmask of "the kernel refused, as expected"
    mov  eax, 10                    # mprotect(page, 4096, PROT_READ|PROT_WRITE): try to make it writable again
    mov  rdi, rbx
    mov  esi, 4096
    mov  edx, 3
    syscall
    cmp  rax, -1                    # -EPERM is -1
    jne  .L1
    or   r13d, 1
.L1:
    mov  eax, 11                    # munmap(page, 4096)
    mov  rdi, rbx
    mov  esi, 4096
    syscall
    cmp  rax, -1
    jne  .L2
    or   r13d, 2
.L2:
    mov  eax, 9                     # mmap(page, 4096, RW, MAP_FIXED|PRIVATE|ANON): try to replace the mapping
    mov  rdi, rbx
    mov  esi, 4096
    mov  edx, 3
    mov  r10d, 0x32                 # MAP_FIXED (0x10) | MAP_PRIVATE | MAP_ANONYMOUS
    mov  r8, -1
    xor  r9d, r9d
    syscall
    cmp  rax, -1
    jne  .L3
    or   r13d, 4
.L3:
    cmp  qword ptr [rbx], 42        # reading still works and the data is intact
    jne  .L4
    or   r13d, 8
.L4:
    mov  edi, r13d                  # 15 = all three changes refused and the data is intact
    jmp  .Lexit
.Lnoseal:
    mov  edi, 98
    jmp  .Lexit
.Lfail:
    mov  edi, 99
.Lexit:
    mov  eax, 60
    syscall
```

Exit status `15` on my machine (kernel 6.18): all three attempts to change the sealed page were refused and the value `42` was still readable. Status `98` means your kernel has no `mseal`. Delete the `mseal` block and the status drops to `0`, because then all three changes succeed and the data is gone.

I also checked the argument rules with a separate small program: `flags = 1` returned `-22` (`EINVAL`), a start address one byte past a page boundary returned `-22`, and a range that included an unmapped page returned `-12` (`ENOMEM`).

Where to use it: seal your guard pages (the `PROT_NONE` page from Program 8) so nothing can make them accessible again, and seal read-only tables after you finish filling them. Remember that a sealed region can never be freed or resized for the life of the process. Allocators, `realloc`, and anything that changes permissions at run time (a JIT, for example) must not touch a sealed range.

## 8. Mixing with C

Asm called from C. Export the label, follow the calling convention, declare it in C:

```x86asm
.intel_syntax noprefix
.globl sum
.text
# long sum(const long *p /*rdi*/, unsigned long n /*rsi*/)
sum:
    xor  eax, eax
    test rsi, rsi
    jz   .Ldone
.Lloop:
    add  rax, [rdi]
    add  rdi, 8
    dec  rsi
    jnz  .Lloop
.Ldone:
    ret
.section .note.GNU-stack,"",@progbits
```

```c
#include <stdio.h>
long sum(const long *p, unsigned long n);
int main(void) { long a[] = {1, 2, 3, 4}; printf("%ld\n", sum(a, 4)); return 0; }
```

`gcc main.c sum.s -o t && ./t` prints `10`. The last `.note.GNU-stack` line stops the linker warning about an executable stack.

C called from asm (here `printf`, linked with libc, so `gcc prog.s -o prog`, not `ld`):

```x86asm
.intel_syntax noprefix
.globl main
.section .rodata
fmt:    .asciz "sum = %ld\n"
.text
main:                       # libc calls main, so rsp is 8 mod 16 here
    sub  rsp, 8             # realign to 0 mod 16 before our own call
    lea  rdi, [rip + fmt]
    mov  esi, 123
    xor  eax, eax           # al = number of vector registers used (varargs rule)
    call printf@PLT
    xor  eax, eax           # return 0
    add  rsp, 8
    ret
.section .note.GNU-stack,"",@progbits
```

Prints `sum = 123`. The two classic mistakes with libc calls are a misaligned stack (crashes inside `printf`, often in an SSE instruction) and forgetting `al` for variadic functions.

## 9. SIMD with SSE2

SSE2 is part of the x86-64 baseline: every x86-64 CPU has it. There are sixteen 128-bit registers `xmm0`-`xmm15`. One register can be seen as 16 bytes, 8 words, 4 dwords, or 2 qwords (lanes). SIMD instructions do the same operation on every lane independently, with no carries between lanes. All `xmm` registers are caller-saved.

| Instruction                                   | What it does                                                                                                        |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `movdqu x, [m]` / `movdqu [m], x`             | load / store 16 bytes, any alignment                                                                                |
| `movdqa x, [m]`                               | same, but the address **must** be 16-aligned or the program faults                                                  |
| `movdqa x, y`                                 | register copy                                                                                                       |
| `movd x, r32` / `movq x, r64` / `movq r64, x` | move between general registers and the low lane                                                                     |
| `pcmpeqb x, y`                                | per byte: `0xFF` if equal, else `0`                                                                                 |
| `paddb` `paddw` `paddd` `paddq`               | per-lane add (byte, word, dword, qword). `psub*` subtracts                                                          |
| `pand` `por` `pxor`                           | bitwise (`pxor x, x` zeroes `x`)                                                                                    |
| `psadbw x, y`                                 | sums absolute byte differences in each 8-byte half. With `y` = 0, it sums the bytes of each half into a 64-bit lane |
| `psrldq x, n`                                 | shift the whole register right by `n` **bytes**                                                                     |
| `pmovmskb r32, x`                             | collect the top bit of each byte into a 16-bit mask in a general register                                           |

Two ideas that matter in practice:

- A compare produces a **mask**: all ones (`-1`) in matching lanes. Subtracting a mask from a counter adds 1 per match: `psubb acc, mask`.
- Byte counters overflow after 255 increments. So you accumulate in bytes for at most 255 iterations, then widen with `psadbw`.

Safety rule: never load bytes outside the buffer. A 16-byte load that starts inside `[p, p + n)` but ends beyond it can fault at a page boundary. Handle the last `n mod 16` bytes with a scalar loop.

### Finding the first match

For a `memchr`-style search you want the position, not a count. `pmovmskb` turns the compare mask into an integer and `tzcnt` finds its lowest set bit:

```x86asm
    movdqu  xmm0, [rip + blk]       # 16 bytes: "abcdefgh\nijklmn\n"
    pcmpeqb xmm0, [rip + nl16]      # 0xFF where the byte is '\n'
    pmovmskb eax, xmm0              # 16-bit mask, bit i = byte i matched
    tzcnt   edi, eax                # index of the first match: 8
```

If the mask is 0 nothing matched (`tzcnt` returns 32), so test `eax` with `test eax, eax` / `jz` first and move on to the next block.

## 10. Scalar floating point

Floats and doubles live in the same `xmm` registers as SIMD data, but scalar instructions use only the lowest lane (`ss` = scalar single, 4 bytes; `sd` = scalar double, 8 bytes). The packed versions (`ps`, `pd`) work on all lanes.

| Instruction                              | What it does                                                                           |
| ---------------------------------------- | -------------------------------------------------------------------------------------- |
| `movss x, [m]` / `movsd x, [m]`          | load a float / double into the low lane (a load from memory zeroes the other lanes)    |
| `addss` `subss` `mulss` `divss` `sqrtss` | scalar single arithmetic (`sd` for doubles). The second operand may be memory          |
| `minss` `maxss`                          | scalar min / max                                                                       |
| `cvtsi2ss x, r32`                        | int to float (`cvtsi2sd` for double)                                                   |
| `cvttss2si r32, x`                       | float to int, truncating toward zero (`cvtss2si` rounds per the current rounding mode) |
| `ucomiss a, b`                           | compare; sets ZF, PF, CF (not SF or OF)                                                |
| `movaps x, y`                            | register copy                                                                          |

ABI: floating-point arguments go in `xmm0`-`xmm7` (counted separately from the integer registers), and a float or double result comes back in `xmm0`.

```x86asm
.intel_syntax noprefix
.globl lerp
.text
# float lerp(float a /*xmm0*/, float b /*xmm1*/, float t /*xmm2*/) = a + (b - a) * t
lerp:
    subss xmm1, xmm0                # b - a
    mulss xmm1, xmm2                # (b - a) * t
    addss xmm0, xmm1                # a + ...
    ret                             # result in xmm0
```

Called from C as `float lerp(float, float, float)`, `lerp(10, 20, 0.25)` gives `12.5` and `lerp(0, 1, 1)` gives `1` (I ran both). I also ran a standalone program computing `2.5 * 4.0 + 5`, then `sqrtss`, then `cvttss2si`, which gives `3`.

`ucomiss` is where floating point differs from integers. After it, you use the **unsigned** jumps (`ja`, `jae`, `jb`, `jbe`), because the result lands in CF and ZF. If either operand is NaN the result is "unordered" and ZF, PF and CF are all set. So `ja` and `jae` are false for NaN (I checked `ja` with a NaN), while `jb`, `jbe` and `je` are true. If NaN input is possible and matters, test the parity flag first (`jp`).

Two precision notes for your rasterizer work. The compiler may fuse `a*b + c` into one fused multiply-add (`vfmadd231ss`, needs FMA3 and `-mfma`) that rounds once, so results can differ in the last bit from `mulss` + `addss`. And `cvttss2si` truncates while `cvtss2si` rounds to nearest even by default; choose on purpose.

## 11. Capstone: count newlines on stdin

This uses every part above: registers and the ABI, `.rodata`/`.bss` data, addressing, flags and `sete`/`cmovb`, loops, `div`, the stack discipline (a callee-saved register keeps a running total across calls), system calls, and SSE2. It is the same task as `wc -l`, so you can verify it.

```x86asm
.intel_syntax noprefix
.globl _start
.set BUFSZ, 65536

.section .rodata
.balign 16
nl16:   .fill 16, 1, 10             # sixteen '\n' bytes

.bss
.balign 64
buf:    .skip BUFSZ
out:    .skip 24                    # 20 digits + '\n' fits

.text
# u64 count_nl_scalar(const u8 *p /*rdi*/, u64 n /*rsi*/)  -> rax
count_nl_scalar:
    xor  eax, eax
    test rsi, rsi
    jz   .Lcs_done
.Lcs_loop:
    cmp  byte ptr [rdi], 10
    sete dl
    movzx edx, dl
    add  rax, rdx
    inc  rdi
    dec  rsi
    jnz  .Lcs_loop
.Lcs_done:
    ret

# u64 count_nl_sse2(const u8 *p /*rdi*/, u64 n /*rsi*/)  -> rax
# Reads only [p, p+n): unaligned 16-byte loads of whole blocks, then a scalar tail.
count_nl_sse2:
    xor  eax, eax
    mov  rcx, rsi
    shr  rcx, 4                     # rcx = number of 16-byte blocks
    jz   .Ltail
    movdqa xmm1, [rip + nl16]
    pxor xmm3, xmm3                 # zero, for psadbw
.Lchunk:
    mov  r8d, 255
    cmp  rcx, r8
    cmovb r8, rcx                   # r8 = min(blocks left, 255): byte lanes can't overflow
    sub  rcx, r8
    pxor xmm2, xmm2                 # 16 byte counters
.Linner:
    movdqu xmm0, [rdi]
    pcmpeqb xmm0, xmm1              # 0xFF where byte == '\n'
    psubb xmm2, xmm0                # subtracting -1 adds 1
    add  rdi, 16
    dec  r8
    jnz  .Linner
    psadbw xmm2, xmm3               # horizontal byte sums -> two 64-bit lanes
    movdqa xmm0, xmm2
    psrldq xmm0, 8
    paddq xmm2, xmm0
    movq rdx, xmm2
    add  rax, rdx
    test rcx, rcx
    jnz  .Lchunk
.Ltail:
    and  rsi, 15                    # leftover bytes
    jz   .Ldone
.Lt_loop:
    cmp  byte ptr [rdi], 10
    sete dl
    movzx edx, dl
    add  rax, rdx
    inc  rdi
    dec  rsi
    jnz  .Lt_loop
.Ldone:
    ret

# void print_u64(u64 v /*rdi*/): writes decimal + '\n' to stdout
print_u64:
    lea  r8, [rip + out + 24]       # cursor, one past the end
    mov  rax, rdi
    mov  ecx, 10
    dec  r8
    mov  byte ptr [r8], 10
.Ldigit:
    xor  edx, edx                   # div divides rdx:rax, so rdx must be 0
    div  rcx                        # rax = quotient, rdx = remainder
    add  dl, '0'
    dec  r8
    mov  [r8], dl
    test rax, rax
    jnz  .Ldigit
    mov  eax, 1                     # write
    mov  edi, 1                     # stdout
    mov  rsi, r8
    lea  rdx, [rip + out + 24]
    sub  rdx, r8                    # length
    syscall
    ret

_start:
    xor  ebx, ebx                   # rbx = running total (callee-saved: survives calls)
.Lread:
    xor  eax, eax                   # read
    xor  edi, edi                   # fd 0
    lea  rsi, [rip + buf]
    mov  edx, BUFSZ
    syscall
    test rax, rax
    js   .Lfail                     # negative = -errno (EINTR not retried here)
    jz   .Lprint                    # 0 = EOF
    lea  rdi, [rip + buf]
    mov  rsi, rax
    call count_nl_sse2              # swap for count_nl_scalar to compare
    add  rbx, rax
    jmp  .Lread
.Lprint:
    mov  rdi, rbx
    call print_u64
    xor  edi, edi
    jmp  .Lexit
.Lfail:
    mov  edi, 1
.Lexit:
    mov  eax, 60
    syscall
```

Build and verify:

```sh
as nlcount.s -o nlcount.o && ld nlcount.o -o nlcount
./nlcount < somefile; wc -l < somefile
cat somefile | ./nlcount          # pipe: read returns short chunks
```

I tested both the SSE2 and scalar versions against `wc -l` on: empty input, no trailing newline, only newlines, 10 MB of random bytes, a 300 KB random mix, a file that straddles the 64 KiB read size, and every input length from 0 to 299 bytes (no mismatches). That is my test set, not proof.

Where each part of this program comes from:

| Part                                                          | Chapter |
| ------------------------------------------------------------- | ------- |
| `rbx` kept across calls, `rax`/`rdi`/`rsi` as args and result | 2, 6    |
| `.rodata`, `.bss`, `[rip + label]`                            | 3       |
| `cmp`/`jz`/`js`, `sete`, `cmovb`, `div`, `movzx`              | 4       |
| loops with test at the bottom, `dec`/`jnz`                    | 5       |
| `call`/`ret`, callee-saved registers                          | 6       |
| `read`, `write`, `exit`                                       | 7       |
| `pcmpeqb`, `psubb`, `psadbw`, byte-counter flush              | 9       |

Exercises, in order of difficulty:

1. Make the read loop retry when `read` returns `-4` (EINTR) instead of failing.
2. Take the byte to count from `argv[1]`. At `_start`, `[rsp]` is `argc`, `[rsp + 8]` is `argv[0]`, `[rsp + 16]` is `argv[1]` (a pointer to a NUL-terminated string).
3. Write `count_nl_pmovmskb`: `pcmpeqb`, `pmovmskb eax, xmm0`, then count bits in the 16-bit mask. `popcnt` is not SSE2; check that your CPU has it, or write a bit-count loop. Time all three versions on a 1 GiB file (pipe it from the page cache with `< file`).

## 12. Common mistakes

- `div` or `idiv` without setting `rdx` first (`xor edx, edx` or `cqo`).
- A signed jump after an unsigned comparison, or the reverse.
- A misaligned `rsp` at a `call` into libc.
- Using `rbx`, `rbp` or `r12`-`r15` without saving and restoring them.
- Expecting `mov al, 1` or `mov ax, 1` to clear the rest of the register.
- Forgetting `byte ptr` / `dword ptr` when no register fixes the size.
- Assuming `read` returns the full count, or that `syscall` preserves `rcx` and `r11`.
- Reading 16 bytes with SIMD when fewer remain in the buffer.
- Using `rcx` for the 4th argument of a syscall (it is `r10`).
- Branching on a float compare without thinking about NaN (`ucomiss` sets CF, ZF and PF).
- Using the result of `tzcnt` or `bsf` on a zero input.

Lookups: Felix Cloutier's instruction reference (https://www.felixcloutier.com/x86/ or https://intel.github.io/SDM/sdm.html), the Intel Intrinsics Guide (for SIMD semantics), and uops.info (latency and throughput). To see how a compiler writes any of this: `gcc -O1 -S -masm=intel file.c` and read `file.s`.
