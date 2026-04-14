//! FLUX Bytecode Opcodes — Complete ISA Definition
//!
//! Port of flux/bytecode/opcodes.py (122 opcodes).
//! Zig enum with comptime metadata for zero-cost dispatch.
//!
//! Encoding formats:
//!   A: 1 byte  — [opcode]
//!   B: 2 bytes — [opcode][rd]
//!   C: 3 bytes — [opcode][rd][rs1]
//!   D: 4 bytes — [opcode][rs1][off_lo][off_hi]
//!   E: 4 bytes — [opcode][rd][rs1][rs2]
//!   G: variable — [opcode][len:u16][data:len bytes]

const std = @import("std");

/// All 122 FLUX opcodes, organized by functional group.
/// Each variant's value matches the Python `Op(IntEnum)` byte values exactly.
pub const Op = enum(u8) {
    // ── Control flow (0x00-0x07) ────────────────────────────────────────
    NOP           = 0x00,
    MOV           = 0x01,
    LOAD          = 0x02,
    STORE         = 0x03,
    JMP           = 0x04,
    JZ            = 0x05,
    JNZ           = 0x06,
    CALL          = 0x07,

    // ── Integer arithmetic (0x08-0x0F) ─────────────────────────────────
    IADD          = 0x08,
    ISUB          = 0x09,
    IMUL          = 0x0A,
    IDIV          = 0x0B,
    IMOD          = 0x0C,
    INEG          = 0x0D,
    INC           = 0x0E,
    DEC           = 0x0F,

    // ── Bitwise (0x10-0x17) ────────────────────────────────────────────
    IAND          = 0x10,
    IOR           = 0x11,
    IXOR          = 0x12,
    INOT          = 0x13,
    ISHL          = 0x14,
    ISHR          = 0x15,
    ROTL          = 0x16,
    ROTR          = 0x17,

    // ── Comparison (0x18-0x1F) ────────────────────────────────────────
    ICMP          = 0x18,
    IEQ           = 0x19,
    ILT           = 0x1A,
    ILE           = 0x1B,
    IGT           = 0x1C,
    IGE           = 0x1D,
    TEST          = 0x1E,
    SETCC         = 0x1F,

    // ── Stack ops (0x20-0x27) ──────────────────────────────────────────
    PUSH          = 0x20,
    POP           = 0x21,
    DUP           = 0x22,
    SWAP          = 0x23,
    ROT           = 0x24,
    ENTER         = 0x25,
    LEAVE         = 0x26,
    ALLOCA        = 0x27,

    // ── Function ops (0x28-0x2F) ──────────────────────────────────────
    RET           = 0x28,
    CALL_IND      = 0x29,
    TAILCALL      = 0x2A,
    MOVI          = 0x2B,
    IREM          = 0x2C,
    CMP           = 0x2D,
    JE            = 0x2E,
    JNE           = 0x2F,

    // ── Memory management (0x30-0x37) ────────────────────────────────
    REGION_CREATE    = 0x30,
    REGION_DESTROY   = 0x31,
    REGION_TRANSFER  = 0x32,
    MEMCOPY          = 0x33,
    MEMSET           = 0x34,
    MEMCMP           = 0x35,
    JL               = 0x36,
    JGE_op           = 0x37,  // renamed to avoid collision

    // ── Type ops (0x38-0x3F) ─────────────────────────────────────────
    CAST          = 0x38,
    BOX           = 0x39,
    UNBOX         = 0x3A,
    CHECK_TYPE    = 0x3B,
    CHECK_BOUNDS  = 0x3C,
    CONF          = 0x3D,
    MERGE         = 0x3E,
    RESTORE       = 0x3F,

    // ── Float arithmetic (0x40-0x47) ─────────────────────────────────
    FADD          = 0x40,
    FSUB          = 0x41,
    FMUL          = 0x42,
    FDIV          = 0x43,
    FNEG          = 0x44,
    FABS          = 0x45,
    FMIN          = 0x46,
    FMAX          = 0x47,

    // ── Float comparison (0x48-0x4F) ─────────────────────────────────
    FEQ           = 0x48,
    FLT           = 0x49,
    FLE           = 0x4A,
    FGT           = 0x4B,
    FGE           = 0x4C,
    JG            = 0x4D,
    JLE           = 0x4E,
    LOAD8         = 0x4F,

    // ── SIMD vector ops (0x50-0x5F) ──────────────────────────────────
    VLOAD         = 0x50,
    VSTORE        = 0x51,
    VADD          = 0x52,
    VSUB          = 0x53,
    VMUL          = 0x54,
    VDIV          = 0x55,
    VFMA          = 0x56,
    STORE8        = 0x57,

    // ── A2A protocol (0x60-0x7B) ─────────────────────────────────────
    TELL            = 0x60,
    ASK             = 0x61,
    DELEGATE        = 0x62,
    DELEGATE_RESULT = 0x63,
    REPORT_STATUS   = 0x64,
    REQUEST_OVERRIDE = 0x65,
    BROADCAST       = 0x66,
    REDUCE          = 0x67,
    DECLARE_INTENT  = 0x68,
    ASSERT_GOAL     = 0x69,
    VERIFY_OUTCOME  = 0x6A,
    EXPLAIN_FAILURE = 0x6B,
    SET_PRIORITY    = 0x6C,

    // A2A trust & capability (0x70-0x77)
    TRUST_CHECK     = 0x70,
    TRUST_UPDATE    = 0x71,
    TRUST_QUERY     = 0x72,
    REVOKE_TRUST    = 0x73,
    CAP_REQUIRE     = 0x74,
    CAP_REQUEST     = 0x75,
    CAP_GRANT       = 0x76,
    CAP_REVOKE      = 0x77,

    // A2A coordination (0x78-0x7B)
    BARRIER             = 0x78,
    SYNC_CLOCK          = 0x79,
    FORMATION_UPDATE    = 0x7A,
    EMERGENCY_STOP      = 0x7B,

    // ── ISA v3 Agent Evolution (0x7C-0x7F) ──────────────────────────
    EVOLVE        = 0x7C,
    INSTINCT      = 0x7D,
    WITNESS       = 0x7E,
    SNAPSHOT      = 0x7F,

    // ── System (0x80-0x84) ──────────────────────────────────────────
    HALT              = 0x80,
    YIELD             = 0x81,
    RESOURCE_ACQUIRE  = 0x82,
    RESOURCE_RELEASE  = 0x83,
    DEBUG_BREAK       = 0x84,

    UNKNOWN = 0xFF,

    /// Human-readable name for this opcode.
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
            .JGE_op => "JGE",
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
            .UNKNOWN => "UNKNOWN",
        };
    }

    /// Resolve an opcode byte to its enum tag. Returns UNKNOWN for unknown bytes.
    pub fn fromByte(byte: u8) Op {
        return std.meta.intToEnum(Op, byte) catch .UNKNOWN;
    }

    /// Get the human-readable name from a raw opcode byte.
    pub fn nameFromByte(byte: u8) []const u8 {
        return fromByte(byte).name();
    }
};

/// Instruction encoding format classification.
/// Matches the Python FORMAT_A through FORMAT_G frozensets.
pub const Format = enum {
    A,  // 1 byte  — opcode only
    B,  // 2 bytes — opcode + rd:u8
    C,  // 3 bytes — opcode + rd:u8 + rs1:u8
    D,  // 4 bytes — opcode + rs1:u8 + offset:i16
    E,  // 4 bytes — opcode + rd:u8 + rs1:u8 + rs2:u8
    G,  // variable — opcode + len:u16 + data
};

/// Return the encoding format for a given opcode byte.
/// This is the equivalent of Python's get_format() function,
/// but uses comptime for zero runtime cost.
pub fn getFormat(op_byte: u8) Format {
    // Format A: 1 byte — opcode only
    if (op_byte == @intFromEnum(Op.NOP) or op_byte == @intFromEnum(Op.HALT) or
        op_byte == @intFromEnum(Op.YIELD) or op_byte == @intFromEnum(Op.DUP) or
        op_byte == @intFromEnum(Op.SWAP) or op_byte == @intFromEnum(Op.DEBUG_BREAK) or
        op_byte == @intFromEnum(Op.EMERGENCY_STOP) or op_byte == @intFromEnum(Op.UNKNOWN))
        return .A;

    // Format B: 2 bytes — opcode + reg:u8
    if (op_byte == @intFromEnum(Op.INC) or op_byte == @intFromEnum(Op.DEC) or
        op_byte == @intFromEnum(Op.ENTER) or op_byte == @intFromEnum(Op.LEAVE) or
        op_byte == @intFromEnum(Op.PUSH) or op_byte == @intFromEnum(Op.POP) or
        op_byte == @intFromEnum(Op.INEG) or op_byte == @intFromEnum(Op.FNEG) or
        op_byte == @intFromEnum(Op.INOT))
        return .B;

    // Format D: 4 bytes — opcode + reg:u8 + imm16:i16
    if (op_byte == @intFromEnum(Op.JMP) or op_byte == @intFromEnum(Op.JZ) or
        op_byte == @intFromEnum(Op.JNZ) or op_byte == @intFromEnum(Op.JE) or
        op_byte == @intFromEnum(Op.JNE) or op_byte == @intFromEnum(Op.JG) or
        op_byte == @intFromEnum(Op.JL) or op_byte == @intFromEnum(Op.JGE_op) or
        op_byte == @intFromEnum(Op.JLE) or op_byte == @intFromEnum(Op.MOVI) or
        op_byte == @intFromEnum(Op.CALL))
        return .D;

    // Format E: 4 bytes — opcode + rd + rs1 + rs2 (ternary ops)
    if (op_byte == @intFromEnum(Op.VFMA) or
        op_byte == @intFromEnum(Op.IADD) or op_byte == @intFromEnum(Op.ISUB) or
        op_byte == @intFromEnum(Op.IMUL) or op_byte == @intFromEnum(Op.IDIV) or
        op_byte == @intFromEnum(Op.IMOD) or op_byte == @intFromEnum(Op.IREM) or
        op_byte == @intFromEnum(Op.IAND) or op_byte == @intFromEnum(Op.IOR) or
        op_byte == @intFromEnum(Op.IXOR) or op_byte == @intFromEnum(Op.ISHL) or
        op_byte == @intFromEnum(Op.ISHR) or op_byte == @intFromEnum(Op.FADD) or
        op_byte == @intFromEnum(Op.FSUB) or op_byte == @intFromEnum(Op.FMUL) or
        op_byte == @intFromEnum(Op.FDIV))
        return .E;

    // Format G: variable — opcode + len:u16 + data
    if (op_byte == @intFromEnum(Op.REGION_CREATE) or
        op_byte == @intFromEnum(Op.REGION_DESTROY) or
        op_byte == @intFromEnum(Op.REGION_TRANSFER) or
        op_byte == @intFromEnum(Op.MEMCOPY) or
        op_byte == @intFromEnum(Op.MEMSET) or
        op_byte == @intFromEnum(Op.MEMCMP) or
        op_byte >= @intFromEnum(Op.TELL) and op_byte <= @intFromEnum(Op.EMERGENCY_STOP) or
        op_byte == @intFromEnum(Op.RESOURCE_ACQUIRE) or
        op_byte == @intFromEnum(Op.RESOURCE_RELEASE))
        return .G;

    // Default: Format C (3 bytes) — opcode + rd:u8 + rs1:u8
    return .C;
}

/// Return the fixed instruction size in bytes for a format (-1 for variable/G).
pub fn formatSize(fmt: Format) isize {
    return switch (fmt) {
        .A => 1,
        .B => 2,
        .C => 3,
        .D => 4,
        .E => 4,
        .G => -1,
    };
}

/// Functional group classification for an opcode byte.
pub const Category = enum {
    control_flow,
    integer_arithmetic,
    bitwise,
    comparison,
    stack,
    function,
    memory,
    type_op,
    float_arithmetic,
    float_comparison,
    simd,
    a2a,
    evolution,
    system,
    unknown,
};

pub fn getCategory(op_byte: u8) Category {
    return switch (op_byte) {
        0x00...0x07 => .control_flow,
        0x08...0x0F => .integer_arithmetic,
        0x10...0x17 => .bitwise,
        0x18...0x1F => .comparison,
        0x20...0x27 => .stack,
        0x28...0x2F => .function,
        0x30...0x37 => .memory,
        0x38...0x3F => .type_op,
        0x40...0x4F => .float_arithmetic,  // includes float comparison
        0x50...0x57 => .simd,
        0x58...0x5F => .unknown,
        0x60...0x7B => .a2a,
        0x7C...0x7F => .evolution,
        0x80...0xFF => .system,
    };
}

// ── Comptime Tests ────────────────────────────────────────────────────────

test "all 122 opcodes have unique byte values" {
    const expected_count = 122;
    var seen: [256]bool = [_]bool{false} ** 256;
    var count: usize = 0;

    const all_opcodes = std.meta.tags(Op);
    for (all_opcodes) |tag| {
        if (tag == .UNKNOWN) continue;
        const byte_val: u8 = @intFromEnum(tag);
        try std.testing.expect(!seen[byte_val]);
        seen[byte_val] = true;
        count += 1;
    }
    try std.testing.expectEqual(expected_count, count);
}

test "format classification matches Python reference" {
    // Spot-check critical opcodes against the Python FORMAT_* frozensets
    try std.testing.expectEqual(Format.A, getFormat(@intFromEnum(Op.NOP)));
    try std.testing.expectEqual(Format.A, getFormat(@intFromEnum(Op.HALT)));
    try std.testing.expectEqual(Format.A, getFormat(@intFromEnum(Op.DUP)));

    try std.testing.expectEqual(Format.B, getFormat(@intFromEnum(Op.INC)));
    try std.testing.expectEqual(Format.B, getFormat(@intFromEnum(Op.PUSH)));
    try std.testing.expectEqual(Format.B, getFormat(@intFromEnum(Op.INEG)));

    try std.testing.expectEqual(Format.C, getFormat(@intFromEnum(Op.MOV)));
    try std.testing.expectEqual(Format.C, getFormat(@intFromEnum(Op.LOAD)));
    try std.testing.expectEqual(Format.C, getFormat(@intFromEnum(Op.IEQ)));

    try std.testing.expectEqual(Format.D, getFormat(@intFromEnum(Op.JMP)));
    try std.testing.expectEqual(Format.D, getFormat(@intFromEnum(Op.CALL)));
    try std.testing.expectEqual(Format.D, getFormat(@intFromEnum(Op.MOVI)));

    try std.testing.expectEqual(Format.E, getFormat(@intFromEnum(Op.IADD)));
    try std.testing.expectEqual(Format.E, getFormat(@intFromEnum(Op.FADD)));

    try std.testing.expectEqual(Format.G, getFormat(@intFromEnum(Op.REGION_CREATE)));
    try std.testing.expectEqual(Format.G, getFormat(@intFromEnum(Op.TELL)));
}

test "format sizes are correct" {
    try std.testing.expectEqual(@as(isize, 1), formatSize(.A));
    try std.testing.expectEqual(@as(isize, 2), formatSize(.B));
    try std.testing.expectEqual(@as(isize, 3), formatSize(.C));
    try std.testing.expectEqual(@as(isize, 4), formatSize(.D));
    try std.testing.expectEqual(@as(isize, 4), formatSize(.E));
    try std.testing.expectEqual(@as(isize, -1), formatSize(.G));
}

test "opcode names match expected strings" {
    try std.testing.expectEqualStrings("NOP", Op.NOP.name());
    try std.testing.expectEqualStrings("HALT", Op.HALT.name());
    try std.testing.expectEqualStrings("IADD", Op.IADD.name());
    try std.testing.expectEqualStrings("REGION_CREATE", Op.REGION_CREATE.name());
    try std.testing.expectEqualStrings("EMERGENCY_STOP", Op.EMERGENCY_STOP.name());
}

test "categories cover all opcode ranges" {
    try std.testing.expectEqual(Category.control_flow, getCategory(0x00));
    try std.testing.expectEqual(Category.control_flow, getCategory(0x07));
    try std.testing.expectEqual(Category.integer_arithmetic, getCategory(0x0F));
    try std.testing.expectEqual(Category.bitwise, getCategory(0x17));
    try std.testing.expectEqual(Category.comparison, getCategory(0x1F));
    try std.testing.expectEqual(Category.stack, getCategory(0x27));
    try std.testing.expectEqual(Category.function, getCategory(0x2F));
    try std.testing.expectEqual(Category.memory, getCategory(0x37));
    try std.testing.expectEqual(Category.type_op, getCategory(0x3F));
    try std.testing.expectEqual(Category.float_arithmetic, getCategory(0x47));
    try std.testing.expectEqual(Category.simd, getCategory(0x57));
    try std.testing.expectEqual(Category.a2a, getCategory(0x7B));
    try std.testing.expectEqual(Category.evolution, getCategory(0x7F));
    try std.testing.expectEqual(Category.system, getCategory(0x84));
}
