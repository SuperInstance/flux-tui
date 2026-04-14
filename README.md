# 🔍 flux-tui

**FLUX Bytecode VM Debugger & Conformance Dashboard**

[![Go Reference](https://pkg.go.dev/badge/github.com/SuperInstance/flux-tui.svg)](https://pkg.go.dev/github.com/SuperInstance/flux-tui)
[![Go Version](https://img.shields.io/badge/Go-1.21+-00ADD8?logo=go)](https://go.dev/)
[![bubbletea](https://img.shields.io/badge/bubbletea-charm-5A56E6?logo=charm)](https://github.com/charmbracelet/bubbletea)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## Overview

**flux-tui** is a terminal-based debugger and conformance testing tool for the [FLUX](https://github.com/SuperInstance/flux-runtime) bytecode virtual machine. Built with Go and the [Charm](https://charm.sh/) ecosystem (`bubbletea` + `lipgloss` + `bubbles`), it provides an interactive TUI for stepping through FLUX bytecode programs, inspecting registers/stack/memory, running conformance test vectors, and browsing the ISA reference — all from your terminal.

Part of the [SuperInstance](https://github.com/SuperInstance) fleet.

---

## Features

- **Interactive step-through debugging** — Execute FLUX bytecode instruction by instruction with live register, stack, and memory views
- **FLUX assembly parser & disassembler** — Two-pass assembler that parses `.fluxasm` source into bytecode, plus a disassembler for inspecting compiled programs
- **Conformance test dashboard** — Run FLUX conformance test vectors against the VM and see pass/fail results in real time, with per-vector diagnostics
- **Bytecode inspector** — Hex dump view of compiled bytecode with instruction boundaries highlighted and opcode annotations
- **ISA reference browser** — Browse all FLUX opcodes, their encoding formats, and execution semantics without leaving the debugger
- **Snapshot/restore debugging primitives** — Save VM state at any point and restore it later for reproducible debugging sessions
- **Single static binary, zero runtime dependencies** — Cross-compile for any platform; no runtime, no JVM, no Python — just one binary

---

## Screenshots

### Debug View
```
┌─ Registers ─────────────┐  ┌─ Stack ────────────────┐
│ R0: 0x00000000  (zero)  │  │ [0] 0x0000002A  (42)  │
│ R1: 0x0000001E  (30)   │  │ [1] 0x0000000F  (15)  │
│ R2: 0x0000000A  (10)   │  │ [2] 0x00000003  (3)   │
│ PC: 0x00000008          │  │ [3] 0x00000001  (1)   │
│ SP: 0x00000004          │  └────────────────────────┘
│ FL: 0b101 (neg|zero|carry) │
└──────────────────────────┘
```
*Step through bytecode with live register and stack inspection.*

### Conformance Dashboard
```
┌─ Conformance Results ────────────────────────────┐
│ PASS  126/138  (91.3%)                           │
│ FAIL    8/138   (5.8%)  │ SKIP    4/138   (2.9%) │
│─────────────────────────────────────────────────│
│ ▸ arith-add-imm          PASS   0.01ms          │
│ ▸ arith-sub-reg          PASS   0.01ms          │
│ ▸ jmp-relative           FAIL   unexpected PC   │
│ ▸ loop-decrement         PASS   0.02ms          │
└─────────────────────────────────────────────────┘
```
*Run the full conformance suite and drill into failures.*

### Bytecode Inspector
```
┌─ Hex Dump ───────────────────────────────────────┐
│ 0000: 02 00 00 00  NOP                          │
│ 0004: 01 0A 00 00  LOAD_IMM R0, 10              │
│ 0008: 01 1E 00 00  LOAD_IMM R1, 30              │
│ 000C: 20 00 01 00  ADD R0, R1                   │
│ 0010: FF 00 00 00  HALT                         │
└─────────────────────────────────────────────────┘
```
*Inspect compiled bytecode with inline disassembly annotations.*

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

# Load and debug compiled bytecode
flux-tui --binary program.fluxbin

# Run conformance tests
flux-tui --conformance

# Start with empty VM
flux-tui
```

### Keyboard Shortcuts

| Key | Action |
|---|---|
| `n` / `→` | Step to next instruction |
| `s` / `Enter` | Step into (follow CALL) |
| `o` / `←` | Step out of current frame |
| `c` | Continue execution until breakpoint or HALT |
| `b` | Toggle breakpoint at current PC |
| `r` | Reset VM to initial state |
| `m` | Toggle memory view |
| `i` | Open ISA reference browser |
| `d` | Open disassembler view |
| `t` | Switch to conformance dashboard |
| `h` | Toggle hex dump view |
| `q` / `Ctrl+C` | Quit |
| `?` | Show help overlay |

### Assembly Example

```fluxasm
; Simple factorial: compute 5!
LOAD_IMM  R0, 5      ; n = 5
LOAD_IMM  R1, 1      ; result = 1
LOAD_IMM  R2, 1      ; multiplier = 1

LOOP:
MUL       R1, R1, R2 ; result *= multiplier
ADD       R2, R2, 1  ; multiplier++
SUB       R0, R0, 1  ; n--
JNZ       R0, @LOOP  ; if n != 0, loop

HALT                ; R1 = 120
```

---

## FLUX ISA Quick Reference

The FLUX bytecode VM uses fixed-width 4-byte instructions with 17 core opcodes:

| Opcode | Hex | Format | Description |
|--------|-----|--------|-------------|
| `NOP` | `0x00` | — | No operation |
| `HALT` | `0xFF` | — | Stop execution |
| `LOAD_IMM` | `0x01` | `01 Rd I16` | Load immediate value into register |
| `LOAD` | `0x02` | `02 Rd [Ra+off]` | Load from memory into register |
| `STORE` | `0x03` | `03 [Ra+off] Rs` | Store register to memory |
| `MOV` | `0x04` | `04 Rd Rs` | Copy register to register |
| `ADD` | `0x10` | `10 Rd Ra Rb` | Integer addition |
| `SUB` | `0x11` | `11 Rd Ra Rb` | Integer subtraction |
| `MUL` | `0x12` | `12 Rd Ra Rb` | Integer multiplication |
| `DIV` | `0x13` | `13 Rd Ra Rb` | Integer division |
| `AND` | `0x14` | `14 Rd Ra Rb` | Bitwise AND |
| `OR` | `0x15` | `15 Rd Ra Rb` | Bitwise OR |
| `XOR` | `0x16` | `16 Rd Ra Rb` | Bitwise XOR |
| `SHL` | `0x17` | `17 Rd Ra Rb` | Shift left |
| `SHR` | `0x18` | `18 Rd Ra Rb` | Shift right |
| `JMP` | `0x20` | `20 I16` | Unconditional jump |
| `JNZ` | `0x21` | `21 Ra I16` | Jump if register is non-zero |

### Encoding Format

All instructions are 4 bytes (32 bits), big-endian:

```
Byte 0:    Opcode
Byte 1:    Destination register (Rd) or unused
Byte 2:    Source register A (Ra) or immediate high byte
Byte 3:    Source register B (Rb) or immediate low byte
```

### Flag Register

The VM maintains a flags register (`FL`) updated after arithmetic operations:

| Flag | Bit | Meaning |
|------|-----|---------|
| Zero | 0 | Result was zero |
| Negative | 1 | Result was negative |
| Carry | 2 | Unsigned overflow |

---

## Architecture

flux-tui is organized into the following packages:

```
flux-tui/
├── cmd/flux-tui/       # CLI entry point
├── tui/                # Bubbletea TUI application
│   ├── debug.go        # Debug view (registers, stack, memory)
│   ├── conformance.go  # Conformance test dashboard
│   ├── hexdump.go      # Bytecode hex inspector
│   ├── isa.go          # ISA reference browser
│   └── snapshot.go     # Snapshot/restore primitives
├── vm/                 # FLUX bytecode virtual machine
│   ├── vm.go           # Core VM: fetch-decode-execute loop
│   ├── registers.go    # Register file and flag handling
│   ├── memory.go       # Memory model (byte-addressable)
│   └── stack.go        # Operand stack
├── assembler/          # Two-pass FLUX assembler
│   ├── parser.go       # Tokenizer and parser for .fluxasm
│   ├── assembler.go    # Label resolution and code emission
│   └── disasm.go       # Disassembler (bytecode → assembly)
└── conformance/        # Conformance test framework
    ├── runner.go       # Test vector execution engine
    ├── vectors.go      # Built-in test vectors
    └── report.go       # Pass/fail reporting
```

- **`vm`** — Pure Go implementation of the FLUX bytecode VM with fetch-decode-execute cycle, 16 general-purpose registers, byte-addressable memory, and an operand stack.
- **`assembler`** — Two-pass assembler: first pass collects labels, second pass resolves references and emits 4-byte instructions. The disassembler reverses the process.
- **`conformance`** — Runs structured test vectors (input bytecode + expected state) against the VM and produces pass/fail reports with per-vector diagnostics.
- **`tui`** — Charm-powered terminal UI built on `bubbletea`'s Elm architecture, styled with `lipgloss`, using `bubbles` components for input and lists.

---

## Development

### Prerequisites

- Go 1.21+

### Build

```bash
go build ./cmd/flux-tui
```

### Test

```bash
go test ./...
```

### Run (development)

```bash
go run ./cmd/flux-tui
```

---

## Contributing

flux-tui follows the [SuperInstance fleet conventions](https://github.com/SuperInstance/fleet-contributing):

1. **Push often** — The fleet captain watches the commit feed as a dashboard. Small, atomic commits with clear messages.
2. **Test first** — Run `go test ./...` before every push. All tests must pass.
3. **Conventional commits** — Use `feat:`, `fix:`, `test:`, `docs:`, `refactor:` prefixes.
4. **The repo IS the agent** — README, tests, and commit history are the primary documentation.
5. **Witness marks** — Leave detailed commit messages explaining *why*, not just *what*.

See [fleet-contributing](https://github.com/SuperInstance/fleet-contributing) for the full contribution guide and vessel templates.

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

## Part of the SuperInstance Fleet

flux-tui is one vessel in the [SuperInstance](https://github.com/SuperInstance) fleet — an ecosystem of AI agent tools, runtimes, and coordination protocols for the FLUX bytecode VM.

| Vessel | Role |
|--------|------|
| [Oracle1](https://github.com/SuperInstance/oracle1-vessel) 🔮 | Lighthouse — fleet coordination, FLUX ecosystem architecture |
| [JetsonClaw1](https://github.com/Lucineer/jetsonclaw1-vessel) ⚡ | Vessel — edge/CUDA runtime, hardware specialization |
| [Babel](https://github.com/SuperInstance/babel-vessel) 🌐 | Scout — multilingual, grammatical analysis |
| [Datum](https://github.com/SuperInstance/super-z-quartermaster) 📋 | Quartermaster — fleet hygiene, auditing, specifications |
| **flux-tui** 🔍 | Debugger — TUI debugging and conformance dashboard |
