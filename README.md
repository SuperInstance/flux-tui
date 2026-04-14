# flux-tui

Standalone FLUX Micro-VM runtime written in Zig. Faithful port of `flux-runtime` (Python) to a single static binary.

## ISA v3 — 102 Opcodes

| Category | Range | Count |
|----------|-------|-------|
| Control flow | 0x00–0x07 | 8 |
| Integer arithmetic | 0x08–0x0F | 8 |
| Bitwise | 0x10–0x17 | 8 |
| Comparison | 0x18–0x1F | 8 |
| Stack ops | 0x20–0x27 | 8 |
| Function ops | 0x28–0x2F | 8 |
| Memory mgmt | 0x30–0x37 | 8 |
| Type ops | 0x38–0x3F | 8 |
| Float arithmetic | 0x40–0x47 | 8 |
| Float comparison | 0x48–0x4F | 8 |
| SIMD vector | 0x50–0x57 | 8 |
| A2A protocol | 0x60–0x7B | 24 |
| Agent evolution | 0x7C–0x7F | 4 |
| System | 0x80–0x84 | 5 |

## Architecture

- **64-register file**: R0-R15 (GP/i32), F0-F15 (float), V0-V15 (SIMD/128-bit)
- **Linear region memory**: capability-based, up to 256 named regions
- **6 encoding formats**: A(1B), B(2B), C(3B), D(4B), E(4B), G(variable)
- **Zero dependencies**: pure Zig, no GC, no runtime

## Build

```bash
zig build          # Build release
zig build test     # Run tests (15 tests)
zig build run      # Run with args
```

## Usage

```bash
flux-tui run <bytecode.bin>       # Execute FLUX bytecode
flux-tui disasm <bytecode.bin>    # Disassemble
flux-tui version                  # Print ISA info
```

## Source Map

```
src/flux/bytecode/opcodes.zig   — 102 opcodes, comptime format/category dispatch
src/flux/vm/registers.zig      — 64-register file (GP, FP, VEC)
src/flux/vm/memory.zig         — Linear region memory manager
src/flux/vm/interpreter.zig    — Fetch-decode-execute loop, all opcodes
src/main.zig                   — CLI entry point, disassembler
```
