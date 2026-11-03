# Learning plan: x86-64 + AArch64 asm, C, Rust

Time estimates assume about 10 h/week and are guesses. Read them as relative sizes, not promises.

## Assumptions

- **PC:** x86-64 running Linux, native or WSL2. Raw-syscall asm needs a real Linux kernel, and WSL2 has one. I don't know your actual setup. `perf` is limited under WSL2, so a native install or dual boot is better for the profiling phases.
- **Pi:** Raspberry Pi 4B on a 64-bit OS, reachable over SSH. It's the ARM asm target.
- **Vulkan:** runs on the PC first (assuming a desktop GPU). The Pi port is the last step of Phase 5. If you meant Vulkan on the Pi only, the steps are the same but debugging is slower and the limits tighter.

## What runs where

| Machine    | Used for                                                                                                            |
| ---------- | ------------------------------------------------------------------------------------------------------------------- |
| **x86 PC** | All C and Rust development, x86 asm, sanitizers, Miri, first-pass benchmarks, Vulkan                                |
| **Pi 4**   | Running ARM asm, aarch64 builds of the C/Rust projects, weak-memory-model tests, all ARM timings, final Vulkan port |

**Workflow:**

- Edit on the PC. Keep a `make run-pi` target that does `rsync` + `ssh` to build and run on the Pi.
- Assemble and debug ARM asm natively on the Pi. It's the least friction.
- Build C natively on the Pi. It's fast enough, and it avoids the sysroot problem below.
- Cross-compile Rust on the PC (`rustup target add aarch64-unknown-linux-gnu`), because `rustc` is slow on a Pi. The simplest linker setup is `aarch64-linux-gnu-gcc` from the `gcc-aarch64-linux-gnu` package. Pointing rustc at clang as the linker is possible but fiddly, so get the simple setup working first.
- `qemu-aarch64` (user mode) on the PC is fine for quick correctness checks. Its timings are meaningless, so take all ARM timings on the Pi.

## Pi 4 facts (verify with `/proc/cpuinfo` and `vulkaninfo`)

- **Core:** Cortex-A72, Armv8.0-A. NEON present, SVE absent.
- **Atomics:** I believe there are no LSE atomics (they arrived in Armv8.1), so atomic read-modify-writes use `ldxr`/`stxr` loops. See the outline-atomics caveat in Phase 3.
- **CRC32:** I believe the CRC32 instructions are present and the crypto extensions are absent. Check the `Features` line before planning A3.
- **Memory model:** weak ordering, which x86's TSO hides. The 4 cores make it a useful testbed for Phase 3.
- **Vulkan:** I believe the Pi 4 supports Vulkan 1.2 via Mesa's V3DV. It's a tile-based GPU with limits well below a desktop one.
- **Thermals:** the Pi throttles. Use a heatsink or fan and the `performance` governor, and report min or median over many runs, never one run.

## Toolchain

| Role                 | Tool                                                                                                                                                                |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Primary C compiler   | `clang`, both machines, `-O2 -g -Wall -Wextra`                                                                                                                      |
| Secondary C compiler | `gcc`, for cross-checking warnings, UB behavior and codegen                                                                                                         |
| Rust                 | `rustc`/`cargo`, stable for normal work, nightly for Miri                                                                                                           |
| Assembler            | `clang -c file.s` on both ISAs (integrated assembler, handles `.intel_syntax noprefix`). Fall back to GNU `as` if a snippet uses a macro or directive LLVM rejects. |
| Static throughput    | `llvm-mca` on both ISAs (`-mcpu=cortex-a72` for the Pi)                                                                                                             |
| Disassembly          | `llvm-objdump` or `objdump`, plus `gdb`                                                                                                                             |
| Sanitizers           | ASan/UBSan under both compilers, TSan, valgrind (aarch64 support exists), Miri for Rust                                                                             |
| Fuzzing              | your own mutation fuzzer, then `clang -fsanitize=fuzzer` for comparison                                                                                             |

No external libraries in the projects (libc/POSIX for C, `std` for Rust, raw syscalls for asm). Build tools like `glslc` are fine.

## Ground rules

- **Pair order:** write the C version first, then an idiomatic Rust version, not a transliteration.
- **`NOTES.md` per pair:** LOC, bugs hit and which tool caught them, runtime, binary size, and the codegen comparison for the hot loop (next section).
- **Timebox:** if a project passes 2x its estimate, cut scope instead of pushing through.
- **Done means:** the exit criteria are met. "I feel comfortable" doesn't count.
- **Cross-arch check:** once a pair works on x86, build and run it on the Pi. It catches portability bugs:
  - Plain `char` is signed on x86 but unsigned on AArch64 Linux.
  - Code that relies on x86's strong ordering breaks.
  - Floating-point results can differ bitwise.
- **Floating point:**
  - FMA contraction differs by compiler. Clang defaults to `-ffp-contract=on` (contracts within a statement). GCC in GNU mode defaults to `fast` (contracts across statements). rustc never contracts unless you call `mul_add`.
  - Baseline x86-64 has no FMA, and baseline AArch64 does, so the same source can differ bitwise between the two machines.
  - Compare images and numeric output with a tolerance, or pin `-ffp-contract=off` in C when comparing against Rust.

## Codegen comparison protocol

Used wherever a phase says "compare codegen". The point is to get differences you can attribute.

**Variants** for each hot function:

| Label              | Command shape                               |
| ------------------ | ------------------------------------------- |
| clang-O2, clang-O3 | `clang -O2 -S` (and `-O3`)                  |
| gcc-O2, gcc-O3     | `gcc -O2 -S` (and `-O3`)                    |
| rustc-O2/O3        | `rustc --emit asm -C opt-level=2` (and `3`) |

**Make it fair:**

- Pin the target: the same `-march`/`-mcpu` for clang and gcc, and `-C target-cpu` for rustc. On the Pi use `cortex-a72`. On the PC use your actual CPU, not `native`, so the result is reproducible and recorded.
- Keep the flags equal: no LTO, no PGO, `-fno-semantic-interposition` if relevant, and `panic=abort` in Rust so unwinding paths don't clutter the output.
- Note the versions: `clang --version`, `gcc --version`, `rustc -vV` (it prints the LLVM version). The clang-vs-rustc comparison is only close to apples to apples when their LLVM versions are near each other. If they differ a lot, say so in the notes.
- Isolate the function: mark it `noinline` and compile it as its own unit, so you compare the loop and not the inliner.
- Disable what's not being tested: use `-fno-vectorize`/`-fno-unroll-loops` (and the Rust equivalents via `-C llvm-args`) when you want to compare scalar code. Remove them for the autovectorization comparison.

**What to record:**

- Instruction count in the hot loop.
- Vectorized or not, and at what width.
- Unrolling factor.
- Bounds checks present (Rust) and where they sit.
- Register spills.
- Whether `restrict` (C) and the implicit `noalias` on `&mut` (Rust) changed anything.
- `llvm-mca` throughput estimate for each variant (clang and rustc share a backend, so differences there are a language signal).

**Interpretation:**

- clang vs rustc differences are mostly language semantics: aliasing information, bounds checks, overflow behavior, UB assumptions. Same LLVM, different IR.
- clang vs gcc differences are mostly backend decisions: vectorizer, inliner, scheduling. They teach you what each backend does, not about the language.
- Then measure. The asm tells you what to suspect, and only timing on the real machine tells you what matters.

## How to read this plan

Every task has an ID, **Requirements** (what exactly to build), **Acceptance** (checks that pass or fail), and **Refs**. A task is done when all its Acceptance bullets and the global criteria G1-G9 hold.

- Numeric thresholds (speedups, tolerances, iteration counts) are my picks, not derived values. If you miss one, the written explanation of why is the deliverable. You may change a number, but write down the reason in `NOTES.md`.
- Refs: most URLs are from memory and not yet checked. P0.7 makes you check every one. Entries marked "(title only)" are things I couldn't pin to a URL.
- "Oracle" means an independent implementation you compare against (GNU tools, Python, brute force). If your test and your code share a bug, you learn nothing, so prefer oracles that share no code with the thing under test.

## Global acceptance criteria (apply to every task unless it says otherwise)

- **G1 Build:** one `make` from a clean checkout builds everything. C is warning-free with `-Wall -Wextra` under clang and gcc. Rust is warning-free under `cargo build`.
- **G2 Tests:** `make test` runs your own test program (no framework), exits non-zero on the first failure, and prints the PRNG seed so failures reproduce. Randomized tests use your own PRNG (xorshift64\* or PCG), not libc `rand`.
- **G3 Memory safety:** C is clean under ASan + UBSan, clang and gcc, on both machines. Unsafe Rust is clean under Miri. Every `unsafe` block has a one-line comment stating the invariant it relies on.
- **G4 Benchmarks:** use the P0.4 harness. At least 21 runs after at least 3 warmups, pinned to one core (`taskset`), min and median reported, results written to a file by the program itself. On the Pi, the thermal check from P0.2 passes before and after.
- **G5 NOTES.md:** has the fields from Ground rules (LOC, bugs and which tool caught them, runtime, binary size, codegen comparison), plus a **Data** paragraph (see S1) and a **Predictions** section (G9).
- **G6 Cross-arch:** after the x86 version passes, the same test suite passes on the Pi (C native, Rust cross-compiled). Every divergence is logged with its cause.
- **G7 Style:** S1-S8 below.
- **G8 Timebox:** actual hours vs estimate are logged in `NOTES.md`. At 2x the estimate, cut scope.
- **G9 Predictions first:** before any measurement or tool run that the task calls a comparison, write your prediction in `NOTES.md` and commit it. After the run, record predicted vs actual. Hindsight is cheap, and predictions are the only way to find out whether your mental model is any good.

## Code style rules (S1-S8)

Reference people: John Carmack, Casey Muratori, Jonathan Blow, Ryan Fleury (plus Mike Acton for data-oriented design).

- **S1 Data first:** before writing code, write down the data: structs and arrays, sizes, lifetimes, who reads and writes what, the common case. This goes in the **Data** paragraph of `NOTES.md`.
- **S2 Memory:** allocation is explicit. Arenas or caller-provided buffers, one place decides lifetimes. No per-object heap allocation and no growth (`realloc`, `Vec::push`) in hot paths.
- **S3 Strings and buffers:** ptr+len (C), `&[u8]` (Rust). NUL-terminated only at the OS boundary or where a task says so.
- **S4 Layout:** SoA or batched where the access pattern is batch-wise. `u32` indices instead of pointers for graph-like data.
- **S5 Control flow:** straight-line code, few abstractions. A function exists because several places call it or because it has a distinct meaning (Carmack on inlining, Muratori on semantic compression). Don't factor early. No callbacks or virtual dispatch in inner loops.
- **S6 Errors:** define the behavior for every input. Asserts for invariants, return values for real errors. No panics as control flow. `unwrap` in Rust only on a proven invariant, with a comment.
- **S7 Build:** one build command. A single translation unit ("unity build") is encouraged in C. Macros only for trivial things (`min`, `max`, `array_count`, `container_of`).
- **S8 Rust:** `std` only, `unsafe` isolated in small functions. No `Rc`/`RefCell`/`Box<dyn>` unless the task is about them. No iterator chains in hot loops unless the asm shows they compile to what the plain loop does.

**Style refs:**

- Carmack, "Inlined Code" (2007): https://number-none.com/blow/john_carmack_on_inlined_code.html
- Carmack, "In-depth: Static Code Analysis" (title only)
- Muratori, "Semantic Compression": https://caseymuratori.com/blog_0015
- Muratori, "Clean Code, Horrible Performance": https://www.computerenhance.com/p/clean-code-horrible-performance
- Muratori, Performance-Aware Programming course: https://www.computerenhance.com
- Fleury: https://www.rfleury.com
- Acton, "Data-Oriented Design and C++", CppCon 2014 (title only)
- Fabian, _Data-Oriented Design_: https://www.dataorienteddesign.com/dodbook/
- Blow, Jai primer by BSVino (secondary source for his design views): https://github.com/BSVino/JaiPrimer/blob/master/JaiPrimer.md

## Phase 0: Setup (1 week)

### P0.1 PC toolchain

**Requirements**

- Install: `clang`, `gcc`, `binutils`, `lld` (optional), `gdb`, `valgrind`, `perf`, `make`, `qemu-user`, the `aarch64-linux-gnu` cross toolchain, `rustup` with stable + nightly + Miri, `llvm-mca`, `llvm-objdump`.
- Write `tools/check_env.sh`. It prints the version of each tool and exits non-zero if any is missing.

**Acceptance**

- `check_env.sh` exits 0 and its output is saved to `env-pc.txt`.
- `perf stat true` works. If it doesn't (WSL2), record that and the decision (native Linux or dual boot for profiling phases).
- `cargo +nightly miri run` works on a hello world.

**Refs:** https://rustup.rs, https://github.com/rust-lang/miri, https://llvm.org/docs/CommandGuide/llvm-mca.html

### P0.2 Pi setup

**Requirements**

- 64-bit OS, SSH key login, `performance` governor, heatsink or fan.
- Install `clang`, `gcc`, `binutils`, `gdb`, `perf`, `valgrind`, `make`.
- The governor setting does not survive a reboot, so persist it (boot script or `cpupower`).
- Capture the `Features` line from `/proc/cpuinfo` and `vulkaninfo --summary`.

**Acceptance**

- `uname -m` prints `aarch64`. `ssh pi true` works without a password prompt.
- Every `scaling_governor` under `/sys/devices/system/cpu/cpu*/cpufreq/` reads `performance` after a reboot.
- After a 10-minute 4-core stress run, `vcgencmd get_throttled` reports `0x0`. Save this check as `tools/pi_thermal_check.sh`; later phases call it.
- `env-pi.txt` exists, and every "I believe" in the Pi 4 facts and Verify sections is marked confirmed or corrected in this plan.

**Refs:** `man cpupower`, Raspberry Pi docs on `vcgencmd`, https://docs.mesa3d.org/drivers/v3dv.html

### P0.3 PC to Pi workflow

**Requirements**

- `make run-pi`: `rsync` (excluding build outputs), then `ssh` to build and run on the Pi. Fails loudly if the Pi is unreachable.
- `make run-qemu`: static aarch64 binary run under `qemu-aarch64`.
- Rust cross-build target for `aarch64-unknown-linux-gnu` using `aarch64-linux-gnu-gcc` as the linker.

**Acceptance**

- From a fresh clone, one command builds and runs a hello world on the Pi (C native, Rust cross) and under qemu. All three print identical output.
- Unplugging the Pi's network makes `make run-pi` exit non-zero in under 10 s.

**Refs:** `man rsync`, https://doc.rust-lang.org/rustc/targets/index.html

### P0.4 Benchmark harness

**Requirements**

- C API: `bench(name, fn, ctx, runs, warmup)`. Uses `clock_gettime(CLOCK_MONOTONIC)`. Reports min, median, max. Writes results to a file.
- A hand-written compiler barrier (`__asm__ volatile("" :: "r"(x) : "memory")`) so benchmarked work isn't optimized away.
- Rust twin with the same output format, using `Instant` and `std::hint::black_box`.

**Acceptance**

- Empty-function benchmark reports the timer overhead, and it's recorded.
- Calibration: a loop of 1e9 dependent `add`s (asm barrier prevents closed-form folding) takes `1e9 / f` seconds within 15%, where `f` is the actual core clock. Pi: read `scaling_cur_freq`. x86: use `perf stat -e cycles` if available, otherwise note that turbo makes this inexact. If it's off by more than 15%, find out why before using the harness for anything.
- C and Rust harnesses give results within 5% of each other on the same calibration loop.

**Refs:** `man clock_gettime`, Brendan Gregg on `perf`: https://www.brendangregg.com/perf.html

### P0.5 gdb at instruction level

**Requirements:** a small C program with a function call and a stack array. Step through it on both machines using `layout asm`, `stepi`, `info registers`, `x/16xb`.

**Acceptance**

- A transcript or notes per machine showing: breakpoint at `main`, stepping into a call, the argument registers (`rdi`/`rsi` or `x0`/`x1`) matching the source values, the return value register after the call, and `x/16xb` on the array matching what the source wrote.
- Answer in notes, with evidence from gdb: where is the return address on x86, and where on AArch64?

**Refs:** gdb manual: https://sourceware.org/gdb/current/onlinedocs/gdb.html

### P0.6 Sanity checks

**Requirements and Acceptance (one result recorded per check)**

- **S-a ASan+UBSan on both machines:** a program with a deliberate heap overflow and a deliberate signed overflow. The reports name the expected error kinds. Pass means the tools detect both.
- **S-b TSan on the Pi:** a program with a deliberate data race. Either TSan reports it, or you record the exact failure message and the decision (for example: TSan on the PC only, Helgrind on the Pi).
- **S-c Rust aarch64:** hello world cross-compiled, copied to the Pi, run. `file` shows aarch64 ELF.
- **S-d valgrind on the Pi:** detects a deliberate leak.

**Refs:** https://clang.llvm.org/docs/AddressSanitizer.html, https://clang.llvm.org/docs/ThreadSanitizer.html, https://valgrind.org/docs/manual/mc-manual.html

### P0.7 References and lookup drill

**Requirements**

- Bookmark: Arm ARM (DDI0487), AAPCS64, Cortex-A72 Software Optimization Guide, SysV x86-64 ABI, Intel SDM, uops.info, Linux syscall tables.
- Create `refs.md` listing every URL in this plan with a "checked on <date>, loads, says what I expected" mark.

**Acceptance**

- Every URL in this plan is checked. Dead or wrong ones are fixed in the plan.
- Three lookups answered from the primary docs and written down with the section or page: (1) the encoding of `ldxr` in the Arm ARM, (2) the load-use latency of `ldr` on the A72 from the SWOG, (3) the latency and throughput of `add r64, r64` on your CPU from uops.info.

**Refs:**

- Arm ARM: https://developer.arm.com/documentation/ddi0487/latest
- AAPCS64: https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst
- Cortex-A72 SWOG: https://developer.arm.com/documentation/uan0016/latest
- SysV ABI: https://gitlab.com/x86-psABIs/x86-64-ABI
- Intel SDM: https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html
- uops.info: https://uops.info
- x86-64 syscalls: https://github.com/torvalds/linux/blob/master/arch/x86/entry/syscalls/syscall_64.tbl
- arm64 syscalls: https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/unistd.h

**Phase 0 done when:** P0.1-P0.7 Acceptance all hold, and you can single-step a C program at instruction level in gdb on both machines and read disassembly.

## Phase 1: Assembly primer (3-4 weeks)

x86 first, then port to ARM. Tooling and tutorials are best on x86, and porting the same programs makes the comparison direct. You know MCU asm already, so this should go fast.

**Phase 1 shared test infrastructure (build once in P1a.4, reuse everywhere):**

- **Guard-page buffers:** `mmap` two pages, `mprotect` one to `PROT_NONE`, place the test buffer so it ends exactly at (or starts exactly after) the guard. Any over-read or under-read is a SIGSEGV.
- **Canary trampoline (asm, per ISA):** loads sentinel values into every callee-saved register, calls the function under test, checks the sentinels afterwards, and returns a mismatch mask. x86: `rbx, rbp, r12-r15`. AArch64: `x19-x28`, `x29`, and the low 64 bits of `v8-v15`.
- **Arch-neutral test driver in C:** the same test source runs against the x86 asm, the AArch64 asm, and the C reference.

### 1a. x86-64 on the PC (about 2 weeks)

#### P1a.1 Raw syscalls

**Requirements:** `_start` that does `write(1, "hello\n", 6)` then `exit(0)`. No libc (`-nostdlib -static`). Syscall args in `rdi, rsi, rdx, r10, r8, r9`, number in `rax`, `rcx` and `r11` clobbered.

**Acceptance**

- `file` says statically linked, and `nm`/`ldd` show no libc.
- `strace` shows exactly two syscalls: `write(1, "hello\n", 6) = 6` and `exit(0)`.
- A variant exiting with code 42 gives `echo $?` = 42.
- Binary size recorded.

**Refs:** `man 2 write`, `man 2 syscall`, syscall_64.tbl (P0.7), Muratori's Computer Enhance for x86 reading skills.

#### P1a.2 itoa and print 1..N

**Requirements**

- `itoa` for the full u64 range, written in asm.
- `N` parsed from `argv[1]` in asm (this teaches the initial stack layout at `_start`: argc at `[rsp]`, argv above it). No argv gives exit code 1.
- Output buffered, with one `write` per full buffer rather than per line.

**Acceptance**

- Output is byte-identical to `seq 1 N` (`cmp`) for N in {0, 1, 9, 10, 99, 100, 12345, 1000000}.
- `itoa` unit-tested through the C harness on {0, 9, 10, 99, 2^32, 2^63, 2^64-1}.
- `strace -c` shows the syscall count is about `bytes_out / buffer_size`, not N.

**Refs:** syscall_64.tbl, Intel SDM `div` and `mul` entries, https://www.felixcloutier.com/x86/ (instruction reference mirror, convenience only).

#### P1a.3 Newline counter, scalar (A1)

**Requirements:** read stdin in 64 KiB chunks into a `.bss` buffer until `read` returns 0, count `\n`, print the count and a newline. A negative `read` result exits non-zero. Short reads from pipes are handled.

**Acceptance**

- Equals `wc -l` on: empty input, input with no trailing newline, only newlines, 100 MB of random bytes, a 1 GiB file.
- Equals `wc -l` through a pipe (`cat f | ./nl`), where reads are short.
- GB/s (min, median) on the 1 GiB file from page cache (use `< file`) recorded.

**Refs:** `man 2 read`.

#### P1a.4 Addressing modes, flags, stack frames

**Requirements:** one asm file with:

- (a) a function summing a field out of an array of structs using `[base + index*scale + disp]`, and a `lea` used for arithmetic.
- (b) a function pair showing signed vs unsigned compare (`jg` vs `ja`), and a 128-bit add using `add`/`adc`.
- (c) a recursive function with an `rbp` frame (factorial or fib).

Also build the shared test infrastructure above.

**Acceptance**

- C harness table passes on edge cases {0, 1, INT64_MIN, INT64_MAX, UINT64_MAX}.
- At least one input where `jg` and `ja` disagree, with a 5-line written explanation of when CF, OF, ZF, SF matter.
- In gdb, `rsp % 16 == 0` at the point of a `call` (before the push of the return address), and you can walk the `rbp` chain by hand.
- Canary trampoline and guard-page buffers work (shown by a deliberately broken function that each one catches).

**Refs:** SysV ABI (stack alignment, red zone), Intel SDM Vol 1 ch. 3 (flags) and Vol 2 for `adc`, `lea`.

#### P1a.5 Asm mini-libc

**Requirements:** `strlen`, `memcpy`, `memchr`, `sum_i64(const i64*, n)` in x86-64 asm, SysV ABI, callable from the C harness. `memcpy` is non-overlapping only (document that overlap is undefined, like libc). Scalar versions never read outside `[p, p+n)` (for `strlen`, never past the NUL).

**Acceptance**

- Randomized test vs the libc functions: lengths 0..256 × source alignments 0..15 × destination alignments 0..15; `memchr` with the byte at every index and absent; `sum` with wraparound values.
- Guard-page test passes for all four (buffer ending right before `PROT_NONE`, and for `memcpy` the destination too).
- Canary trampoline reports no clobbered callee-saved register.
- Speed vs glibc reported (not required to win).

**Refs:** SysV ABI, https://www.felixcloutier.com/x86/ (for `rep movsb` etc.)

#### P1a.6 SSE2 newline counter

**Requirements**

- 16-byte loads with `pcmpeqb`. Count by subtracting the compare result (`psubb`, since a match is -1) into a byte accumulator and flushing with `psadbw` at most every 255 iterations. No `popcnt` (it isn't SSE2).
- Head and tail handled without reading outside the buffer. Aligned loads never cross a page, so you may load the aligned block containing the pointer and mask out bytes outside the range. Or use scalar head and tail. Pick one and document it.
- Optional second function: `memchr_sse2` using `pmovmskb` + `bsf`.

**Acceptance**

- Matches the scalar version for every (start offset 0..15) × (length 0..64), exhaustively.
- Guard-page test: buffer both ending and starting at a `PROT_NONE` boundary, no SIGSEGV.
- Speedup vs P1a.3 scalar on a 32 KiB L1-resident buffer looped many times is at least 4x (my guess). On the 1 GiB file the limit is memory bandwidth, and you state the bandwidth ceiling you measured with a plain read loop.
- If you miss 4x, explain with `llvm-mca` or `perf stat` data.

**Refs:** Intel Intrinsics Guide (for instruction semantics): https://www.intel.com/content/www/us/en/docs/intrinsics-guide/index.html, uops.info for latencies.

#### P1a.7 Three-way codegen comparison (x86)

**Requirements:** C and Rust versions of: `sum`, `strlen`-style scan, count-matching-bytes. Follow the codegen protocol exactly (all variants, pinned target, versions recorded, `noinline`, separate unit). Include your hand-written asm versions in the table.

**Acceptance**

- Table in `NOTES.md` with every "What to record" field for every (function × variant). No empty cells.
- Predictions (G9) written before looking: which variant has the fewest instructions in the hot loop and which is fastest.
- Each difference of more than 20% in instruction count or vectorization is attributed to one named cause in one sentence.
- Timing for all variants on the same machine, with a predicted-vs-measured line.

**Refs:** https://godbolt.org (quick exploration only, record real command lines locally), https://llvm.org/docs/CommandGuide/llvm-mca.html, Agner Fog's manuals: https://www.agner.org/optimize/, uops.info.

### 1b. AArch64 on the Pi (about 2 weeks)

#### P1b.1 Raw syscalls, print 1..N, scalar newline counter

**Requirements:** port P1a.1, P1a.2 and P1a.3. `svc #0`, number in `x8`, args in `x0`-`x5`. `write` is 64, `exit` is 93. `argv[1]` parsed from the initial stack (`sp` points at argc, 16-byte aligned).

**Acceptance**

- Same acceptance as P1a.1, P1a.2 and P1a.3 on the Pi, with `strace` there (the newline counter is checked against `wc -l` on the same inputs).
- Output files from the Pi and from the PC are byte-identical (`cmp`).
- Same binary under `qemu-aarch64` on the PC gives the same output.

**Refs:** arm64 syscall header (P0.7), AAPCS64, `man 2 syscall` (per-arch register table).

#### P1b.2 Addressing, flags, frames

**Requirements:** the equivalents of P1a.4, using:

- pre-index and post-index addressing, `ldp`/`stp` including `stp x29, x30, [sp, #-16]!` prologue and `ldp x29, x30, [sp], #16` epilogue.
- `adds`/`subs`/`cmp` with `b.hi` vs `b.gt`, a 128-bit add with `adds`/`adc`, the zero register (`cmp` is `subs xzr, ...`), and `csel`/`cset`.
- a recursive function with a frame record.

**Acceptance**

- The same edge-case table as P1a.4 passes through the same C driver.
- Written explanation of why a non-leaf function must save `x30`, confirmed in gdb by showing `x30` overwritten by the inner `bl`.
- Experiment: misalign `sp` and use it for a memory access. Record what happens on the Pi (I expect SIGBUS, but verify).
- Canary trampoline for `x19-x29` and `d8-d15` low halves works.

**Refs:** Arm ARM (A64 instruction set chapters), AAPCS64, Cortex-A72 SWOG.

#### P1b.3 Asm mini-libc (AArch64)

**Requirements:** the P1a.5 functions in AArch64 asm, AAPCS64, called from the same arch-neutral C driver.

**Acceptance:** same as P1a.5, on the Pi: randomized tests, guard pages, canaries, speed vs glibc.

**Refs:** AAPCS64, Arm ARM.

#### P1b.4 NEON newline counter and `memchr`

**Requirements**

- Count: `cmeq` per 16 bytes, accumulate by subtraction in a byte accumulator, flush with a widening add (`uaddlv` or `uadalp`) at most every 255 iterations.
- `memchr_neon` (find first match): `cmeq`, then `shrn v.8b, v.8h, #4` to get a 64-bit mask with 4 bits per input byte, `fmov` to a GPR, `rbit` + `clz` for the first set position. This is the movemask replacement.
- Head and tail handled as in P1a.6.

**Acceptance**

- Both match the scalar versions for every (start offset 0..15) × (length 0..64).
- Guard-page tests pass.
- Speedup vs scalar on a 32 KiB buffer is at least 3x (my guess). If it's less, explain with `llvm-mca -mcpu=cortex-a72` and the SWOG throughput numbers.
- Notes state how many bits per byte the mask has and how you map the bit index to the byte index.

**Refs:** Kutenin, "Porting x86 vector bitmask optimizations to Arm NEON": https://community.arm.com/arm-community-blogs/b/servers-and-cloud-computing-blog/posts/porting-x86-vector-bitmask-optimizations-to-arm-neon, Arm Intrinsics: https://developer.arm.com/architectures/instruction-sets/intrinsics/, Cortex-A72 SWOG.

#### P1b.5 Three-way codegen comparison (AArch64)

**Requirements:** repeat P1a.7 on the Pi with `-mcpu=cortex-a72` / `-C target-cpu=cortex-a72`. Run `llvm-mca -mcpu=cortex-a72` from the PC on each variant's hot loop.

**Acceptance**

- Same table and predictions rules as P1a.7.
- Extra column: `llvm-mca` predicted cycles per iteration vs measured cycles per iteration (measured time × actual frequency / iterations). Report the ratio per variant and a one-line hypothesis for any ratio outside 0.7-1.4.

**Refs:** same as P1a.7, plus Cortex-A72 SWOG.

### P1c One-page comparison

**Requirements:** one page (about 60 lines of markdown). A table covering: syscall ABI, addressing modes, flags handling, encoding (variable length vs fixed 32-bit), register counts, how SIMD reductions differ. Plus one paragraph on what the three compilers did differently on each ISA.

**Acceptance**

- All six table rows present, and every claim has either a snippet from your own asm or a section reference to the Arm ARM or Intel SDM.
- The compiler paragraph cites specific rows of the P1a.7 and P1b.5 tables.

**Refs:** Arm ARM, Intel SDM, your own notes.

**Phase 1 done when:**

- All Acceptance above holds.
- The same `wc -l` works on both architectures in scalar and SIMD versions, verified against `wc -l` on large files (P1a.3, P1a.6, P1b.1, P1b.4).
- Explain every instruction: for one 10-line C loop, you have annotated disassembly from one compiler on each ISA with every instruction explained, none marked "?", cross-checked against the manuals.

## Phase 2: Small projects, C + Rust pairs (8-10 weeks)

Read the Rust Book alongside, about a chapter per project, so the Rust side doesn't start blind. Develop and test on the PC, then run the finished pair on the Pi. Build the C side with both clang and gcc and keep `-Wall -Wextra` clean under both. A warning one compiler gives and the other doesn't is worth a line in the notes.

Rust side of every pair: idiomatic Rust, not a transliteration. Same CLI, same observable behavior, same test inputs as the C side.

### P2.1 `wc`/`grep` clone

**Main lesson:** ptr+len vs NUL-terminated, `&[u8]` vs `&str`, `Result`, I/O. Compare with your asm `wc`.
**Codegen target:** inner scan loop, C vs Rust bounds checks, autovectorization.

**Requirements**

- **`wc`:** flags `-l`, `-w`, `-c` (bytes). Files and stdin. Fixed-size read buffer, never the whole file in memory. A word is a maximal run of non-whitespace bytes, whitespace being the C-locale `isspace` set (space, `\t \n \v \f \r`). Bytes, not UTF-8.
- **`grep`:** fixed-string mode (like `grep -F`) with `-n` and `-c`. Prints lines containing the pattern. Lines up to 1 MiB are supported. A longer line is a reported error (exit 2), never silent truncation.
- **Kernighan/Pike matcher:** `match(re, text)` supporting `c`, `.`, `*` (after a single char or `.`), `^`, `$`. Written twice: NUL-terminated C-string version, and ptr+len version. Rust version over `&[u8]`. CLI flag `-r` uses it. No escaping; document that.
- Exit codes like grep: 0 a match found, 1 none, 2 error.
- Counts and matches that straddle read-buffer boundaries are handled correctly.

**Acceptance**

- Byte-identical output (`cmp`) vs GNU `wc` and `grep -a` (the `-a` avoids GNU's "Binary file matches") on: empty file, no trailing newline, CRLF, embedded NULs, 1 GiB file, a file of only `\n`, stdin fed one byte at a time.
- 1000 random small inputs from a generator script, C and Rust both match the oracle.
- Regex tests restricted to the supported subset match `grep -a` with a basic regex on the same inputs.
- Long-line test: a 2 MiB line gives exit 2 and a message, no crash, no truncation.
- Pathological regex: construct an input and pattern (for example `a*a*a*a*a*b` against `aaaa...a`) where the matcher goes super-linear. Time input sizes over a range and report the growth (I expect polynomial with degree about the number of stars). One paragraph on why, with the Cox article.
- Table of MB/s on a large cached file: asm scalar, asm SIMD, C, Rust (min and median). Any gap above 20% between C and Rust is explained by the codegen comparison.
- Rust: no `unwrap` on I/O paths, data kept as `&[u8]`, errors via `Result`.

**Refs:** POSIX `wc` and `grep` specs (opengroup.org), Kernighan, "A Regular Expression Matcher" in _Beautiful Code_ (code by Rob Pike) and _The Practice of Programming_ ch. 9 (titles only), Cox, "Regular Expression Matching Can Be Simple And Fast": https://swtch.com/~rsc/regexp/regexp1.html, Rust Book chs. 4, 9, 12: https://doc.rust-lang.org/book/

### P2.2 Tokenizer + Pratt evaluator

**Main lesson:** tagged unions vs enums, exhaustive `match`, `Box` vs indices, token lifetimes. `-Wswitch` warns, Rust refuses to compile.
**Codegen target:** `match`/`switch` lowering (jump table vs compare chain).

**Requirements**

- **Language:** `i64` integer expressions. Number literals (decimal), binary `+ - * / % ^`, unary `-`, parentheses, identifiers bound by assignment (`x = expr`, right-associative, lowest precedence), variable table of fixed capacity.
- **Defined semantics, written in notes:** `^` is right-associative; `-2^2` is `-4` (unary minus binds looser than `^`); `/` and `%` truncate toward zero like C; `^` uses exponentiation by squaring and a negative exponent is an error; any overflow (including `INT64_MIN / -1` and `INT64_MIN % -1`) is an error; division or modulo by zero is an error.
- **Pipeline:** tokenizer produces an array of tokens (kind + byte span into the source, no string copies). Parser produces an AST in a flat node array indexed by `u32`, allocated from an arena (reuse P2.3 when you have it, otherwise a fixed array). Evaluator walks the AST.
- **Rust:** same pipeline with indices. Plus a second small `Box`-based AST variant used only for comparison (parse and eval benchmark).
- **Errors:** report kind and byte offset: bad character, unexpected token, unbalanced paren, overflow, division by zero, nesting too deep. Nesting limit 256, so `((((...` with 1e6 parens returns an error and does not smash the stack.

**Acceptance**

- At least 50 table-driven (expr → value or error+offset) tests including precedence, `2^3^2 = 512`, `-2^2`, associativity of `-` and `/`, assignment chains, and overflow boundaries (`9223372036854775807 + 1`, `-9223372036854775808 / -1`).
- Oracle: Python with big ints, written to match your defined semantics (Python `//` floors and C truncates, so don't use it naively). A random expression generator produces 10 000 expressions. C, Rust and the oracle agree on value or on "error".
- Robustness: 1e6 random byte strings and 1e6 mutated valid expressions never crash or hang (timeout 1 s each) under ASan/UBSan, and under Miri for a smaller seed set on the Rust side.
- Exhaustiveness: add a new node kind. Record the actual diagnostics from clang and gcc with `-Wswitch -Wswitch-enum`, and the Rust compile error. Show that adding `default:` silences the C warning (and say why that matters).
- Codegen: `eval` switch lowered by each compiler at O2/O3. Record jump table vs compare chain, and what changes with 4, 8, 16 node kinds and with sparse enum values.

**Refs:** Nystrom, "Pratt Parsers: Expression Parsing Made Easy": https://journal.stuffwithstuff.com/2011/03/19/pratt-parsers-expression-parsing-made-easy/, matklad, "Simple but Powerful Pratt Parsing": https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html, Pratt, "Top Down Operator Precedence" (1973, title only), _Crafting Interpreters_ ch. 17: https://craftinginterpreters.com, Rust Book chs. 6 and 15.

### P2.3 Bump arena

**Main lesson:** alignment, ASan poisoning (C) vs Miri (Rust). Deliberately broken variants and which tool catches each.
**Codegen target:** the `alloc` fast path, how few instructions can it be.

**Requirements**

- **C:** `Arena { u8 *base; usize cap; usize pos; }` backed by `mmap` (reserve a large range, commit not required). `arena_alloc(a, size, align)` returns NULL on exhaustion and leaves the arena unchanged. Arithmetic is overflow-safe (`size + align` can't wrap). `arena_mark`, `arena_pop_to(mark)`, `arena_reset`. Optional zero-on-alloc.
- **ASan integration:** on `pop_to`/`reset`, manually poison the released range. On alloc, unpoison exactly the returned range.
- **Rust:** typed `alloc<T: Copy>(&self) -> &mut T` using interior mutability (`Cell<usize>`) and one `unsafe`. `reset(&mut self)` takes exclusive access, so use-after-reset by safe code is a compile error. No `Drop` support, and notes say why.
- **Four broken variants**, each at most 30 lines, in both languages where expressible: misalignment, use after reset, overlapping allocations, aliased `&mut`.

**Acceptance**

- Functional tests: alignments 1..4096 (powers of two) return aligned pointers; size 0; exhaustion leaves state unchanged; `pop_to` restores `pos`; randomized test against a simple model, 1e6 ops.
- **The table.** Rows: the four broken variants. Columns: ASan, UBSan (`-fsanitize=alignment`), valgrind (C); Miri with Stacked Borrows and with `-Zmiri-tree-borrows` (Rust); each under clang and gcc where applicable. Each cell: caught / not caught, how it was reported, one line on why.
- Predictions (G9) filled in before running. I expect valgrind to miss use-after-reset on an `mmap` arena unless you add client requests (`VALGRIND_MAKE_MEM_NOACCESS`). Test that rather than trust me.
- At least one cell that surprised you is analyzed in a paragraph.
- No empty cells. Don't move on until this is done.
- Fast path: at least 3 formulations tried (for example `pos + size > cap` vs `size > cap - pos`, power-of-two alignment mask vs generic, pointer bump vs offset) with instruction counts per compiler and an explanation of the minimum.

**Refs:** Fleury, "Untangling Lifetimes: The Arena Allocator": https://www.rfleury.com/p/untangling-lifetimes-the-arena-allocator, stevenlr, "Handmade Rust 1: Allocators": https://stevenlr.com/blog/handmade-rust-1-allocators/, Wellons, "Arena allocator tips and tricks": https://nullprogram.com/blog/2023/09/27/, ASan manual poisoning: https://github.com/google/sanitizers/wiki/AddressSanitizerManualPoisoning, Valgrind client requests (Memcheck manual), Miri README (Stacked/Tree Borrows flags), Rustonomicon, "Aliasing" chapter: https://doc.rust-lang.org/nomicon/aliasing.html, Jung et al., "Stacked Borrows" (POPL 2020, title only).

### P2.4 Generational handle pool

**Main lesson:** index+generation handles, SoA, and where neither language checks at compile time.
**Codegen target:** handle validation, the cost of the generation check.

**Requirements**

- `Handle { u32 index; u32 gen; }`. Index 0 / gen 0 is the null handle. Fixed capacity.
- SoA storage: `gen[]`, per-slot free-list link (intrusive, LIFO), and at least three payload arrays (for example `pos_x[]`, `pos_y[]`, `hp[]`).
- API: `create`, `destroy`, `is_valid`, iteration over live slots (skip dead).
- Generation wrap policy decided and tested (retire the slot forever on wrap, or accept wrap and document the stale-handle ABA window).
- Rust: typed handles `Handle<T>` via `PhantomData`, so handles for different pools can't be mixed (a compile-time check that is possible), contrasted with stale-handle use, which no compiler catches.

**Acceptance**

- Invariant checker (free list acyclic and terminates; alive + free = capacity; no slot both alive and in the free list; live generations never zero) run after every op in a randomized test against a model (bool array + generation array), 1e7 ops.
- Stale handles are always rejected until the wrap policy says otherwise. Double destroy returns an error and corrupts nothing. Capacity exhaustion is handled.
- A 10-line demo in each language showing a stale `Copy` handle compiles and is caught only at runtime, plus one paragraph.
- Microbenchmarks: random-order access of 1e6 entities through (a) validated handle, (b) raw index, (c) pointer to AoS struct; working set both L1/L2-resident and larger than LLC. ns/op table.
- SoA vs AoS: update one field of all entities. Predict first. Report measured speedup, and explain any case where AoS wins or ties.
- Codegen: instruction count of the validation (`gen[idx] == h.gen`). In Rust, record the extra bounds check. In C, show you need your own bounds check, and add it.

**Refs:** Weissflog, "Handles are the better pointers": https://floooh.github.io/2018/06/17/handles-vs-pointers.html, Acton CppCon 2014 (style refs), Fabian, _Data-Oriented Design_ (style refs), `std::marker::PhantomData` docs.

### P2.5 Doubly linked list

**Main lesson:** intrusive list in C, then `Rc<RefCell>`, raw pointers under Miri, and indices in Rust.
**Codegen target:** insert/remove, what `RefCell` borrow checks cost in instructions.

**Requirements**

- **C:** circular intrusive list with a sentinel. Node embedded in the user struct, `container_of` via `offsetof`. `insert_before`, `insert_after`, `remove`, `push_front/back`, `pop_front/back`, iteration, and removal safe during iteration.
- **Rust, four versions** with the same operation set and tests: (a) indices into a `Vec` of nodes, (b) `Rc<RefCell<Node>>` with `Weak` for `prev`, (c) raw `*mut Node` with `unsafe`, (d) a deliberately wrong `Rc`-cycle version (strong `prev`).

**Acceptance**

- Shared randomized test (insert/remove at random positions, 1e6 ops) against a `Vec`-based model. After every op in small runs: forward and backward walks are mirrors, length counter matches, list is circular.
- C: no leaks under LeakSanitizer or valgrind. Rust (c): Miri-clean under Stacked and Tree Borrows. Rust (d): Miri reports the leak. (Verify that it does.)
- One deliberately broken raw-pointer version that Miri flags (for example an aliasing violation), with the message recorded.
- Codegen table: instructions in insert and remove for C, (a), (b), (c), including the `RefCell` borrow-flag check and panic path.
- Traversal benchmark with N = 1e3 and N = 1e6, nodes allocated in order and in shuffled order, for C list, (a), (b), (c). Predict the ratio shuffled/ordered first, then report it.

**Refs:** "Learn Rust With Entirely Too Many Linked Lists": https://rust-unofficial.github.io/too-many-lists/, Linux `include/linux/list.h` (read only), `std::collections::LinkedList` docs (its own warning about when to use it), Rust Book ch. 15.

**Phase 2 done when:** all five pairs satisfy their Acceptance on both machines, every `NOTES.md` exists with its codegen section, the P2.3 table is complete, and you can say which tool you'd expect to flag each class of memory bug and have the table to back it.

## Phase 3: Concurrency (4 weeks)

Read the matching chapters of _Rust Atomics and Locks_ alongside. C uses pthreads + `<stdatomic.h>` under TSan. Rust uses `std::thread`, scoped threads, `Mutex`/`Condvar` and atomics under Miri.

**Phase 3 general refs:** Bos, _Rust Atomics and Locks_ (chs. 1-3, 5, 7): https://marabos.nl/atomics/, Preshing, "Acquire and Release Semantics": https://preshing.com/20120913/acquire-and-release-semantics/, cppreference `std::memory_order`: https://en.cppreference.com/w/cpp/atomic/memory_order, TSan docs (P0.6).

### P3.1 SPSC ring buffer

**Requirements**

- Fixed capacity, power of two. Free-running `u64` head and tail, masked on use. Fixed-size elements (`u64`, then a 64-byte job struct).
- `try_push` / `try_pop`, non-blocking. Producer: load own tail relaxed, load head acquire, write slot, store tail release. Consumer is the mirror.
- `head` and `tail` on separate cache lines (64 bytes, check on both CPUs).
- Optional: cached copy of the other index (Rigtorp's trick), measured as a separate variant.
- C with `<stdatomic.h>`, Rust with `UnsafeCell<[MaybeUninit<T>; N]>` and `AtomicU64`.

**Acceptance**

- 1e8 sequence numbers pass through. The consumer verifies exact order, no loss, no duplicates.
- Capacity 1 and 2, full and empty detection, and wraparound past `u32::MAX` of the free-running index are tested.
- TSan clean (C), on both machines if TSan works on the Pi, else documented fallback from P0.6. Miri clean with a small run (1e4 items) and `-Zmiri-many-seeds`.
- Throughput (items/s, min and median) on both machines, producer and consumer on different physical cores. Also on the same core pair (SMT sibling on x86 if available) to show the cost of cache-line ping-pong.

**Refs:** Rigtorp, "Optimizing a ring buffer for throughput": https://rigtorp.se/ringbuffer/, Preshing (above), Rust Atomics and Locks ch. 5.

### P3.2 MPMC queue

**Requirements**

- Bounded queue, per-slot sequence numbers, CAS on enqueue and dequeue positions (Vyukov's design). Capacity power of two.
- Configurations 1P1C, 4P1C, 1P4C, 4P4C (oversubscribing the Pi's 4 cores is fine).
- Baseline: a mutex + condvar queue with the same interface.

**Acceptance**

- Every producer pushes `(producer_id, seq)`. Every item is consumed exactly once (bitmap or counter check). Per consumer, items from one producer arrive in increasing `seq` (FIFO).
- TSan clean, Miri clean on a small run.
- Notes explain, in your own words, why per-slot sequence numbers avoid ABA.
- Throughput table vs the mutex baseline for all four configurations on both machines. Report honestly if lock-free loses under contention.

**Refs:** Vyukov, "Bounded MPMC queue": https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue, Rust Atomics and Locks chs. 5 and 7.

### P3.3 Job system

**Requirements**

- Thread pool with N workers (default = physical cores). `parallel_for(range, grain, fn, ctx)` blocks until all chunks are done (atomic completion counter). Queue is your P3.2 MPMC with preallocated job structs.
- Idle workers sleep (condvar or futex), not spin forever.
- Clean shutdown: all threads joined.
- No allocation in the steady state.
- Rust: `parallel_for<F: Fn(Range<usize>) + Sync>(&self, range, grain, &F)` that accepts a non-`'static` borrow. The pool is long-lived, so this needs `unsafe` lifetime erasure justified by the blocking wait. Miri checks it.

**Acceptance**

- Parallel integer sum/transform equals the serial result exactly. 1e4 repetitions with random sizes including 0, 1, sizes below the thread count, and a prime, no hang (watchdog timeout), no lost chunk.
- No allocation: `nm -u job_system.o` shows no `malloc`/`free`/`realloc` (C), and `strace -f -e trace=memory` shows no `brk`/`mmap`/`munmap` during steady state.
- Idle CPU: with the pool idle for 10 s, CPU time used by the process is under 1% of wall time.
- Scaling, compute-bound workload (about 50 integer ops per element, working set in cache): speedup vs 1 thread is at least 0.7 × physical cores on both machines (Pi: at least 2.8x on 4 cores).
- Memory-bound workload (saxpy on a large array): report the plateau, and compare it to the memory bandwidth measured with a plain read loop.
- Grain sweep: time vs grain from 1 element up to `N/threads`. Report per-job overhead in ns (from the small-grain regime).
- TSan clean (C), Miri clean on a small run (Rust).

**Refs:** Gyrling, "Parallelizing the Naughty Dog Engine Using Fibers", GDC 2015 (title only, context for design alternatives), Molecular Matters, "Job System 2.0" (title only), Rust Atomics and Locks ch. 9 (building locks) for Condvar reasoning, `man 2 futex`, `man 7 pthreads`.

### P3.4 Memory-order experiment

**Requirements**

Build a small litmus harness from scratch: many independent test instances per run (arrays of 1e6 instance pairs), two threads released by a barrier, outcome counters.

- **Message passing (MP):** writer does `data = 1; flag = 1`. Reader spins until `flag == 1`, then reads `data`. Violation: reader sees `data == 0`. Variants: relaxed, release/acquire, seq_cst.
- **Store buffering (SB):** `x = 1; r1 = y` and `y = 1; r2 = x`. Violation: `r1 == 0 && r2 == 0`. Variants: relaxed, release/acquire, seq_cst. This is the positive control: x86's TSO allows it even with release/acquire, and only seq_cst (with `xchg` or `mfence`) forbids it.
- The weakened-ordering SPSC ring from P3.1 (relaxed everywhere), run for 1e8+ items.
- The same litmus tests under Miri with `-Zmiri-many-seeds`.

**Acceptance**

- Results table: variant × machine → violations / trials, trials at least 1e9 per cell for MP and SB.
- SB with relaxed and with release/acquire produces violations on x86 (positive control; if it doesn't, your harness is broken and you fix it before drawing any other conclusion).
- SB with seq_cst produces zero on both machines.
- For MP relaxed on x86: look at the generated asm to see whether the compiler reordered the stores, and say whether any observed violation comes from the compiler or the CPU.
- On the Pi: if MP relaxed shows no violations in at least 1e9 trials, say so and say what you'd change (more instances per run, different cache-line placement of `data` and `flag`). Absence of failures is not evidence.
- Miri: record which variants it flags and with how many seeds.
- Cross-check against a reference tool for at least SB and MP: `herd7` / `litmus7` (diy suite) if installable, else the published expected outcomes from the Arm and x86-TSO docs.

**Refs:** Sewell et al., "x86-TSO: A Rigorous and Usable Programmer's Model for x86 Multiprocessors" (CACM 2010, title only), Arm, "Barrier Litmus Tests and Cookbook" (title only), Arm ARM section B2 (memory model), Preshing (above), Miri README (`-Zmiri-many-seeds`, weak memory emulation), diy/herdtools7: https://github.com/herd/herdtools7, Linux `Documentation/memory-barriers.txt` (read for how real code thinks about it).

### P3.5 Atomics codegen comparison

**Requirements**

Operations: release store, acquire load, seq_cst store, seq_cst load, `fetch_add` (relaxed and acq_rel), `compare_exchange` (strong, acq_rel success, relaxed failure), `fence(seq_cst)`. Compilers: clang, gcc, rustc. Targets: x86-64; AArch64 default; AArch64 with `-mno-outline-atomics`; AArch64 with `-march=armv8.1-a` (LSE); rustc with and without `-C target-feature=+lse`. Each function `noinline`, own unit, per the protocol.

**Acceptance**

- Table with the exact instruction sequence for every (operation × compiler × target) cell. No empty cells. "Same as above" is allowed only with the diff shown.
- Predictions (G9) for the baseline x86 and AArch64 cells before generating (release store is `mov` on x86, `stlr` on A64, `lock xadd`, `ldxr`/`stxr` loops, and so on). Mismatches explained.
- For every installed compiler version, record whether outline-atomics helper calls (`__aarch64_ldadd4_acq_rel` and friends) appear by default.
- The LSE binary is not run on the Pi. Run it for correctness only under `qemu-aarch64 -cpu max` on the PC.
- Notes state what rustc emits for `aarch64-unknown-linux-gnu` by default.

**Refs:** Arm ARM (LDXR/STXR, LDADD, CAS, LDAR/STLR entries), GCC `-moutline-atomics` docs, LLVM AArch64 docs on atomics (title only), https://godbolt.org for quick exploration, cppreference `memory_order`, "C/C++11 mappings to processors" by Sewell (title only, a well-known table of exactly these sequences).

### P3.6 Explain the orderings

**Requirements:** for every atomic operation in your SPSC ring and MPMC queue, a table row: operation, ordering used, instruction on x86, instruction on A64, what bug appears if it is weakened to relaxed.

**Acceptance**

- Every atomic in both structures has a row, and each row's instructions are copied from your own disassembly.
- For at least three rows, you have a concrete failing interleaving written as a two-thread timeline.
- A friend (or you, a week later, cold) can say from a snippet of A64 asm which barrier is missing. If you can't, the explanation isn't done.

**Refs:** Arm ARM B2 (memory model), Rust Atomics and Locks ch. 3, Preshing (above).

**Phase 3 done when:**

- P3.1-P3.6 Acceptance holds.
- The pool runs a parallel-for with measurable speedup on both machines (4 cores on the Pi), per P3.3.
- TSan and Miri are clean.
- You can explain from the disassembly why a given ordering is or isn't needed on ARM.

## Phase 4: Software rasterizer (6-8 weeks)

The main project before Vulkan, and where assembly comes back.

**Phase 4 general refs:**

- Pineda, "A Parallel Algorithm for Polygon Rasterization" (SIGGRAPH 1988, title only)
- Giesen, "Triangle rasterization in practice": https://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/
- Giesen, "Optimizing the basic rasterizer": https://fgiesen.wordpress.com/2013/02/10/optimizing-the-basic-rasterizer/
- Giesen, "A trip through the Graphics Pipeline 2011": https://fgiesen.wordpress.com/2011/07/09/a-trip-through-the-graphics-pipeline-2011-index/
- Sokolov, tinyrenderer (for orientation only, it is not edge-function based): https://github.com/ssloy/tinyrenderer
- Abrash, _Graphics Programming Black Book_ (title only)

### P4.1 Scalar C rasterizer (PC)

**Requirements**

- **Targets:** RGBA8 framebuffer, `float` depth buffer, PPM (P6) output. Fixed resolution constant (start 1280x720).
- **Scene:** indexed triangle mesh in SoA (`x[] y[] z[]`, `u32` indices), procedurally generated (cube, UV sphere with 10k-50k triangles, ground plane). No model files and no loader.
- **Math:** hand-written 4x4 float matrix multiply, MVP transform, perspective divide, viewport transform. Vulkan-style conventions, documented now so P5.3 can match: NDC y down, depth 0..1, pixel centers at +0.5.
- **Clipping:** near-plane clip of triangles crossing `w <= epsilon` (Sutherland-Hodgman against one plane, producing 1 or 2 triangles). Left/right/top/bottom handled by bounding box scissor. Triangles fully outside are rejected.
- **Coverage:** vertices snapped to fixed point with at least 4 subpixel bits. Edge functions in exact integer arithmetic (no float in coverage). Top-left fill rule, so edges shared by two triangles are covered exactly once.
- **Range analysis in notes:** write down the maximum viewport size and subpixel precision, and show that the edge function and its increments fit in the integer type you use (int32 overflows easily here, so state what you did, such as int64 or block-relative origin).
- **Shading:** flat first, then Gouraud with perspective-correct interpolation (interpolate `attr/w` and `1/w`). Depth test with `z` interpolated linearly in screen space.
- **Robustness:** zero-area triangles, vertices at 1e9, NaN/inf coordinates are rejected or clamped without UB or hang.
- **Tiling:** bin triangles into 64x64 tiles with a counting pass, prefix sum, scatter pass (arena-allocated arrays, no per-tile allocation). Each tile is rasterized independently, preserving triangle submission order within the tile.

**Acceptance**

- Five committed golden scenes with PPM outputs: single triangle, two-triangle quad sharing an edge, intersecting triangles (depth test), triangle crossing the near plane, cube.
- Brute-force oracle: on a 16x16 target, 1e5 random triangles, your coverage matches an independent exact-rational (int64) point-in-triangle test with the top-left rule, bit for bit. The oracle shares no code with the rasterizer.
- Shared-edge test: draw the quad with additive counting (increment a counter per covered pixel). Every pixel inside the quad has count exactly 1, none 0 or 2.
- Binned output is bit-identical to unbinned output on all five scenes and the sphere scene.
- Degenerate and huge-coordinate triangles: ASan/UBSan clean, finishes in under 1 s.
- ms/frame (min, median) for the sphere scene recorded.

**Refs:** Phase 4 general refs, Microsoft Learn, Direct3D "Rasterization Rules" (title only, the clearest statement of top-left), Vulkan spec "Rasterization" chapter: https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html, Giesen, "The barycentric conspiracy" (title only), Low, "Perspective-Correct Interpolation" (2002 technical note, title only).

### P4.2 Rust port

**Requirements**

- Idiomatic Rust version of the same rasterizer: same scene, same fixed-point semantics, same tiling.
- Codegen comparison per the protocol on the inner coverage-test loop: clang vs gcc vs rustc, O2/O3, `restrict` on and off in C, raw pointers vs slices in Rust.

**Acceptance**

- Coverage and depth results bit-exact with the C version on all golden scenes and the sphere. Colors within 1 LSB per channel with `-ffp-contract=off` on the C side, otherwise within 2 LSB (see P4.7).
- Codegen table with all "What to record" fields. At least one bounds check removed by a source change (iterator, slice windowing, hoisted assert), with before/after asm and before/after timing, each attributed.
- Predictions (G9) before generating: bounds checks present, vectorized or not, effect of `noalias` vs `restrict`.
- Miri clean on a tiny scene if any `unsafe` is used.

**Refs:** Nethercote, _The Rust Performance Book_ (bounds checks section): https://nnethercote.github.io/perf-book/, LLVM LangRef `noalias`: https://llvm.org/docs/LangRef.html, `std::arch` docs: https://doc.rust-lang.org/core/arch/, codegen protocol above.

### P4.3 SoA layout and parallelism

**Requirements**

- Triangle setup output in SoA arrays (edge coefficients per edge in separate arrays, bounding boxes, attributes).
- One job (P3.3) per tile or per small batch of tiles. Tiles own their pixels exclusively, so no atomics in the raster stage. Draw order preserved within a tile, so output is deterministic.
- Profile with `perf stat`, `perf record`, and `cachegrind` on a small scene.

**Acceptance**

- Output is bit-identical to the serial version for 1..16 threads, 100 runs each.
- Speedup vs 1 thread on both machines, reported alongside the P3.3 scaling numbers. A gap is explained.
- Profile report: top 3 hotspots with percentages, cachegrind instruction and cache-miss counts, and one concrete change driven by the profile with before/after timing.
- AoS to SoA conversion benchmarked separately (predict first).
- Tile size sweep (16, 32, 64, 128) with the best size justified by a measurement.

**Refs:** `man perf-record`, Gregg, perf page: https://www.brendangregg.com/perf.html, Valgrind Cachegrind manual: https://valgrind.org/docs/manual/cg-manual.html, Giesen, "Optimizing the basic rasterizer", Muratori, Performance-Aware Programming course (style refs).

### P4.4 SIMD intrinsics

**Requirements**

- Kernel: evaluate the three edge functions for 4 (SSE2, NEON) or 8 (AVX2) pixels per step with incremental stepping, producing a coverage mask, then masked write/blend.
- **Range analysis first:** show the edge function fits in int32 lanes for your viewport and subpixel precision, or use a block-relative origin to make it fit. If it can't, say what you used instead.
- x86: SSE2 baseline and AVX2 (check your CPU), runtime check with `__builtin_cpu_supports` (C) / `is_x86_feature_detected!` (Rust). NEON on the Pi. Intrinsics headers (`immintrin.h`, `arm_neon.h`) come with the compiler and are allowed.
- C and Rust (`core::arch`, `#[target_feature(enable = "avx2")]`).

**Acceptance**

- Coverage bit-exact vs the scalar rasterizer on 1e6 random triangles including partial blocks at tile and screen edges. Rendered images equal on the golden scenes.
- Speedup vs scalar per machine reported (min and median).
- Cross-compiler comparison of the intrinsics inner loop: instruction count, spills, whether the compilers reordered or fused intrinsics, `llvm-mca` estimate. At least one difference between clang and gcc explained.
- Predictions (G9) before the first run.

**Refs:** Intel Intrinsics Guide, Arm Intrinsics (P1a.6 and P1b.4 refs), `core::arch` docs, Giesen, "Optimizing the basic rasterizer", Cortex-A72 SWOG (NEON throughput), uops.info.

### P4.5 A4: asm kernel

**Requirements**

- **Pick one kernel now and write it in notes:** `saxpy` (`y[i] = a * x[i] + y[i]`, `f32`) is the default. The alternative is the batched edge-function test.
- One x86-64 asm version (SSE2) and one AArch64 asm version (NEON), each in two numeric flavors:
  - **Non-fused:** `mulps`+`addps` / `fmul`+`fadd` (not `fmla`). This must match scalar C compiled with `-ffp-contract=off` bit for bit.
  - **Fused (optional):** `vfmadd` (AVX2+FMA) / `fmla`. Compared by ULP error.
- Callable from C and from Rust via `extern "C"`, with the signature documented. Handles `n` of any size including 0 and tails, and unaligned pointers. Document whether `x` and `y` may alias.
- ABI: SysV (`rdi, rsi, ...`, `xmm0-7`, callee-saved `rbx, rbp, r12-r15`, red zone 128 bytes only for leaf code) and AAPCS64 (`x0-x7`, `v0-v7`, callee-saved `x19-x28` and low 64 bits of `v8-v15`, don't use `x18`). Stack 16-byte aligned on both.
- Optional: wrap one instruction with Rust `asm!` and with GCC/Clang extended asm, and compare the constraint models.

**Acceptance**

- `n` in 0..67 × pointer misalignment 0..15, plus a guard-page test and the canary trampoline (P1a.4) on both ISAs, all pass.
- Non-fused versions are bit-identical to scalar C (`-ffp-contract=off`). Fused versions are within 1 ULP of the exactly rounded result (compute the reference in `double`, round to `float`).
- Called successfully from both a C driver and a Rust driver on each machine.
- Optional inline asm item: same snippet in three syntaxes plus a table of operand, clobber and memory syntax. Demonstrate one miscompile at `-O2` caused by a missing clobber, and show the asm that proves it.

**Refs:** SysV ABI, AAPCS64, Arm ARM (FMUL, FADD, FMLA entries), Intel SDM Vol 2 (MULPS, ADDPS, VFMADD), Rust Reference, "Inline assembly": https://doc.rust-lang.org/reference/inline-assembly.html, GCC manual, "Extended Asm": https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html

### P4.6 Benchmarking

**Requirements**

- Variants: scalar, autovectorized (-O3), intrinsics, asm. Compilers: clang, gcc, rustc. Compared within each machine only.
- Three scenes with different triangle size profiles: many tiny triangles, medium, few huge (to expose coverage-test-bound vs fill-bound behavior).
- A script that runs everything and writes a CSV, and a script that turns the CSV into the markdown table. No hand-copied numbers.

**Acceptance**

- Per G4 (21+ runs, 3+ warmups, pinned). Coefficient of variation (stddev / median) at most 5% per cell, otherwise the cell is flagged and the noise source is named.
- Pi: `pi_thermal_check.sh` passes before and after, otherwise the whole run is repeated.
- ms/frame table per variant per scene per machine. Raw CSV committed.
- Short write-up: what the codegen comparison predicted vs what timing showed (G9 predictions quoted).

**Refs:** G4, P0.4, Gregg on `perf`.

### P4.7 Float caveat and image diff tool

**Requirements**

- Hand-written image diff tool (about 50 lines): reads two PPMs, reports max abs diff per channel, count of pixels over a tolerance, and writes a diff PPM (amplified).
- Tolerance policy documented. Coverage and depth-test outcome must be bit-exact (integer math). Color within 1 LSB per channel when `-ffp-contract=off` is used and operation order is the same. Otherwise within 2 LSB. Anything beyond is explained, not waved through.

**Acceptance**

- Diff tool tested on synthetic images with known differences.
- All C (both compilers), Rust, intrinsics and asm versions agree per the policy on all golden scenes and the sphere scene, on both machines.
- Notes contain one example where FMA contraction (or its absence) changes pixel values, with the disassembly showing the difference.

**Refs:** Phase 0 Ground rules (floating point), GCC docs on `-ffp-contract`: https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html, Clang docs on `-ffp-contract`.

### P4.8 Optional: texture mapping

**Requirements:** perspective-correct UV interpolation, nearest sampling (bilinear optional), a procedural checkerboard texture (or the P6.1 PNG decoder output).

**Acceptance**

- A plane viewed at a grazing angle shows no affine "swimming". Render with affine interpolation too and show they differ at one named pixel by a number you computed by hand.
- At least 10 hand-picked pixels match texel values computed from the formula.

**Refs:** Low (P4.1 refs), Lengyel, _Mathematics for 3D Game Programming and Computer Graphics_ (title only).

**Phase 4 done when:**

- You render a shaded or textured scene with a measured frame time.
- The C (both compilers), Rust, intrinsics and asm versions agree within the P4.7 tolerance.
- You have the ms/frame table per variant per machine, plus the write-up of what the codegen comparison predicted vs what the timing showed.

## Phase 5: Vulkan (6-8 weeks)

**Phase 5 general refs:**

- Vulkan spec: https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html
- Vulkan Guide: https://docs.vulkan.org/guide/latest/
- vulkan-tutorial.com: https://vulkan-tutorial.com
- Sascha Willems' examples (read-only, don't copy): https://github.com/SaschaWillems/Vulkan
- Mesa V3DV (Pi 4 driver): https://docs.mesa3d.org/drivers/v3dv.html
- stevenlr, "Handmade Rust 4: Vulkan bindings": https://stevenlr.com/blog/handmade-rust-4-vulkan-bindings/
- Khronos, "Understanding Vulkan Synchronization": https://www.khronos.org/blog/understanding-vulkan-synchronization

### P5.1 Loading

**Requirements**

- `dlopen("libvulkan.so.1")`, `dlsym("vkGetInstanceProcAddr")`, then load global, instance and device functions into a struct of function pointers. Only the subset you use. No link-time dependency on the loader.
- C: official headers (`vulkan/vulkan.h` with `VK_NO_PROTOTYPES`). Headers are specification files, not libraries. `glslc` is a build tool and is allowed.
- Rust: hand-written bindings for the subset: `#[repr(C)]` structs, `extern "system"` function pointer types, `sType` constants.
- Every `VkResult` checked. Non-success prints the decoded name and aborts.

**Acceptance**

- Automated layout test: for every hand-declared Rust struct, `size_of` and `offset_of!` of every field equal the C `sizeof` and `offsetof` printed by a C program compiled against the official header. The test fails if any differ.
- Every `sType` constant you use is asserted equal to the header's value.
- Prints `vkEnumerateInstanceVersion` and the physical device name and type on the PC and the Pi.

**Refs:** Vulkan spec, Loader chapter, Vulkan-Loader docs (title only: "LoaderInterfaceArchitecture"), Vulkan-Headers: https://github.com/KhronosGroup/Vulkan-Headers, `vk.xml` in Vulkan-Docs as the authoritative struct list, stevenlr (above).

### P5.2 Headless compute

**Requirements**

- Instance (with the validation layer and `VK_EXT_debug_utils` messenger, see P5.4), physical device pick, a queue family with `COMPUTE`, logical device.
- Host-visible coherent buffers (memory type chosen by required property flags, not index guesses), descriptor set layout/pool/set, pipeline layout, compute pipeline from a SPIR-V file built by `glslc` at build time, command buffer, dispatch, fence wait, readback.
- Kernels: an integer kernel (for exact comparison) and `saxpy` (to compare with P4.5).
- Teardown in reverse creation order.

**Acceptance**

- Integer kernel output equals the CPU reference exactly. `saxpy` is within 1 ULP of the CPU result.
- `N` = 1, a non-multiple of the workgroup size, and 1e7 all pass (shader has a bounds guard).
- Validation message count at warning or above is 0, and the program prints that count.
- Positive control: deliberately introduce one misuse (wrong buffer usage flag, or a missing barrier). The validation layer reports it. If it doesn't, validation isn't actually on.
- Teardown produces no validation leak messages.

**Refs:** Vulkan spec chapters on memory allocation, descriptor sets, compute pipelines, command buffers; vulkan-tutorial.com (compute shader chapter); Willems' compute examples; Khronos synchronization blog (above).

### P5.3 Offscreen render

**Requirements**

- Color image `R8G8B8A8_UNORM` (UNORM on purpose, no sRGB conversion, so bytes compare with the software output) and depth image `D32_SFLOAT`.
- Classic render pass + framebuffer, not dynamic rendering. The Pi 4 driver is Vulkan 1.2, so check before depending on newer features.
- Graphics pipeline with vertex and fragment shaders (MVP via push constants or a UBO), same mesh data and same matrices as P4.1 (including the conventions documented there).
- Correct layout transitions and barriers. `vkCmdCopyImageToBuffer` to a host-visible buffer, then write PPM.
- Diff with the P4.7 tool.

**Acceptance**

- On the five golden scenes and the sphere: pixels where coverage differs from the software rasterizer are at most 0.1% of covered pixels, and every one lies within 1 pixel of a triangle edge (verified by computing the distance, not by eyeballing). Interior colors within 2 LSB. These numbers are my picks; if you change them, write why.
- Depth-test outcome matches except within 1 pixel of intersection lines.
- Shared-edge quad: no gaps (use a clear color distinct from the quad and check no clear-color pixels inside).
- Zero validation warnings.

**Refs:** Vulkan spec, "Rasterization", "Coordinate Transformations", "Render Pass"; vulkan-tutorial.com, "Drawing a triangle"; Vulkan Guide, notes on differences from OpenGL (Y-down NDC, depth range 0..1); Willems' offscreen example.

### P5.4 Validation layers from day one

**Requirements**

- Validation layer enabled by default in debug builds, via a `VK_VALIDATE` env var or build flag. Debug messenger callback prints severity, message ID, and message text.
- Synchronization validation and best-practices validation enabled through `VK_EXT_validation_features`.
- A test mode where any message at warning or above makes the program exit non-zero.
- On the Pi: check whether the layer package is available for your OS image. If not, build the layer from source (it's a tool, not a project dependency) or document that the Pi runs without it and the PC is authoritative.

**Acceptance**

- `make test-vk` fails on any warning or above and keeps the full log.
- At least 3 validation messages you triggered or ran into are documented in `NOTES.md`: message ID, what it meant, the fix.
- Pi validation status recorded.

**Refs:** Vulkan Guide, validation layers chapter: https://docs.vulkan.org/guide/latest/, `VK_EXT_validation_features` spec entry, Khronos synchronization blog (above).

### P5.5 Presentation

**Requirements**

- X11 (Xlib or XCB) loaded with `dlopen` and a hand-declared handful of functions (open display, create window, map, events, close). Keep it thin. Wayland needs protocol XML code generation and is out of scope unless you want it.
- `VK_KHR_surface` + `VK_KHR_xlib_surface` (or xcb), swapchain (FIFO), acquire/present, semaphores, 2 frames in flight with per-frame fences, resize handling (`VK_ERROR_OUT_OF_DATE_KHR` and suboptimal → recreate), clean quit on window close.
- Timestamp queries (`vkCmdWriteTimestamp`) for GPU time per frame, separately from CPU frame time. Use `timestampPeriod` from the device limits.
- Pi: `VK_KHR_display` for direct presentation from a console, or X11 on the Pi desktop. Record which one worked.

**Acceptance**

- A rotating scene runs for 10 minutes at stable vsync with zero validation messages, including through resize and minimize.
- Frames in flight demonstrated: a timeline (CPU submit time vs GPU time) showing CPU is not waiting on the same frame's fence.
- Clean shutdown: validation reports no leaks, valgrind shows no leaks attributable to your code (driver noise is noted, not hidden).
- Pi: image presented by one of the two methods and the choice and the reason recorded.

**Refs:** Vulkan spec WSI chapter, vulkan-tutorial.com, "Swapchain recreation", Khronos Vulkan Samples, "swapchain semaphore reuse" (title only), "Xlib - C Language X Interface" manual, XCB tutorial, Mesa v3dv docs (above), `VK_KHR_display` spec entry.

### P5.6 Pi port

**Requirements**

- Native C build on the Pi, cross-built Rust.
- Capture `vulkaninfo --summary`. Check and print at startup: `apiVersion`, `deviceType`, `maxImageDimension2D`, `maxComputeWorkGroupSize` and `maxComputeWorkGroupInvocations`, `maxPushConstantsSize`, `timestampPeriod`, supported formats for color and depth attachments, memory heaps. The program checks every feature and limit it needs and exits with a clear message if one is missing.
- Same scene, three resolutions (640x360, 1280x720, 1920x1080). Compare against the Pi software rasterizer from P4.

**Acceptance**

- Offscreen and presented paths run on the Pi. Image diff vs the software rasterizer within P5.3 tolerances, or each excess is explained.
- Table: ms/frame for software and Vulkan at the three resolutions, with GPU timestamp time and wall time (including readback if offscreen) reported separately. Pi thermal check passes before and after.
- One paragraph on which path wins and why, backed by a measurement (for example GPU time vs total frame time showing that upload or readback dominates), not a guess.

**Refs:** Mesa v3dv docs, Raspberry Pi docs (title only), `vulkaninfo` man page, Phase 4 numbers.

**Phase 5 done when:** a Vulkan-rendered scene matches the software rasterizer within tolerance on the PC (P5.3), runs on the Pi (P5.6), and you have a frame-time comparison between the software and Vulkan paths on both machines, with validation clean throughout.

## Phase 6: Pick from the rest (open-ended)

None of these are required for the goals above. Order by interest. Each one has Requirements, Acceptance and Refs like everything else, and G1-G9 apply.

### P6.1 PNG decoder with your own inflate, plus A3 (CRC-32/Adler-32 in asm) [C+Rust]

**Requirements**

- **Inflate (RFC 1951):** stored, fixed-Huffman and dynamic-Huffman blocks. Canonical Huffman decoding with your own tables (count/symbol arrays, as in `puff.c`, are fine). zlib wrapper (RFC 1950) with Adler-32 check. A caller-supplied output limit, so a decompression bomb fails cleanly.
- **PNG:** chunk walker (IHDR, PLTE, IDAT concatenated, IEND), CRC-32 check on every chunk, color types 0, 2, 3, 4, 6 with their valid bit depths, the five scanline filters (None, Sub, Up, Average, Paeth, with the exact Paeth tie-break order and correct bytes-per-pixel handling). Non-interlaced is required, Adam7 is a stretch.
- **A3, asm (both ISAs):**
  - CRC-32 IEEE (reflected polynomial `0xEDB88320`). AArch64: `crc32b/h/w/x` loop (check the `crc32` flag in `/proc/cpuinfo`). x86: slicing-by-8 in asm as the baseline; PCLMULQDQ folding as a stretch.
  - Adler-32 scalar in asm with deferred modulo (at most 5552 bytes between reductions). SIMD optional.
  - Don't confuse polynomials. x86 SSE4.2 `crc32` and AArch64 `crc32c*` are CRC-32C (Castagnoli). AArch64 `crc32b/h/w/x` (no `c`) are IEEE.
- **Mutation fuzzer** (about 50 lines): bit flips, byte replacement with extreme values, chunk insert/delete/duplicate, length field set to extremes.

**Acceptance**

- Inflate: byte-exact vs Python `zlib` on random and structured inputs (0 bytes to 1 MiB) compressed at levels 0-9 and with `Z_HUFFMAN_ONLY`, `Z_FIXED`, `Z_RLE`.
- Invalid streams are rejected with an error code, never a crash: truncated data, bad distance, over-subscribed and incomplete code length sets, output over the limit.
- Known vectors: CRC-32("123456789") = `0xCBF43926`, Adler-32("Wikipedia") = `0x11E60398`. Both match `zlib.crc32` / `zlib.adler32` on random lengths 0..1e5 with random start misalignment. Chaining across chunks equals one-shot.
- PNGSuite: every valid image decodes to pixels matching an oracle (Python imaging or `pngtopnm`, outside your project). Every deliberately corrupt file (`x*.png`) is rejected with an error, not a crash. Result table per file.
- Fuzz: at least 1e6 mutated inputs, 1 s timeout each, zero crashes or hangs under ASan/UBSan (C), debug build and a smaller Miri run (Rust).
- Then `clang -fsanitize=fuzzer` on the C inflate and PNG entry points for a fixed 1 hour. Record how many distinct bugs it found that your fuzzer didn't, and the coverage numbers for both.
- Asm CRC and Adler throughput in MB/s vs bytewise table baseline on both machines.

**Refs:** RFC 1951: https://www.rfc-editor.org/rfc/rfc1951, RFC 1950: https://www.rfc-editor.org/rfc/rfc1950, PNG spec: https://www.w3.org/TR/PNG/, PNGSuite: http://www.schaik.com/pngsuite/, `puff.c` in zlib `contrib/puff` (read after you've written yours), Gopal et al., "Fast CRC Computation for Generic Polynomials Using PCLMULQDQ" (Intel, 2009, title only), Brumme, "Fast CRC32": https://create.stephan-brumme.com/crc32/, Arm ARM (CRC32 instruction entries), libFuzzer: https://llvm.org/docs/LibFuzzer.html

### P6.2 HTTP/1.1 server [C+Rust]

**Requirements**

- TCP accept loop, one connection handled by one worker from your P3.3 pool (blocking I/O). Stretch: a hand-declared `extern "C"` epoll loop.
- Zero-copy request parsing: method, target, version and headers as (offset, length) spans into the receive buffer. Per-request arena (P2.3), reset after each response.
- Methods `GET` and `POST` (body with `Content-Length` only). HTTP/1.1 keep-alive by default, `Connection: close` honored, pipelined requests handled.
- Limits and statuses: header block over 8 KiB gives 431; malformed request gives 400; unknown path 404; wrong method 405; `Transfer-Encoding` on requests gives 501; HTTP version other than 1.0 or 1.1 gives 505; duplicate or conflicting `Content-Length` gives 400 (request smuggling defense). Idle connection timeout 10 s.
- Endpoints, kept simple so they can be reproduced elsewhere: `GET /health` returns `ok`; `GET /bytes?n=K` returns K bytes (K capped); `POST /echo` returns the body.
- Graceful shutdown on SIGINT.

**Acceptance**

- At least 20 raw-socket conformance tests with byte-exact expected responses, including: each valid request split across TCP writes at every byte offset (send 1 byte at a time), two pipelined requests in one write, oversized headers, duplicate `Content-Length`, bare-LF line endings (accept or reject, but document which and why), request with a body larger than declared, and a client that connects and sends nothing (closed after the timeout).
- `curl --http1.1` works for each endpoint. `wrk` (or `wrk2`) runs 60 s without errors.
- ASan/UBSan/TSan clean under load (C), Miri clean on the parser with a unit-test corpus (Rust).
- No leaks: RSS flat after warmup over 1e6 requests (plateau within 1%), open fd count back to baseline after the load stops (`ls /proc/$pid/fd | wc -l`).
- Throughput and latency numbers recorded with the exact load generator command, using constant-rate mode (`wrk2`) for latency, because closed-loop generators understate tail latency (coordinated omission).

**Refs:** RFC 9112: https://www.rfc-editor.org/rfc/rfc9112, RFC 9110: https://www.rfc-editor.org/rfc/rfc9110, Beej's Guide to Network Programming: https://beej.us/guide/bgnet/, `man 7 epoll`, `man 2 accept4`, Kegel, "The C10K problem": http://www.kegel.com/c10k.html, Tene, "How NOT to Measure Latency" (talk, title only), `wrk2`: https://github.com/giltene/wrk2

### P6.3 TLSF allocator [C+Rust]

**Requirements**

- Two-level segregated fit: first-level index by `floor(log2(size))`, second-level linear subdivision (4 or 5 bits), a bitmap per level, segregated free lists, boundary-tag block headers (size, free bit, prev-free bit, prev-physical link), immediate coalescing.
- API over a caller-provided pool (an arena or a static buffer): `alloc(size)`, `free(ptr)`. `realloc` and aligned alloc are optional. Returned pointers aligned to at least 16.
- All operations O(1) with no unbounded loops.
- Rust version over a `&mut [u8]` pool or raw pointers, with the same layout.
- Find-first-set / find-last-set via compiler builtins (`__builtin_ctz`/`clz`, `trailing_zeros`/`leading_zeros`), and separately a portable hand-written fallback for comparison.

**Acceptance**

- Invariant checker that walks physical blocks in address order and verifies: sizes sum to the pool size; no two adjacent free blocks; `prev_free` flags consistent with the previous block; every free block sits in the list for its (fl, sl); a bitmap bit is set iff its list is non-empty; free lists are consistently doubly linked; returned pointers are aligned.
- Randomized hammer: 1e7 operations, sizes log-uniform in 1..64 KiB, random frees. Checker after every op in a small pool, every 1e4 ops in a large one. Each allocation is filled with a per-allocation byte pattern and verified at free (catches overlap).
- Exhaustion returns NULL with the pool intact. After freeing everything, the pool is a single free block.
- Fragmentation: replay one fixed allocation trace and report peak overhead vs requested bytes. Speed (ns/op, min and median) vs glibc `malloc` on the same trace.
- Codegen: record what each compiler emits for ctz/clz on baseline x86-64 (`bsf`/`bsr`, possibly `rep bsf`), with `-march` for BMI/LZCNT (`tzcnt`/`lzcnt`), and on AArch64 (`rbit`+`clz`, `clz`). Instruction counts of the find-suitable-block path.

**Refs:** Masmano, Ripoll, Crespo, Real, "TLSF: a New Dynamic Memory Allocator for Real-Time Systems": http://www.gii.upv.es/tlsf/main/docs.html, Wilson et al., "Dynamic Storage Allocation: A Survey and Critical Review" (1995, title only), Conte's TLSF implementation (read only after your own works): https://github.com/mattconte/tlsf

### P6.4 Lox bytecode VM (clox from the book, then a Rust port)

clox is a single-pass Pratt compiler emitting bytecode, with no AST. The arena-AST idea belongs to jlox (part 1). If you want an AST-based variant, that's a separate exercise.

**Requirements**

- **C:** follow part III of the book (chapters 14-30), in your own style (S1-S8, so adapt the book's heap-allocated objects where it conflicts, and note each deviation).
- **Test runner:** write your own (about 50 lines). The official one needs Dart. It parses `// expect:`, `// expect runtime error:`, and compile error comments from the book's `test/` files, runs your VM, and compares stdout and exit codes.
- **Dispatch:** `switch` and computed goto (GCC/Clang extension) selectable by a compile flag. Rust: `match` loop. Check the current state of Rust's explicit tail calls (`become`) and try it on nightly if available.
- **Rust:** port through the same chapters except GC, where you use arena handles or indices and no collection (or document what you did). Skip the GC chapter in Rust if time is tight, and say so.
- **Stress mode:** C `DEBUG_STRESS_GC` equivalent (collect on every allocation) behind a flag.

**Acceptance**

- C passes every test file in the book's `test/` for the chapters implemented, except documented skips, with ASan/UBSan clean, including the GC stress mode.
- Rust passes the same test files except those depending on GC behavior, listed explicitly. Miri on a small subset.
- Benchmarks from the book's `test/benchmark/`: timings (min and median) per machine for C switch, C computed goto, Rust match, on both ISAs.
- Codegen on the dispatch loop, all 3 compilers, both ISAs: instruction count for `OP_CONSTANT`, `OP_ADD`, `OP_JUMP_IF_FALSE` handlers, and whether dispatch is one shared indirect branch or replicated per handler. Predict before generating.
- Written conclusion: how much computed goto bought on each ISA, and whether the codegen difference explains it.

**Refs:** Nystrom, _Crafting Interpreters_: https://craftinginterpreters.com, test suite repo: https://github.com/munificent/craftinginterpreters, Bendersky, "Computed goto for efficient dispatch tables": https://eli.thegreenplace.net/2012/07/12/computed-goto-for-efficient-dispatch-tables, Ertl and Gregg, "The Structure and Performance of Efficient Interpreters" (JILP 2003, title only), GCC manual, "Labels as Values", Rust tracking issue for `explicit_tail_calls` (look up the current one).

### P6.5 Game project (Handmade Hero style), one language

Only do this if you still want it after Vulkan.

**Requirements**

- Platform layer + game code as a shared object. Platform owns all memory (permanent arena, per-frame arena, scratch). Game exports one entry point, for example `game_update_and_render(Memory*, Input*, Framebuffer*)`.
- Frame arena reset each frame. Entities via generational handles (P2.4), SoA components.
- Fixed-timestep simulation (for example 60 Hz) with an accumulator, deterministic given the same input sequence.
- Software-rendered framebuffer (reuse the P4 rasterizer or a simple 2D one) blitted to an X11 window (`XPutImage` or shared memory).
- Hot reload: poll the `.so` mtime, `dlclose`/`dlopen` the new one, `dlsym` the entry point. Game state survives because it lives in platform memory.
- Input record and replay: record input per frame to a file, replay it deterministically.

**Acceptance**

- Edit a constant, rebuild, see the change within 1 s with no restart. A checksum of the whole state memory taken just before and just after reload is identical.
- Replay a recorded 60 s input file 3 times: the final state checksum is identical all 3 times.
- Frame time: p99 under 2x median over 5 minutes at the target rate.
- No allocation in the game loop (`nm -u game.so` shows no `malloc`-family symbols, and `strace` shows no `brk`/`mmap` during steady state). Arena high-water mark printed and within its budget.
- 10-minute soak: RSS flat.

**Refs:** Handmade Hero (live code editing and input recording episodes): https://handmadehero.org, Fiedler, "Fix Your Timestep!": https://gafferongames.com/post/fix_your_timestep/, Nystrom, _Game Programming Patterns_, "Game Loop": https://gameprogrammingpatterns.com/game-loop.html, `man 3 dlopen`, Fleury's writing on program structure (style refs).

### P6.6 After that: axum comparison

**Requirements**

- Reimplement the P6.2 endpoints with identical semantics in axum, Spring (Boot) and FastAPI. Libraries are allowed here, this is a comparison, not a learning-to-build task.
- Same machine, same load generator command. Load generator pinned to cores not used by the server. Release or production settings for each (`cargo build --release`, JVM with a warmup period excluded from measurement, `uvicorn` with workers = physical cores).
- Connection counts 1, 64, 1024. For each framework: saturation throughput, then latency percentiles (p50, p99, p99.9) at 50% of that framework's saturation rate using a constant-rate generator. CPU use and RSS recorded.

**Acceptance**

- A report with: hardware, OS, all versions, exact commands, raw outputs.
- At least 3 runs per cell with the spread reported. Cells with CV over 10% are flagged.
- Correctness check: all four servers return byte-identical bodies for the same requests before any load test.
- The largest difference between your server and the best framework explained by a measurement (`perf`, or a CPU/RSS breakdown), not by assumption.

**Refs:** `wrk2`: https://github.com/giltene/wrk2, Tene, "How NOT to Measure Latency", TechEmpower methodology notes (for what not to copy blindly): https://www.techempower.com/benchmarks/, axum docs: https://docs.rs/axum, Spring Boot docs, FastAPI/uvicorn docs.

## Dependencies

- Phase 1 `wc` (P1a.3, P1b.1) → P2.1 (same task, three ways)
- Phase 1 guard-page buffers and canary trampoline (P1a.4) → P1a.5, P1a.6, P1b.2-P1b.4, P4.5
- P0.4 benchmark harness → every benchmark
- P2.3 (arena) → P2.2 (optional), P4.1 tiling, P6.2 per-request arena, P6.5
- P2.4 (handle pool) → P6.5
- P3.2 (MPMC queue) → P3.3 (job system) → P4.3 rasterizer, P6.2 HTTP server
- P4.1 → P4.2 → P4.3 → P4.4 → P4.6
- P4.5 (A4) → P4.6, P5.2 (saxpy comparison)
- P4.7 (diff tool) → P5.3
- Phase 4 → Phase 5 (reference image and conventions)
- P6.1 PNG decoder → P4.8 texturing (optional)
- P6.2 → P6.6

## Timeline

| Phase                             | Weeks                        |
| --------------------------------- | ---------------------------- |
| 0 Setup                           | 1                            |
| 1 Assembly primer (x86, then ARM) | 3-4                          |
| 2 Small pairs                     | 8-10                         |
| 3 Concurrency                     | 4                            |
| 4 Rasterizer + asm kernels        | 6-8                          |
| 5 Vulkan                          | 6-8                          |
| **Total to Vulkan**               | **about 28-35 (7-8 months)** |

I added acceptance criteria that are stricter than the original "done when" lines (oracles, exhaustive tests, written predictions). They cost time, and I did not re-estimate the phases. Treat the totals above as a lower bound until you've finished Phase 1 and compared actual hours to estimate (G8).

## If you need to cut

Cut these first, since they add the least new knowledge per hour:

1. The Rust port of the linked-list variants (P2.5 Rust versions a-d).
2. The GCC leg of the three-way comparisons in Phase 2 (keep it in Phases 1, 3 and 4).
3. The Pi Vulkan port (P5.6).
4. Anything in Phase 6.

Cut within tasks, not only whole tasks, if you must: the optional items (P1a.6 `memchr_sse2`, P3.1 cached-index variant, P4.5 fused kernel and inline asm item, P4.8) go before any acceptance bullet marked as an oracle or an exhaustive test.

Keep the x86 half of Phase 1. It's the ISA you'll actually use alongside C and Rust.

## Verify before relying on it

These are from memory:

- Pi 4 feature flags (CRC32 present, crypto and LSE absent) and Vulkan 1.2 via V3DV
- Default FP-contraction and outline-atomics behavior for your installed clang and gcc versions (check with `-v` and by looking at the output)
- Whether TSan works on your Pi kernel
- Syscall numbers and register lists
- What Miri models for weak memory, and that `-Zmiri-many-seeds` and `-Zmiri-tree-borrows` are still the flag names
- Whether Clang is packaged for your Pi OS image
- The Fleury and stevenlr references
- Every other URL in this plan (P0.7 makes you do it)
- That valgrind misses use-after-reset in an `mmap` arena without client requests (P2.3 asks you to test it)
- That a misaligned `sp` access faults with SIGBUS in userspace on the Pi (P1b.2)
- That Miri reports an `Rc` cycle as a leak (P2.5)
- That `qemu-aarch64 -cpu max` executes LSE instructions (P3.5)
- Whether the Pi OS image ships the Vulkan validation layer package (P5.4), and which of `VK_KHR_display` or X11 works on it (P5.5)
- The numeric thresholds in Acceptance bullets (all picks, see "How to read this plan")

Check against the Arm ARM, the SysV ABI, uops.info, `/proc/cpuinfo`, `vulkaninfo`, and the compiler docs.
