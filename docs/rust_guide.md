# Rust, step by step

For your plan: Rust used the way the C guide uses C. Standard library only, no external crates, slices instead of pointer arithmetic, indices instead of references for linked data, `unsafe` kept small and justified. Same capstone as the other guides (count newlines on stdin) so you can compare every version.

Every program here was compiled with `rustc 1.75.0` (the Ubuntu package) and run on x86-64 Linux. Things I could **not** do in my environment: there was no AArch64 Rust target installed, so no Rust code was compiled or run for the Pi; there was no Miri, so nothing is Miri-checked (your plan asks for that); and I used `rustc` directly, not Cargo. Compiler error text quoted is from 1.75 and will be worded differently in newer versions.

## 0. Setup

```sh
rustc -O prog.rs -o prog                      # optimized build
rustc prog.rs -o prog                         # opt-level 0: debug assertions and overflow checks are ON
rustc -O --emit asm -C llvm-args=-x86-asm-syntax=intel prog.rs -o prog.s    # see the assembly (Intel syntax)
rustc --explain E0382                         # long explanation of any error code
```

For the Pi you would install the target (`rustup target add aarch64-unknown-linux-gnu`) and an Arm linker, or build natively on the Pi. I did not test that. One file and one command is enough for everything in this guide.

## 1. Values and types

| Type                                           | Notes                                                               |
| ---------------------------------------------- | ------------------------------------------------------------------- |
| `u8` `u16` `u32` `u64` `u128`, `i8` ... `i128` | fixed-width integers                                                |
| `usize`, `isize`                               | pointer-sized; use `usize` for lengths and indices                  |
| `f32`, `f64`, `bool`                           |                                                                     |
| `char`                                         | a Unicode scalar value, **4 bytes**. Not a byte. Use `u8` for bytes |

There are no implicit conversions between integer types. You write `as` (or `try_from`) and mean it. `as` never fails; it truncates, reinterprets, or saturates:

- `300i32 as u8` is `44`; `-1i32 as u32` is `4294967295`; `-1i32 as u8` is `255` (truncate or reinterpret the bits).
- `3.9f32 as i32` is `3` (toward zero), and `f32::NAN as i32` is `0`. Float-to-int casts saturate and are defined, unlike C.

Overflow in **safe Rust is never undefined behavior**. What happens depends on the build: with debug assertions on (plain `rustc`, or Cargo's debug profile) it panics; in an optimized build (`-O`) it wraps silently, unless you add `-C overflow-checks=on`. To say what you mean, use explicit methods: `checked_add` (returns `Option`), `wrapping_add`, `saturating_add`, `overflowing_add`.

```rust
fn add1(x: i32) -> i32 { x + 1 }

fn main() {
    let a: u8 = 250;
    println!("{:?} {:?} {} {}", a.checked_add(10), a.checked_add(5), a.wrapping_add(10), a.saturating_add(10));
    println!("{} {} {} {} {}", 300i32 as u8, -1i32 as u32, -1i32 as u8, 3.9f32 as i32, f32::NAN as i32);
    println!("sizes: {} {} {} {} {} char={}", std::mem::size_of::<u8>(), std::mem::size_of::<u32>(),
             std::mem::size_of::<u64>(), std::mem::size_of::<usize>(), std::mem::size_of::<i128>(),
             std::mem::size_of::<char>());
    let x: i32 = std::hint::black_box(i32::MAX);    // black_box: stop the compiler seeing the constant
    println!("wrapping: {}", x.wrapping_add(1));
    println!("plain add1: {}", add1(x));
}
```

Output of the first three lines: `None Some(255) 4 255`, then `44 4294967295 255 3 0`, then `sizes: 1 4 8 8 16 char=4`. Then the two builds differ:

- `rustc -C opt-level=0`: prints `wrapping: -2147483648`, then panics with `attempt to add with overflow` and exits with status 101.
- `rustc -O`: prints `wrapping: -2147483648` and `plain add1: -2147483648`, exit status 0.

Compare with the C guide: there, `x + 1` on a signed `int` at its maximum is undefined behavior and the compiler may assume it never happens. Here it is defined, as a panic in debug builds and a wrap in release builds. That is a real difference in the language contract, not a style difference.

## 2. Ownership and borrowing

The rules the compiler enforces:

- Every value has exactly one owner. Assigning or passing a value that is not `Copy` **moves** it, and the old name can't be used any more.
- You may have many shared references (`&T`) **or** one exclusive reference (`&mut T`) to a value at a time, never both.
- A reference can't outlive the value it points to.

Integer, float, `bool`, `char`, shared references and arrays of `Copy` types are `Copy`: assigning them copies. Everything else moves, and duplicating it takes an explicit `.clone()`.

The shared-xor-exclusive rule is what lets the compiler assume two references never overlap (the thing C's `restrict` promises, enforced instead of trusted). Two programs that fail to compile, with the real messages:

```rust
fn main() {
    let v = vec![1, 2, 3];
    let w = v;                               // v is moved into w
    println!("{} {}", v.len(), w.len());     // error: v used after move
}
```

```rust
error[E0382]: borrow of moved value: `v`
 --> e1.rs:4:23
   |                       ^ value borrowed here after move
```

```rust
fn main() {
    let mut v = vec![1, 2, 3];
    let first = &v[0];                       // shared borrow, used below
    v.push(4);                               // needs &mut v while `first` is alive
    println!("{}", first);
}
```

```rust
error[E0502]: cannot borrow `v` as mutable because it is also borrowed as immutable
 --> e2.rs:4:5
   |     ^^^^^^^^^ mutable borrow occurs here
```

The second one is the Rust version of a classic C bug: `push` may reallocate the vector, which would leave `first` pointing at freed memory. C compiles it and misbehaves at run time. Rust refuses it at compile time.

## 3. Slices: pointer and length, built in

`&[u8]` is a pointer plus a length (16 bytes, which I confirmed with `size_of`, against 8 for a plain `&u8`). It is the `Bytes` struct from the C guide, with the compiler tracking validity. A subslice `&data[a..b]` copies nothing.

```rust
fn find(b: &[u8], c: u8) -> usize {                     // index of first c, or b.len() if none
    b.iter().position(|&x| x == c).unwrap_or(b.len())
}

fn main() {
    let line: &[u8] = b"key=value";
    let eq = find(line, b'=');
    let (k, v) = (&line[..eq], &line[eq + 1..]);        // subslices: no copy, each carries its own length
    println!("key={} value={}", String::from_utf8_lossy(k), String::from_utf8_lossy(v));
    println!("size_of &[u8] = {}, size_of &u8 = {}", std::mem::size_of::<&[u8]>(), std::mem::size_of::<&u8>());

    let data = [1u8, 2, 3];
    let i = std::hint::black_box(5usize);
    println!("{:?}", data.get(i));                      // checked access: prints None
    println!("{}", data[i]);                            // indexing: panics
}
```

Output: `key=key value=value`, `size_of &[u8] = 16, size_of &u8 = 8`, `None`, then `thread 'main' panicked ... index out of bounds: the len is 3 but the index is 5`.

Indexing with `[]` is bounds-checked and panics on failure. Use `.get(i)` when you want an `Option` instead. `b"..."` is a byte-string literal of type `&[u8; N]`. Use `&[u8]` for binary data. `&str` must be valid UTF-8 and is for text.

## 4. Enums, match, `Option` and `Result`

A Rust `enum` is a tagged union: a tag plus the largest variant's data. `match` must cover every variant, and the compiler checks that. This is the exhaustiveness checking the C guide could only get as an optional warning.

```rust
enum Tok { Num(i64), Plus, Minus }
fn name(t: &Tok) -> &'static str {
    match t {
        Tok::Num(_) => "num",
        Tok::Plus => "plus",
    }
}
```

```rust
error[E0004]: non-exhaustive patterns: `&Tok::Minus` not covered
 --> e3.rs:3:11
   |           ^ pattern `&Tok::Minus` not covered
```

Adding a variant later breaks every `match` that forgot it, at compile time. (A catch-all `_ =>` arm silences that check, so use it sparingly.)

`Option<T>` replaces null: `Some(x)` or `None`. `Result<T, E>` replaces error codes: `Ok(x)` or `Err(e)`. The `?` operator returns early with the error.

```rust
use std::mem::size_of;

#[derive(Debug, Clone, Copy, PartialEq)]
enum Tok { Num(i64), Plus, Minus }

#[derive(Debug, PartialEq)]
enum ParseErr { Empty, BadDigit(usize), TooLong }

fn parse_u32(s: &[u8]) -> Result<u32, ParseErr> {
    if s.is_empty() { return Err(ParseErr::Empty); }
    let mut v: u32 = 0;
    for (i, &c) in s.iter().enumerate() {
        if !c.is_ascii_digit() { return Err(ParseErr::BadDigit(i)); }
        v = v.checked_mul(10).and_then(|v| v.checked_add((c - b'0') as u32)).ok_or(ParseErr::TooLong)?;
    }
    Ok(v)
}

fn sum_two(a: &[u8], b: &[u8]) -> Result<u32, ParseErr> {
    Ok(parse_u32(a)? + parse_u32(b)?)                   // ? returns early on Err
}

fn main() {
    println!("size_of Tok = {}, Option<&u8> = {}, Option<u32> = {}", size_of::<Tok>(), size_of::<Option<&u8>>(), size_of::<Option<u32>>());
    println!("{:?} {:?} {:?}", parse_u32(b"123"), parse_u32(b"12x"), parse_u32(b"99999999999"));
    println!("{:?} {:?}", sum_two(b"40", b"2"), sum_two(b"40", b""));
}
```

Output: `size_of Tok = 16, Option<&u8> = 8, Option<u32> = 8`, `Ok(123) Err(BadDigit(2)) Err(TooLong)`, `Ok(42) Err(Empty)`. Note that `Option<&u8>` takes no more space than a plain pointer: a reference is never null, so `None` uses the null value as its tag. (`Option<u32>` is 8 bytes because it needs a separate tag.) The compiler also warned that `Plus` and `Minus` were never constructed. Every `Result` you ignore also gets a warning.

## 5. Memory: arrays, `Vec`, and indices instead of references

- `[T; N]` is a fixed-size array on the stack (or inside a struct or static). Its size is part of its type.
- `Vec<T>` is a growable heap array. Pushing past capacity reallocates and copies. I watched the capacity of a `Vec<u32>` grow as I pushed 40 items: `[0, 4, 8, 16, 32, 64]`, a reallocation at each step. `Vec::with_capacity(40)` allocates once. In a hot path, size it up front (rule S2 in your plan).
- Linked data (lists, trees, graphs) with references fights the borrow checker. Use indices into flat arrays instead:

```rust
fn main() {
    const NIL: u32 = u32::MAX;
    let value: [u32; 4] = [10, 20, 30, 40];
    let next:  [u32; 4] = [2, NIL, 3, 1];      // 0 -> 2 -> 3 -> 1
    let (mut i, mut sum) = (0u32, 0u32);
    while i != NIL { sum += value[i as usize]; i = next[i as usize]; }
    println!("list sum = {}", sum);          // 100
}
```

Indices are 4 bytes instead of 8, sit in contiguous arrays, and involve no lifetimes. The cost: nothing stops you using an index after the thing it referred to is gone (the compiler can't see that). Your plan's generational handles (task P2.4) are the fix.

## 6. `unsafe`, and a typed arena

`unsafe` lets you do five things the compiler can't verify: dereference a raw pointer, call an unsafe function, access a mutable static, implement an unsafe trait, and read a union field. It does **not** turn off the borrow checker. Keep unsafe blocks tiny, and put a comment on each stating the invariant it relies on.

A bump arena for `Copy` values, with the same design as the C arena. `reset` takes `&mut self`, so the compiler refuses to let you keep any reference handed out before the reset:

```rust
use std::cell::Cell;
use std::marker::PhantomData;

struct Arena<'a> {
    base: *mut u8,
    cap: usize,
    pos: Cell<usize>,
    _buf: PhantomData<&'a mut [u8]>,
}

impl<'a> Arena<'a> {
    fn new(buf: &'a mut [u8]) -> Self {
        Arena { base: buf.as_mut_ptr(), cap: buf.len(), pos: Cell::new(0), _buf: PhantomData }
    }

    // Only for Copy types: no destructors to run when the arena is reset.
    fn alloc<T: Copy>(&self, v: T) -> Option<&mut T> {
        let (size, align) = (std::mem::size_of::<T>(), std::mem::align_of::<T>());
        let addr = self.base as usize + self.pos.get();
        let aligned = addr.checked_add(align - 1)? & !(align - 1);
        let start = aligned - self.base as usize;
        if start > self.cap || size > self.cap - start { return None; }
        self.pos.set(start + size);
        // SAFETY: [start, start+size) is inside the buffer, aligned for T, and never handed out twice,
        // because pos only moves forward until reset(&mut self), which needs no outstanding borrows.
        unsafe {
            let p = self.base.add(start) as *mut T;
            p.write(v);
            Some(&mut *p)
        }
    }

    fn reset(&mut self) { self.pos.set(0); }
}

fn main() {
    let mut storage = [0u8; 64];
    let mut arena = Arena::new(&mut storage);
    let a = arena.alloc(1u8).unwrap();
    let b = arena.alloc(0x1122334455667788u64).unwrap();
    let addr = (&*b as *const u64) as usize;
    *a += 1;
    println!("a={} b={:#x} b aligned to 8: {} pos={}", a, b, addr % 8 == 0, arena.pos.get());
    println!("oversize: {:?}", arena.alloc([0u8; 100]).is_none());
    arena.reset();
    println!("after reset pos={}", arena.pos.get());
}
```

Output: `a=2 b=0x1122334455667788 b aligned to 8: true pos=16`, `oversize: true`, `after reset pos=0`. The `pos=16` can differ on another run or machine, because a `[u8; 64]` has alignment 1 and the padding depends on where the stack puts it. The alignment check is the part that matters.

If you add `*a = 5;` after `arena.reset();`, the program no longer compiles:

```rust
error[E0502]: cannot borrow `arena` as mutable because it is also borrowed as immutable
  --> r6b.rs:45:5
   |             ----- immutable borrow occurs here
   |     ^^^^^^^^^^^^^ mutable borrow occurs here
   |     ------ immutable borrow later used here
```

Use-after-reset, which is a silent bug in C, is a compile error here. This arena has **not** been run under Miri (it wasn't available to me). Task P2.3 in your plan asks you to do exactly that, and to try broken variants against it.

## 7. Talking to the OS

Standard-library I/O is a thin layer over the same `read` and `write` system calls as in the other guides, with errors as `Result` values instead of `-1` and `errno`:

- `Read::read(&mut buf)` returns `io::Result<usize>`. `Ok(0)` is end of input. `Ok(n)` can be less than the buffer size (always check `n`).
- An interrupted call comes back as `Err(e)` with `e.kind() == io::ErrorKind::Interrupted`. Retry it.
- `Write::write_all(&bytes)` loops until everything is written. In C you write that loop yourself.
- `std::process::exit(code)` ends the process with a status.

You can also declare `read` and `write` yourself in an `extern "C"` block and call them in `unsafe`, with no standard-library I/O at all, the way your plan's Vulkan bindings declare their functions. I did not test that variant here. The capstone uses `std::io`.

## 8. Mixing with assembly

### Calling assembly from Rust

Declare the function in an `extern "C"` block. Calling it is `unsafe`, because the compiler can't check what the assembly does:

```rust
use std::arch::asm;

extern "C" {
    fn sum(p: *const i64, n: u64) -> i64;           // defined in sum.s
}

fn popcnt_asm(x: u64) -> u64 {
    let r: u64;
    // SAFETY: popcnt only reads x and writes r; it needs the POPCNT CPU feature.
    unsafe { asm!("popcnt {r}, {x}", r = out(reg) r, x = in(reg) x, options(pure, nomem, nostack)); }
    r
}

fn main() {
    let a = [1i64, 2, 3, 4];
    // SAFETY: sum reads exactly n i64 values starting at p; the array has 4.
    let s = unsafe { sum(a.as_ptr(), a.len() as u64) };
    println!("sum = {}", s);
    println!("popcnt: {} {}", popcnt_asm(0xF0F0), 0xF0F0u64.count_ones());
}
```

```sh
as sum.s -o sum.o && rustc -O prog.rs -C link-arg=sum.o -o prog && ./prog
```

It printed `sum = 10` and `popcnt: 8 8`, using the `sum.s` from the x86-64 guide. The inline `asm!` macro uses Intel syntax by default on x86 (GCC's inline asm uses AT&T order). Operands are named: `out(reg)` for an output register, `in(reg)` for an input. The `options(...)` are promises to the compiler (`pure`: no side effects, `nomem`: touches no memory, `nostack`: doesn't use the stack), and a false promise is undefined behavior.

### What the compiler does with plain Rust

The compiled assembly is the way to see what the language guarantees cost. I compiled these with `rustc -O`:

```rust
pub fn ones(x: u64) -> u32 { x.count_ones() }
pub fn sum_idx(a: &[i64], n: usize) -> i64 { let mut s = 0; for i in 0..n { s += a[i]; } s }
pub fn sum_len(a: &[i64]) -> i64 { let mut s = 0; for i in 0..a.len() { s += a[i]; } s }
pub fn sum_iter(a: &[i64], n: usize) -> i64 { a[..n].iter().sum() }
```

- `count_ones` on baseline x86-64 compiled to an inline bit-twiddling sequence (shifts, masks and adds with 64-bit constants), not a function call (GCC emitted a call to a helper, as the C guide shows). With `-C target-feature=+popcnt` it became a single `popcnt rax, rdi` and `ret`.
- `sum_idx` kept a bounds check: its assembly contains a call to `panic_bounds_check`, and the loop was not vectorized. The compiler can't know that `n <= a.len()`.
- `sum_len` has no bounds check (the loop bound is the slice's own length) and was vectorized (`paddq` appears).
- `sum_iter` has no `panic_bounds_check` call and was vectorized. The slice `a[..n]` is checked once, up front.

The rule that falls out: iterate over slices, or over a range derived from the slice's length, or slice once before the loop. Index in a loop with an unrelated bound only when you have to.

## 9. SIMD with `core::arch`

The intrinsics have the same names as in C (`_mm_cmpeq_epi8`, `_mm_sub_epi8`, ...), live in `std::arch::x86_64` (and `std::arch::aarch64` for NEON), and are `unsafe` to call in this compiler version. Use the mapping table from the C guide, chapter 8. For instructions beyond the baseline (AVX2, say), either guard with `is_x86_feature_detected!("avx2")` at run time and put the code in a function marked `#[target_feature(enable = "avx2")]`, or compile for a specific target.

The NEON names in Rust follow the C names: `vdupq_n_u8`, `vld1q_u8`, `vceqq_u8`, `vsubq_u8`, `vaddlvq_u8`. I could not compile for AArch64 here, so the capstone has no NEON branch. Writing it on your Pi is exercise 1.

Will the compiler vectorize the plain loop for you? Here it did something: compiling the scalar version with `rustc -O` produced `pcmpeqb` in the assembly. But it was still about 3.5 times slower than the hand-written byte-accumulator version in the capstone (about 142 ms against 40 ms on my test file). I did not investigate why. A guess is that it widens each compare result into 64-bit lanes, which would cost more work per 16 bytes. Check with `perf` or `llvm-mca` before believing the guess.

## 10. Capstone: count newlines on stdin

The same program as in the other guides. It uses: `u8` and `&[u8]`, a fixed stack buffer, `Result` handling around `read`, a hand-written number formatter, and SSE2 in one small `unsafe` block with the invariant written next to it.

```rust
use std::io::{self, Read, Write};

const BUFSZ: usize = 65536;

fn count_nl_scalar(p: &[u8]) -> u64 {
    let mut total = 0u64;
    for &b in p { total += (b == b'\n') as u64; }
    total
}

#[cfg(all(target_arch = "x86_64", not(force_scalar)))]
fn count_nl(p: &[u8]) -> u64 {
    use std::arch::x86_64::*;
    let (body, tail) = p.split_at(p.len() / 16 * 16);
    let mut total = 0u64;
    // SAFETY: SSE2 is part of the x86_64 baseline. Every load reads 16 bytes from
    // a chunks_exact(16) block, so it stays inside `body`; the loads are unaligned.
    unsafe {
        let nl = _mm_set1_epi8(b'\n' as i8);
        let zero = _mm_setzero_si128();
        for group in body.chunks(255 * 16) {               // at most 255 blocks per byte-counter flush
            let mut acc = _mm_setzero_si128();
            for block in group.chunks_exact(16) {
                let v = _mm_loadu_si128(block.as_ptr() as *const __m128i);
                acc = _mm_sub_epi8(acc, _mm_cmpeq_epi8(v, nl));
            }
            let s = _mm_sad_epu8(acc, zero);               // horizontal byte sums: two 64-bit lanes
            total += _mm_cvtsi128_si64(s) as u64 + _mm_cvtsi128_si64(_mm_srli_si128::<8>(s)) as u64;
        }
    }
    total + count_nl_scalar(tail)
}

#[cfg(any(not(target_arch = "x86_64"), force_scalar))]
fn count_nl(p: &[u8]) -> u64 { count_nl_scalar(p) }

fn print_u64(mut v: u64) -> io::Result<()> {
    let mut out = [0u8; 24];
    let mut i = out.len() - 1;
    out[i] = b'\n';
    loop {
        i -= 1;
        out[i] = b'0' + (v % 10) as u8;
        v /= 10;
        if v == 0 { break; }
    }
    io::stdout().lock().write_all(&out[i..])
}

fn main() {
    let mut buf = [0u8; BUFSZ];
    let mut total = 0u64;
    let mut stdin = io::stdin().lock();
    loop {
        match stdin.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => total += count_nl(&buf[..n]),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(_) => std::process::exit(1),
        }
    }
    if print_u64(total).is_err() { std::process::exit(1); }
}
```

Build and verify:

```sh
rustc -O nlcount.rs -o nlcount                           # SSE2 path on x86-64, scalar elsewhere
rustc -O --cfg force_scalar nlcount.rs -o nlcount_sc     # scalar path (newer rustc may warn about the unknown cfg)
rustc -C opt-level=0 -C debug-assertions=on nlcount.rs -o nlcount_dbg
./nlcount < somefile; wc -l < somefile
cat somefile | ./nlcount                                 # pipe: read returns short chunks
```

What I tested: the SSE2 build, the forced-scalar build and the debug build (overflow checks and bounds checks on, so any index or arithmetic mistake would panic) against `wc -l` on: empty input, no trailing newline, only newlines, 10 MB of random bytes, a 300 KB random mix, a file that straddles the 64 KiB read size, and every input length from 0 to 299 bytes. No mismatches. Not tested: Miri, the AArch64 target, and anything beyond that set of inputs.

Rough speed on the same 256 MiB file as in the C guide (best of 5, my container, includes the kernel copy in `read`, so not benchmark-grade): the SSE2 build about 40 ms and the scalar source at `-O` about 142 ms. Use your plan's benchmark harness (P0.4) for real numbers and compare with your assembly and C versions.

Where each part comes from:

| Part                                          | Chapter |
| --------------------------------------------- | ------- |
| `u8`, `u64`, `as` casts, overflow behavior    | 1       |
| `&buf[..n]`, `split_at`, `chunks_exact`       | 3       |
| `match` on the `read` result, `Interrupted`   | 4, 7    |
| fixed `[u8; N]` buffer, no `Vec`              | 5       |
| the `unsafe` block with its invariant comment | 6       |
| `core::arch` intrinsics, 255-block flush      | 9       |

Exercises, in order of difficulty:

1. On your Pi, add a `#[cfg(target_arch = "aarch64")]` branch using the NEON intrinsics from chapter 9, in the same shape as the SSE2 one. Test it against `wc -l` and against the scalar build.
2. Take the byte to count from `std::env::args_os()`, and exit with an error status if the argument is missing or isn't exactly one byte.
3. Write `find_nl(p: &[u8]) -> Option<usize>` using `_mm_movemask_epi8` and `trailing_zeros()`. Test it against `p.iter().position(...)`, including a newline at the last byte of a 16-byte block.
4. Compare the inner loop's assembly in the assembly, C and Rust versions (instruction counts), and time all three with your harness.
5. Run the unsafe parts under Miri, as your plan asks.

## 11. C and Rust side by side

| Concept                     | C                                        | Rust                                                                              |
| --------------------------- | ---------------------------------------- | --------------------------------------------------------------------------------- |
| bytes with a length         | `const u8 *p, size_t n`                  | `&[u8]` (pointer and length, tracked by the compiler)                             |
| index out of range          | undefined behavior, unchecked            | panic; `.get(i)` returns `Option`                                                 |
| signed overflow             | undefined behavior                       | defined: panic in debug, wraps in release                                         |
| unsigned overflow           | wraps, defined                           | same rule as signed: panic in debug, wraps in release; use `wrapping_*` to say so |
| absent value                | `NULL` pointer                           | `Option<&T>` (same size as a pointer)                                             |
| errors                      | return code and `errno`                  | `Result<T, E>` and `?`                                                            |
| `switch` / `match` coverage | optional warning (`-Wswitch`)            | compile error if not exhaustive                                                   |
| aliasing                    | assumed possible unless `restrict`       | `&mut` is exclusive, enforced                                                     |
| memory lifetime             | manual (arenas, mark/pop)                | ownership and borrow checker (`reset(&mut self)`)                                 |
| type conversion             | implicit conversions                     | explicit `as`, never undefined behavior                                           |
| inline assembly             | `__asm__`, AT&T operand order by default | `asm!`, Intel syntax by default on x86                                            |
| SIMD                        | `<emmintrin.h>`, `<arm_neon.h>`          | `std::arch::x86_64`, `std::arch::aarch64` (`unsafe`)                              |

## 12. Common mistakes

- Calling `unwrap()` on an I/O or parse result in code that should report an error.
- Indexing in a loop when iterating would do. I measured the difference in chapter 8: a kept bounds check and no vectorization.
- Growing a `Vec` with `push` in a hot loop instead of using `with_capacity`.
- Treating `as` as a checked conversion. It truncates silently.
- Expecting an overflow panic in an optimized build. It wraps unless you ask for checks.
- Reaching for `Rc<RefCell<...>>` to build graphs. Use indices into flat arrays.
- Cloning everywhere to make the borrow checker quiet, which hides a design problem and costs copies.
- Writing `unsafe` without a comment stating the invariant, or without running it under Miri.
- Using `&str` for binary data. Use `&[u8]`.
- Printing with `println!` inside a hot loop (it locks stdout each time).
