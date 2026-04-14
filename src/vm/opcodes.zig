//! FLUX Bytecode Opcodes — Complete ISA Definition
//!
//! Defines all 122 opcodes for the FLUX Micro-VM, organized into functional
//! groups with comptime format classification for the fetch-decode pipeline.
//!
//! Instruction encoding formats:
//!   Format A (1 byte):   [opcode]
//!   Format B (2 bytes):  [opcode][reg:u8]
//!   Format C (3 bytes):  [opcode][rd:u8][rs1:u8]
//!   Format D (4 bytes):  [opcode][rs1:u8][off_lo:u8][off_hi:u8]  (i16 offset)
//!   Format E (4 bytes):  [opcode][rd:u8][rs1:u8][rs2:u8]
//!   Format G (variable): [opcode][len:u16][data:len bytes]

const std = @import("std");

/// FLUX opcode enum — covers the full 0x00–0x9F address space.
/// Values match the Python `Op` IntEnum exactly for bytecode compatibility.
pub const Op = enum(u8) {
    // ═══════════════════════════════════════════════════════════
    // Control flow (0x00-0x07)
    // ═══════════════════════════════════════════════════════════
    NOP   = 0x00,
    MOV   = 0x01,
    LOAD  = 0x02,
    STORE = 0x03,
    JMP   = 0x04,
    JZ    = 0x05,
    JNZ   = 0x06,
    CALL  = 0x07,

    // ═══════════════════════════════════════════════════════════
    // Integer arithmetic (0x08-0x0F)
    // ═══════════════════════════════════════════════════════════
    IADD = 0x08,
    ISUB = 0x09,
    IMUL = 0x0A,
    IDIV = 0x0B,
    IMOD = 0x0C,
    INEG = 0x0D,
    INC  = 0x0E,
    DEC  = 0x0F,

    // ═══════════════════════════════════════════════════════════
    // Bitwise (0x10-0x17)
    // ═══════════════════════════════════════════════════════════
    IAND = 0x10,
    IOR  = 0x11,
    IXOR = 0x12,
    INOT = 0x13,
    ISHL = 0x14,
    ISHR = 0x15,
    ROTL = 0x16,
    ROTR = 0x17,

    // ═══════════════════════════════════════════════════════════
    // Comparison (0x18-0x1F)
    // ═══════════════════════════════════════════════════════════
    ICMP  = 0x18,
    IEQ   = 0x19,
    ILT   = 0x1A,
    ILE   = 0x1B,
    IGT   = 0x1C,
    IGE   = 0x1D,
    TEST  = 0x1E,
    SETCC = 0x1F,

    // ═══════════════════════════════════════════════════════════
    // Stack ops (0x20-0x27)
    // ═══════════════════════════════════════════════════════════
    PUSH   = 0x20,
    POP    = 0x21,
    DUP    = 0x22,
    SWAP   = 0x23,
    ROT    = 0x24,
    ENTER  = 0x25,
    LEAVE  = 0x26,
    ALLOCA = 0x27,

    // ═══════════════════════════════════════════════════════════
    // Function ops (0x28-0x2F)
    // ═══════════════════════════════════════════════════════════
    RET       = 0x28,
    CALL_IND  = 0x29,
    TAILCALL  = 0x2A,
    MOVI      = 0x2B,
    IREM      = 0x2C,
    CMP       = 0x2D,
    JE        = 0x2E,
    JNE       = 0x2F,

    // ═══════════════════════════════════════════════════════════
    // Memory mgmt (0x30-0x37)
    // ═══════════════════════════════════════════════════════════
    REGION_CREATE  = 0x30,
    REGION_DESTROY = 0x31,
    REGION_TRANSFER = 0x32,
    MEMCOPY        = 0x33,
    MEMSET         = 0x34,
    MEMCMP         = 0x35,
    JL             = 0x36,
    JGE_fmt        = 0x37,

    // ═══════════════════════════════════════════════════════════
    // Type ops (0x38-0x3F)
    // ═══════════════════════════════════════════════════════════
    CAST         = 0x38,
    BOX          = 0x39,
    UNBOX        = 0x3A,
    CHECK_TYPE   = 0x3B,
    CHECK_BOUNDS = 0x3C,
    CONF         = 0x3D,
    MERGE        = 0x3E,
    RESTORE      = 0x3F,

    // ═══════════════════════════════════════════════════════════
    // Float arithmetic (0x40-0x47)
    // ═══════════════════════════════════════════════════════════
    FADD = 0x40,
    FSUB = 0x41,
    FMUL = 0x42,
    FDIV = 0x43,
    FNEG = 0x44,
    FABS = 0x45,
    FMIN = 0x46,
    FMAX = 0x47,

    // ═══════════════════════════════════════════════════════════
    // Float comparison (0x48-0x4F)
    // ═══════════════════════════════════════════════════════════
    FEQ    = 0x48,
    FLT    = 0x49,
    FLE    = 0x4A,
    FGT    = 0x4B,
    FGE    = 0x4C,
    JG     = 0x4D,
    JLE    = 0x4E,
    LOAD8  = 0x4F,

    // ═══════════════════════════════════════════════════════════
    // SIMD vector ops (0x50-0x5F)
    // ═══════════════════════════════════════════════════════════
    VLOAD  = 0x50,
    VSTORE = 0x51,
    VADD   = 0x52,
    VSUB   = 0x53,
    VMUL   = 0x54,
    VDIV   = 0x55,
    VFMA   = 0x56,
    STORE8 = 0x57,

    // ═══════════════════════════════════════════════════════════
    // A2A protocol (0x60-0x7F)
    // ═══════════════════════════════════════════════════════════
    TELL              = 0x60,
    ASK               = 0x61,
    DELEGATE          = 0x62,
    DELEGATE_RESULT   = 0x63,
    REPORT_STATUS     = 0x64,
    REQUEST_OVERRIDE  = 0x65,
    BROADCAST         = 0x66,
    REDUCE            = 0x67,
    DECLARE_INTENT    = 0x68,
    ASSERT_GOAL       = 0x69,
    VERIFY_OUTCOME    = 0x6A,
    EXPLAIN_FAILURE   = 0x6B,
    SET_PRIORITY      = 0x6C,
    TRUST_CHECK       = 0x70,
    TRUST_UPDATE      = 0x71,
    TRUST_QUERY       = 0x72,
    REVOKE_TRUST      = 0x73,
    CAP_REQUIRE       = 0x74,
    CAP_REQUEST       = 0x75,
    CAP_GRANT         = 0x76,
    CAP_REVOKE        = 0x77,
    BARRIER           = 0x78,
    SYNC_CLOCK        = 0x79,
    FORMATION_UPDATE  = 0x7A,
    EMERGENCY_STOP    = 0x7B,

    // ═══════════════════════════════════════════════════════════
    // ISA v3 — Agent Evolution & Instinct (0x7C-0x7F)
    // ═══════════════════════════════════════════════════════════
    EVOLVE   = 0x7C,
    INSTINCT = 0x7D,
    WITNESS  = 0x7E,
    SNAPSHOT = 0x7F,

    // ═══════════════════════════════════════════════════════════
    // System (0x80-0x9F)
    // ═══════════════════════════════════════════════════════════
    HALT              = 0x80,
    YIELD             = 0x81,
    RESOURCE_ACQUIRE  = 0x82,
    RESOURCE_RELEASE  = 0x83,
    DEBUG_BREAK       = 0x84,

    /// Catch-all for unknown opcode bytes
    unknown,

    // ── Comptime helpers ──────────────────────────────────────────

    /// Instruction encoding format for this opcode.
    pub const Format = enum { A, B, C, D, E, G };

    /// Returns the encoding format for a given opcode value at comptime.
    /// This is the Zig equivalent of the Python `get_format()` function.
    pub fn format(self: Op) Format {
        return switch (self) {
            // Format A: 1 byte — opcode only
            .NOP, .HALT, .YIELD, .DUP, .SWAP, .DEBUG_BREAK, .EMERGENCY_STOP => .A,

            // Format B: 2 bytes — opcode + reg:u8
            .INC, .DEC, .ENTER, .LEAVE, .PUSH, .POP, .INEG, .FNEG => .B,

            // Format D: 4 bytes — opcode + reg:u8 + imm16:i16
            .JMP, .JZ, .JNZ, .JE, .JNE, .JG, .JL, .JGE_fmt, .JLE,
            .MOVI, .CALL, .TAILCALL => .D,

            // Format E: 4 bytes — opcode + rd:u8 + rs1:u8 + rs2:u8
            .VFMA,
            .IADD, .ISUB, .IMUL, .IDIV, .IMOD, .IREM,
            .IAND, .IOR, .IXOR, .ISHL, .ISHR,
            .FADD, .FSUB, .FMUL, .FDIV => .E,

            // Format G: variable — opcode + len:u16 + data:len bytes
            .REGION_CREATE, .REGION_DESTROY, .REGION_TRANSFER,
            .MEMCOPY, .MEMSET, .MEMCMP,
            .TELL, .ASK, .DELEGATE, .DELEGATE_RESULT,
            .REPORT_STATUS, .REQUEST_OVERRIDE, .BROADCAST, .REDUCE,
            .DECLARE_INTENT, .ASSERT_GOAL, .VERIFY_OUTCOME,
            .EXPLAIN_FAILURE, .SET_PRIORITY,
            .TRUST_CHECK, .TRUST_UPDATE, .TRUST_QUERY, .REVOKE_TRUST,
            .CAP_REQUIRE, .CAP_REQUEST, .CAP_GRANT, .CAP_REVOKE,
            .BARRIER, .SYNC_CLOCK, .FORMATION_UPDATE,
            .RESOURCE_ACQUIRE, .RESOURCE_RELEASE => .G,

            // Everything else defaults to Format C: 3 bytes
            else => .C,
        };
    }

    /// Returns the fixed instruction size in bytes, or null for variable-length (Format G).
    pub fn instructionSize(self: Op) ?usize {
        return switch (self.format()) {
            .A => @as(usize, 1),
            .B => @as(usize, 2),
            .C => @as(usize, 3),
            .D => @as(usize, 4),
            .E => @as(usize, 4),
            .G => null,
        };
    }

    /// Human-readable name for an opcode (for disassembly / error messages).
    pub fn name(self: Op) []const u8 {
        return switch (self) {
            .NOP => "NOP",
            .MOV => "MOV",
            .LOAD => "LOAD",
            .STORE => "STORE",
            .JMP => "JMP",
            .JZ => "JZ",
            .JNZ => "JNZ",
            .CALL => "CALL",
            .IADD => "IADD",
            .ISUB => "ISUB",
            .IMUL => "IMUL",
            .IDIV => "IDIV",
            .IMOD => "IMOD",
            .INEG => "INEG",
            .INC => "INC",
            .DEC => "DEC",
            .IAND => "IAND",
            .IOR => "IOR",
            .IXOR => "IXOR",
            .INOT => "INOT",
            .ISHL => "ISHL",
            .ISHR => "ISHR",
            .ROTL => "ROTL",
            .ROTR => "ROTR",
            .ICMP => "ICMP",
            .IEQ => "IEQ",
            .ILT => "ILT",
            .ILE => "ILE",
            .IGT => "IGT",
            .IGE => "IGE",
            .TEST => "TEST",
            .SETCC => "SETCC",
            .PUSH => "PUSH",
            .POP => "POP",
            .DUP => "DUP",
            .SWAP => "SWAP",
            .ROT => "ROT",
            .ENTER => "ENTER",
            .LEAVE => "LEAVE",
            .ALLOCA => "ALLOCA",
            .RET => "RET",
            .CALL_IND => "CALL_IND",
            .TAILCALL => "TAILCALL",
            .MOVI => "MOVI",
            .IREM => "IREM",
            .CMP => "CMP",
            .JE => "JE",
            .JNE => "JNE",
            .REGION_CREATE => "REGION_CREATE",
            .REGION_DESTROY => "REGION_DESTROY",
            .REGION_TRANSFER => "REGION_TRANSFER",
            .MEMCOPY => "MEMCOPY",
            .MEMSET => "MEMSET",
            .MEMCMP => "MEMCMP",
            .JL => "JL",
            .JGE_fmt => "JGE",
            .CAST => "CAST",
            .BOX => "BOX",
            .UNBOX => "UNBOX",
            .CHECK_TYPE => "CHECK_TYPE",
            .CHECK_BOUNDS => "CHECK_BOUNDS",
            .CONF => "CONF",
            .MERGE => "MERGE",
            .RESTORE => "RESTORE",
            .FADD => "FADD",
            .FSUB => "FSUB",
            .FMUL => "FMUL",
            .FDIV => "FDIV",
            .FNEG => "FNEG",
            .FABS => "FABS",
            .FMIN => "FMIN",
            .FMAX => "FMAX",
            .FEQ => "FEQ",
            .FLT => "FLT",
            .FLE => "FLE",
            .FGT => "FGT",
            .FGE => "FGE",
            .JG => "JG",
            .JLE => "JLE",
            .LOAD8 => "LOAD8",
            .VLOAD => "VLOAD",
            .VSTORE => "VSTORE",
            .VADD => "VADD",
            .VSUB => "VSUB",
            .VMUL => "VMUL",
            .VDIV => "VDIV",
            .VFMA => "VFMA",
            .STORE8 => "STORE8",
            .TELL => "TELL",
            .ASK => "ASK",
            .DELEGATE => "DELEGATE",
            .DELEGATE_RESULT => "DELEGATE_RESULT",
            .REPORT_STATUS => "REPORT_STATUS",
            .REQUEST_OVERRIDE => "REQUEST_OVERRIDE",
            .BROADCAST => "BROADCAST",
            .REDUCE => "REDUCE",
            .DECLARE_INTENT => "DECLARE_INTENT",
            .ASSERT_GOAL => "ASSERT_GOAL",
            .VERIFY_OUTCOME => "VERIFY_OUTCOME",
            .EXPLAIN_FAILURE => "EXPLAIN_FAILURE",
            .SET_PRIORITY => "SET_PRIORITY",
            .TRUST_CHECK => "TRUST_CHECK",
            .TRUST_UPDATE => "TRUST_UPDATE",
            .TRUST_QUERY => "TRUST_QUERY",
            .REVOKE_TRUST => "REVOKE_TRUST",
            .CAP_REQUIRE => "CAP_REQUIRE",
            .CAP_REQUEST => "CAP_REQUEST",
            .CAP_GRANT => "CAP_GRANT",
            .CAP_REVOKE => "CAP_REVOKE",
            .BARRIER => "BARRIER",
            .SYNC_CLOCK => "SYNC_CLOCK",
            .FORMATION_UPDATE => "FORMATION_UPDATE",
            .EMERGENCY_STOP => "EMERGENCY_STOP",
            .EVOLVE => "EVOLVE",
            .INSTINCT => "INSTINCT",
            .WITNESS => "WITNESS",
            .SNAPSHOT => "SNAPSHOT",
            .HALT => "HALT",
            .YIELD => "YIELD",
            .RESOURCE_ACQUIRE => "RESOURCE_ACQUIRE",
            .RESOURCE_RELEASE => "RESOURCE_RELEASE",
            .DEBUG_BREAK => "DEBUG_BREAK",
            .unknown => "UNKNOWN",
        };
    }

    /// Check if this opcode belongs to the A2A protocol range (0x60-0x7F).
    pub fn isA2A(self: Op) bool {
        const byte: u8 = @intFromEnum(self);
        return byte >= 0x60 and byte <= 0x7F;
    }
};

// ═══════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════

test "opcode values match Python source" {
    // Spot-check critical opcodes for byte-level compatibility
    try std.testing.expectEqual(@as(u8, 0x00), @intFromEnum(Op.NOP));
    try std.testing.expectEqual(@as(u8, 0x01), @intFromEnum(Op.MOV));
    try std.testing.expectEqual(@as(u8, 0x07), @intFromEnum(Op.CALL));
    try std.testing.expectEqual(@as(u8, 0x08), @intFromEnum(Op.IADD));
    try std.testing.expectEqual(@as(u8, 0x2B), @intFromEnum(Op.MOVI));
    try std.testing.expectEqual(@as(u8, 0x2D), @intFromEnum(Op.CMP));
    try std.testing.expectEqual(@as(u8, 0x60), @intFromEnum(Op.TELL));
    try std.testing.expectEqual(@as(u8, 0x7C), @intFromEnum(Op.EVOLVE));
    try std.testing.expectEqual(@as(u8, 0x80), @intFromEnum(Op.HALT));
}

test "format classification — Format A" {
    try std.testing.expectEqual(Op.Format.A, Op.NOP.format());
    try std.testing.expectEqual(Op.Format.A, Op.HALT.format());
    try std.testing.expectEqual(Op.Format.A, Op.DUP.format());
    try std.testing.expectEqual(Op.Format.A, Op.SWAP.format());
    try std.testing.expectEqual(Op.Format.A, Op.YIELD.format());
}

test "format classification — Format B" {
    try std.testing.expectEqual(Op.Format.B, Op.INC.format());
    try std.testing.expectEqual(Op.Format.B, Op.DEC.format());
    try std.testing.expectEqual(Op.Format.B, Op.PUSH.format());
    try std.testing.expectEqual(Op.Format.B, Op.POP.format());
    try std.testing.expectEqual(Op.Format.B, Op.INEG.format());
    try std.testing.expectEqual(Op.Format.B, Op.FNEG.format());
}

test "format classification — Format C" {
    try std.testing.expectEqual(Op.Format.C, Op.MOV.format());
    try std.testing.expectEqual(Op.Format.C, Op.LOAD.format());
    try std.testing.expectEqual(Op.Format.C, Op.STORE.format());
    try std.testing.expectEqual(Op.Format.C, Op.IEQ.format());
    try std.testing.expectEqual(Op.Format.C, Op.RET.format());
}

test "format classification — Format D" {
    try std.testing.expectEqual(Op.Format.D, Op.JMP.format());
    try std.testing.expectEqual(Op.Format.D, Op.JZ.format());
    try std.testing.expectEqual(Op.Format.D, Op.JNZ.format());
    try std.testing.expectEqual(Op.Format.D, Op.JE.format());
    try std.testing.expectEqual(Op.Format.D, Op.MOVI.format());
    try std.testing.expectEqual(Op.Format.D, Op.CALL.format());
}

test "format classification — Format E" {
    try std.testing.expectEqual(Op.Format.E, Op.IADD.format());
    try std.testing.expectEqual(Op.Format.E, Op.IMUL.format());
    try std.testing.expectEqual(Op.Format.E, Op.VFMA.format());
    try std.testing.expectEqual(Op.Format.E, Op.FADD.format());
}

test "format classification — Format G (variable)" {
    try std.testing.expectEqual(Op.Format.G, Op.TELL.format());
    try std.testing.expectEqual(Op.Format.G, Op.REGION_CREATE.format());
    try std.testing.expectEqual(Op.Format.G, Op.MEMCOPY.format());
    try std.testing.expectEqual(Op.Format.G, Op.RESOURCE_ACQUIRE.format());
}

test "instruction size" {
    try std.testing.expectEqual(@as(?usize, 1), Op.NOP.instructionSize());
    try std.testing.expectEqual(@as(?usize, 2), Op.PUSH.instructionSize());
    try std.testing.expectEqual(@as(?usize, 3), Op.MOV.instructionSize());
    try std.testing.expectEqual(@as(?usize, 4), Op.IADD.instructionSize());
    try std.testing.expectEqual(@as(?usize, 4), Op.MOVI.instructionSize());
    try std.testing.expectEqual(@as(?usize, null), Op.TELL.instructionSize());
}

test "A2A range detection" {
    try std.testing.expect(Op.TELL.isA2A());
    try std.testing.expect(Op.ASK.isA2A());
    try std.testing.expect(Op.DELEGATE.isA2A());
    try std.testing.expect(Op.EMERGENCY_STOP.isA2A());
    try std.testing.expect(!Op.NOP.isA2A());
    try std.testing.expect(!Op.IADD.isA2A());
    try std.testing.expect(!Op.HALT.isA2A());
}

test "opcode name strings" {
    try std.testing.expectEqualStrings("NOP", Op.NOP.name());
    try std.testing.expectEqualStrings("IADD", Op.IADD.name());
    try std.testing.expectEqualStrings("HALT", Op.HALT.name());
    try std.testing.expectEqualStrings("REGION_CREATE", Op.REGION_CREATE.name());
    try std.testing.expectEqualStrings("UNKNOWN", Op.unknown.name());
}
