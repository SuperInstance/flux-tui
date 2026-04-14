//! FLUX VM Core Library
//!
//! A faithful Zig port of the Python flux-runtime VM:
//! - 122 opcodes across 7 encoding formats (A-G)
//! - 64-register file (16 GP, 16 FP, 16 VEC)
//! - Capability-based linear region memory
//! - Fetch-decode-execute interpreter loop
//!
//! ISA Reference: SuperInstance/flux-runtime/src/flux/bytecode/opcodes.py

pub const opcodes = @import("opcodes.zig");
pub const registers = @import("registers.zig");
pub const memory = @import("memory.zig");
pub const interpreter = @import("interpreter.zig");
pub const decoder = @import("decoder.zig");

test {
    _ = opcodes;
    _ = registers;
    _ = memory;
    _ = interpreter;
    _ = decoder;
}
