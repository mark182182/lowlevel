# AArch64 assembly, step by step

Linux, GNU `as`, the A64 instruction set (64-bit Arm; your Raspberry Pi 4 runs it). Same layout as the x86-64 guide, so you can read them side by side. Every complete program was assembled with GNU as 2.42 and run under `qemu-aarch64` 8.2.2 on an x86-64 machine, and the outputs and exit codes quoted are what I got. I have **not** run them on real Arm hardware. qemu is an emulator and can be more forgiving, so run the capstone on your Pi before relying on anything about speed, alignment faults or memory ordering.

## 0. Setup

On the Pi, natively:

```sh
as prog.s -o prog.o && ld prog.o -o prog && ./prog; echo $?
```

On an x86-64 PC, with a cross toolchain and the emulator (`apt install binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu qemu-user`):

```sh
aarch64-linux-gnu-as prog.s -o prog.o && aarch64-linux-gnu-ld prog.o -o prog && qemu-aarch64 ./prog; echo $?
```

For programs linked against libc, add `-L /usr/aarch64-linux-gnu` to the `qemu-aarch64` command so it finds the Arm libc. `$?` is the exit status (0-255), your only output channel early on. Debugging: `gdb ./prog` on the Pi, `objdump -d prog`, `strace ./prog`.

There is only one A64 syntax, so there is no `.intel_syntax` line. Comments are `//`. Immediate numbers carry a `#`: `mov x0, #42`.

## 1. The machine in six lines

- 31 general registers `x0`-`x30` (64-bit), plus `sp` and a zero register. Memory is touched only by load and store instructions. Arithmetic never has a memory operand.
- Every instruction is exactly 4 bytes. Most arithmetic is three-operand: `op dest, src1, src2`.
- There is no `push`, no `pop`, and `call` does not touch the stack: `bl` puts the return address in register `x30`.
- Flags (N, Z, C, V) are set only by instructions that ask for it (`adds`, `subs`, `ands` and the compares `cmp`, `tst`, `fcmp`). On x86 most arithmetic sets flags.
- Linux on Arm is little-endian, like x86.
- The program counter is not an ordinary register. Branches change it.

## 2. Registers

| Register                            | Role                                                                                                    |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `x0`-`x7` (`w0`-`w7` = low 32 bits) | arguments and results; `x0` is the return value                                                         |
| `x8`                                | syscall number                                                                                          |
| `x9`-`x15`                          | scratch (caller-saved)                                                                                  |
| `x16`, `x17`                        | scratch used by linker-inserted code; don't keep values in them across calls                            |
| `x18`                               | reserved by the platform ABI. Don't use it                                                              |
| `x19`-`x28`                         | callee-saved                                                                                            |
| `x29`                               | frame pointer by convention; callee-saved                                                               |
| `x30`                               | link register (LR): the return address                                                                  |
| `sp`                                | stack pointer; must be 16-byte aligned whenever it is used to address memory                            |
| `xzr` / `wzr`                       | reads as 0, writes are discarded                                                                        |
| `v0`-`v31`                          | SIMD and floating point (views `b`, `h`, `s`, `d`, `q`); the low 64 bits of `v8`-`v15` are callee-saved |

The rules:

- Writing a `w` register **zeroes the upper 32 bits** of the `x` register, like x86's 32-bit rule.
- There are no 8-bit or 16-bit register writes. Byte and halfword access exists only in loads and stores (`ldrb`, `strh`, ...).
- Register number 31 means `sp` in some instructions and `xzr` in others. `cmp x0, #3` is really `subs xzr, x0, #3`.

Calling convention (AAPCS64): integer arguments in `x0`-`x7`, float arguments in `v0`-`v7` (counted separately), results in `x0` (`x1` too for a 128-bit value) or `v0`. System calls: number in `x8`, arguments in `x0`-`x5`, result in `x0`.

### Program 1: exit with a chosen status

```arm
.globl _start
.text
_start:
    mov  x8, #93            // syscall number: exit
    mov  x0, #42            // argument 1: status
    svc  #0                 // supervisor call: enter the kernel
```

`echo $?` shows `42`. `.globl _start` exports the entry symbol so the linker finds it.

### Program 2: the 32-bit write rule

```arm
_start:
    mov  x0, #-1            // all 64 bits set
    mov  w0, #7             // 32-bit write: upper half becomes zero
    lsr  x0, x0, #32        // shift the upper half down: now 0
    mov  x8, #93
    svc  #0
```

Exit status `0`. There is no `dil`-style partial register to demonstrate the other half of the x86 rule: on Arm that case does not exist.

## 3. Memory and data

The data directives and sections are the same GNU ones as in the x86 guide:

| Directive                                           | Emits                                        |
| --------------------------------------------------- | -------------------------------------------- |
| `.byte` / `.hword` / `.word` (or `.long`) / `.quad` | 1 / 2 / 4 / 8 byte integers                  |
| `.ascii "hi"` / `.asciz "hi"`                       | the bytes / the bytes plus a trailing 0      |
| `.fill n, size, value` / `.skip n` / `.balign n`    | repetitions / zero bytes / alignment padding |

Sections: `.text` code, `.rodata` read-only data, `.data` writable data, `.bss` zeroed data.

**Getting an address.** There is no `[rip + label]` operand. Use a pair: `adrp x1, label` (address of the 4 KiB page containing `label`, PC-relative) then `add x1, x1, :lo12:label` (the offset within that page). `adr x1, label` does it in one instruction but only reaches about 1 MiB. Define a macro if the pair gets repetitive (the capstone does).

**Addressing modes** (loads and stores only):

| Operand            | Meaning                                                                                                                                                  |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[x0]`             | address in `x0`                                                                                                                                          |
| `[x0, #8]`         | base + immediate. For `ldr x` the offset is a multiple of 8 up to 32760; the assembler uses the unscaled form (`ldur`) for small negative or odd offsets |
| `[x0, x1]`         | base + register                                                                                                                                          |
| `[x0, x1, lsl #3]` | base + register × 8. The shift is 0 or log2 of the access size                                                                                           |
| `[x0, #8]!`        | pre-index: `x0 += 8`, then access                                                                                                                        |
| `[x0], #8`         | post-index: access, then `x0 += 8`                                                                                                                       |

Load and store instructions: `ldr`/`str` (64-bit with `x`, 32-bit with `w`), `ldrb`/`strb` (byte), `ldrh`/`strh` (halfword), `ldrsb`/`ldrsh`/`ldrsw` (load and **sign**-extend), and `ldp`/`stp` (two registers at once). Plain `ldrb` and `ldrh` zero-extend.

**Constants.** An arithmetic immediate is 12 bits (optionally shifted left by 12). Logical immediates (`and`, `orr`, `eor`) use a special bit-pattern encoding, so some values won't assemble. `mov x0, #imm` picks `movz`, `movn` or `orr` as it fits. Any 64-bit constant takes `movz` plus up to three `movk`, 16 bits each:

```arm
    movz x0, #0x1122, lsl #48
    movk x0, #0x3344, lsl #32
    movk x0, #0x5566, lsl #16
    movk x0, #0x7788            // x0 = 0x1122334455667788
    lsr  x0, x0, #56            // top byte: 0x11 = 17, so the exit status is 17
```

### Program 3: sum an array

```arm
.globl _start
.section .rodata
.balign 8
nums:   .quad 10, 20, 30, 40, 50
.text
_start:
    adrp x1, nums               // page address of nums
    add  x1, x1, :lo12:nums     // plus the offset within the page
    mov  x0, #0                 // sum
    mov  x2, #0                 // i
.Lloop:
    ldr  x3, [x1, x2, lsl #3]   // x3 = nums[i]
    add  x0, x0, x3
    add  x2, x2, #1
    cmp  x2, #5
    b.lo .Lloop                 // while (i < 5), unsigned
    mov  x8, #93
    svc  #0
```

Exit status `150`. Notice that the sum can't be written as `add x0, x0, [x1, ...]`: memory must be loaded into a register first.

### Program 4: loads of different widths

```arm
.globl _start
.section .rodata
.balign 8
x:  .long -2
w:  .quad 0x1122334455667788
.text
_start:
    adrp x1, x
    add  x1, x1, :lo12:x
    ldrsw x0, [x1]              // sign-extend 32 -> 64: -2
    adrp x2, w
    add  x2, x2, :lo12:w
    ldrb w3, [x2]               // lowest byte: little-endian gives 0x88
    add  x0, x0, x3             // 134
    mov  x8, #93
    svc  #0
```

Status `134`, the same as the x86 version. Same lesson: pick the sign-extending or zero-extending load by whether the value is signed.

### Structs and arrays

For `struct P { int32 x, y, hp; }` (12 bytes) the field offsets are 0, 4 and 8, and element `i` starts at `base + i*12`. A64 has no scale-by-3 addressing, so `madd` (multiply-add) computes the address:

```arm
.globl _start
.section .rodata
.balign 4
parts:  .long 1,2,10,  3,4,20,  5,6,30,  7,8,40
.text
_start:
    adrp x1, parts
    add  x1, x1, :lo12:parts
    mov  x0, #0                 // sum
    mov  x2, #0                 // i
    mov  x4, #12                // sizeof(struct P)
.Lloop:
    madd x3, x2, x4, x1         // x3 = x2*x4 + x1 = &parts[i]
    ldr  w5, [x3, #8]           // .hp is at offset 8
    add  x0, x0, x5
    add  x2, x2, #1
    cmp  x2, #4
    b.lo .Lloop
    mov  x8, #93
    svc  #0                     // 100
```

Status `100`. As on x86, struct-of-arrays (separate contiguous arrays per field) needs only the scaled-index load from Program 3 and is what SIMD loads want. Measure before choosing.

## 4. Arithmetic and flags

| Instruction                           | Effect                                                             |
| ------------------------------------- | ------------------------------------------------------------------ |
| `add d, a, b` / `sub d, a, b`         | `d = a + b` / `d = a - b`, flags untouched                         |
| `adds` / `subs` / `ands`              | same, **and set the flags**                                        |
| `neg d, a`                            | `d = -a`                                                           |
| `mul d, a, b`                         | `d = a * b` (low 64 bits)                                          |
| `madd d, a, b, c` / `msub d, a, b, c` | `d = c + a*b` / `d = c - a*b`                                      |
| `umulh` / `smulh`                     | high 64 bits of the 128-bit product                                |
| `udiv d, a, b` / `sdiv d, a, b`       | quotient only. **Division by zero gives 0, no trap**               |
| `and` `orr` `eor` `bic` `mvn`         | bitwise (`bic` = and-not, `mvn` = not)                             |
| `lsl` `lsr` `asr` `ror`               | shifts and rotate, by an immediate or a register                   |
| `cmp a, b` / `tst a, b`               | `subs xzr, a, b` / `ands xzr, a, b`: set flags, discard the result |

There is no remainder instruction. Compute it from the quotient:

```arm
    mov  x0, #100
    mov  x1, #7
    udiv x2, x0, x1             // 14
    msub x3, x2, x1, x0         // 100 - 14*7 = 2
```

Flags: **N** negative (top bit of the result), **Z** zero, **C** carry, **V** signed overflow. One difference from x86 that bites: after a subtraction or `cmp`, **C is set when there was no borrow**, the opposite sense of x86's CF. `cmp 5, 3` gives C = 1 (5 >= 3 unsigned), and `cmp 3, 5` gives C = 0 (I checked both with `cset`).

Conditions, after `cmp a, b`:

| `a ? b` | signed | unsigned |
| ------- | ------ | -------- |
| `<`     | `lt`   | `lo`     |
| `<=`    | `le`   | `ls`     |
| `>`     | `gt`   | `hi`     |
| `>=`    | `ge`   | `hs`     |
| `==`    | `eq`   | `eq`     |
| `!=`    | `ne`   | `ne`     |

Use them with `b.cond label` (branch), or with the conditional-data instructions:

| Instruction                              | Effect                                                 |
| ---------------------------------------- | ------------------------------------------------------ |
| `csel d, a, b, cond`                     | `d = cond ? a : b`                                     |
| `cset d, cond`                           | `d = cond ? 1 : 0`                                     |
| `cinc d, a, cond`                        | `d = cond ? a + 1 : a`                                 |
| `cbz x, label` / `cbnz x, label`         | branch if `x` is zero / nonzero. **No flags involved** |
| `tbz x, #n, label` / `tbnz x, #n, label` | branch if bit `n` of `x` is 0 / 1                      |

### Program 5: signed vs unsigned, side by side

```arm
.globl _start
.section .rodata
.balign 8
vals:   .quad 5, -3, 7, -1, 2
.text
_start:
    adrp x1, vals
    add  x1, x1, :lo12:vals
    mov  x2, #0                 // i
    mov  x8, #0                 // count > 0, signed   (x8 is free until we exit)
    mov  x9, #0                 // count > 0, unsigned
.Lloop:
    ldr  x3, [x1, x2, lsl #3]
    cmp  x3, #0
    cinc x8, x8, gt             // signed:   if x3 > 0 then x8 += 1
    cinc x9, x9, hi             // unsigned: if x3 > 0 then x9 += 1   (same flags, no new compare)
    add  x2, x2, #1
    cmp  x2, #5
    b.lo .Lloop
    mov  x10, #10
    madd x0, x8, x10, x9        // x0 = x8*10 + x9
    mov  x8, #93
    svc  #0
```

Status `35`: signed count 3, unsigned count 5. One `cmp` feeds two different interpretations. No branches inside the loop except the loop branch.

### Bit instructions and multiword arithmetic

| Instruction                   | Result                                                    |
| ----------------------------- | --------------------------------------------------------- |
| `clz d, a`                    | count of leading zero bits                                |
| `rbit d, a`                   | reverse the bit order                                     |
| `rev d, a`                    | reverse the byte order                                    |
| `adc d, a, b` / `sbc d, a, b` | `a + b + C` / `a - b - (1 - C)`, for multiword arithmetic |

There is no `ctz` instruction: trailing zeros = `rbit` then `clz`. The index of the highest set bit is `63 - clz`. There is no scalar `popcnt` in the base A64 set (the Pi 4's Cortex-A72 predates the extension that adds one), so use NEON: `cnt` counts bits per byte, `addv` sums them.

```arm
    mov  x0, #0xF0F0
    fmov d0, x0                 // move to a SIMD register
    cnt  v0.8b, v0.8b           // popcount per byte
    addv b0, v0.8b              // sum the bytes: 8
    umov w1, v0.b[0]
    mov  x0, #0x50
    rbit x2, x0
    clz  x2, x2                 // trailing zeros of 0x50: 4
    clz  x3, x0
    mov  x4, #63
    sub  x3, x4, x3             // highest set bit: 63 - clz = 6
```

That fragment ran (8 + 4 + 6 = 18). A 128-bit add:

```arm
    adds x0, x0, x2             // low halves; sets C on unsigned overflow
    adc  x1, x1, x3             // high halves + C
```

## 5. Control flow patterns

C `if (a > b) { body }` (signed):

```arm
    cmp  x0, x1
    b.le .Lskip                 // branch on the opposite condition
    ...body...
.Lskip:
```

Count-down loop, with the flag set by the decrement itself (no separate `cmp`):

```arm
    cbz  x1, .Lend              // guard: skip the loop if n == 0
.Lloop:
    ...body...
    subs x1, x1, #1
    b.ne .Lloop
.Lend:
```

### Jump tables (switch)

```arm
.globl _start
.section .rodata
.balign 8
table:  .quad .Lc0, .Lc1, .Lc2
.text
select:                         // switch (x0) { 0: 10; 1: 20; 2: 30; default: 99 }
    cmp  x0, #2
    b.hi .Ldef                  // one unsigned compare also rejects negative values
    adrp x1, table
    add  x1, x1, :lo12:table
    ldr  x2, [x1, x0, lsl #3]
    br   x2                     // indirect branch, no link
.Lc0: mov x0, #10
    ret
.Lc1: mov x0, #20
    ret
.Lc2: mov x0, #30
    ret
.Ldef: mov x0, #99
    ret
```

`select(1)` returns 20 and `select(-5)` returns 99 (I ran both). `br` is an indirect branch, `blr` is an indirect call.

## 6. The stack and functions

- There is no `push` or `pop`. You move `sp` and store explicitly. The pair idiom: `stp x29, x30, [sp, #-16]!` (pre-index: `sp -= 16`, then store both) and `ldp x29, x30, [sp], #16` (load both, then `sp += 16`).
- `bl label` sets `x30` to the return address and jumps. `ret` jumps to `x30`. Because `bl` **overwrites `x30`**, any function that calls another must save `x30` first. A leaf function needs nothing.
- **Callee-saved:** `x19`-`x28`, `x29`, `sp`, and the low 64 bits of `v8`-`v15`. **Caller-saved:** `x0`-`x17`, `x30` (clobbered by `bl`), `v0`-`v7`, `v16`-`v31`.
- **Alignment:** `sp` must be 16-byte aligned whenever it is the base of a memory access, so keep it aligned at all times, not only at calls. The hardware can fault on a misaligned `sp`. I have not tested that on your Pi.
- A frame record is the saved `x29`/`x30` pair at the bottom of the frame, with `x29` pointing at it.

### Program 6: recursive factorial

```arm
.globl _start
.text
// u64 fact(u64 n)       n in x0, result in x0
fact:
    cmp  x0, #1
    b.hi .Lrec
    mov  x0, #1
    ret
.Lrec:
    stp  x29, x30, [sp, #-32]!  // push the frame record (sp stays 16-aligned)
    mov  x29, sp
    str  x19, [sp, #16]         // save callee-saved x19
    mov  x19, x0                // keep n across the call
    sub  x0, x0, #1
    bl   fact                   // x0 = fact(n-1); bl overwrites x30
    mul  x0, x0, x19
    ldr  x19, [sp, #16]
    ldp  x29, x30, [sp], #32    // restore fp and lr; ret then uses the restored x30
    ret

_start:
    mov  x0, #5
    bl   fact
    mov  x8, #93
    svc  #0                     // status 120
```

Status `120`. Without the `stp`/`ldp` pair, the recursive `bl` would destroy the return address and `ret` would loop forever.

### Stack arguments

The first eight integer arguments are in registers. The ninth goes on the stack, at `[sp]` at the moment of the call:

```arm
// long f9(a..h in x0..x7; i on the stack) = sum
f9:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    add  x0, x0, x1
    add  x0, x0, x2
    add  x0, x0, x3
    add  x0, x0, x4
    add  x0, x0, x5
    add  x0, x0, x6
    add  x0, x0, x7
    str  x0, [sp, #16]          // a local variable
    ldr  x1, [sp, #32]          // 9th arg: just above our 32-byte frame
    ldr  x0, [sp, #16]
    add  x0, x0, x1
    ldp  x29, x30, [sp], #32
    ret
// caller:
    sub  sp, sp, #16            // reserve 16 bytes to keep sp 16-aligned
    str  x9, [sp]               // 9th argument at [sp]
    bl   f9
    add  sp, sp, #16
```

Called with 1..8 in registers and 9 on the stack, it returns `45`. The caller reserves 16 bytes for one 8-byte argument because `sp` may never be misaligned.

## 7. System calls

`svc #0` hands control to the kernel. Number in `x8`, arguments in `x0`-`x5`, result in `x0`; a value from `-4095` to `-1` is `-errno`. Unlike x86's `syscall`, the kernel preserves every register except `x0`.

| Call                    | `x8` | `x0`   | `x1`        | `x2`  |
| ----------------------- | ---- | ------ | ----------- | ----- |
| `read(fd, buf, count)`  | 63   | fd     | buf address | count |
| `write(fd, buf, count)` | 64   | fd     | buf address | count |
| `exit(status)`          | 93   | status |             |       |

These numbers come from Linux's generic syscall table, which all newer architectures share. That is why they differ from x86-64 (`read` 0, `write` 1, `exit` 60). `exit` (93) ends the calling thread, which ends the process in a single-threaded program (`exit_group` is 94). File descriptors and the short-`read` caveat are the same as on x86.

### Virtual memory: mmap, mprotect, page faults, and /proc

What "memory" means to your program (the same model as on x86-64):

- Every address you use is **virtual**. The CPU's MMU translates each load and store through page tables that the kernel maintains, in fixed-size pages. The page size is 4096 bytes on most AArch64 Linux systems, but some kernels use 16 KiB or 64 KiB pages. Run `getconf PAGESIZE` on your Pi, and if it isn't 4096, use that value for every length and offset below.
- A load or store does **not** call the OS. It just uses the address. If the page is not mapped, or the access breaks the page's permissions, the CPU raises a _page fault_ and the kernel decides: either it fixes things up (for example by supplying a zeroed page the first time you touch fresh anonymous memory), or it kills the process with SIGSEGV. A shell reports that as status 139, which is 128 + 11.
- To get memory, change its permissions, or give it back, you ask the kernel with system calls. After that, reading and writing it is ordinary `ldr` and `str`.
- Your own process's layout is visible in `/proc/self/maps`. Kernel memory is not accessible from user mode, and another process's memory is reachable only through mechanisms that need permission (`/proc/<pid>/mem`, `ptrace`, `process_vm_readv`).

| Call                                    | `x8` | `x0`                          | `x1`   | `x2` | `x3`  | `x4`          | `x5`   |
| --------------------------------------- | ---- | ----------------------------- | ------ | ---- | ----- | ------------- | ------ |
| `mmap(addr, len, prot, flags, fd, off)` | 222  | addr (0: kernel chooses)      | length | prot | flags | fd (-1: none) | offset |
| `munmap(addr, len)`                     | 215  | addr                          | length |      |       |               |        |
| `mprotect(addr, len, prot)`             | 226  | addr                          | length | prot |       |               |        |
| `brk(addr)`                             | 214  | new break (0: just report it) |        |      |       |               |        |

Constants (the same as on x86-64): `PROT_NONE` 0, `PROT_READ` 1, `PROT_WRITE` 2, `PROT_EXEC` 4 (add them). `MAP_PRIVATE` 0x02 and `MAP_ANONYMOUS` 0x20 together are `0x22`: memory not backed by any file, zero-filled. Addresses and lengths for `mprotect` and `munmap` must be multiples of the page size. A raw system call returns the address or `-errno`, with no libc-style `MAP_FAILED`. Test with `cmn x0, #4095` followed by `b.hs`: `cmn` adds 4095, and the carry flag is set exactly when `x0` is in `[-4095, -1]`.

### Program 7: get a page, use it, give it back

```arm
.globl _start
.text
_start:
    mov  x8, #222                   // mmap
    mov  x0, #0                     // addr = 0: let the kernel choose
    mov  x1, #4096                  // length
    mov  x2, #3                     // PROT_READ | PROT_WRITE
    mov  x3, #0x22                  // MAP_PRIVATE | MAP_ANONYMOUS
    mov  x4, #-1                    // fd = -1 (no file)
    mov  x5, #0                     // offset = 0
    svc  #0
    cmn  x0, #4095
    b.hs .Lfail                     // carry set: x0 + 4095 wrapped, so x0 is in [-4095, -1] (-errno)
    mov  x19, x0                    // x19 = base address of the new page
    mov  x1, #40
    str  x1, [x19]                  // ordinary stores: no system call involved
    mov  x1, #2
    str  x1, [x19, #4088]           // last 8 bytes of the page
    ldr  x20, [x19]
    ldr  x1, [x19, #4088]
    add  x20, x20, x1               // 40 + 2
    mov  x8, #215                   // munmap
    mov  x0, x19
    mov  x1, #4096
    svc  #0
    cbnz x0, .Lfail
    mov  x0, x20                    // status 42
    b    .Lexit
.Lfail:
    mov  x0, #99
.Lexit:
    mov  x8, #93
    svc  #0
```

Exit status `42` (I ran it under qemu). The kernel typically allocates the physical page on first touch rather than at `mmap` time (I did not measure that here). After `munmap`, any access to that range faults.

### Program 8: a guard page

Map two pages, then remove all permissions from the second one with `mprotect`. This is the guard-page buffer your plan's tests use to catch over-reads: put the buffer so it ends exactly where the guard page begins.

```arm
_start:
    mov  x8, #222                   // mmap two pages
    mov  x0, #0
    mov  x1, #8192
    mov  x2, #3
    mov  x3, #0x22
    mov  x4, #-1
    mov  x5, #0
    svc  #0
    cmn  x0, #4095
    b.hs .Lfail
    mov  x19, x0
    mov  x8, #226                   // mprotect(base + 4096, 4096, PROT_NONE)
    add  x0, x19, #4096
    mov  x1, #4096
    mov  x2, #0
    svc  #0
    cbnz x0, .Lfail
    mov  w1, #7
    strb w1, [x19, #4095]           // last byte of the first page: fine
    ldrb w20, [x19, #4095]
    add  x2, x19, #4096             // a byte offset of 4096 does not fit the immediate field (0..4095)
    mov  w1, #1
    strb w1, [x2]                   // first byte of the guard page: page fault -> SIGSEGV
    mov  x0, x20                    // never reached
    b    .Lexit
.Lfail:
    mov  x0, #99
.Lexit:
    mov  x8, #93
    svc  #0
```

The shell reports status `139` (under qemu it also prints that the guest got a segmentation fault). Note the comment on the `add`: my first version wrote `strb w1, [x19, #4096]` and the assembler refused it with `immediate offset out of range`. The unsigned offset field in `ldr`/`str` byte forms holds 0 to 4095, and larger offsets need a separate address calculation.

### Program 9: look at your own address space

Open `/proc/self/maps`, read it, and write it to stdout. `openat` is call 56 (`AT_FDCWD` is -100, `O_RDONLY` is 0), `close` is 57.

```arm
.globl _start
.section .rodata
path:   .asciz "/proc/self/maps"
.bss
.balign 16
buf:    .skip 4096
.text
_start:
    mov  x8, #56                    // openat(AT_FDCWD, path, O_RDONLY)
    mov  x0, #-100
    adrp x1, path
    add  x1, x1, :lo12:path
    mov  x2, #0
    svc  #0
    cmp  x0, #0
    b.lt .Lfail
    mov  x19, x0                    // fd
.Lloop:
    mov  x8, #63                    // read(fd, buf, 4096)
    mov  x0, x19
    adrp x1, buf
    add  x1, x1, :lo12:buf
    mov  x2, #4096
    svc  #0
    cmp  x0, #0
    b.lt .Lfail
    b.eq .Ldone
    mov  x2, x0                     // write(1, buf, n)
    mov  x8, #64
    mov  x0, #1
    adrp x1, buf
    add  x1, x1, :lo12:buf
    svc  #0
    b    .Lloop
.Ldone:
    mov  x8, #57                    // close(fd)
    mov  x0, x19
    svc  #0
    mov  x0, #0
    b    .Lexit
.Lfail:
    mov  x0, #1
.Lexit:
    mov  x8, #93
    svc  #0
```

Under qemu this ran and printed a plausible map, but qemu builds that text for its emulated guest, so it says little about a real kernel. **Run it on your Pi** and read the result: the first column is the address range, the second the permissions (`r`, `w`, `x`, and `p` for private), then the file offset, device, inode and name. Expect your executable's segments (code `r-xp`, read-only data, the writable `.bss` with no name), plus `[stack]`, `[vdso]` and `[vvar]`. Which region is writable, which executable, and where does the stack sit relative to your code? Every `mmap` you add before the read loop shows up as a new line.

### Reading and writing memory through the kernel

On x86-64 the guide shows `/proc/self/mem`, a file whose "offsets" are your virtual addresses: `pread64` and `pwrite64` on it read and write memory through the kernel, even into pages your own store instructions could not write. On AArch64 the system call numbers are `openat` 56, `pread64` 67 and `pwrite64` 68, and the code has the same shape as the x86-64 Program 10. I did not run an AArch64 version: qemu does not give the guest a real `/proc/self/mem`, so you would have to try it on the Pi. Reading another process's memory works the same way with `/proc/<pid>/mem` but needs permission (the same user plus the system's `ptrace` policy, or root).

### Program 10: the program break (`brk`)

`brk` is the older interface: the kernel keeps one "program break", the end of the heap, and you move it. Most allocators use `mmap` for large blocks and `brk` for small ones. For memory of your own, `mmap` is simpler.

```arm
.globl _start
.text
_start:
    mov  x8, #214                   // brk(0): returns the current program break
    mov  x0, #0
    svc  #0
    mov  x19, x0
    add  x0, x19, #4096             // ask for one more page
    mov  x8, #214
    svc  #0
    cmp  x0, x19
    b.ls .Lfail                     // unchanged or smaller: failed
    mov  x1, #42
    str  x1, [x19]                  // the new page [old break, old break + 4096) is writable
    ldr  x0, [x19]
    b    .Lexit
.Lfail:
    mov  x0, #99
.Lexit:
    mov  x8, #93
    svc  #0
```

Exit status `42` under qemu.

### Program 11: locking a mapping with `mseal`

Page permissions are not final: `mprotect` can make a read-only page writable again, `munmap` can remove it, and `mmap` with `MAP_FIXED` can replace it. That is what an attacker with a memory-write bug uses to turn your data into code or to remove a guard page. `mseal` closes that door. It is system call **462**, the same number on AArch64 and x86-64, and was added in Linux 6.10. Check `uname -r` on your Pi: an older kernel returns `-ENOSYS` (`-38`).

`mseal(addr, len, flags)`:

- `flags` must be 0. `addr` must be page-aligned. `len` is rounded up to whole pages. The whole range must be mapped.
- After it succeeds, the kernel refuses to change those mappings: `munmap`, `mremap`, `mprotect`, and `mmap` with `MAP_FIXED` over them fail with `-EPERM` (`-1`), and so do some destructive `madvise` calls. It cannot be undone. The seal lasts until the process exits.
- Sealing does **not** change the current permissions. A sealed read-write page stays writable. To make something immutable, set its permissions first and then seal it.
- It protects the mapping (its range and permissions), not the contents of a writable page.

```arm
.globl _start
.text
_start:
    mov  x8, #222                   // mmap one read/write page
    mov  x0, #0
    mov  x1, #4096
    mov  x2, #3                     // PROT_READ | PROT_WRITE
    mov  x3, #0x22                  // MAP_PRIVATE | MAP_ANONYMOUS
    mov  x4, #-1
    mov  x5, #0
    svc  #0
    cmn  x0, #4095
    b.hs .Lfail
    mov  x19, x0                    // x19 = page address
    mov  x1, #42
    str  x1, [x19]                  // put data in it
    mov  x8, #226                   // mprotect(page, 4096, PROT_READ): make it read-only
    mov  x0, x19
    mov  x1, #4096
    mov  x2, #1
    svc  #0
    cbnz x0, .Lfail

    mov  x8, #462                   // mseal(page, 4096, 0)
    mov  x0, x19
    mov  x1, #4096
    mov  x2, #0
    svc  #0
    cbnz x0, .Lnoseal               // e.g. -ENOSYS on a kernel older than 6.10 (or an emulator that lacks it)

    mov  x20, #0                    // x20 = bitmask of "the kernel refused, as expected"
    mov  x8, #226                   // mprotect(page, 4096, PROT_READ|PROT_WRITE): try to make it writable again
    mov  x0, x19
    mov  x1, #4096
    mov  x2, #3
    svc  #0
    cmn  x0, #1                     // x0 == -1 (-EPERM)?  cmn adds 1, so Z is set when x0 is -1
    mov  x1, #1
    orr  x2, x20, x1
    csel x20, x2, x20, eq           // set bit 0 only if the result was -EPERM
    mov  x8, #215                   // munmap(page, 4096)
    mov  x0, x19
    mov  x1, #4096
    svc  #0
    cmn  x0, #1
    mov  x1, #2
    orr  x2, x20, x1
    csel x20, x2, x20, eq
    mov  x8, #222                   // mmap(page, 4096, RW, MAP_FIXED|PRIVATE|ANON): try to replace the mapping
    mov  x0, x19
    mov  x1, #4096
    mov  x2, #3
    mov  x3, #0x32                  // MAP_FIXED (0x10) | MAP_PRIVATE | MAP_ANONYMOUS
    mov  x4, #-1
    mov  x5, #0
    svc  #0
    cmn  x0, #1
    mov  x1, #4
    orr  x2, x20, x1
    csel x20, x2, x20, eq
    ldr  x1, [x19]                  // reading still works and the data is intact
    cmp  x1, #42
    mov  x1, #8
    orr  x2, x20, x1
    csel x20, x2, x20, eq
    mov  x0, x20                    // 15 = all three changes refused and the data is intact
    b    .Lexit
.Lnoseal:
    mov  x0, #98
    b    .Lexit
.Lfail:
    mov  x0, #99
.Lexit:
    mov  x8, #93
    svc  #0
```

Expected status on a kernel with `mseal`: `15`. Status `98` means `mseal` failed (most likely no support).

**What I could and could not verify for AArch64.** Under `qemu-aarch64` 8.2.2, syscall 462 returned `-ENOSYS` (38), so this program exits with `98` there: the emulator predates the call. I checked the rest of the logic by replacing the `mseal` call and the three refusals with stubs that return the expected values; the bitmask code then exited `15`. I have **not** run the real `mseal` calls on AArch64. The x86-64 version of this program, which has identical logic, ran on a real Linux 6.18 kernel and exited `15`. Run this one on your Pi and compare. If you get `98`, your Pi's kernel is older than 6.10.

Where to use it: seal your guard pages (the `PROT_NONE` page from Program 8) so nothing can make them accessible again, and seal read-only tables after you finish filling them. A sealed region can never be freed or resized for the life of the process, so allocators, `realloc`, and anything that changes permissions at run time (a JIT, for example) must not touch it.

## 8. Mixing with C

Asm called from C: export the label, follow the calling convention, declare it in C.

```arm
.globl sum
.text
// long sum(const long *p /*x0*/, unsigned long n /*x1*/)
sum:
    mov  x2, #0
    cbz  x1, .Ldone
.Lloop:
    ldr  x3, [x0], #8           // load, then x0 += 8 (post-index)
    add  x2, x2, x3
    subs x1, x1, #1
    b.ne .Lloop
.Ldone:
    mov  x0, x2
    ret
.section .note.GNU-stack,"",@progbits
```

```c
#include <stdio.h>
long sum(const long *p, unsigned long n);
int main(void) { long a[] = {1, 2, 3, 4}; printf("%ld\n", sum(a, 4)); return 0; }
```

On the Pi: `gcc main.c sum.s -o t && ./t`. On a PC: `aarch64-linux-gnu-gcc main.c sum.s -o t && qemu-aarch64 -L /usr/aarch64-linux-gnu ./t`. It prints `10`. This function is a leaf that uses only caller-saved registers, so it needs no stack work.

C called from asm (here `printf`, so link with `gcc`, not `ld`):

```arm
.globl main
.section .rodata
fmt:    .asciz "sum = %ld\n"
.text
main:
    stp  x29, x30, [sp, #-16]!  // save fp/lr: the call below overwrites lr
    mov  x29, sp
    adrp x0, fmt
    add  x0, x0, :lo12:fmt
    mov  x1, #123
    bl   printf
    mov  w0, #0                 // return 0
    ldp  x29, x30, [sp], #16
    ret
.section .note.GNU-stack,"",@progbits
```

Prints `sum = 123`. On Linux AArch64 a variadic call passes its arguments exactly like any other call, so there is no counterpart to x86's `al` rule. (Apple's arm64 ABI passes variadic arguments on the stack. This guide covers Linux only.) The classic mistake here is forgetting to save `x30`: `main` would return to the wrong place.

## 9. SIMD with NEON, and scalar floating point

NEON (Advanced SIMD) is part of the AArch64 baseline. There are thirty-two 128-bit registers `v0`-`v31`. A register arrangement says how to see it: `.16b` (16 bytes), `.8h` (8 halfwords), `.4s` (4 words), `.2d` (2 doublewords), and `.8b`, `.4h`, `.2s` for just the low 64 bits. Operations act on every lane independently with no carries between lanes. All `v` registers are caller-saved except the low 64 bits of `v8`-`v15`.

| Instruction                                      | What it does                                               |
| ------------------------------------------------ | ---------------------------------------------------------- |
| `ld1 {v0.16b}, [x0]` / `ld1 {v0.16b}, [x0], #16` | load 16 bytes / load, then advance `x0` by 16              |
| `st1 {v0.16b}, [x0]`                             | store 16 bytes                                             |
| `movi v1.16b, #10`                               | fill every byte with a constant (no constant table needed) |
| `dup v1.16b, w1`                                 | fill every byte from a general register                    |
| `cmeq v0.16b, v0.16b, v1.16b`                    | per byte: `0xFF` if equal, else `0`                        |
| `add` `sub` `and` `orr` `eor` on `.16b`          | per-lane arithmetic and bitwise                            |
| `uaddlv h3, v2.16b`                              | add all 16 bytes into one wider value                      |
| `addv b0, v0.8b`                                 | add all lanes into one lane                                |
| `umov w0, v0.b[0]`                               | copy one lane to a general register                        |
| `fmov x0, d0`                                    | copy the low 64 bits to a general register                 |
| `cnt v0.8b, v0.8b`                               | per-byte bit count                                         |
| `shrn v0.8b, v0.8h, #4`                          | narrowing shift: the movemask idiom below                  |

The two ideas from the x86 guide carry over. A compare gives a mask (all ones in matching lanes), and `sub acc, acc, mask` adds 1 per match. Byte counters overflow after 255 additions, so flush them (`uaddlv`) at least that often. Never load bytes outside the buffer. NEON loads from ordinary memory do not need 16-byte alignment.

There is no `pmovmskb` on Arm. The replacement packs the mask 4 bits per input byte:

```arm
    ld1  {v0.16b}, [x1]         // 16 bytes: "abcdefgh\nijklmn\n"
    movi v1.16b, #10
    cmeq v0.16b, v0.16b, v1.16b // 0xFF where the byte is '\n'
    shrn v0.8b, v0.8h, #4       // 16 bytes -> 64 bits: 4 mask bits per input byte
    fmov x0, d0                 // mask into a general register
    rbit x0, x0
    clz  x0, x0                 // trailing zero bits = 4 * index of the first match
    lsr  x0, x0, #2             // divide by 4: byte index 8
```

This gave index 8 on the sample block. If the mask is 0 nothing matched and `clz` returns 64, so test the mask first (`cbz`).

### Scalar floating point

Scalar float and double use the low part of the same registers, named `s0` (float) and `d0` (double).

| Instruction                         | What it does                             |
| ----------------------------------- | ---------------------------------------- |
| `ldr s0, [x1]` / `str s0, [x1]`     | load / store a float (`d0` for a double) |
| `fadd` `fsub` `fmul` `fdiv` `fsqrt` | arithmetic, e.g. `fadd s0, s0, s1`       |
| `fmin` `fmax`                       | min / max (a NaN input gives NaN)        |
| `fmadd d, a, b, c`                  | fused `c + a*b`, rounded once            |
| `scvtf s2, w2`                      | signed int to float                      |
| `fcvtzs w0, s0`                     | float to int, truncating toward zero     |
| `fcmp a, b`                         | compare, setting N, Z, C, V              |

Float arguments arrive in `s0`-`s7` (or `d0`-`d7`) and the result leaves in `s0` (or `d0`).

```arm
.globl lerp
.globl clampf
.text
// float lerp(float a /*s0*/, float b /*s1*/, float t /*s2*/) = a + (b - a) * t
lerp:
    fsub s1, s1, s0
    fmul s1, s1, s2
    fadd s0, s0, s1
    ret
// float clampf(float x /*s0*/, float lo /*s1*/, float hi /*s2*/)
clampf:
    fmax s0, s0, s1
    fmin s0, s0, s2
    ret
.section .note.GNU-stack,"",@progbits
```

From C, `lerp(10, 20, 0.25)` gives `12.5`, `lerp(0, 1, 1)` gives `1`, and `clampf` of `-1`, `0.5`, `7` between 0 and 1 gives `0`, `0.5`, `1` (I ran these). A standalone program computing `2.5 * 4.0 + 5`, then `fsqrt`, then `fcvtzs` gives `3`.

`fcmp` has a trap that integer compares don't. If either operand is NaN the result is "unordered", and the flags become N=0, Z=0, C=1, V=1. Then `eq`, `gt`, `ge` and `mi` are false, but `lt`, `le`, `hi` and `hs` are **true**. I checked that `gt` is false and `hi` is true for a NaN. So after `fcmp`, use `mi` for `<`, `ls` for `<=`, `gt` for `>`, `ge` for `>=` and `eq` for `==`: those are false when a NaN is involved. Also: compilers may contract `a*b + c` into a single `fmadd` (one rounding), so results can differ from separate `fmul` and `fadd` in the last bit.

## 10. Capstone: count newlines on stdin

The same program as the x86 guide's capstone, so you can compare the two line by line. It uses every part above: registers and the ABI, `.rodata`/`.bss` data, addressing, flags and conditional-select instructions, loops, division, the stack discipline (a callee-saved register holds a running total across calls), system calls, and NEON.

```arm
.set BUFSZ, 65536
.macro ldaddr reg, sym              // reg = address of sym (page + offset)
    adrp \reg, \sym
    add  \reg, \reg, :lo12:\sym
.endm

.bss
.balign 64
buf:    .skip BUFSZ
out:    .skip 24                    // 20 digits + '\n' fits

.text
// u64 count_nl_scalar(const u8 *p /*x0*/, u64 n /*x1*/)  -> x0
count_nl_scalar:
    mov  x2, #0
    cbz  x1, .Lcs_done
.Lcs_loop:
    ldrb w3, [x0], #1
    cmp  w3, #10
    cinc x2, x2, eq                 // x2 += (w3 == 10)
    subs x1, x1, #1
    b.ne .Lcs_loop
.Lcs_done:
    mov  x0, x2
    ret

// u64 count_nl_neon(const u8 *p /*x0*/, u64 n /*x1*/)  -> x0
// Reads only [p, p+n): whole 16-byte blocks, then a scalar tail.
count_nl_neon:
    mov  x2, #0                     // total
    lsr  x3, x1, #4                 // x3 = number of 16-byte blocks
    cbz  x3, .Ltail
    movi v1.16b, #10                // sixteen '\n' bytes, no constant table needed
.Lchunk:
    mov  x4, #255
    cmp  x3, x4
    csel x4, x3, x4, lo             // x4 = min(blocks left, 255): byte lanes can't overflow
    sub  x3, x3, x4
    movi v2.16b, #0                 // 16 byte counters
.Linner:
    ld1  {v0.16b}, [x0], #16        // load 16 bytes, advance x0
    cmeq v0.16b, v0.16b, v1.16b     // 0xFF where byte == '\n'
    sub  v2.16b, v2.16b, v0.16b     // subtracting -1 adds 1
    subs x4, x4, #1
    b.ne .Linner
    uaddlv h3, v2.16b               // sum all 16 bytes (max 4080) into h3
    umov w5, v3.h[0]
    add  x2, x2, x5
    cbnz x3, .Lchunk
.Ltail:
    and  x1, x1, #15                // leftover bytes
    cbz  x1, .Ldone
.Lt_loop:
    ldrb w5, [x0], #1
    cmp  w5, #10
    cinc x2, x2, eq
    subs x1, x1, #1
    b.ne .Lt_loop
.Ldone:
    mov  x0, x2
    ret

// void print_u64(u64 v /*x0*/): writes decimal + '\n' to stdout
print_u64:
    ldaddr x5, out
    add  x5, x5, #24                // x5 = end of buffer
    mov  x6, x5                     // remember the end
    mov  w3, #10
    sub  x5, x5, #1
    strb w3, [x5]                   // '\n'
    mov  x2, #10
.Ldigit:
    udiv x3, x0, x2                 // x3 = v / 10
    msub x4, x3, x2, x0             // x4 = v - x3*10 = v % 10 (there is no remainder instruction)
    add  w4, w4, #'0'
    sub  x5, x5, #1
    strb w4, [x5]
    mov  x0, x3
    cbnz x0, .Ldigit
    mov  x1, x5                     // buffer
    sub  x2, x6, x5                 // length
    mov  x0, #1                     // stdout
    mov  x8, #64                    // write
    svc  #0
    ret

.globl _start
_start:
    mov  x19, #0                    // x19 = running total (callee-saved: survives calls)
.Lread:
    mov  x0, #0                     // fd 0
    ldaddr x1, buf
    mov  x2, #BUFSZ
    mov  x8, #63                    // read
    svc  #0
    cmp  x0, #0
    b.lt .Lfail                     // negative = -errno (EINTR not retried here)
    b.eq .Lprint                    // 0 = EOF
    mov  x1, x0                     // n = bytes read
    ldaddr x0, buf
    bl   count_nl_neon              // swap for count_nl_scalar to compare
    add  x19, x19, x0
    b    .Lread
.Lprint:
    mov  x0, x19
    bl   print_u64
    mov  x0, #0
    b    .Lexit
.Lfail:
    mov  x0, #1
.Lexit:
    mov  x8, #93
    svc  #0
```

Build and verify (on the Pi drop the `aarch64-linux-gnu-` prefix and `qemu-aarch64`):

```sh
aarch64-linux-gnu-as nlcount.s -o nlcount.o && aarch64-linux-gnu-ld nlcount.o -o nlcount
qemu-aarch64 ./nlcount < somefile; wc -l < somefile
cat somefile | qemu-aarch64 ./nlcount     # pipe: read returns short chunks
```

Under qemu I tested both the NEON and scalar versions against `wc -l` on: empty input, no trailing newline, only newlines, 10 MB of random bytes, a 300 KB random mix, a file that straddles the 64 KiB read size, and every input length from 0 to 299 bytes (no mismatches). That says the logic is right, not that it is fast or that it behaves identically on a Cortex-A72: run it on the Pi, and do not use qemu timings for anything.

Where each part comes from:

| Part                                                 | Chapter |
| ---------------------------------------------------- | ------- |
| `x19` kept across calls, `x0` as argument and result | 2, 6    |
| `.rodata`, `.bss`, `adrp` + `add` (the macro)        | 3       |
| `cbz`, `cinc`, `csel`, `udiv`, `msub`, `b.lt`/`b.eq` | 4       |
| loops with `subs`/`b.ne`, `cbnz`                     | 5       |
| `bl`/`ret`, callee-saved register                    | 6       |
| `read`, `write`, `exit` through `svc`                | 7       |
| `cmeq`, `sub`, `uaddlv`, byte-counter flush          | 9       |

Exercises, in order of difficulty:

1. Retry the `read` when it returns `-4` (EINTR) instead of failing.
2. Take the byte to count from `argv[1]`. At `_start`, `[sp]` is `argc`, `[sp, #8]` is `argv[0]`, `[sp, #16]` is `argv[1]`.
3. Write `find_nl_neon`, returning the index of the first newline in a buffer (or -1) with the `shrn` idiom from chapter 9.
4. On the Pi, time the scalar and NEON versions on a 1 GiB file from the page cache (`< file`) with `perf stat`. Predict the ratio first.

## 11. x86-64 vs AArch64, side by side

| Concept                      | x86-64                                                                    | AArch64                                                    |
| ---------------------------- | ------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Arguments / result           | `rdi rsi rdx rcx r8 r9` / `rax`                                           | `x0`-`x7` / `x0`                                           |
| Syscall                      | `syscall`; `rax` = number; args `rdi rsi rdx r10 r8 r9`; write 1, exit 60 | `svc #0`; `x8` = number; args `x0`-`x5`; write 64, exit 93 |
| Instruction form             | two-operand, destination is also a source                                 | three-operand: `op d, a, b`                                |
| Memory in arithmetic         | allowed (`add rax, [rdi]`)                                                | never: load into a register first                          |
| Zero a register              | `xor eax, eax`                                                            | `mov x0, #0` (or read `xzr`)                               |
| Address of a label           | `lea rsi, [rip + label]`                                                  | `adrp x1, label` + `add x1, x1, :lo12:label`               |
| 64-bit constant              | `mov rax, imm64`                                                          | `movz` + up to three `movk`                                |
| Which instructions set flags | most arithmetic                                                           | only `s`-suffixed ones and `cmp`/`tst`/`fcmp`              |
| Carry after a compare        | CF = borrow                                                               | C = NOT borrow                                             |
| Signed / unsigned branches   | `jl jg` / `jb ja`                                                         | `b.lt b.gt` / `b.lo b.hi`                                  |
| Conditional data             | `cmovcc`, `setcc`                                                         | `csel`, `cset`, `cinc`                                     |
| Call / return                | `call` pushes the return address, `ret` pops it                           | `bl` sets `x30`, `ret` jumps to `x30`                      |
| Stack                        | `push` / `pop`                                                            | `stp` / `ldp` with pre/post-index                          |
| Stack alignment              | 16 bytes at a `call`                                                      | 16 bytes whenever `sp` addresses memory                    |
| Divide                       | `div`: quotient and remainder, SIGFPE on zero                             | `udiv`: quotient only (remainder via `msub`), zero gives 0 |
| Popcount                     | `popcnt`                                                                  | NEON `cnt` + `addv`                                        |
| Vector mask to integer       | `pmovmskb`                                                                | `cmeq` + `shrn #4` + `fmov`                                |
| Callee-saved                 | `rbx rbp r12`-`r15`                                                       | `x19`-`x28`, `x29`, low half of `v8`-`v15`                 |
| Instruction size             | 1 to 15 bytes                                                             | always 4                                                   |

## 12. Common mistakes

- Not saving `x30` in a function that calls another, so `ret` goes to the wrong place.
- Expecting plain `add` or `sub` to set flags. Use `adds`/`subs` or a `cmp`.
- Using `x18`, which the ABI reserves.
- Letting `sp` become misaligned, even briefly.
- Writing `ldr x0, label` when you meant to get the address. Use `adrp` + `add` for the address and `ldr` for the value.
- Out-of-range immediates: `add x0, x0, #4097` and many `and`/`orr` masks do not encode. Build big constants with `movz`/`movk`.
- Using `lt`, `le`, `hi` or `hs` after `fcmp` and expecting NaN to compare false.
- Assuming `udiv`/`sdiv` trap on zero (they return 0), or that a remainder instruction exists.
- Assuming `read` returns the full count.
- Loading 16 bytes with NEON when fewer remain in the buffer.

Lookups: the Arm Architecture Reference Manual (DDI0487) for every instruction, Arm's own A64 instruction set documentation, and `aarch64-linux-gnu-gcc -O1 -S file.c` to see how a compiler writes any of this.
