# C, step by step

For your plan: C as a thin layer over the machine, no libraries beyond the OS interface, pointer+length instead of NUL-terminated strings, explicit memory instead of `malloc`. Same shape as the assembly guides, with the same capstone (count newlines on stdin) so you can compare all versions.

Every program here was compiled with GCC 13.3 and run on x86-64 Linux. Programs that matter for AArch64 were also built with `aarch64-linux-gnu-gcc` and run under `qemu-aarch64`, not on real Arm hardware. I did not have clang installed, so anything about clang is untested. Sizes, timings and warnings quoted are what I observed on that setup.

## 0. Setup

```sh
gcc -O2 -Wall -Wextra prog.c -o prog                       # normal build
gcc -O1 -g -fsanitize=address,undefined prog.c -o prog     # checking build: run your tests with this
gcc -O2 -S -masm=intel prog.c -o prog.s                    # see the assembly
```

One `.c` file, one command. A single translation unit is enough for everything in this guide. `-Wall -Wextra` is not optional: several lessons below are warnings the compiler gives you for free. Cross-compile for the Pi from a PC with `aarch64-linux-gnu-gcc` and run with `qemu-aarch64 -L /usr/aarch64-linux-gnu ./prog`.

## 1. Types, values, and the machine model

Use fixed-width types from `<stdint.h>` and give them short names:

```c
typedef uint8_t u8;  typedef uint32_t u32;  typedef uint64_t u64;
```

Use `size_t` for sizes and indices, `ssize_t` for a size-or-error result (as `read` returns). Plain `int` is for small counters you know are small.

The rules that cause most bugs:

- **Unsigned arithmetic wraps** and that is defined: `0u - 1` is the largest value.
- **Signed overflow is undefined behavior** (UB). The compiler may assume it never happens (chapter 5).
- **Integer promotion:** anything smaller than `int` is converted to `int` before arithmetic, so `uint8_t + uint8_t` is an `int`.
- **Mixed signed/unsigned comparison:** the signed side is converted to unsigned. `-1 < 1u` is false. `-Wextra` warns about this.
- **Division truncates toward zero**, and `%` takes the sign of the left operand.
- **Right shift of a negative number** is implementation-defined (GCC and clang shift arithmetically). Shifting by the type's width or more is UB.
- **`char` signedness is platform-dependent.** Use `u8` for bytes, never plain `char`.

```c
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <limits.h>

int main(void) {
    printf("char=%zu short=%zu int=%zu long=%zu long long=%zu void*=%zu size_t=%zu\n",
           sizeof(char), sizeof(short), sizeof(int), sizeof(long), sizeof(long long),
           sizeof(void *), sizeof(size_t));
    printf("char is %s\n", (char)-1 < 0 ? "signed" : "unsigned");

    uint8_t  a = 250;  a += 10;                 // unsigned wraps: 260 mod 256
    uint32_t b = 0;    b -= 1;                  // 4294967295
    printf("u8 250+10 = %u, u32 0-1 = %u\n", a, b);

    int8_t   s = -1;   uint32_t u = 1;
    printf("(-1 < 1u): %d\n", (int)(s < u));    // -1 becomes 0xFFFFFFFF: prints 0

    uint8_t  x = 200, y = 100;
    printf("x+y as int = %d, as u8 = %u\n", x + y, (uint8_t)(x + y));  // 300, then 44

    int neg = -7;
    printf("-7 / 2 = %d, -7 %% 2 = %d, -7 >> 1 = %d\n", neg / 2, neg % 2, neg >> 1);
    return 0;
}
```

Output on x86-64 and on AArch64 (qemu) was identical except one line: `char is signed` on x86-64 and `char is unsigned` on AArch64 Linux. Everything else: sizes `1 2 4 8 8 8 8`, `u8 250+10 = 4`, `u32 0-1 = 4294967295`, `(-1 < 1u): 0`, `x+y as int = 300, as u8 = 44`, `-7 / 2 = -3, -7 % 2 = -1, -7 >> 1 = -4`. With `-Wextra`, GCC also warned about the signed/unsigned comparison (`-Wsign-compare`).

## 2. Memory: pointers, arrays, and pointer+length

- An array name in an expression becomes a pointer to its first element. `p[i]` means `*(p + i)`, and pointer arithmetic is scaled by the element size, which is exactly the scaled-index addressing you saw in assembly.
- A function parameter written `int a[10]` is really `int *a`. `sizeof a` inside the function is the size of a pointer. GCC warns with `-Wsizeof-array-argument`; I observed `sizeof(int[10]) = 40` but `sizeof` on the parameter `= 8`.
- **Strings: use pointer + length.** A NUL-terminated string needs a scan to find its length and can't hold a zero byte. A slice is two words, costs nothing to take a substring of, and works for any bytes.
- **Struct layout:** fields are laid out in order, each at an offset aligned to its own size, with padding inserted. Put the largest fields first to save space. `offsetof` gives the offset.
- `const` documents and enforces read-only use. `restrict` promises that two pointers do not overlap.

```c
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
typedef uint8_t u8;  typedef uint32_t u32;  typedef uint64_t u64;

typedef struct { const u8 *p; size_t n; } Bytes;     // pointer + length

static Bytes bytes_slice(Bytes b, size_t from, size_t to) {   // no copy, no NUL
    return (Bytes){ b.p + from, to - from };
}
static size_t bytes_find(Bytes b, u8 c) {            // index of first c, or b.n if none
    for (size_t i = 0; i < b.n; i++) if (b.p[i] == c) return i;
    return b.n;
}

typedef struct { u32 x, y, hp; } P;                  // 12 bytes, align 4
typedef struct { u8 tag; u64 v; u8 tag2; } Padded;   // 24 bytes: padding after tag and tag2
typedef struct { u64 v; u8 tag, tag2; } Packed2;     // same fields reordered: 16 bytes

int main(void) {
    Bytes line = { (const u8 *)"key=value", 9 };
    size_t eq = bytes_find(line, '=');
    Bytes k = bytes_slice(line, 0, eq), v = bytes_slice(line, eq + 1, line.n);
    printf("key=%.*s value=%.*s\n", (int)k.n, (const char *)k.p, (int)v.n, (const char *)v.p);
    printf("sizeof P=%zu offsetof hp=%zu\n", sizeof(P), offsetof(P, hp));
    printf("Padded=%zu (v at %zu)  Packed2=%zu\n", sizeof(Padded), offsetof(Padded, v), sizeof(Packed2));

    P aos[4] = {{1,2,10},{3,4,20},{5,6,30},{7,8,40}};
    u32 hp_soa[4] = {10,20,30,40};
    u64 s1 = 0, s2 = 0;
    for (size_t i = 0; i < 4; i++) s1 += aos[i].hp;      // stride 12 bytes
    for (size_t i = 0; i < 4; i++) s2 += hp_soa[i];      // stride 4 bytes
    printf("AoS %llu SoA %llu\n", (unsigned long long)s1, (unsigned long long)s2);
    return 0;
}
```

Output: `key=key value=value`, `sizeof P=12 offsetof hp=8`, `Padded=24 (v at 8)  Packed2=16`, `AoS 100 SoA 100`. The same struct-of-arrays vs array-of-structs trade-off as in the assembly guides: SoA reads only the field the loop uses.

### Aliasing, `restrict`, and type punning

If the compiler can't prove two pointers are distinct, it must assume a store through one may change what the other points to. I compiled two versions of the same loop with `gcc -O2`:

```c
void add_i(int *a, int *b, int n)                   { for (int i = 0; i < n; i++) a[i] += *b; }
void add_r(int *restrict a, int *restrict b, int n) { for (int i = 0; i < n; i++) a[i] += *b; }
```

In `add_i` the loop body reloads `*b` from memory on every iteration (`mov eax, DWORD PTR [rsi]` inside the loop), because `a[i]` might be `*b`. In `add_r` the load is hoisted above the loop and the loop is unrolled by two. `restrict` is a promise: if you break it, the behavior is undefined.

To reinterpret the bytes of one type as another, do not cast pointers (that violates the strict aliasing rule and is UB). Use `memcpy`; it compiles to a register move:

```c
u32 float_bits(float f) { u32 u; memcpy(&u, &f, sizeof u); return u; }   // gcc -O2: movd eax, xmm0 ; ret
```

`float_bits(1.0f)` returned `0x3f800000`.

## 3. Control flow and functions

`for`, `while`, `switch` and `if` compile to the compares and jumps you wrote by hand. A dense `switch` usually becomes a jump table. A function is a label that follows the platform's calling convention (arguments in `rdi rsi rdx ...` on x86-64, `x0`-`x7` on AArch64), which is why C and your assembly can call each other.

- `static` on a function or global gives it internal linkage: not visible to other files, and easier for the compiler to inline. Use it by default.
- A pointer to a function is an address you call indirectly. A table of them is a hand-built `switch`:

```c
static int op_add(int a, int b) { return a + b; }
static int op_sub(int a, int b) { return a - b; }
static int op_mul(int a, int b) { return a * b; }
typedef int (*BinOp)(int, int);
static const BinOp ops[] = { op_add, op_sub, op_mul };
// ops[0](7, 3) == 10, ops[1](7, 3) == 4, ops[2](7, 3) == 21   (I ran this)
```

Indirect calls are harder for the CPU to predict and for the compiler to inline, so keep them out of inner loops.

## 4. Memory: an arena instead of `malloc`

A bump arena is a block of memory plus a position. Allocating moves the position forward; freeing a group of allocations at once moves it back. One decision (the arena's lifetime) replaces many `free` calls.

```c
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
typedef uint8_t u8;  typedef uint64_t u64;

typedef struct { u8 *base; size_t cap, pos; } Arena;

static void *arena_alloc(Arena *a, size_t size, size_t align) {   // align: power of two
    size_t p = (a->pos + (align - 1)) & ~(align - 1);              // round up
    if (p > a->cap || size > a->cap - p) return 0;                 // can't wrap around
    a->pos = p + size;
    return a->base + p;
}
#define ARENA_NEW(a, T, n) ((T *)arena_alloc((a), sizeof(T) * (n), _Alignof(T)))

static u8 storage[1024] __attribute__((aligned(16)));

int main(void) {
    Arena a = { storage, sizeof storage, 0 };
    u8  *c = ARENA_NEW(&a, u8, 1);
    u64 *q = ARENA_NEW(&a, u64, 4);              // forces padding after the byte
    printf("c at +%zu, q at +%zu (aligned to 8: %s), pos=%zu\n",
           (size_t)(c - storage), (size_t)((u8 *)q - storage),
           ((uintptr_t)q % 8 == 0) ? "yes" : "no", a.pos);
    size_t mark = a.pos;                         // a mark is just a number
    (void)ARENA_NEW(&a, u8, 100);
    a.pos = mark;                                // frees everything allocated since the mark
    void *too_big = arena_alloc(&a, 1u << 20, 8);
    printf("after pop pos=%zu, oversize alloc -> %s\n", a.pos, too_big ? "ptr" : "NULL");
    return 0;
}
```

Output: `c at +0, q at +8 (aligned to 8: yes), pos=40` and `after pop pos=40, oversize alloc -> NULL`. Points to notice: the allocation after a 1-byte object is padded to an 8-byte boundary, the overflow check is written as `size > cap - p` so it can never wrap around, and exhaustion returns NULL and leaves the arena unchanged. For the full set of broken variants and which tool catches each, see task P2.3 in your plan.

## 5. Undefined behavior and the tools

UB means the standard places no requirements on the program, and the compiler is allowed to assume it never happens. It is not "the hardware does something odd". This program shows it:

```c
#include <stdio.h>
#include <limits.h>
__attribute__((noinline)) int grows(int x)  { return x + 1 > x; }      // true for every x ... if signed overflow can't happen
__attribute__((noinline)) int add1(int x)   { return x + 1; }
__attribute__((noinline)) unsigned ugrows(unsigned x) { return x + 1 > x; }
int main(void) {
    printf("grows(INT_MAX)   = %d\n", grows(INT_MAX));
    printf("ugrows(UINT_MAX) = %u\n", ugrows(UINT_MAX));
    printf("add1(INT_MAX)    = %d\n", add1(INT_MAX));
    return 0;
}
```

What I observed with GCC 13 at both `-O0` and `-O2`: `grows(INT_MAX) = 1`, `ugrows(UINT_MAX) = 0` (unsigned wraps, defined), and `add1(INT_MAX) = -2147483648` (the hardware's wrap). Even at `-O0` the assembly for `grows` is just `mov eax, 1`: GCC folded the comparison to "always true" because signed overflow is UB. So UB is not something only the optimizer exploits.

With `-fsanitize=undefined`, UBSan reported `signed integer overflow: 2147483647 + 1 cannot be represented in type 'int'` for `add1` (line 4) but **not** for `grows`. The compiler had already removed the addition, so the sanitizer had nothing left to instrument. The lesson: a sanitizer only reports UB that survives to the code it instruments, so a clean sanitizer run is not proof.

AddressSanitizer catches memory errors. For `int *a = malloc(4 * sizeof *a); a[4] = 1;` it reported `heap-buffer-overflow ... WRITE of size 4` with the source line.

Habit: build and run your tests with `-fsanitize=address,undefined`, and use unsigned types when you want wraparound.

## 6. Talking to the OS without stdio

For raw input and output, `<unistd.h>` gives thin wrappers over the system calls from the assembly guides: `read(fd, buf, n)`, `write(fd, buf, n)`, `_exit(code)`. They return the byte count, `0` at end of input, or `-1` with `errno` set. Rules you already know from the assembly guides apply: `read` may return fewer bytes than asked for (always check the return value), `write` may too, and `EINTR` means "interrupted, try again". You don't need `printf` for a program that reads bytes and prints a number: the capstone below formats its own number into a buffer.

## 7. Mixing with assembly

### Calling assembly from C

Declare the function in C, export the label in the `.s` file, and link both:

```c
#include <stdio.h>
long sum(const long *p, unsigned long n);       // defined in sum.s
int main(void) { long a[] = {1, 2, 3, 4}; printf("%ld\n", sum(a, 4)); return 0; }
```

```sh
gcc main.c sum.s -o t && ./t                                        # x86-64: uses sum.s from the x86 guide
aarch64-linux-gnu-gcc main.c sum.s -o t \
  && qemu-aarch64 -L /usr/aarch64-linux-gnu ./t                      # AArch64: uses sum.s from the AArch64 guide
```

Both printed `10`. The C file is identical. Only the assembly differs, because the two ISAs have different registers and the same C signature maps to different registers in each.

### Inline assembly

```c
#include <stdio.h>
#include <stdint.h>
typedef uint64_t u64;

static inline u64 popcnt_asm(u64 x) {
    u64 r;
    __asm__("popcnt %1, %0" : "=r"(r) : "r"(x) : "cc");   // AT&T order: source first
    return r;
}
int main(void) {
    printf("%llu %llu\n", (unsigned long long)popcnt_asm(0xF0F0), (unsigned long long)__builtin_popcountll(0xF0F0));
    return 0;
}
```

Both printed `8`. The pieces: the template string, then outputs (`"=r"(r)`: write to a register, assign to `r`), then inputs (`"r"(x)`), then clobbers (what the instruction destroys besides its outputs: `"cc"` = the flags, `"memory"` = arbitrary memory). The compiler trusts these lists completely. A missing clobber produces silently wrong code at higher optimization levels. Inline asm in GCC uses AT&T operand order (source first) unless you compile with `-masm=intel`.

Prefer builtins and intrinsics over inline asm when they exist. `__builtin_popcountll` compiles differently depending on the target. On default x86-64 (no `-mpopcnt`) I observed `call __popcountdi2@PLT`, a helper function in libgcc, because plain x86-64 does not guarantee a `popcnt` instruction. With `-mpopcnt` it compiled to `xor eax, eax` / `popcnt rax, rdi` / `ret`. That is the baseline-versus-extension distinction from the assembly guides.

## 8. SIMD with intrinsics

Intrinsics are C functions that map nearly one-to-one onto SIMD instructions, with typed vector variables the compiler allocates registers for. On x86-64 include `<emmintrin.h>` (SSE2 is baseline, so no flags are needed). On AArch64 include `<arm_neon.h>` (NEON is baseline).

| Operation                    | SSE2 (x86-64)                       | NEON (AArch64)                                                             |
| ---------------------------- | ----------------------------------- | -------------------------------------------------------------------------- |
| 16 copies of a byte          | `_mm_set1_epi8(c)`                  | `vdupq_n_u8(c)`                                                            |
| load 16 bytes, any alignment | `_mm_loadu_si128(p)`                | `vld1q_u8(p)`                                                              |
| per-byte equal, as a mask    | `_mm_cmpeq_epi8` (`pcmpeqb`)        | `vceqq_u8` (`cmeq`)                                                        |
| per-byte subtract            | `_mm_sub_epi8` (`psubb`)            | `vsubq_u8` (`sub`)                                                         |
| sum the bytes                | `_mm_sad_epu8` + extract (`psadbw`) | `vaddlvq_u8` (`uaddlv`)                                                    |
| mask to an integer           | `_mm_movemask_epi8` (`pmovmskb`)    | no single instruction; `vshrn_n_u16(v, 4)` then move to a general register |

The design is the same as in the assembly guides: compare to get a mask, subtract the mask from a byte counter (adds 1 per match), flush at most every 255 iterations, and handle the last `n % 16` bytes with a scalar loop so nothing outside the buffer is read.

**Will the compiler do it for you?** I compiled the plain scalar loop (`total += (p[i] == '\n')`) with GCC 13.3. At `-O1` and `-O2` the assembly contains no `pcmpeqb`: not vectorized. At `-O3` it does contain `pcmpeqb`. So the answer depends on the optimization level, the compiler and its version. Check the assembly and measure instead of assuming.

## 9. Capstone: count newlines on stdin

The same program as in the assembly guides, in C. It uses everything above: fixed-width types, pointer+length, a static buffer, `read`/`write` with error handling, a hand-written number formatter, and SIMD behind a compile-time switch.

```c
#include <stdint.h>
#include <stddef.h>
#include <errno.h>
#include <unistd.h>
#if defined(__SSE2__) && !defined(FORCE_SCALAR)
#include <emmintrin.h>
#elif defined(__ARM_NEON) && !defined(FORCE_SCALAR)
#include <arm_neon.h>
#endif

typedef uint8_t  u8;
typedef uint64_t u64;

#define BUFSZ 65536
static u8 buf[BUFSZ];

// Reads only p[0..n).
static u64 count_nl_scalar(const u8 *p, size_t n) {
    u64 total = 0;
    for (size_t i = 0; i < n; i++) total += (p[i] == '\n');
    return total;
}

#if defined(__SSE2__) && !defined(FORCE_SCALAR)
static u64 count_nl(const u8 *p, size_t n) {
    u64 total = 0;
    const __m128i nl = _mm_set1_epi8('\n'), zero = _mm_setzero_si128();
    size_t blocks = n / 16;
    while (blocks) {
        size_t chunk = blocks < 255 ? blocks : 255;       // byte lanes overflow after 255 adds
        blocks -= chunk;
        __m128i acc = _mm_setzero_si128();
        for (size_t i = 0; i < chunk; i++, p += 16)
            acc = _mm_sub_epi8(acc, _mm_cmpeq_epi8(_mm_loadu_si128((const __m128i *)p), nl));
        __m128i s = _mm_sad_epu8(acc, zero);              // horizontal byte sums: two 64-bit lanes
        total += (u64)_mm_cvtsi128_si64(s) + (u64)_mm_cvtsi128_si64(_mm_srli_si128(s, 8));
    }
    return total + count_nl_scalar(p, n & 15);
}
#elif defined(__ARM_NEON) && !defined(FORCE_SCALAR)
static u64 count_nl(const u8 *p, size_t n) {
    u64 total = 0;
    const uint8x16_t nl = vdupq_n_u8('\n');
    size_t blocks = n / 16;
    while (blocks) {
        size_t chunk = blocks < 255 ? blocks : 255;
        blocks -= chunk;
        uint8x16_t acc = vdupq_n_u8(0);
        for (size_t i = 0; i < chunk; i++, p += 16)
            acc = vsubq_u8(acc, vceqq_u8(vld1q_u8(p), nl));
        total += vaddlvq_u8(acc);
    }
    return total + count_nl_scalar(p, n & 15);
}
#else
static u64 count_nl(const u8 *p, size_t n) { return count_nl_scalar(p, n); }
#endif

static void print_u64(u64 v) {
    u8 out[24];
    size_t i = sizeof out;
    out[--i] = '\n';
    do { out[--i] = (u8)('0' + v % 10); v /= 10; } while (v);
    if (write(1, out + i, sizeof out - i) < 0) _exit(1);
}

int main(void) {
    u64 total = 0;
    for (;;) {
        ssize_t r = read(0, buf, BUFSZ);
        if (r < 0) { if (errno == EINTR) continue; return 1; }
        if (r == 0) break;
        total += count_nl(buf, (size_t)r);
    }
    print_u64(total);
    return 0;
}
```

Build and verify:

```sh
gcc -O2 -Wall -Wextra nlcount.c -o nlcount                       # SIMD path (SSE2 or NEON, chosen by the compiler's target)
gcc -O2 -Wall -Wextra -DFORCE_SCALAR nlcount.c -o nlcount_sc     # scalar path
gcc -O1 -g -fsanitize=address,undefined nlcount.c -o nlcount_san
./nlcount < somefile; wc -l < somefile
cat somefile | ./nlcount                                         # pipe: read returns short chunks
```

What I tested: the SSE2 build, the forced-scalar build and the ASan+UBSan build on x86-64, and the NEON build via `aarch64-linux-gnu-gcc` under qemu, against `wc -l` on: empty input, no trailing newline, only newlines, 10 MB of random bytes, a 300 KB random mix, a file that straddles the 64 KiB read size, and every input length from 0 to 299 bytes. No mismatches in any build, and no sanitizer reports. That shows the logic is right on those inputs. It does not show the code is fast on your machine or correct on a real Cortex-A72.

A rough speed check, on a 256 MiB file in the page cache with a newline every 50 bytes (best of 5 runs, my container, includes the kernel copy in `read`, so not benchmark-grade): the SSE2 build took about 42 ms, the scalar source built at `-O2` about 103 ms, and the scalar source at `-O3` about 70 ms (where GCC auto-vectorizes). Use the benchmark harness from your plan (P0.4) for real numbers, and compare against your assembly versions.

Where each part comes from:

| Part                                                       | Chapter |
| ---------------------------------------------------------- | ------- |
| `u8`, `u64`, `size_t`, `ssize_t`, wraparound and promotion | 1       |
| pointer + length (`p`, `n`), `static` buffer, no `malloc`  | 2, 4    |
| `static` functions, loops, tail handling                   | 3       |
| `read`/`write` return values, `EINTR`, short reads         | 6       |
| `_mm_*` / `v*q_u8` intrinsics, 255-iteration flush         | 8       |
| sanitizer build                                            | 5       |

Exercises, in order of difficulty:

1. Replace the static `buf` with memory taken from the arena in chapter 4.
2. Take the byte to count from `argv[1]` (`int main(int argc, char **argv)`; reject a missing or multi-byte argument with an error exit code).
3. Write `find_nl`, returning the index of the first newline in a buffer (or `n` if none), using `_mm_movemask_epi8` + `__builtin_ctz` on x86-64 and `vshrn_n_u16` on AArch64. Test it against a plain loop, including blocks where the newline is the last byte of a 16-byte block.
4. Compare `gcc -O2 -S -masm=intel` for `count_nl` with your hand-written assembly: count instructions in the inner loop, and time both with your harness.

## 10. Common mistakes

- Using plain `char` for bytes (signedness differs by platform: signed on x86-64, unsigned on AArch64 Linux). Use `u8`.
- Comparing signed with unsigned (`-1 < 1u` is false). Keep `-Wextra` on.
- Writing `sizeof` on an array parameter. It gives the size of a pointer.
- Relying on signed overflow, for example `if (x + 1 > x)`. The compiler may treat that as always true.
- Thinking a clean sanitizer run proves the absence of UB.
- Casting pointers to reinterpret data instead of using `memcpy`.
- Using `int` for sizes and indices. Use `size_t`.
- Assuming `read` or `write` transfers the full count, or forgetting to retry on `EINTR`.
- Reading 16 bytes with a SIMD load when fewer than 16 remain in the buffer.
- Letting a byte-counter lane run past 255 additions before widening.
- Passing `restrict` pointers that actually overlap.
- Returning a pointer to a local variable (use caller-provided memory or an arena).
