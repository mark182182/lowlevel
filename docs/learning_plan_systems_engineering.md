# Systems Engineering Learning Plan

A dependency-ordered extension of the repository's x86-64, AArch64, C, Rust, concurrency, software-rasterizer and Vulkan work.

**Primary objective:** become a capable systems programmer who can reason from source code down through compiler output, ABI, operating-system behavior and CPU/GPU execution. The plan is intentionally broader than embedded development. It supports applications to operating-systems, platform, compiler/toolchain, networking/dataplane, GPU and performance-critical C/C++ roles.

**Design constraint:** keep Vulkan and graphics as a real destination. Do not replace the existing plan with an embedded/RTOS-only curriculum.

**Workload assumption:** roughly 8–10 focused hours per week. Time estimates are planning ranges, not promises. The complete plan is intentionally longer than a single job-search preparation cycle. Apply to suitable jobs while learning; do not wait for every phase to be complete.

---

## 0. How this plan relates to the existing repository

The repository already has substantial material. This document is the **master sequence**; it does not replace the detailed exercises in the existing documents.

| Existing document / phase                     | Keep it for                                                                                            | How this plan uses it                                                                                                  |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `docs/x86-64_assembly_guide.md`               | x86-64 registers, addressing, flags, stack, syscalls, SSE2                                             | Foundation for P1 and the compiler/ABI labs                                                                            |
| `docs/AArch64_assembly_guide.md`              | AArch64 registers, addressing, flags, stack, syscalls, NEON                                            | Foundation for P1 and cross-architecture work                                                                          |
| `docs/C_guide.md`                             | C types, pointers, memory, arenas, UB, OS calls, asm, SIMD                                             | Main language reference for P2–P6                                                                                      |
| `docs/rust_guide.md`                          | ownership, slices, enums, unsafe, OS calls, FFI, SIMD                                                  | Rust counterpart; use selectively rather than duplicating every project                                                |
| `docs/linux_kernel_c_abi_assembly_syscall.md` | Linux syscall ABI and C ABI                                                                            | Keep as an ABI/syscall reference; it is not a kernel-internals course                                                  |
| `docs/learning_plan_x86-64_aarch64_c_rust.md` | Original P0–P6 project sequence, especially assembly, C/Rust pairs, concurrency, rasterizer and Vulkan | Preserve as the detailed legacy/foundation plan. The master sequence below changes the order and adds systems subjects |
| `asm-x86/`                                    | Small native assembly programs                                                                         | Keep them as executable exercises and fix the correctness issues listed in P0                                          |

The original learning plan is deliberately preserved. Where its schedule conflicts with this master plan, use the master plan's dependency order and use the original plan's per-task acceptance criteria for its existing projects.

### Current strengths to retain

- Direct comparison of x86-64 and AArch64 instead of treating assembly as one generic subject.
- Explicit pointer-plus-length interfaces, allocation ownership and data layout in C.
- Rust ownership and `unsafe` isolation as a contrasting model, not as a replacement for understanding C.
- Disassembly and code-generation inspection as a normal part of learning.
- Guard pages, canary trampolines, independent test oracles and cross-architecture correctness checks.
- SPSC/MPMC concurrency work and the job system.
- A software rasterizer before Vulkan, so the graphics API is not mistaken for the graphics pipeline itself.
- Vulkan from manually loaded function pointers and carefully checked bindings, as an intentional low-level exercise.

### Gaps this extension addresses

1. C++ systems programming. It is used heavily in several target roles and is not currently represented in the repository.
2. Operating-system fundamentals beyond the syscall boundary, especially processes, scheduling, virtual memory and Linux userspace behavior.
3. Linux kernel architecture and practical kernel debugging.
4. ELF, object files, relocations, dynamic linking, compiler pipelines and LLVM IR.
5. Performance measurement as a disciplined engineering activity, not just timing a loop.
6. Networking below the HTTP layer: packet formats, kernel networking, eBPF/XDP and userspace packet processing.
7. GPU execution and compute architecture beyond Vulkan API mechanics.
8. Portfolio packaging: reproducible builds, tests, benchmarks, technical write-ups and clear project scope.

---

## 1. Target capability and job alignment

At the end of the common core, the intended capability is not “expert in every subsystem.” It is the ability to read, write, debug and measure non-trivial native software, explain what the compiler and operating system do, and demonstrate one or two deeper specializations.

| Engineering direction                    | Core knowledge                                                         | Specialization knowledge                                             | Relevant job families                                            |
| ---------------------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Platform / systems software              | C, C++, ABI, CPU architecture, Linux userspace, concurrency, debugging | Linux internals, boot, device model, drivers, firmware interfaces    | ARM platform software, Canonical Linux, hardware platform teams  |
| Kernel / OS                              | C, memory, CPU architecture, processes, synchronization                | kernel memory management, scheduler, VFS, interrupts, drivers        | Linux kernel, OS and virtualization teams                        |
| Compiler / toolchain                     | C/C++, assembly, ABI, object files, CPU architecture                   | IR, SSA, optimization, register allocation, instruction selection    | LLVM/GCC, compiler backend and toolchain teams                   |
| Networking / dataplane                   | C/C++, Linux, concurrency, CPU caches, profiling                       | TCP/IP, packet processing, eBPF/XDP, DPDK, RDMA, NIC queues          | Arista-like networking and high-performance infrastructure teams |
| GPU / accelerated compute                | C/C++, memory, concurrency, CPU/GPU boundary, profiling                | GPU architecture, compute shaders, CUDA or Vulkan compute, occupancy | NVIDIA-like GPU, accelerated computing and graphics teams        |
| Graphics / engine                        | C/C++, math, data layout, SIMD, concurrency                            | rasterization, GPU pipeline, Vulkan, rendering architecture          | Rendering, game engine, visualization and graphics systems teams |
| Performance-critical application systems | C++, memory, concurrency, profiling, networking/OS basics              | media pipelines, allocators, runtimes, low-latency IO                | video, simulation, infrastructure and performance teams          |

### What not to optimize for

- Do not choose a job solely because it lists Rust. Evaluate the actual subsystem and constraints. A Rust SDK can be further from the metal than a C++ rendering engine.
- Do not assume that every embedded job involves architecture or kernel work. Some are mostly application logic on an RTOS.
- Do not assume that a “systems” title guarantees low-level implementation. Ask how much time is spent implementing, debugging, profiling, integrating and maintaining code.
- Do not attempt to master all branches before applying. The common core plus one credible project is enough to start interviewing for some transition roles.

---

## 2. Rules for working through the plan

### 2.1 Required output for each substantial task

Every substantial task produces these artifacts:

1. **Source:** small, readable implementation in the repository.
2. **Tests:** deterministic tests plus boundary and failure cases.
3. **Build:** exact command or build target from a clean checkout.
4. **Investigation:** disassembly, debugger transcript, trace or profile where relevant.
5. **Notes:** a short `NOTES.md` covering design, data layout, invariants, bugs, tools, results and limitations.
6. **Conclusion:** what changed your mental model, and what you would test next.

Not every exercise needs a benchmark. Only benchmark when performance is part of the question. A benchmark that cannot be reproduced is not evidence.

### 2.2 Data-oriented design rules

Keep the repository's existing S1–S8 style rules. Apply these additional rules:

- Start with the data layout, access pattern, ownership and lifetime. Draw the data flow before designing abstractions.
- Prefer explicit capacities, spans and pointer-plus-length interfaces where they clarify ownership and bounds.
- Avoid dynamic allocation in hot paths unless allocation behavior is the subject of the experiment.
- Use indices for relocatable or densely stored graph-like data when that is simpler than pointer-rich structures.
- Keep platform and operating-system calls at explicit boundaries.
- Use abstractions when they remove duplicated policy or clarify ownership; do not create layers merely to make code look object-oriented.
- Measure before claiming that a layout, branch, abstraction or language feature is faster.
- Do not hand-write assembly for code that the compiler already emits well. Use assembly to understand, test a hypothesis or satisfy a real interface/performance requirement.

### 2.3 C, C++ and Rust policy

- **C:** primary language for ABI, OS interfaces, memory layout, kernel-adjacent work and low-level libraries.
- **C++:** primary additional language for production systems, graphics, networking, compiler and hardware-platform roles. Learn modern language features as tools; retain explicit data and ownership reasoning.
- **Rust:** learn its ownership model, safe systems interfaces, FFI and `unsafe` boundaries. Do not port every project merely to maintain symmetry. Port selected projects where the comparison teaches something.
- **Assembly:** use x86-64 and AArch64 to understand generated code, calling conventions, atomics, SIMD and architecture differences.

### 2.4 Acceptance and timeboxing

- A task is complete when its acceptance criteria hold, not when the source compiles once.
- Record actual hours. If actual effort reaches twice the estimate, cut optional scope and preserve the core learning objective.
- If a specific hardware feature is unavailable, record the limitation and use a documented alternative (QEMU, another host, a CPU feature gate or a synthetic test). Do not pretend that an unavailable feature was tested.
- A performance threshold is a hypothesis, not a universal law. If the target is missed, explain it using measurements rather than forcing the code to meet an arbitrary number.
- Keep a `refs.md` with source links and access dates. Prefer processor manuals, ABI specifications, kernel docs, compiler docs and API specifications over informal summaries.

### 2.5 Benchmark rules

Use the original P0.4 benchmark harness as a starting point, but improve it where necessary:

- Record CPU model, microcode if available, core count, OS/kernel, compiler versions, flags, frequency policy and power/thermal state.
- Distinguish warm-cache, cold-cache, compute-bound and memory-bound measurements.
- Pin threads only when that is appropriate to the experiment; document CPU affinity and SMT placement.
- Use enough independent repetitions to expose variance. Report median and spread (min/max or percentiles), not just the best run.
- Keep the benchmark harness from measuring setup, allocation or file IO unless those are the intended subject.
- Check that the compiler did not remove the work. Inspect optimized assembly and use an appropriate observable result or compiler barrier.
- Use `perf stat` counters when available: cycles, instructions, branches, branch misses, cache references/misses, context switches and task-clock. Event availability differs by CPU.
- Do not compare timings across different machines as if they were directly comparable. Compare behavior and normalized metrics, and state the hardware.
- Avoid microbenchmarks as the sole evidence for application-level improvements.

---

## 3. Roadmap overview

The plan has a common core and optional specializations. The original assembly, C/Rust, concurrency, rasterizer and Vulkan projects remain central.

| Phase | Focus                                                      | Estimated effort | Priority                                                         |
| ----- | ---------------------------------------------------------- | ---------------: | ---------------------------------------------------------------- |
| P0    | Repository audit, build discipline and environment         |        1–2 weeks | Required                                                         |
| P1    | x86-64/AArch64 assembly and ABI foundation                 |        3–4 weeks | Required; mostly existing                                        |
| P2    | C memory, data structures and selected Rust comparisons    |        5–8 weeks | Required; mostly existing                                        |
| P3    | Linux userspace and OS fundamentals                        |        4–6 weeks | Required                                                         |
| P4    | Systems-oriented C++                                       |        4–6 weeks | Required for broad C++ job access                                |
| P5    | Concurrency and performance engineering                    |        4–6 weeks | Required; reuse existing Phase 3                                 |
| P6    | ELF, linkers, compiler pipeline and LLVM fundamentals      |        4–6 weeks | Required for toolchain awareness; deeper specialization optional |
| P7    | Software rasterizer and Vulkan/GPU                         |      12–16 weeks | Primary personal specialization; existing work                   |
| P8    | Linux kernel and platform engineering                      |        5–8 weeks | Optional specialization                                          |
| P9    | Networking and dataplane engineering                       |        5–8 weeks | Optional specialization                                          |
| P10   | One focused specialization project and portfolio hardening |        4–8 weeks | Required before a focused application push                       |

The estimates are not all additive in practice. P7 can overlap with P3–P6 after the prerequisites are known. P8 and P9 are branches; do not complete both just because they are listed.

### Recommended first job-search checkpoint

Start applying when P0–P5 are substantially complete and at least one project demonstrates native debugging, memory correctness, performance measurement and a real subsystem. For a compiler role, prioritize P6. For ARM/Canonical/Arista platform roles, prioritize P3 and P8. For graphics/GPU roles, prioritize P7.

---

# P0. Repository audit and reproducible environment

**Estimate:** 1–2 weeks.  
**Goal:** make the current repository safe to extend and straightforward for another engineer to build.

## P0.1 Fix known correctness issues

Review the existing C and assembly material before adding more tasks.

### C guide review

- Make arena allocation arithmetic overflow-safe. Check capacity using subtraction-based bounds (`size <= cap - aligned_pos`) after first proving `aligned_pos <= cap`; do not rely on unchecked `pos + size`.
- Check multiplication in typed allocation helpers before computing `sizeof(T) * count`.
- Validate alignment assumptions. A generic alignment function must either support arbitrary positive alignments or explicitly require power-of-two alignment and assert/reject otherwise.
- Correct the explanation of struct member alignment: members are placed according to their implementation-defined alignment requirements, and the structure's alignment is at least the strictest member requirement, subject to ABI rules. Do not equate alignment with member size.
- Make raw `write()` examples handle partial writes and `EINTR`, or explicitly label them as minimal examples that omit robust IO handling.
- Review integer conversion, signed overflow and pointer arithmetic examples for undefined behavior.

### Assembly review

- In `asm-x86/2_arithmetic/main.asm`, make the low-byte overwrite of `ebx` explicit and verify the expected result. `mov bl, 8` changes the low byte of `ebx`; it does not preserve the original 64 value.
- In `asm-x86/4_control_flow/main.asm`, do not rely on `rsi` surviving `ut_log_start`. Under the System V AMD64 ABI, `rsi` is caller-saved. Preserve any value needed after the call in a callee-saved register or stack slot, or recompute it.
- Audit all calls for stack alignment and caller/callee-saved register correctness.

**Acceptance**

- Each issue is fixed or explicitly retained as a labeled teaching example with expected output.
- Every code snippet in the C and assembly guides is either compile-tested or marked pseudocode.
- A clean build script exists and returns non-zero on failure.
- `git diff --check` is clean.

## P0.2 Common build and test entry points

**Requirements**

Add a minimal build layout without introducing a large build framework:

- A root `Makefile` with `all`, `test`, `clean`, `format-check` (only if a formatter is adopted), `run-x86`, and optional `run-pi` targets.
- C builds with Clang and GCC using explicit standard version and warnings. Start with `-std=c17 -Wall -Wextra -Wpedantic -Wconversion` where practical; document any deliberate exceptions.
- Rust uses Cargo, stable by default. Pin dependencies to none unless an exercise explicitly studies a library.
- Assembly builds through the system assembler or compiler integrated assembler, with the ABI stated in each file.
- Keep generated binaries and build outputs out of version control.

**Acceptance**

- A fresh clone can run `make` and `make test` with documented prerequisites.
- `make clean && make && make test` succeeds.
- Each failure returns a non-zero exit status and identifies the failed target.
- Tool versions are recorded in `docs/environment.md` or a generated environment report.

## P0.3 Debugger and disassembly workflow

**Requirements**

Practice `gdb`/`lldb`, `objdump`, `readelf`, `nm`, `strace` and `perf` on a small C program compiled with `-O0 -g` and `-O2 -g`.

**Acceptance**

Record a short transcript showing:

- Breakpoint at `main`, stepping into a function and inspecting arguments/return values.
- Reading a stack frame and inspecting a local array.
- Disassembling the optimized function.
- Listing ELF sections and symbols.
- Tracing at least one open/read/write or mmap syscall.
- One comparison where optimized source-level stepping differs from the unoptimized build.

## P0.4 Hardware and platform inventory

Record actual machine data rather than assuming the Raspberry Pi model or CPU features.

**Acceptance**

- Save `uname -a`, `/proc/cpuinfo`, `lscpu`, compiler versions and available SIMD/atomic features.
- If using a Pi, record board revision, OS, kernel, cooling, governor, memory and `vcgencmd get_throttled` result where supported.
- Record Vulkan device and driver information if available.
- Clearly distinguish available hardware from emulated hardware.

**P0 complete when:** correctness issues are addressed, clean builds/tests work and the debugger/toolchain environment is recorded.

---

# P1. Assembly, machine model and ABI foundation

**Estimate:** 3–4 weeks.  
**Primary material:** existing x86-64 and AArch64 assembly guides and original learning-plan Phase 1.

Keep the original P1 acceptance criteria: raw syscalls, integer conversion, scalar and SIMD newline counters, addressing modes, flags, stack frames, mini-libc functions, guard pages, canary trampolines and cross-architecture comparison.

## P1.1 Complete the x86-64 and AArch64 exercises

- Finish the x86-64 exercises first, then port the same semantics to AArch64.
- Keep the C test harness architecture-neutral.
- Use primary ABI manuals for calling-convention claims.
- Treat syscall ABI and C function ABI as separate interfaces.

**Additional acceptance**

- Explain caller-saved and callee-saved registers for System V AMD64 and AAPCS64.
- Explain stack alignment at a call boundary, return-address handling and red-zone rules.
- Demonstrate one intentional ABI violation and show how the test harness catches it.
- Explain zero-extension behavior when writing a 32-bit x86-64 register and how partial-register writes differ.
- Identify the AArch64 link register, frame pointer and reserved/platform register caveats.

## P1.2 Machine representation and instruction semantics

Use small programs to inspect:

- Little-endian representation.
- Signed and unsigned integer interpretation.
- Sign extension and zero extension.
- Two's-complement arithmetic.
- Integer overflow in C versus instruction-level wraparound.
- Floating-point representation, rounding and FMA contraction.
- Unaligned loads and alignment constraints.
- Atomic read-modify-write instructions.

**Acceptance**

For each item, include a source example, bytes or registers observed in the debugger, and a short statement distinguishing language semantics from processor behavior.

## P1.3 Cross-architecture code generation report

Produce a concise x86-64 versus AArch64 report covering:

- Calling convention and syscall differences.
- Register files and stack rules.
- Addressing modes and instruction encoding.
- Conditional flags and branches.
- SIMD and reduction patterns.
- Atomic instruction families and memory ordering.
- Compiler output for the same C function.

**P1 complete when:** the original Phase 1 acceptance holds and you can read a small C function's disassembly on both architectures without unexplained instructions in the hot path.

---

# P2. C memory model, data structures and selected Rust comparisons

**Estimate:** 5–8 weeks.  
**Primary material:** `C_guide.md`, `rust_guide.md`, original learning-plan Phase 2.

The current C and Rust guides already cover types, pointers, pointer-plus-length, arenas, UB, OS calls, FFI, SIMD and basic unsafe Rust. Do not rewrite those sections. Complete the original projects selectively.

## P2.1 C correctness and memory discipline

Complete and harden:

- `wc`/fixed-string `grep` clone.
- Tokenizer and Pratt evaluator.
- Bump arena.
- Generational handle pool.
- Linked-list comparison only as a data-layout experiment.

**Additional acceptance**

- Every allocator checks size arithmetic, alignment and exhaustion.
- Every externally supplied buffer has explicit length and error behavior.
- Tests include empty input, maximum values, misalignment, invalid handles, repeated reset/free and failure paths.
- ASan/UBSan are clean on valid inputs; deliberate broken versions are isolated and labeled.
- The notes distinguish a language-level UB guarantee from observed machine behavior.

## P2.2 Rust comparison policy

Port projects when the comparison teaches ownership, layout, bounds checks, FFI or generated code. Do not spend equal time rewriting every linked-list variant.

Required Rust topics:

- Ownership, borrowing and slices.
- `Result` and explicit error handling.
- `repr(C)` and C ABI.
- Raw pointers and narrowly scoped `unsafe`.
- `MaybeUninit` only with explicit initialization invariants.
- Atomics and threads (expanded in P5).
- C FFI on both x86-64 and AArch64.

**Acceptance**

- Every `unsafe` block has a nearby invariant comment.
- Miri is used on the Rust exercises where it can validate the relevant behavior; document what Miri does not model.
- C and Rust interfaces agree on size, alignment, ownership and error conventions.

## P2.3 Allocator experiments

Retain the arena and handle-pool projects. Add one allocator comparison only after the arena is correct:

- Bump arena.
- Fixed-size pool/free list.
- Optional TLSF only as an advanced project.

**Acceptance**

- Replay a fixed allocation/free trace.
- Report requested bytes, committed/reserved bytes if applicable, peak overhead, fragmentation and allocation latency distribution.
- Do not claim the custom allocator is generally better based on one synthetic trace.

**P2 complete when:** one C project is robust, tested and profiled; one Rust comparison demonstrates a real semantic or code-generation difference; allocator invariants are explicit.

---

# P3. Linux userspace and operating-system fundamentals

**Estimate:** 4–6 weeks.  
**Priority:** required for platform, kernel, infrastructure and performance roles.

The existing syscall/ABI guide is a starting point, not completion of this phase. Work in Linux userspace first; only then enter kernel internals in P8.

## P3.1 Processes and execution

**Study**

- Process versus thread.
- `fork`, `execve`, `waitpid` and exit status.
- Process address spaces.
- File descriptors and descriptor inheritance.
- Signals and signal safety.
- `/proc` process information.
- Context switches and scheduling policy basics.

**Project: process inspector**

Write a C utility that accepts a PID and reports selected information from `/proc/<pid>`: command line, status, memory maps, file descriptors, thread IDs and selected status counters. Handle process exit/races and permission failures.

**Acceptance**

- No shelling out to `ps` or `lsof` for the core implementation.
- Correct behavior for nonexistent PID, permission denied, process disappearing during inspection and malformed/missing proc entries.
- Compare selected output against `ps`, `pmap` and `lsof` as independent oracles; explain where formats differ.
- Use `strace` to understand which kernel interfaces the tool uses.

## P3.2 Virtual memory

**Study**

- Virtual address spaces and page granularity.
- Page tables and page walks at a conceptual level.
- Demand paging, minor/major faults and copy-on-write.
- `mmap`, `munmap`, `mprotect`, `madvise` and guard pages.
- Anonymous versus file-backed mappings.
- RSS, virtual size and committed/resident memory distinctions.
- TLBs and huge pages at a conceptual level.

**Project: virtual-memory experiments**

Build a C program with selectable experiments: reserve a large virtual range, touch pages at controlled intervals, map a file, use copy-on-write after fork, protect a page and trigger a controlled fault in a child process.

**Acceptance**

- Each experiment records the hypothesis before the run.
- Use `/proc/<pid>/smaps` or other documented counters to observe mappings and residency.
- Explain why virtual size, RSS and allocation size are not interchangeable.
- The intentional fault is isolated in a child and does not crash the test harness.
- Results include page size and kernel version.

## P3.3 System calls, IO and readiness

**Study**

- User/kernel transition at a conceptual level.
- File descriptors as kernel-managed references.
- `read`/`write` partial completion and `EINTR`.
- Blocking versus nonblocking IO.
- `select`, `poll` and `epoll`.
- `eventfd`, `timerfd` and pipes as useful event sources.
- `io_uring` is optional and should follow a strong understanding of ordinary syscalls and `epoll`.

**Project: event-driven IO multiplexer**

Write a small C program that accepts multiple client connections, reads bounded messages and writes responses using nonblocking sockets and `epoll`. Keep the protocol intentionally simple and document its state machine.

**Acceptance**

- Handles partial reads/writes, `EAGAIN`, peer close, interrupted calls and clients that send one byte at a time.
- Uses bounded per-connection buffers and explicit limits.
- Handles at least 1,024 concurrent local connections without busy-spinning.
- Reports active connections, bytes, errors and event-loop iterations.
- Tests include slow clients and disconnects during output.

## P3.4 Filesystems and dynamic loading

**Study**

- Pathnames versus file descriptors.
- Inodes, directory entries and file metadata at the Linux abstraction level.
- Page cache and buffered IO basics.
- Shared libraries, dynamic loader and symbol resolution at a conceptual level (deep ELF work is P6).
- `dlopen`, `dlsym` and `dlclose`.

**Project: shared-library plugin boundary**

Build a host executable and a shared library exposing a narrow C ABI. Version the interface structure and validate its size/version before use.

**Acceptance**

- The host can load/unload the library and report missing symbols and incompatible ABI versions cleanly.
- No C++ types or Rust-specific types cross the C ABI.
- Demonstrate what breaks when a struct layout or function signature changes without versioning.
- Inspect the binary with `readelf` and `nm`.

## P3.5 Operating-system concepts report

Write a short report answering:

- What changes during a process context switch?
- What does a page fault mean, and what are common causes?
- Why is `malloc` not equivalent to reserving and touching physical memory?
- Why can a thread be blocked even when its process has runnable work elsewhere?
- What happens to open file descriptors across `fork` and `exec`?
- What does `epoll` report, and why must nonblocking code handle partial IO?

**P3 complete when:** the process inspector, VM experiments and event-driven server pass their tests, and you can explain the above without confusing userspace abstractions with kernel implementation details.

---

# P4. C++ for systems and performance-critical software

**Estimate:** 4–6 weeks.  
**Priority:** required if applying broadly to C++ platform, networking, compiler, graphics or performance roles.

The goal is not to become a language-lawyer. Learn the parts of C++ that affect object lifetime, layout, binary interfaces, generic code and performance.

## P4.1 Object model and lifetime

**Study**

- Storage duration and object lifetime.
- Constructors/destructors and RAII.
- Copy and move operations.
- Value categories at a practical level.
- Placement `new` and explicit lifetime management (advanced; use only when needed).
- Triviality, standard-layout and trivially-copyable types.
- Padding, alignment, `sizeof`, `alignof` and `offsetof` restrictions.
- Strict aliasing and object representation.

**Project: lifetime and layout lab**

Create a set of small programs showing object construction/destruction, moves, container invalidation, placement construction and structure layout. Compare the generated code at `-O0` and `-O2`.

**Acceptance**

- Explain exactly when each object's lifetime begins and ends.
- Show one invalid-lifetime example under sanitizers where detectable, and explain when a tool cannot prove correctness.
- Show the layout and alignment of a few standard-layout structs on x86-64 and AArch64.
- No reliance on undefined behavior as a benchmark trick.

## P4.2 Systems-oriented generic programming

**Study**

- Templates and function templates.
- `constexpr` and compile-time computation.
- Type traits and concepts at a practical level.
- `std::span` and non-owning views.
- `std::array`, `std::vector`, `std::string` and their invalidation rules.
- Custom allocators as a later topic, not a first exercise.
- `std::variant` and explicit tagged unions.

**Project: typed views and containers**

Implement a small fixed-capacity vector or span-based API and compare it with standard containers. Measure only when there is a real question (bounds checks, allocation, cache layout, iteration).

**Acceptance**

- Interfaces make ownership and capacity clear.
- No allocation occurs in the hot loop unless intentionally measured.
- Record codegen for an indexed loop over a raw pointer, `std::span` and `std::vector` after optimization.
- Explain when the abstractions compile away and when they do not.

## P4.3 C++ concurrency and atomics

**Study**

- `std::thread`, mutex, condition variable and `std::jthread` where supported.
- Atomic types and memory orders.
- False sharing and cache-line contention.
- RAII for locks and thread lifetime.
- C++ memory model basics; do not infer behavior from x86 alone.

**Acceptance**

- Implement the same small SPSC queue interface in C and C++.
- Compare the C and C++ source and generated code.
- Run TSan where supported.
- Explain release/acquire publication with an explicit two-thread timeline.

## P4.4 C ABI and mixed-language boundary

**Study**

- `extern "C"`.
- Name mangling.
- C-compatible data types and layout.
- Ownership transfer and error codes across the boundary.
- Exceptions must not unwind through a C ABI boundary.
- Opaque handles versus exposing internal structs.

**Project: C host + C++ subsystem**

Build a C executable that calls a C++ library through a small exported C API. Use an opaque handle and explicit create/destroy functions.

**Acceptance**

- The public header compiles as C and C++.
- No exception crosses the boundary.
- Ownership and thread-safety rules are documented.
- `nm -C`, `readelf` and debugger output are used to inspect symbols and calls.

## P4.5 Build systems and compilation hygiene

Use the existing Makefile for simple projects. Add CMake only when a project genuinely needs multiple targets, generated sources or cross-platform configuration.

**Acceptance**

- A small C++ project builds with Clang and GCC.
- Debug and optimized configurations work.
- Compiler warnings are treated deliberately; explain any disabled warning.
- A clean build succeeds without stale generated files.

**P4 complete when:** you can write and debug a modest C++ subsystem, explain its lifetime/ownership model and export a stable C ABI.

---

# P5. Concurrency, synchronization and performance engineering

**Estimate:** 4–6 weeks.  
**Primary material:** original learning-plan Phase 3 plus the benchmark protocol in this document.

Keep the original SPSC ring, MPMC queue, job system, memory-order experiments and atomics codegen comparison. Do not weaken the correctness criteria merely to reach the performance stage.

## P5.1 Complete the original concurrency projects

- SPSC bounded ring with explicit memory ordering.
- MPMC queue with a documented progress guarantee and limitations.
- Thread pool/job system with bounded work and clean shutdown.
- Litmus experiments for message passing and store buffering.
- x86-64 versus AArch64 atomics codegen report.

**Additional acceptance**

- State whether each data structure is wait-free, lock-free or blocking. Do not use “lock-free” as a synonym for “uses atomics.”
- Distinguish linearizability, FIFO ordering and per-producer ordering.
- Include wraparound and shutdown tests.
- Use a timeout/watchdog so deadlocks fail deterministically.
- Record a contention profile, not only throughput.

## P5.2 Performance analysis lab

**Study**

- CPU cycles, instructions, IPC and frequency.
- Branch prediction and branch misses.
- Cache hierarchy, cache misses and memory bandwidth.
- False sharing and cache-line ownership.
- NUMA basics.
- System-call overhead and context switches.
- CPU affinity and SMT.
- Flame graphs and sampling profilers.
- Amdahl's law and parallel scaling.

**Project: performance dossier**

Take one existing project (rasterizer, parser, allocator or job system). Establish a baseline, profile it, select one bottleneck, change one thing and measure again.

**Acceptance**

- Include the exact command lines, flags, machine/OS data and raw output.
- Use at least one profiler/counter source and one independent timing method.
- Show before/after behavior and a reason the change should affect the measured bottleneck.
- State the confidence limits and any confounding factors.
- Include at least one change that did not help, and explain what the measurement taught you.

## P5.3 Memory and CPU performance experiments

Implement and measure:

- AoS versus SoA traversal.
- Linear versus pointer-chasing access.
- Working sets that fit in L1, L2, LLC and exceed LLC.
- Branch-heavy versus branchless variants where semantically equivalent.
- Scalar versus vectorized operations.
- Thread-local versus contended counters.
- False-sharing versus padded counters.

**Acceptance**

- The same data and result are used for each variant.
- Verify compiler output and prevent dead-code elimination.
- Explain when cache effects, memory bandwidth or instruction throughput dominate.
- Never claim a universal win from one CPU.

**P5 complete when:** the original concurrency acceptance holds and one existing program has a credible profiler-guided performance report.

---

# P6. Executables, linkers, compilers and toolchains

**Estimate:** 4–6 weeks.  
**Priority:** common core for platform work; deeper compiler work is a specialization.

This phase turns “I can inspect assembly” into “I understand how source becomes an executable and how a compiler targets a machine.”

## P6.1 Compilation pipeline

**Study**

- Preprocessing, parsing, semantic analysis, optimization, code generation and assembly.
- Translation units and separate compilation.
- Debug and optimized builds.
- Compiler driver versus compiler frontend/backend.
- Target triple, CPU features and ABI.

**Project: compilation explorer**

For a small C and C++ program, capture preprocessed source, compiler IR where available, assembly, object file and final executable. Compare Clang and GCC.

**Acceptance**

- Build each stage with explicit commands.
- Explain which stage introduces a selected transformation.
- Compare one optimization at `-O0`, `-O2` and `-O3`.
- Record compiler version and target options.

## P6.2 ELF, relocations and linking

**Study**

- ELF headers and program headers.
- Sections versus segments.
- Symbols and symbol tables.
- Relocations.
- Static and dynamic linking.
- PLT/GOT at a conceptual and inspection level.
- Position-independent code and PIE.
- Shared libraries, SONAME and symbol visibility.
- Dynamic loader and library search paths.
- Debug symbols and separate debug files.

**Project: ELF inspection suite**

Write scripts and small C utilities that inspect your own executables and shared libraries using `readelf`, `objdump`, `nm`, `ldd` (understood as a convenience tool, not a safe parser for untrusted binaries) and `file`.

**Acceptance**

- Explain the difference between a section and a loadable segment.
- Identify entry point, dynamic interpreter, needed shared libraries and exported symbols.
- Show a relocation before and after linking.
- Demonstrate a missing-symbol failure and an ABI mismatch in a controlled test.
- Explain static versus dynamic linking trade-offs.

## P6.3 LLVM IR and compiler optimization

**Study**

- LLVM IR syntax and type model.
- SSA form, basic blocks and control-flow graphs.
- `phi` nodes.
- Dominance at a practical level.
- Alias information and `noalias`.
- Integer overflow flags and poison/undefined behavior concepts.
- Loop transformations and vectorization.
- Target-independent versus target-specific optimization.

**Project: IR exploration**

Compile selected C functions to LLVM IR and compare them with generated assembly. Choose examples involving aliasing, bounds, signed overflow, loop vectorization and function inlining.

**Acceptance**

- Annotate the relevant IR for at least four examples.
- Explain one optimization that occurs in IR and one that is target-specific.
- Connect a source-level semantic rule to a concrete optimization.
- Do not infer LLVM IR behavior from a single compiler version; record the version.

## P6.4 Extend the existing Pratt parser into a compiler

The original P2.2 Pratt evaluator is a suitable base.

**Requirements**

- Preserve token spans and explicit error offsets.
- Add a typed or clearly constrained IR (constants, unary ops, binary ops, variables and basic blocks only if needed).
- Add constant folding with overflow semantics matching the language definition.
- Add a simple backend: either emit a small stack-based bytecode first, or emit LLVM IR through textual IR generation.
- Keep the first language intentionally small. Do not add classes, closures or a garbage collector.

**Acceptance**

- Existing parser/evaluator tests remain green.
- Compiler output agrees with the interpreter for at least 10,000 generated expressions.
- Constant folding does not change error behavior or overflow semantics.
- Disassemble or inspect generated IR and explain a representative expression from source to machine code.

## P6.5 Compiler backend specialization (optional)

For a compiler/toolchain target such as HTEC or an LLVM backend team, extend into:

- Instruction selection and legalization.
- Register allocation and spills.
- Calling convention lowering.
- Instruction scheduling.
- Machine description / target patterns.
- CPU feature selection and tuning.
- Debug info and unwind information.

**Project options**

1. Implement a tiny register allocator for a toy IR.
2. Add a small optimization pass to LLVM, built against one pinned LLVM version.
3. Implement a simple machine-code emitter for a limited subset of AArch64 or x86-64 instructions, with a disassembler/test oracle.

**Acceptance**

- The selected project has a small, testable scope.
- Correctness is checked against a reference implementation or compiler output where possible.
- Generated code follows the target ABI.
- Register spills and call-clobbered registers are handled correctly.

**P6 complete when:** you understand object files and dynamic linking, can trace source to IR and assembly, and have extended the Pratt project into a compiler or completed an equivalent toolchain experiment.

---

# P7. Software rasterizer, Vulkan and GPU architecture

**Estimate:** 12–16 weeks for the existing rasterizer and Vulkan path, plus 2–4 weeks for GPU architecture extensions.  
**Priority:** primary personal specialization; keep it.

Use the original learning-plan Phases 4 and 5. They are already unusually detailed and should remain the source of acceptance criteria for rasterization, C/Rust comparisons, SIMD, assembly kernels, validation, offscreen rendering and presentation.

## P7.1 Keep the software rasterizer

Retain:

- Scalar C baseline.
- Fixed-point edge-function coverage and top-left rule.
- Clipping and depth behavior.
- Golden scenes and independent coverage oracle.
- Tiling and deterministic parallel rasterization.
- Rust port as a selected comparison.
- SIMD and assembly kernels only after profiling the scalar implementation.
- Image diff tool and explicit floating-point tolerances.

**Additional acceptance**

- The renderer has a clear data-oriented layout and no hidden allocation in the inner raster loop.
- The notes include a profile-driven change, not just a list of optimizations tried.
- Image output and benchmark runs are reproducible from documented commands.

## P7.2 Keep the Vulkan path

Retain the original plan's manually loaded Vulkan function pointers, C headers, hand-written Rust bindings, layout verification, headless compute, offscreen render, validation layers, swapchain and Pi port where hardware allows.

Do not skip validation. Vulkan synchronization bugs are difficult to reason about without validation and a clear resource-state model.

## P7.3 GPU architecture and execution model

**Study**

- CPU versus GPU execution and scheduling.
- SIMD versus SIMT terminology and the limits of the analogy.
- Warps/wavefronts or execution groups (vendor-specific terminology varies).
- Divergence and masked execution.
- Register pressure and occupancy.
- Global/device memory, caches, shared/workgroup memory and local storage.
- Memory coalescing and access patterns.
- Barriers and synchronization scope.
- Command submission and CPU/GPU overlap.
- Shader compilation and SPIR-V.
- Timestamp queries and GPU profiling.

**Project: GPU compute laboratory**

Add a set of compute workloads to the Vulkan project:

1. Elementwise transform.
2. Reduction.
3. Histogram or prefix-sum experiment.
4. Tiled matrix multiplication (small enough to understand).
5. A memory-bound workload and a compute-bound workload.

**Acceptance**

- Every GPU result is checked against a CPU reference.
- Handle non-multiple workgroup sizes and explicit bounds.
- Measure CPU submission time separately from GPU execution time.
- Include warmup and repeated runs.
- Sweep workgroup size and at least two memory-access patterns.
- Explain observed performance using hardware counters or a profiler where available; otherwise state that the driver/device does not expose the needed data.
- Record API version, physical device, driver, limits and enabled extensions.

## P7.4 Optional CUDA comparison

Only if you have access to an NVIDIA GPU and want to explore NVIDIA-specific roles.

- Implement one or two compute kernels in CUDA.
- Compare the execution and memory model with Vulkan compute.
- Keep the algorithm and input/output contract identical.
- Do not compare raw timings unless device, clocks, compiler flags and measurement methodology are recorded.

**P7 complete when:** the existing Vulkan acceptance is satisfied and at least one compute workload has a correct CPU oracle, GPU timing and a written performance analysis.

---

# P8. Linux kernel and platform engineering specialization

**Estimate:** 5–8 weeks.  
**Priority:** choose this branch for ARM platform, Canonical Linux, kernel, firmware/platform or similar systems roles.

Do this after P3. It is not a prerequisite for graphics or compiler specialization.

## P8.1 Kernel architecture and source navigation

**Study**

- Kernel entry and initialization at a conceptual level.
- Kernel configuration and build system.
- Kernel/user-space boundary.
- System-call entry path.
- Kernel threads and workqueues.
- Scheduling concepts and task state.
- Kernel memory allocators (SLAB/SLUB concepts).
- VFS and filesystem abstractions.
- Interrupts, exceptions and deferred work.
- Locking primitives and lock ordering.

**Acceptance**

- Build one kernel version for QEMU or a disposable test VM.
- Navigate from a userspace syscall to the relevant kernel implementation for one operation.
- Identify a subsystem's main data structures and locking rules from source comments/docs.
- Record the exact kernel commit/version and config.

## P8.2 QEMU Linux boot and initramfs

**Project**

Boot a Linux kernel in QEMU with a minimal initramfs and a small userspace init program. Start with a known working configuration; then make controlled changes.

**Acceptance**

- The system boots reproducibly from a script.
- Capture serial console output.
- Identify kernel command line, initramfs contents and init process.
- Intentionally break one configuration item and document the resulting failure and diagnosis.
- Use a VM snapshot or disposable disk image. Do not experiment on a machine containing important data.

## P8.3 Kernel module and device interface

**Project**

Write a minimal out-of-tree module for a test kernel. Start with a module that logs init/exit and exposes a small read-only status interface. Only after that consider a simple character device.

**Acceptance**

- Build against the exact target kernel headers.
- Load/unload in the disposable VM, inspect `dmesg` and module metadata.
- Validate copy sizes, permissions, error codes and concurrent access if a device interface is added.
- Demonstrate a negative test and clean teardown.
- Document why kernel code has a different failure cost from userspace code.

## P8.4 Driver and hardware interface concepts

Study without requiring physical hardware:

- MMIO versus port IO.
- DMA and DMA mapping constraints.
- Interrupts and polling.
- Device tree basics on ARM platforms.
- PCI/PCIe enumeration basics.
- IOMMU purpose.
- Endianness and register access.
- Cache coherency between CPU and device.

**Optional project**

Use QEMU's emulated devices or a documented platform example to trace a device from enumeration/configuration through driver binding and data transfer. Do not write a real hardware driver until the interface and hardware documentation are available.

## P8.5 ARM boot and platform software

For ARM-oriented roles, add:

- AArch64 exception levels.
- Secure versus non-secure world at a conceptual level.
- Boot ROM → firmware → bootloader → kernel sequence for a chosen board.
- U-Boot environment and boot commands.
- Device tree handoff.
- UEFI/EDK II concepts.
- Trusted Firmware-A concepts.
- Cross-compilation and root filesystem construction.
- Yocto or Buildroot at a basic build/use level.

**Acceptance**

- Draw the boot chain for one real board and cite the board documentation.
- Build a small kernel/rootfs image or reproduce an existing documented build.
- Explain which stage owns each transition and what artifact is passed forward.
- Do not claim firmware bring-up competence from merely running a prebuilt image.

**P8 complete when:** you can boot and inspect a Linux VM, build/load a simple module safely, navigate a kernel subsystem and explain a real ARM boot chain.

---

# P9. Networking and dataplane specialization

**Estimate:** 5–8 weeks.  
**Priority:** choose this branch for Arista-like networking, high-performance networking, infrastructure or AI networking roles.

## P9.1 Network fundamentals and packet representation

**Study**

- Ethernet frame structure and MTU.
- IPv4 and IPv6 headers.
- TCP and UDP header fields.
- Checksums.
- Routing and neighbor resolution.
- TCP connection state and retransmission at a conceptual level.
- Byte order and unaligned parsing.
- Fragmentation and segmentation offloads at a conceptual level.

**Project: packet parser**

Write a bounded parser for Ethernet, IPv4/IPv6, TCP and UDP byte buffers. It must never read beyond the supplied length.

**Acceptance**

- Handles truncated headers, invalid lengths, VLAN tags and unsupported protocol types.
- Uses explicit byte-order conversions; no unaligned struct-cast assumptions.
- Fuzzes at least 100,000 generated/mutated packet buffers under ASan/UBSan.
- Compares a packet capture against `tcpdump`/Wireshark interpretation.

## P9.2 Socket and event-driven networking

Use the P3 event-loop server as a base.

**Add**

- TCP connection lifecycle and backpressure.
- Bounded output queues.
- Fairness between connections.
- Timeouts and idle connection handling.
- Scatter/gather IO (`readv`/`writev`) as an experiment.
- `sendfile` or zero-copy mechanisms as optional extensions.

**Acceptance**

- Correctly handles slow readers, half-close, reset, abrupt disconnect and server shutdown.
- Load test reports throughput plus p50/p99 latency at controlled offered load.
- Resource usage remains bounded under clients that never finish a request.

## P9.3 Linux networking stack and eBPF/XDP

**Study**

- Kernel networking path at a high level: socket, protocol, routing, qdisc and driver/NIC boundaries.
- `sk_buff` conceptually.
- NAPI polling.
- XDP hook and action model.
- eBPF verifier constraints and maps.
- `bpftool` and `iproute2` observability.

**Project: simple XDP filter**

If the kernel and privileges support it, implement a small XDP program that counts or drops a chosen packet class. Use a VM or isolated test interface; never attach experimental drop rules to the only network interface used to manage the machine.

**Acceptance**

- Document kernel version, config, privileges and available BPF features.
- Verify counters and packet behavior from userspace.
- Include a safe detach/cleanup path.
- If eBPF cannot be enabled in the environment, document the blocker and complete the packet parser plus userspace datapath instead.

## P9.4 DPDK, RDMA and NIC hardware (advanced / hardware-dependent)

Do not start here. First understand ordinary sockets, Linux networking and packet formats.

Possible extensions:

- DPDK poll-mode drivers and hugepages.
- Kernel bypass trade-offs.
- NIC receive/transmit queues and descriptor rings.
- DMA and memory registration.
- RDMA verbs and queue pairs.
- RSS, flow steering and offloads.
- NUMA locality and CPU pinning.

**Acceptance for any hardware-dependent project**

- Name the NIC, driver, firmware and enabled offloads.
- Report packet size, batch size, queue count, core affinity and NUMA placement.
- Compare against a kernel networking baseline on the same hardware.
- Separate CPU cost, throughput, latency and packet loss.
- State which results cannot be reproduced without the same NIC.

**P9 complete when:** the packet parser is fuzz-tested and the event-driven server is robust; one optional kernel/userspace datapath extension is complete if the environment supports it.

---

# P10. Focused specialization and portfolio hardening

**Estimate:** 4–8 weeks.  
**Goal:** turn learning into credible evidence for interviews. Choose one primary project and at most one secondary project.

## P10.1 Pick one primary project

Choose based on the roles you actually want to apply for:

| Target                     | Primary project                                                  | Evidence it should demonstrate                                  |
| -------------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------- |
| ARM / platform software    | Linux boot + module + ARM cross-build or architecture experiment | C, ABI, Linux, architecture, debugging, cross-compilation       |
| Canonical / Linux          | Process inspector + VM experiments + Linux performance dossier   | Linux userspace, memory, profiling, system behavior             |
| Kernel / OS                | QEMU kernel build + subsystem investigation + module             | Kernel source navigation, build/debug workflow, C correctness   |
| HTEC / compilers           | Pratt compiler + LLVM IR or compiler pass                        | parsing, IR, optimization, ABI, generated code                  |
| Arista / networking        | packet parser + event-driven dataplane + XDP/DPDK option         | C/C++, concurrency, networking, performance, bounded memory     |
| NVIDIA / GPU               | Vulkan compute lab + GPU profiling + CPU reference               | C/C++, GPU model, synchronization, memory and performance       |
| Graphics / engine          | software rasterizer + Vulkan renderer                            | data layout, math, SIMD, concurrency, graphics pipeline         |
| Hawk-Eye / performance C++ | low-latency media or packet pipeline                             | C++, threading, bounded buffers, profiling, latency measurement |

## P10.2 Repository quality bar

Each showcased project should have:

- One paragraph explaining the problem and the non-goals.
- A dependency-free build or a clearly documented minimal toolchain.
- Exact build and test commands.
- A diagram of the main data flow or subsystem boundary.
- Tests and an independent oracle for critical behavior.
- Sanitizer/debugger instructions.
- Performance results only where meaningful, including hardware and tool versions.
- A `NOTES.md` with design trade-offs, bugs found and known limitations.
- A short README that tells an engineer where to start in under two minutes.

## P10.3 Interview explanation drill

For the primary project, prepare a 10-minute explanation:

1. What problem does it solve?
2. What is the main data layout and why?
3. What are the important invariants?
4. What failure cases did you test?
5. What does the compiler generate for the hot path?
6. What did profiling show?
7. What did you change based on evidence?
8. What would you improve with another week?

Be ready to draw the memory layout, state machine or call path without opening the code.

## P10.4 Application readiness checklist

You are ready to apply to a role when you can show:

- A professional-quality C or C++ project, not only exercises.
- Confident native debugging with GDB/LLDB.
- Basic understanding of the target OS and ABI.
- Correctness tests and sanitizer use.
- Ability to read optimized assembly and explain a relevant hot path.
- One specialization-specific artifact (kernel, compiler, packet processing, GPU or renderer).
- Clear communication about what is learned versus what has been done professionally.

Do not describe personal projects as professional production experience. Present them as evidence of initiative and technical capability.

---

## 4. Dependency graph

The dependency graph below is the recommended order. Optional branches can be skipped without blocking the others.

```text
P0 Repository/build/debugger hygiene
  |
  v
P1 Assembly + ABI + machine representation
  |
  v
P2 C memory + data structures + selected Rust
  |
  +------------------------+
  |                        |
  v                        v
P3 Linux userspace       P4 C++ systems
  |                        |
  +------------+-----------+
               |
               v
        P5 Concurrency + performance
               |
       +-------+--------+----------------+
       |                |                |
       v                v                v
P6 Toolchain/ELF    P8 Kernel/platform  P9 Networking
       |                |                |
       +----------------+----------------+
                        |
                        v
               P10 Portfolio/application

P7 Rasterizer/Vulkan uses P1, P2 and P5. It can be developed in parallel
once the basic C, memory and debugging foundations are in place.
```

### Dependencies from the original plan

Keep the original learning plan's task dependencies, including:

- P0.4 benchmark harness → every benchmark.
- P1 guard pages and ABI canaries → assembly mini-libc and SIMD exercises.
- P2.3 arena → rasterizer and request/job data where useful.
- P2.4 handles → game project.
- P3 MPMC/job system → parallel rasterizer.
- P4 software rasterizer → Vulkan image comparison.
- P4.7 image diff → Vulkan offscreen render.
- P6.1 PNG decoder → optional texture mapping.

The phase numbers in the original document are local to that document; the P0–P10 labels in this master plan are the canonical roadmap labels. Avoid confusing the two when writing notes.

---

## 5. A practical schedule

This is an example at 8–10 hours per week. The actual pace depends on prior experience, environment setup and how much of the original plan is already complete.

| Period      | Main focus                      | Deliverable                                          |
| ----------- | ------------------------------- | ---------------------------------------------------- |
| Weeks 1–2   | P0 repo audit and environment   | Clean build/test, corrected examples, tool inventory |
| Weeks 3–6   | P1 assembly and ABI             | x86/AArch64 reports and working harness              |
| Weeks 7–12  | P2 C and selected Rust projects | Arena, parser/tool and memory-safety notes           |
| Weeks 13–18 | P3 Linux userspace              | Process inspector, VM lab, event-driven server       |
| Weeks 19–24 | P4 C++ systems                  | C ABI library and lifetime/layout lab                |
| Weeks 25–30 | P5 concurrency/performance      | Job system and profile-guided optimization report    |
| Weeks 31–36 | P6 ELF/compiler                 | ELF report and Pratt compiler/LLVM IR                |
| Weeks 37–50 | P7 rasterizer/Vulkan/GPU        | Renderer plus GPU compute investigation              |
| Weeks 51–58 | P8 or P9 specialization         | One kernel/platform or networking project            |
| Weeks 59–62 | P10 portfolio                   | Clean project READMEs and interview walkthrough      |

This schedule is not a promise or a reason to postpone job applications for 62 weeks. The recommended first application checkpoint is after P5 plus one role-relevant project. Continue learning during the job search and interview process.

### If time is limited

Cut in this order:

1. Duplicate Rust ports that do not reveal a new ownership/codegen issue.
2. Repeated compiler comparisons that do not answer a new question.
3. Advanced allocator experiments such as TLSF.
4. The MPMC lock-free implementation if a correct mutex baseline already teaches the concurrency objective; revisit later.
5. The Pi Vulkan port if the device/driver is too constrained.
6. DPDK and RDMA unless you have suitable hardware and target a networking role.
7. Deep compiler backend work unless targeting compiler jobs.

Do **not** cut the C memory model, ABI, Linux userspace, debugger, sanitizer or one credible profiling project.

---

## 6. Reference shelf

Prefer the official or primary source for the subject being studied. Check current versions and access dates before relying on a specific API, command-line flag or feature.

### Processor architecture and ABI

- Arm Architecture Reference Manual: <https://developer.arm.com/documentation/ddi0487/latest>
- AAPCS64: <https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst>
- System V AMD64 ABI: <https://gitlab.com/x86-psABIs/x86-64-ABI>
- Intel Software Developer Manuals: <https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html>
- uops.info: <https://uops.info>
- Agner Fog optimization manuals: <https://www.agner.org/optimize/>

### C, C++ and Rust

- WG14 C committee drafts and publications: <https://www.open-std.org/jtc1/sc22/wg14/>
- C++ working draft: <https://eel.is/c++draft/>
- cppreference C++ reference: <https://en.cppreference.com/w/>
- Rust Book: <https://doc.rust-lang.org/book/>
- Rust Reference: <https://doc.rust-lang.org/reference/>
- Rustonomicon: <https://doc.rust-lang.org/nomicon/>
- Miri: <https://github.com/rust-lang/miri>

### Linux and operating systems

- Linux kernel documentation: <https://docs.kernel.org/>
- Linux kernel source: <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/>
- man-pages project: <https://man7.org/linux/man-pages/>
- The Linux Programming Interface (book; use as a structured explanation, verify current API behavior with man pages)
- QEMU documentation: <https://www.qemu.org/docs/master/>

### Compilers and toolchains

- LLVM documentation: <https://llvm.org/docs/>
- LLVM Language Reference: <https://llvm.org/docs/LangRef.html>
- Clang command guide: <https://clang.llvm.org/docs/ClangCommandLineReference.html>
- GCC documentation: <https://gcc.gnu.org/onlinedocs/>
- System V ELF ABI: <https://refspecs.linuxfoundation.org/elf/gabi4+/contents.html>
- GNU binutils documentation: <https://sourceware.org/binutils/docs/>

### Networking

- Linux networking documentation: <https://docs.kernel.org/networking/>
- eBPF documentation: <https://docs.kernel.org/bpf/>
- libbpf documentation: <https://docs.kernel.org/bpf/libbpf/>
- DPDK documentation: <https://doc.dpdk.org/guides/>
- RFC Editor: <https://www.rfc-editor.org/>
- Wireshark documentation: <https://www.wireshark.org/docs/>

### Performance

- Brendan Gregg's Linux performance material: <https://www.brendangregg.com/linuxperf.html>
- `perf` documentation: <https://perf.wiki.kernel.org/>
- Linux perf examples: <https://www.brendangregg.com/perf.html>

### Graphics and GPU

- Vulkan specification: <https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html>
- Vulkan Guide: <https://docs.vulkan.org/guide/latest/>
- Vulkan-Hpp / Vulkan-Headers: <https://github.com/KhronosGroup/Vulkan-Headers>
- Vulkan validation layers: <https://github.com/KhronosGroup/Vulkan-ValidationLayers>
- SPIR-V specification and tools: <https://github.com/KhronosGroup/SPIRV-Tools>
- Mesa documentation: <https://docs.mesa3d.org/>

### Data-oriented design and performance-aware programming

- Casey Muratori, Semantic Compression: <https://caseymuratori.com/blog_0015>
- Casey Muratori, Performance-Aware Programming: <https://www.computerenhance.com/>
- John Carmack, Inlined Code: <https://number-none.com/blow/john_carmack_on_inlined_code.html>
- Fabian, Data-Oriented Design: <https://www.dataorienteddesign.com/dodbook/>
- Ryan Fleury: <https://www.rfleury.com/>

A link being listed here does not mean every claim in it has been independently verified. Record the exact page, section and access date in `refs.md` when using it for a concrete decision.

---

## 7. Final completion criteria

The full roadmap is complete only when all common-core criteria and one specialization's criteria are met.

### Common core

- [ ] Clean, reproducible build and test entry points.
- [ ] Correct x86-64 and AArch64 ABI/assembly exercises.
- [ ] C programs with explicit memory ownership, bounds and error behavior.
- [ ] Selected Rust projects with carefully justified `unsafe` and FFI.
- [ ] Linux userspace projects involving processes, virtual memory and nonblocking IO.
- [ ] A C++ project showing object lifetime, data layout and C ABI interoperability.
- [ ] Concurrency work with correctness tests and explicit progress guarantees.
- [ ] At least one measured performance investigation using a profiler or hardware counters.
- [ ] ELF/linker/compiler pipeline report and source-to-assembly investigation.

### One specialization

- [ ] **Kernel/platform:** QEMU boot, kernel source investigation and a safe module/device-interface exercise; or
- [ ] **Compiler/toolchain:** a compiler or LLVM IR/pass project; or
- [ ] **Networking:** fuzz-tested parser plus robust dataplane/event-driven server; or
- [ ] **GPU/graphics:** software rasterizer, validated Vulkan renderer and profiled compute workload.

### Portfolio

- [ ] One primary project has a concise README, reproducible build, tests and design notes.
- [ ] Benchmarks include hardware, software versions, commands and limitations.
- [ ] At least one important implementation choice is explained with evidence.
- [ ] You can explain what you know, what you have implemented and what you have not yet done professionally without overstating experience.

**The point of this plan is not to check every box.** The point is to build a common systems foundation, choose a direction based on genuine interest and produce enough concrete evidence that an engineering team can evaluate your ability.
