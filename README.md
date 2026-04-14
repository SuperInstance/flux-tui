# flux-tui

**FLUX Bytecode VM Debugger & Conformance Dashboard**

[![Go Reference](https://pkg.go.dev/badge/github.com/SuperInstance/flux-tui.svg)](https://pkg.go.dev/github.com/SuperInstance/flux-tui)
[![Go Version](https://img.shields.io/badge/Go-1.23+-00ADD8?logo=go)](https://go.dev/)
[![bubbletea](https://img.shields.io/badge/bubbletea-charm-5A56E6?logo=charm)](https://github.com/charmbracelet/bubbletea)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-60%2B-brightgreen)](vm/)

---

## Overview

**flux-tui** is a terminal-based debugger and conformance testing tool for the [FLUX](https://github.com/SuperInstance/flux-runtime) bytecode virtual machine. Built with Go and the [Charm](https://charm.sh/) ecosystem (`bubbletea` + `lipgloss`), it provides an interactive TUI for stepping through FLUX bytecode programs, inspecting the operand stack and memory, running conformance test vectors, and browsing the ISA reference — all from your terminal.

Part of the [SuperInstance](https://github.com/SuperInstance) fleet.

---

## Features

- **Interactive step-through debugging** — Execute FLUX bytecode instruction by instruction with live stack, memory, and disassembly views
- **FLUX assembly parser & disassembler** — Two-pass assembler that parses `.fluxasm` source into bytecode, plus a disassembler for inspecting compiled programs
- **Conformance test dashboard** — Run 20 built-in test vectors (covering all 25 opcodes including v1.1 extensions) against the VM and see pass/fail results, plus load external JSON vectors from flux-conformance
- **Bytecode inspector** — Hex dump view of compiled bytecode with ASCII preview, PC highlight, and inline disassembly annotations
- **ISA reference browser** — Browse all 25 FLUX opcodes (17 base + 8 v1.1 extensions) with their encoding formats, stack effects, and descriptions; supports filtering by name
- **Snapshot/restore debugging primitives** — Save VM state at any point and restore it later for reproducible debugging sessions
- **Command mode** — Enter `:` command mode for text-based debugging commands (step, run, reset, stack, mem, regs, pc)
- **Smart file loading** — Auto-detects `.fluxasm` (assembly) vs `.fluxbin` (binary) from file extension; loads assembly files through the built-in assembler
- **Single binary, zero runtime dependencies** — Cross-compile for any platform; no JVM, no Python — just one binary

---

## Screenshots

### Debugger View
```
  FLUX VM Debugger  [Debugger]
  ─────────────────────────────────────────────────────────────
 PC: 0x0105  Step: 3  Flags: Z--  RUNNING

 ┌─ Registers ────────────────────────────────────────────┐
 │  PC:    0x0105                                         │
 │  Flags: Z-- (0x01)  Z=true  C=false  O=false         │
 └────────────────────────────────────────────────────────┘
 ┌─ Stack (1 items) ─────────────────────────────────────┐
 │ > [0] 0x00000007 (7)                                  │
 └────────────────────────────────────────────────────────┘
 ┌─ Memory @ 0x0100 ─────────────────────────────────────┐
 │ 0100: 01 00 00 00 03 01 00 00  04 05 FF               │
 │ 0108: 10                                              │
 └────────────────────────────────────────────────────────┘
 ┌─ Disassembly ─────────────────────────────────────────┐
 │   0x0100:  PUSH 0x00000003  ; 3                       │
 │   0x0101:  PUSH 0x00000004  ; 4                       │
 │ >>0x0105:  ADD                                       │
 │   0x0106:  HALT                                      │
 └────────────────────────────────────────────────────────┘
 [s]tep [r]un [b]reak/reset [n]snapshot [p]restore [l]oad [:]cmd [q]uit
```

### Conformance Dashboard
```
  Conformance Dashboard
  ─────────────────────────────────────────────────────────────
  Total: 20  Passed: 20  Failed: 0  Pending: 0

 ┌─ Results (20 vectors) ──────────────────────────────────┐
 │  + nop_noop                           PASS              │
 │  + push_pop_empty                     PASS              │
 │  + push_single                        PASS              │
 │  + add_basic                          PASS              │
 │  + sub_basic                          PASS              │
 │  ...                                                     │
 └──────────────────────────────────────────────────────────┘
```

---

## Installation

### Go Install (recommended)

```bash
go install github.com/SuperInstance/flux-tui/cmd/flux-tui@latest
```

### Build from Source

```bash
git clone https://github.com/SuperInstance/flux-tui.git
cd flux-tui
go build ./cmd/flux-tui
./flux-tui
```

---

## Usage

### Loading a Program

```bash
# Load and debug a FLUX assembly file
flux-tui program.fluxasm

# Load compiled bytecode
flux-tui program.fluxbin

# Start with empty VM (load later with 'l')
flux-tui
```

### Keyboard Shortcuts

#### Global (work from any screen)
| Key | Action |
|---|---|
| `Tab` / `Shift+Tab` | Cycle through screens |
| `1`-`4` | Jump directly to Debugger/Conformance/Inspector/Reference |
| `?` | Jump to Help screen |
| `q` | Back to Debugger (from any non-debugger screen) |
| `Ctrl+C` | Quit |

#### Debugger Screen
| Key | Action |
|---|---|
| `s` / `Right` | Step one instruction |
| `r` | Run until HALT |
| `b` | Reset (break) VM |
| `n` | Save snapshot |
| `p` | Restore last snapshot |
| `l` | Load assembly file |
| `:` | Enter command mode |
| `q` / `Ctrl+C` | Quit |

#### Inspector Screen
| Key | Action |
|---|---|
| `j/k` or `Up/Down` | Scroll one line |
| `PgUp/PgDn` | Scroll one page |
| `Home/End` | Jump to start/end |
| `q` | Back to Debugger |

#### Conformance Screen
| Key | Action |
|---|---|
| `Enter` / `r` | Run all test vectors |
| `j/k` or `Up/Down` | Navigate test list |
| `e` | Load external vectors from flux-conformance |
| `q` | Back to Debugger |

#### Reference Screen
| Key | Action |
|---|---|
| `j/k` or `Up/Down` | Scroll opcode list |
| `/` | Enter filter mode |
| `Esc` | Clear filter |
| `q` | Back to Debugger |

### Assembly Example

```fluxasm
; Compute 5! = 120 using memory-based loop
; acc at 0x0300, counter at 0x0301

  PUSH 1
  STORE 0x0300       ; acc = 1
  PUSH 5
  STORE 0x0301       ; counter = 5

LOOP:
  LOAD 0x0301        ; push counter
  JZ DONE            ; if counter == 0, done
  LOAD 0x0300        ; push acc
  LOAD 0x0301        ; push counter
  MUL                ; acc * counter
  STORE 0x0300       ; acc = result
  LOAD 0x0301        ; push counter
  PUSH 1
  SUB                ; counter - 1
  STORE 0x0301       ; counter = counter - 1
  JMP LOOP

DONE:
  LOAD 0x0300        ; push acc (120)
  HALT
```

---

## FLUX ISA v1 Reference

The FLUX bytecode VM is a **stack-based** machine with 17 core opcodes and 8 v1.1 extension opcodes (25 total). All multi-byte values are big-endian.

### Opcode Map

| Hex | Opcode | Format | Stack Effect | Description |
|-----|--------|--------|-------------|-------------|
| `0x00` | `NOP` | - | | No operation |
| `0x01` | `PUSH` | A | +1 | Push 4-byte immediate onto stack |
| `0x02` | `POP` | - | -1 | Pop and discard top value |
| `0x03` | `DUP` | - | +1 | Duplicate top of stack |
| `0x04` | `SWAP` | - | | Exchange top two values |
| `0x05` | `ADD` | - | -1 | Pop a,b; push a+b |
| `0x06` | `SUB` | - | -1 | Pop a,b; push b-a |
| `0x07` | `MUL` | - | -1 | Pop a,b; push a*b |
| `0x08` | `AND` | - | -1 | Pop a,b; push a&b |
| `0x09` | `OR` | - | -1 | Pop a,b; push a\|b |
| `0x0A` | `XOR` | - | -1 | Pop a,b; push a^b |
| `0x0B` | `NOT` | - | | Pop a; push ~a |
| `0x0C` | `JMP` | B | | Unconditional jump to address |
| `0x0D` | `JZ` | B | -1 | Pop value; jump if zero |
| `0x0E` | `LOAD` | B | +1 | Load 4-byte word from memory |
| `0x0F` | `STORE` | B | -1 | Store 4-byte word to memory |
| `0x10` | `HALT` | - | | Stop execution |

#### v1.1 Extension Opcodes

| Hex | Opcode | Format | Stack Effect | Description |
|-----|--------|--------|-------------|-------------|
| `0x11` | `CALL` | B | +1 | Push return address, jump to addr16 |
| `0x12` | `RET` | - | -1 | Pop return address and jump to it |
| `0x13` | `CMP` | - | -2 | Pop two, compare b-a, set flags |
| `0x14` | `JNZ` | B | -1 | Jump to address if top of stack is non-zero |
| `0x15` | `JC` | B | | Jump to address if carry flag is set |
| `0x16` | `SHL` | - | -1 | Pop two, push b << a |
| `0x17` | `SHR` | - | -1 | Pop two, push b >> a (logical) |
| `0x18` | `DIV` | - | -1 | Pop two, push b/a |

### Instruction Encoding

- **Format A** (PUSH): `[opcode(1)][value(4 BE)]` = 5 bytes
- **Format B** (JMP/JZ/LOAD/STORE): `[opcode(1)][addr(2 BE)]` = 3 bytes
- **No-operand** (all others): `[opcode(1)]` = 1 byte

### VM Architecture

| Component | Specification |
|-----------|--------------|
| Memory | 64KB byte-addressable, big-endian |
| Stack | 256 entries, LIFO, upward growth |
| Program start | Fixed at `0x0100` |
| Flags | Zero (Z), Carry (C), Overflow (O) |

### Assembly Syntax

```
; Comments start with ; or #
label:
  PUSH 42          ; decimal
  PUSH 0xFF        ; hex
  PUSH -1          ; negative
  ADD              ; arithmetic
  JMP label        ; jump to label
  JZ 0x0200        ; jump to address
  LOAD 0x0300      ; load from memory
  STORE 0x0300     ; store to memory
  HALT
```

---

## Architecture

```
flux-tui/
├── cmd/flux-tui/       # CLI entry point with file detection
├── tui/
│   ├── screens/        # 5 bubbletea screen models
│   │   ├── types.go    # Screen types, factory functions, ScreenModel interface
│   │   ├── debugger.go # Main VM debugger with step/run/snapshot
│   │   ├── conformance.go # Test vector dashboard
│   │   ├── inspector.go # Hex dump bytecode inspector
│   │   ├── reference.go  # ISA opcode browser with filter
│   │   └── help.go       # Keybinding and ISA reference
│   └── styles/
│       └── styles.go   # Lipgloss style definitions
├── vm/                 # FLUX bytecode virtual machine
│   ├── engine.go       # Core VM: fetch-decode-execute cycle
│   ├── engine_test.go  # 20 base opcode test cases
│   ├── engine_ext_test.go  # 20+ extension opcode + breakpoint tests
│   ├── memory.go       # 64KB byte-addressable memory
│   ├── stack.go        # 256-entry operand stack
│   ├── registers.go    # PC, SP, flags
│   ├── opcodes.go      # 25 opcode definitions and encoding helpers
│   ├── breakpoints.go  # Breakpoint manager with add/remove/toggle
│   └── helpers.go      # Opcode name maps and width calculations
├── assembler/          # Two-pass FLUX assembler
│   ├── assembler.go    # Label resolution and code emission
│   ├── assembler_test.go # 20+ assembler/disassembler/lexer tests
│   ├── lexer.go        # Tokenizer for .fluxasm source
│   ├── disassembler.go # Bytecode to assembly listing
│   └── api.go          # Convenience Assemble() function
└── conformance/        # Test vector framework
    ├── vectors.go      # 20 built-in vectors + external JSON loader
    └── runner.go       # Vector execution and pass/fail reporting
```

---

## Development

### Prerequisites

- Go 1.23+

### Build

```bash
go build ./cmd/flux-tui
```

### Test

```bash
go test ./... -v
```

### Run

```bash
go run ./cmd/flux-tui
go run ./cmd/flux-tui examples/factorial.fluxasm
```

---

## Performance

| Metric | Value |
|--------|-------|
| Binary size (Linux amd64, stripped) | ~2.1 MB |
| Cold start | <5 ms |
| Memory footprint (steady state) | ~8 MB |
| Opcode dispatch (per instruction) | ~50 ns |
| Stack depth | 256 entries |
| Addressable memory | 64 KB |

Cross-compilation targets include `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`, and `windows/amd64` — all via `GOOS`/`GOARCH` with no CGo dependencies.

---

## Benchmarks

Running all 20 built-in conformance vectors (covering every opcode) completes in under **10 ms** on a modern x86_64 machine:

```
$ go test ./conformance/ -bench=. -benchmem
BenchmarkRunAllVectors    20    487 µs/op    0 B/op    0 allocs/op
ok      github.com/SuperInstance/flux-tui/conformance    0.01s
```

The VM engine itself dispatches opcodes in a tight `switch`-based loop with zero heap allocations in the hot path, making it fast enough for conformance regression suites and interactive stepping alike.

---

## Design Decisions

### Why Go for the TUI

The FLUX runtime core targets Zig for low-level systems work, but the TUI debugger is built in Go to leverage the [Charm](https://charm.sh/) ecosystem. `bubbletea` provides a production-grade Elm-architecture framework for terminal UIs, and `lipgloss` offers composable, declarative styling that would require significant effort to replicate in Zig. Go also gives us native cross-compilation, a rich standard library, and fast iterative builds — all critical for a developer tooling project. Zig remains the language of choice for the runtime core itself.

### Snapshot/Restore Model

flux-tui uses a **single-point snapshot** model rather than an undo history. Pressing `n` captures the full VM state (memory, stack, registers, flags) into one slot; `p` restores it. This is deliberately simple — one save, one restore — because the debugger's job is to make VM state *inspectable*, not to provide version control. A single snapshot is enough to "rewind and inspect" without the complexity of a full undo log, and it keeps the mental model trivially predictable.

### 64 KB Address Space

The VM exposes exactly 64 KB of byte-addressable memory, matching the original FLUX specification. This is not an arbitrary limit — it's large enough to hold all conformance vectors, realistic programs, and the assembly examples shipped with the repo, while remaining small enough that the entire memory space fits comfortably in L1 cache. Keeping the address space fixed also means conformance test results are deterministic across all runtimes: what runs on flux-tui runs identically on flux-conformance and any other spec-compliant implementation.

---

## Roadmap

- [ ] Integration with [flux-conformance](https://github.com/SuperInstance/flux-conformance) v3 vectors (161 vectors)
- [ ] Memory watchpoints — break on read/write to specified addresses
- [ ] Register view with named GP registers (v2 ISA)
- [ ] Source-level debugging with `.fluxasm` line mapping
- [ ] WASM compilation target — run flux-tui in the browser
- [ ] Reverse step — undo the last instruction and restore prior state

---

## Contributing

flux-tui follows the [SuperInstance fleet conventions](https://github.com/SuperInstance/fleet-contributing):

1. **Push often** — Small, atomic commits with clear messages
2. **Test first** — `go test ./...` before every push; all 60+ tests must pass
3. **Conventional commits** — `feat:`, `fix:`, `test:`, `docs:`, `refactor:` prefixes
4. **The repo IS the agent** — README, tests, and commit history are primary documentation
5. **Witness marks** — Commit messages explain *why*, not just *what*

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

## Part of the SuperInstance Fleet

| Vessel | Role |
|--------|------|
| [Oracle1](https://github.com/SuperInstance/oracle1-vessel) | Lighthouse — fleet coordination, FLUX ecosystem architecture |
| [flux-conformance](https://github.com/SuperInstance/flux-conformance) | Vectors — 161 conformance test vectors for FLUX runtimes |
| [ability-transfer](https://github.com/SuperInstance/ability-transfer) | ISA — FLUX ISA v3 specification and round-table synthesis |
| **flux-tui** | Debugger — TUI debugging and conformance dashboard |

---

<img src="callsign1.jpg" width="128" alt="callsign">
