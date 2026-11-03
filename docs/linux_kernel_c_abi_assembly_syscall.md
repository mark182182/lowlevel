# Pure Assembly on Linux: System Calls, C ABI, and Kernel Interaction

## 1. Introduction

It is entirely possible to write complex Linux applications using pure assembly without depending on C, libc, or C-based syscall wrappers.

The important thing is understanding the distinction between three different concepts:

1. **C ABI (Application Binary Interface):** Defines how userspace functions exchange arguments, return values, and control.
2. **Linux syscall ABI:** Defines how userspace requests services directly from the Linux kernel.
3. **CPU instructions:** Instructions such as `call`, `ret`, and `syscall` that implement the actual control transfers.

These concepts are related, but they are not interchangeable.

The most important realization is:

**An ABI is a calling convention, not a programming language.**

You can implement functions that follow the C ABI entirely in assembly. You can also invoke Linux system calls directly from assembly without involving libc.

---

## 2. Understanding the Three Layers

Consider memory allocation through `mmap`.

There are two primary execution paths.

### A. Calling the libc implementation of mmap

When you call `mmap()` through libc, the execution path looks like this:

```text
+--------------------------------+
|     Your Assembly Application  |
+--------------------------------+
                |
                | call mmap
                v
+--------------------------------+
|         glibc mmap()           |
|                                |
|  Userspace C library function  |
|                                |
|  System V AMD64 ABI            |
+--------------------------------+
                |
                | syscall
                v
+--------------------------------+
|       Linux System Call        |
|                                |
|       Linux Syscall ABI        |
+--------------------------------+
                |
                v
+--------------------------------+
|          Linux Kernel          |
|                                |
|  mmap implementation           |
+--------------------------------+
```

In this scenario:

- Your assembly application calls a userspace function.
- The function is implemented and provided by glibc.
- The function translates the arguments into the Linux syscall convention.
- It executes the `syscall` CPU instruction.
- The Linux kernel performs the requested operation.

This approach introduces a dependency on libc.

### B. Calling the Linux kernel directly

You can bypass libc entirely.

```text
+--------------------------------+
|     Your Assembly Application  |
+--------------------------------+
                |
                |
                | Load syscall number
                | Load syscall arguments
                |
                v
+--------------------------------+
|       syscall Instruction      |
|                                |
|       Linux Syscall ABI        |
+--------------------------------+
                |
                v
+--------------------------------+
|          Linux Kernel          |
|                                |
|  mmap implementation           |
+--------------------------------+
```

In this scenario:

- Your assembly application prepares the arguments.
- It places the syscall number in the appropriate register.
- It executes the `syscall` instruction.
- The CPU transitions into kernel execution.
- The kernel performs the requested operation.

There is no intermediate userspace C function.

This is the approach used when building a fully independent assembly runtime.

---

## 3. Understanding the C ABI

On Linux x86-64, the standard userspace calling convention is System V AMD64 ABI.

It defines how functions receive their arguments, return values, and preserve registers.

For integer and pointer arguments, the register assignment is:

| Argument     | Register |
| ------------ | -------- |
| 1            | RDI      |
| 2            | RSI      |
| 3            | RDX      |
| 4            | RCX      |
| 5            | R8       |
| 6            | R9       |
| Return value | RAX      |

For example, consider this C function:

```c
void example(int a, int b, int c);
```

Calling this function from assembly means placing its arguments into the appropriate registers and executing `call`.

```asm
mov edi, 10
mov esi, 20
mov edx, 30

call example
```

The function can be implemented in C, C++, Rust, or assembly, provided it respects the required ABI.

**The C ABI does not require the implementation to be written in C.**

It only defines the binary-level contract between the caller and the callee.

---

## 4. Understanding the Linux Syscall ABI

The Linux x86-64 syscall interface uses a different register convention.

| Purpose        | Register |
| -------------- | -------- |
| Syscall number | RAX      |
| Argument 1     | RDI      |
| Argument 2     | RSI      |
| Argument 3     | RDX      |
| Argument 4     | R10      |
| Argument 5     | R8       |
| Argument 6     | R9       |
| Return value   | RAX      |

There is one particularly important difference:

**The fourth argument uses R10 instead of RCX.**

The reason is that the `syscall` instruction uses RCX and R11 internally. Both registers are clobbered during the transition.

The actual instruction that enters the Linux kernel is:

```asm
syscall
```

This is a CPU instruction, not a function from libc.

For Linux x86-64, the syscall number for `mmap` is 9.

---

## 5. Directly Invoking mmap From Assembly

Let's implement memory allocation without libc.

The following example uses NASM syntax.

### Complete executable

```asm
global _start

section .text

_start:
    ; mmap(
    ;     NULL,
    ;     4096,
    ;     PROT_READ | PROT_WRITE,
    ;     MAP_PRIVATE | MAP_ANONYMOUS,
    ;     -1,
    ;     0
    ; )

    mov     eax, 9
    xor     edi, edi
    mov     esi, 4096
    mov     edx, 3
    mov     r10d, 0x22
    mov     r8, -1
    xor     r9d, r9d

    syscall

    ; Check for a raw kernel error.
    cmp     rax, -4095
    jae     .error

    ; Write a value into allocated memory.
    mov     byte [rax], 42

    ; exit(0)
    mov     eax, 60
    xor     edi, edi
    syscall

.error:
    ; exit(1)
    mov     eax, 60
    mov     edi, 1
    syscall
```

Compile and execute:

```bash
nasm -f elf64 main.asm -o main.o
ld -o main main.o
./main
```

Notice what is absent:

- No C compiler.
- No libc.
- No C runtime startup code.
- No external userspace syscall wrapper.
- No dependency on `mmap()` as a C library function.

The executable starts directly at `_start`.

The application invokes the kernel using the CPU's `syscall` instruction.

### Understanding the error handling

Linux raw system calls return negative error numbers directly in RAX.

For example:

```text
-ENOMEM
-EINVAL
-EACCES
```

The kernel reserves the return range from `-4095` through `-1` for errors.

This differs from the libc `mmap()` interface, which returns `MAP_FAILED` and sets `errno`.

When bypassing libc, you are responsible for handling the raw return values.

---

## 6. The Difference Between call and syscall

This is probably the easiest way to recognize the distinction when reading assembly.

### Case A: Calling a userspace function

```asm
extern mmap

mov     edi, 0
mov     esi, 4096
mov     edx, 3
mov     ecx, 0x22
mov     r8, -1
xor     r9d, r9d

call    mmap
```

The instruction:

```asm
call mmap
```

transfers execution to a userspace function identified by the symbol `mmap`.

Normally, when linking against glibc, this symbol resolves to the libc implementation.

However, `call` itself does not imply libc. The target could also be your own assembly function.

### Case B: Calling the kernel directly

```asm
mov     eax, 9
xor     edi, edi
mov     esi, 4096
mov     edx, 3
mov     r10d, 0x22
mov     r8, -1
xor     r9d, r9d

syscall
```

The instruction:

```asm
syscall
```

is a dedicated CPU instruction that transitions into kernel execution.

There is no userspace function call between your application and the kernel.

### Quick comparison

| Instruction or API | Meaning                                  |
| ------------------ | ---------------------------------------- |
| `call mmap`        | Calls a userspace function named `mmap`  |
| `call my_function` | Calls another userspace function         |
| `syscall()`        | Usually the generic libc syscall wrapper |
| `syscall`          | CPU instruction that enters the kernel   |
| `ret`              | Returns from a userspace function        |

One subtle but important distinction:

`syscall()` and `syscall` are not the same thing.

- `syscall()` is a C library function.
- `syscall` is an assembly instruction.

Even the following C code:

```c
syscall(SYS_mmap, ...);
```

uses a userspace library function to invoke the underlying kernel interface.

---

## 7. Implementing Your Own C-ABI-Compatible Function in Assembly

There is another important possibility.

You can implement your own functions in assembly that follow the System V AMD64 ABI while invoking the kernel directly internally.

For example:

```asm
global my_mmap

my_mmap:
    ; Arguments arrive using System V AMD64 ABI.
    ;
    ; RDI = address
    ; RSI = length
    ; RDX = protection
    ; RCX = flags
    ; R8  = file descriptor
    ; R9  = offset

    ; Translate the fourth argument.
    mov     r10, rcx

    ; Linux x86-64 mmap syscall.
    mov     eax, 9

    ; Direct kernel transition.
    syscall

    ret
```

This function:

1. Receives arguments using the normal System V AMD64 ABI.
2. Translates the fourth argument from RCX to R10.
3. Loads the Linux syscall number.
4. Executes the kernel transition.
5. Returns the raw kernel result through RAX.

You can call this function using the normal userspace calling convention:

```asm
mov     edi, 0
mov     esi, 4096
mov     edx, 3
mov     ecx, 0x22
mov     r8, -1
xor     r9d, r9d

call    my_mmap
```

There is no libc involved.

The important distinction is that `my_mmap` is a userspace assembly function implementing the C-compatible calling convention. Its internal implementation talks directly to the Linux kernel.

This is a useful technique when building your own runtime or syscall abstraction layer.

---

## 8. Differentiating ABI Compatibility From Language Dependencies

These concepts should be kept separate.

| Concept           | What it defines                                                   |
| ----------------- | ----------------------------------------------------------------- |
| C ABI             | How compatible userspace functions exchange arguments and results |
| Linux syscall ABI | How userspace communicates with the Linux kernel                  |
| C language        | A programming language                                            |
| libc              | A userspace library providing standard C and POSIX interfaces     |
| `call`            | CPU instruction for transferring control to a function            |
| `syscall`         | CPU instruction for entering kernel execution                     |

An assembly function can follow the C ABI without being written in C.

An assembly application can invoke the Linux syscall ABI without linking against libc.

And a C library can itself be implemented using assembly internally.

These are independent concerns.

---

## 9. What About Complex Applications?

There is no fundamental limitation preventing you from implementing complex applications entirely in assembly.

You can implement:

| Subsystem                  | Possible in pure userspace assembly?                      |
| -------------------------- | --------------------------------------------------------- |
| Memory allocator           | Yes                                                       |
| Virtual memory management  | Yes                                                       |
| File operations            | Yes                                                       |
| Networking                 | Yes                                                       |
| TCP/UDP protocols          | Yes                                                       |
| HTTP server                | Yes                                                       |
| Thread creation            | Yes                                                       |
| Synchronization primitives | Yes                                                       |
| Custom data structures     | Yes                                                       |
| Parsing and serialization  | Yes                                                       |
| Compression algorithms     | Yes                                                       |
| Database engine            | Yes                                                       |
| Compiler                   | Yes                                                       |
| Custom runtime             | Yes                                                       |
| GUI application            | Yes, using appropriate graphical interfaces and protocols |

However, you need to implement the functionality that libc and other userspace libraries normally provide.

For example:

- Memory allocation and deallocation.
- String and buffer manipulation.
- Error handling.
- File buffering.
- Process initialization.
- Argument and environment parsing.
- Thread-local storage.
- Synchronization.
- Networking protocols.
- Higher-level runtime functionality.

Also, not every operating-system interface is a syscall. Some services, such as DNS resolution and TLS, require additional protocol implementations or userspace libraries.

The absence of libc does not eliminate these requirements. It makes them your responsibility.

---

## 10. Recommended Architecture for a Pure Assembly Runtime

A reasonable architecture would look like this:

```text
+---------------------------------------------+
|               APPLICATION                   |
|                                             |
|   Application logic                         |
|   Algorithms                                |
|   Custom data structures                    |
+---------------------------------------------+
                      |
                      v
+---------------------------------------------+
|             CUSTOM RUNTIME                  |
|                                             |
|   Memory allocator                          |
|   String and buffer operations              |
|   Containers                                |
|   Error handling                            |
|   Runtime initialization                    |
|   Thread management                         |
+---------------------------------------------+
                      |
                      v
+---------------------------------------------+
|             SYSCALL ABSTRACTION             |
|                                             |
|   mmap / munmap                             |
|   read / write                              |
|   openat / close                            |
|   socket / connect                          |
|   clone / futex                             |
|   exit                                      |
+---------------------------------------------+
                      |
                      v
+---------------------------------------------+
|             LINUX SYSCALL ABI               |
|                                             |
|   Register preparation                      |
|   Syscall numbers                           |
|   syscall instruction                       |
|   Raw error handling                        |
+---------------------------------------------+
                      |
                      v
+---------------------------------------------+
|                 LINUX KERNEL                |
+---------------------------------------------+
```

The syscall abstraction should be extremely small and predictable.

For example, you might implement:

```asm
sys_mmap:
    mov     eax, 9
    mov     r10, rcx
    syscall
    ret

sys_munmap:
    mov     eax, 11
    syscall
    ret

sys_read:
    mov     eax, 0
    syscall
    ret

sys_write:
    mov     eax, 1
    syscall
    ret
```

These wrappers use the System V ABI at their entry points but directly invoke the Linux kernel internally.

That gives the rest of your application a consistent interface without depending on libc.

For production use, you would also document their argument conventions, error behavior, and register-clobbering rules.

---

## 11. Important Caveat: The Kernel Can Still Be Written in C

When saying that your application is pure assembly, we are discussing the userspace application and its dependencies.

Linux itself is largely implemented in C, with some assembly and other language components.

That does not make your application dependent on C.

The execution boundary is:

```text
YOUR APPLICATION                 LINUX KERNEL
----------------                 ------------

Assembly                        C / Assembly / Other
    |                                   |
    | syscall instruction               |
    +---------------------------------->|
                                        |
                                  Kernel executes
                                        |
    |<----------------------------------+
    |
    | Raw syscall result
    |
```

The kernel's internal implementation language is irrelevant to the userspace application's language dependencies.

If you also want an operating system whose kernel contains no C, that is a different project: you would need to implement your own kernel or use an operating system designed around another implementation language.

---

## 12. Final Mental Model

The entire distinction can be summarized in three statements:

**1. ABI describes a contract.**

It defines how functions communicate. It does not dictate which language implements them.

**2. `call` invokes a userspace function.**

That function could be implemented in C, assembly, or another language. Its actual implementation is determined by symbol resolution and linking.

**3. `syscall` enters the Linux kernel.**

It is a CPU instruction that uses the Linux syscall ABI. It does not require a C function or libc wrapper.

The most important distinction to remember:

> Using the C ABI does not mean using C. Calling a function that follows the C ABI is perfectly compatible with pure assembly development.

You can implement your own C-ABI-compatible functions in assembly, invoke Linux system calls directly, build your own runtime, and develop complex userspace applications without a single C source file or libc dependency.

### Scope of this discussion

The register assignments, syscall numbers, and examples in this document target **Linux x86-64 (AMD64), using NASM syntax and the System V AMD64 ABI**.

Other architectures and operating systems use different calling conventions, syscall numbers, and transition instructions.

### Useful references

- [System V Application Binary Interface – AMD64 Architecture Processor Supplement](https://gitlab.com/x86-psABIs/x86-64-ABI)
- [Linux manual page: syscall(2)](https://man7.org/linux/man-pages/man2/syscall.2.html)
- [Linux manual page: mmap(2)](https://man7.org/linux/man-pages/man2/mmap.2.html)
- [Linux kernel syscall definitions](https://github.com/torvalds/linux/tree/master/arch/x86/entry)
- [Linux nolibc implementation](https://codebrowser.dev/linux/linux/tools/include/nolibc/)
