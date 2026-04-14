//! FLUX Bytecode ISA — Complete opcode definitions with comptime metadata.
//!
//! Ported from flux-runtime/src/flux/bytecode/opcodes.py
//! 122 opcodes across 9 functional categories, 6 encoding formats.

const std = @import("std");

// ━━━ Instruction Encoding Formats ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Format A (1 byte):  [opcode]
// Format B (2 bytes): [opcode][reg:u8]
// Format C (3 bytes): [opcode][rd:u8][rs1:u8]
// Format D (4 bytes): [opcode][rs1:u8][off_lo:u8][off_hi:u8]  (signed i16)
// Format E (4 bytes): [opcode][rd:u8][rs1:u8][rs2:u8]
// Format G (variable):[opcode][len:u16_le][data:len bytes]

pub const Format = enum(u3) {
    A = 0, // 1 byte:   opcode only
    B = 1, // 2 bytes:  opcode + reg
    C = 2, // 3 bytes:  opcode + rd + rs1
    D = 3, // 4 bytes:  opcode + reg + i16 offset
    E = 4, // 4 bytes:  opcode + rd + rs1 + rs2
    G = 5, // variable: opcode + u16 len + data
};

// ━━━ Opcode Categories ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub const Category = enum(u4) {
    control = 0,
    int_arith = 1,
    bitwise = 2,
    comparison = 3,
    stack = 4,
    function = 5,
    memory = 6,
    type_op = 7,
    float_arith = 8,
    float_cmp = 9,
    simd = 10,
    a2a = 11,
    system = 12,
    meta = 13,
};

// ━━━ Complete Opcode Enumeration ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub const Opcode = enum(u8) {
    // ── Control flow (0x00-0x07) ───────────────────────────────────────
    NOP = 0x00,
    MOV = 0x01,
    LOAD = 0x02,
    STORE = 0x03,
    JMP = 0x04,
    JZ = 0x05,
    JNZ = 0x06,
    CALL = 0x07,

    // ── Integer arithmetic (0x08-0x0F) ─────────────────────────────────
    IADD = 0x08,
    ISUB = 0x09,
    IMUL = 0x0A,
    IDIV = 0x0B,
    IMOD = 0x0C,
    INEG = 0x0D,
    INC = 0x0E,
    DEC = 0x0F,

    // ── Bitwise (0x10-0x17) ────────────────────────────────────────────
    IAND = 0x10,
    IOR = 0x11,
    IXOR = 0x12,
    INOT = 0x13,
    ISHL = 0x14,
    ISHR = 0x15,
    ROTL = 0x16,
    ROTR = 0x17,

    // ── Comparison (0x18-0x1F) ─────────────────────────────────────────
    ICMP = 0x18,
    IEQ = 0x19,
    ILT = 0x1A,
    ILE = 0x1B,
    IGT = 0x1C,
    IGE = 0x1D,
    TEST = 0x1E,
    SETCC = 0x1F,

    // ── Stack ops (0x20-0x27) ──────────────────────────────────────────
    PUSH = 0x20,
    POP = 0x21,
    DUP = 0x22,
    SWAP = 0x23,
    ROT = 0x24,
    ENTER = 0x25,
    LEAVE = 0x26,
    ALLOCA = 0x27,

    // ── Function ops (0x28-0x2F) ───────────────────────────────────────
    RET = 0x28,
    CALL_IND = 0x29,
    TAILCALL = 0x2A,
    MOVI = 0x2B,
    IREM = 0x2C,
    CMP = 0x2D,
    JE = 0x2E,
    JNE = 0x2F,

    // ── Memory management (0x30-0x37) ──────────────────────────────────
    REGION_CREATE = 0x30,
    REGION_DESTROY = 0x31,
    REGION_TRANSFER = 0x32,
    MEMCOPY = 0x33,
    MEMSET = 0x34,
    MEMCMP = 0x35,
    JL = 0x36,
    JGE = 0x37,

    // ── Type ops (0x38-0x3F) ───────────────────────────────────────────
    CAST = 0x38,
    BOX = 0x39,
    UNBOX = 0x3A,
    CHECK_TYPE = 0x3B,
    CHECK_BOUNDS = 0x3C,
    CONF = 0x3D,
    MERGE = 0x3E,
    RESTORE = 0x3F,

    // ── Float arithmetic (0x40-0x47) ───────────────────────────────────
    FADD = 0x40,
    FSUB = 0x41,
    FMUL = 0x42,
    FDIV = 0x43,
    FNEG = 0x44,
    FABS = 0x45,
    FMIN = 0x46,
    FMAX = 0x47,

    // ── Float comparison (0x48-0x4F) ───────────────────────────────────
    FEQ = 0x48,
    FLT = 0x49,
    FLE = 0x4A,
    FGT = 0x4B,
    FGE = 0x4C,
    JG = 0x4D,
    JLE = 0x4E,
    LOAD8 = 0x4F,

    // ── SIMD vector ops (0x50-0x5F) ───────────────────────────────────
    VLOAD = 0x50,
    VSTORE = 0x51,
    VADD = 0x52,
    VSUB = 0x53,
    VMUL = 0x54,
    VDIV = 0x55,
    VFMA = 0x56,
    STORE8 = 0x57,

    // ── A2A protocol (0x60-0x7F) ──────────────────────────────────────
    TELL = 0x60,
    ASK = 0x61,
    DELEGATE = 0x62,
    DELEGATE_RESULT = 0x63,
    REPORT_STATUS = 0x64,
    REQUEST_OVERRIDE = 0x65,
    BROADCAST = 0x66,
    REDUCE = 0x67,
    DECLARE_INTENT = 0x68,
    ASSERT_GOAL = 0x69,
    VERIFY_OUTCOME = 0x6A,
    EXPLAIN_FAILURE = 0x6B,
    SET_PRIORITY = 0x6C,
    TRUST_CHECK = 0x70,
    TRUST_UPDATE = 0x71,
    TRUST_QUERY = 0x72,
    REVOKE_TRUST = 0x73,
    CAP_REQUIRE = 0x74,
    CAP_REQUEST = 0x75,
    CAP_GRANT = 0x76,
    CAP_REVOKE = 0x77,
    BARRIER = 0x78,
    SYNC_CLOCK = 0x79,
    FORMATION_UPDATE = 0x7A,
    EMERGENCY_STOP = 0x7B,

    // ── ISA v3 — Agent Evolution & Instinct (0x7C-0x7F) ───────────────
    EVOLVE = 0x7C,
    INSTINCT = 0x7D,
    WITNESS = 0x7E,
    SNAPSHOT = 0x7F,

    // ── System (0x80-0x9F) ─────────────────────────────────────────────
    HALT = 0x80,
    YIELD = 0x81,
    RESOURCE_ACQUIRE = 0x82,
    RESOURCE_RELEASE = 0x83,
    DEBUG_BREAK = 0x84,

    _,

    // ── Comptime metadata ──────────────────────────────────────────────
    pub fn format(self: Opcode) Format {
        return switch (self) {
            // Format A: opcode only
            .NOP, .HALT, .YIELD, .DUP, .SWAP, .DEBUG_BREAK, .EMERGENCY_STOP => .A,
            // Format B: opcode + reg
            .INC, .DEC, .ENTER, .LEAVE, .PUSH, .POP, .INEG, .FNEG, .INOT, .FABS, .FMIN, .FMAX => .B,
            // Format D: opcode + reg + i16 offset
            .JMP, .JZ, .JNZ, .JE, .JNE, .JG, .JL, .JGE, .JLE, .MOVI, .CALL, .TAILCALL => .D,
            // Format E: opcode + rd + rs1 + rs2
            .VFMA,
            .IADD, .ISUB, .IMUL, .IDIV, .IMOD, .IREM,
            .IAND, .IOR, .IXOR, .ISHL, .ISHR, .ROTL, .ROTR,
            .FADD, .FSUB, .FMUL, .FDIV,
            .VADD, .VSUB, .VMUL, .VDIV => .E,
            // Format G: variable-length
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
            // Default: Format C (opcode + rd + rs1)
            else => .C,
        };
    }

    pub fn category(self: Opcode) Category {
        return switch (self) {
            .NOP, .MOV, .JMP, .JZ, .JNZ, .CALL, .JE, .JNE, .JG, .JL, .JGE, .JLE => .control,
            .IADD, .ISUB, .IMUL, .IDIV, .IMOD, .IREM, .INEG, .INC, .DEC, .MOVI => .int_arith,
            .IAND, .IOR, .IXOR, .INOT, .ISHL, .ISHR, .ROTL, .ROTR => .bitwise,
            .ICMP, .IEQ, .ILT, .ILE, .IGT, .IGE, .TEST, .SETCC, .CMP => .comparison,
            .PUSH, .POP, .DUP, .SWAP, .ROT, .ENTER, .LEAVE, .ALLOCA => .stack,
            .RET, .CALL_IND, .TAILCALL => .function,
            .LOAD, .STORE, .LOAD8, .STORE8,
            .REGION_CREATE, .REGION_DESTROY, .REGION_TRANSFER,
            .MEMCOPY, .MEMSET, .MEMCMP => .memory,
            .CAST, .BOX, .UNBOX, .CHECK_TYPE, .CHECK_BOUNDS => .type_op,
            .FADD, .FSUB, .FMUL, .FDIV, .FNEG, .FABS, .FMIN, .FMAX => .float_arith,
            .FEQ, .FLT, .FLE, .FGT, .FGE => .float_cmp,
            .VLOAD, .VSTORE, .VADD, .VSUB, .VMUL, .VDIV, .VFMA => .simd,
            .TELL, .ASK, .DELEGATE, .DELEGATE_RESULT,
            .REPORT_STATUS, .REQUEST_OVERRIDE, .BROADCAST, .REDUCE,
            .DECLARE_INTENT, .ASSERT_GOAL, .VERIFY_OUTCOME,
            .EXPLAIN_FAILURE, .SET_PRIORITY,
            .TRUST_CHECK, .TRUST_UPDATE, .TRUST_QUERY, .REVOKE_TRUST,
            .CAP_REQUIRE, .CAP_REQUEST, .CAP_GRANT, .CAP_REVOKE,
            .BARRIER, .SYNC_CLOCK, .FORMATION_UPDATE,
            .EMERGENCY_STOP => .a2a,
            .HALT, .YIELD, .RESOURCE_ACQUIRE, .RESOURCE_RELEASE, .DEBUG_BREAK => .system,
            .EVOLVE, .INSTINCT, .WITNESS, .SNAPSHOT, .CONF, .MERGE, .RESTORE => .meta,
            else => .control,
        };
    }

    /// Human-readable mnemonic string.
    pub fn name(self: Opcode) []const u8 {
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
            .JGE => "JGE",
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
            else => "UNKNOWN",
        };
    }

    /// Return the fixed instruction size in bytes, or -1 for variable-length (Format G).
    pub fn instructionSize(self: Opcode) i32 {
        return switch (self.format()) {
            .A => 1,
            .B => 2,
            .C => 3,
            .D => 4,
            .E => 4,
            .G => -1,
        };
    }
};

// ━━━ Comptime Validation ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Total number of defined opcodes (not counting the `_` catch-all).
pub const opcode_count = blk: {
    var count: usize = 0;
    for (std.meta.fields(Opcode)) |f| {
        if (!std.mem.eql(u8, f.name, "_")) count += 1;
    }
    break :blk count;
};

test "opcode count matches Python source (102 defined)" {
    // 102 explicitly defined opcodes in the Python source (some gap bytes
    // like 0x6D-0x6F are unused, and 0x58-0x5F are partially unused).
    try std.testing.expectEqual(@as(usize, 102), opcode_count);
}

test "format classification consistency" {
    const all_formats = [_]Format{ .A, .B, .C, .D, .E, .G };
    inline for (std.meta.fields(Opcode)) |f| {
        if (comptime std.mem.eql(u8, f.name, "_")) continue;
        const op: Opcode = @enumFromInt(f.value);
        const fmt = op.format();
        // Verify it's one of the valid formats
        var found = false;
        for (all_formats) |valid| {
            if (fmt == valid) found = true;
        }
        try std.testing.expect(found);
    }
}

test "instruction size matches format" {
    inline for (std.meta.fields(Opcode)) |f| {
        if (comptime std.mem.eql(u8, f.name, "_")) continue;
        const op: Opcode = @enumFromInt(f.value);
        const size = op.instructionSize();
        switch (op.format()) {
            .A => try std.testing.expectEqual(@as(i32, 1), size),
            .B => try std.testing.expectEqual(@as(i32, 2), size),
            .C => try std.testing.expectEqual(@as(i32, 3), size),
            .D => try std.testing.expectEqual(@as(i32, 4), size),
            .E => try std.testing.expectEqual(@as(i32, 4), size),
            .G => try std.testing.expectEqual(@as(i32, -1), size),
        }
    }
}

test "encode/round-trip" {
    // Verify that opcode byte values match the Python IntEnum exactly
    try std.testing.expectEqual(@as(u8, 0x00), @intFromEnum(Opcode.NOP));
    try std.testing.expectEqual(@as(u8, 0x01), @intFromEnum(Opcode.MOV));
    try std.testing.expectEqual(@as(u8, 0x80), @intFromEnum(Opcode.HALT));
    try std.testing.expectEqual(@as(u8, 0x7F), @intFromEnum(Opcode.SNAPSHOT));
    try std.testing.expectEqual(@as(u8, 0x56), @intFromEnum(Opcode.VFMA));
    try std.testing.expectEqual(@as(u8, 0x60), @intFromEnum(Opcode.TELL));
    try std.testing.expectEqual(@as(u8, 0x84), @intFromEnum(Opcode.DEBUG_BREAK));
}
