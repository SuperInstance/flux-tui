//! FLUX Bytecode Decoder — Instruction decoding utilities
//!
//! Decodes raw bytecode into structured instruction representations.
//! Supports all 7 encoding formats (A-G).

const std = @import("std");
const opcodes = @import("opcodes.zig");

/// Decoded instruction representation.
pub const DecodedInstruction = struct {
    opcode: u8,
    format: opcodes.Format,
    size: usize,
    /// Decoded operands depend on format:
    ///   A: none
    ///   B: rd
    ///   C: rd, rs1
    ///   D: rs1, offset (i16)
    ///   E: rd, rs1, rs2
    ///   G: variable data slice
    rd: u8 = 0,
    rs1: u8 = 0,
    rs2: u8 = 0,
    offset: i16 = 0,
    imm8: u8 = 0,
    data: []const u8 = &[_]u8{},
};

/// Decode a single instruction from bytecode starting at the given offset.
/// Returns the decoded instruction and the next offset.
pub fn decodeInstruction(bytecode: []const u8, offset: usize) !struct { DecodedInstruction, usize } {
    if (offset >= bytecode.len) {
        return error.EndOfBytecode;
    }

    const op_byte = bytecode[offset];
    const fmt = opcodes.getFormat(op_byte);

    var instr = DecodedInstruction{
        .opcode = op_byte,
        .format = fmt,
        .size = 0,
    };

    switch (fmt) {
        .A => {
            instr.size = 1;
            return .{ instr, offset + 1 };
        },
        .B => {
            if (offset + 2 > bytecode.len) return error.TruncatedInstruction;
            instr.rd = bytecode[offset + 1];
            instr.size = 2;
            return .{ instr, offset + 2 };
        },
        .C => {
            if (offset + 3 > bytecode.len) return error.TruncatedInstruction;
            instr.rd = bytecode[offset + 1];
            instr.rs1 = bytecode[offset + 2];
            instr.size = 3;
            return .{ instr, offset + 3 };
        },
        .D => {
            if (offset + 4 > bytecode.len) return error.TruncatedInstruction;
            instr.rs1 = bytecode[offset + 1];
            // Little-endian i16
            const lo: u16 = bytecode[offset + 2];
            const hi: u16 = bytecode[offset + 3];
            const raw: u16 = lo | (hi << 8);
            instr.offset = @bitCast(raw);
            instr.size = 4;
            return .{ instr, offset + 4 };
        },
        .E => {
            if (offset + 4 > bytecode.len) return error.TruncatedInstruction;
            instr.rd = bytecode[offset + 1];
            instr.rs1 = bytecode[offset + 2];
            instr.rs2 = bytecode[offset + 3];
            instr.size = 4;
            return .{ instr, offset + 4 };
        },
        .G => {
            if (offset + 3 > bytecode.len) return error.TruncatedInstruction;
            // u16 length prefix (little-endian)
            const data_len: u16 = bytecode[offset + 1] | (@as(u16, bytecode[offset + 2]) << 8);
            const total_size: usize = 3 + data_len;
            if (offset + total_size > bytecode.len) return error.TruncatedInstruction;
            instr.data = bytecode[offset + 3 .. offset + total_size];
            instr.size = total_size;
            return .{ instr, offset + total_size };
        },
    }
}

/// Disassemble a single instruction to a human-readable string.
/// Caller owns the returned buffer (written to the provided writer).
pub fn disassembleInstruction(bytecode: []const u8, offset: usize, writer: anytype) !usize {
    const instr, const next_offset = try decodeInstruction(bytecode, offset);

    const op_name = opcodes.Op.nameFromByte(instr.opcode);
    try writer.print("0x{X:0>4}: {s}", .{ offset, op_name });

    switch (instr.format) {
        .A => {},
        .B => try writer.print(" R{}", .{instr.rd}),
        .C => try writer.print(" R{}, R{}", .{ instr.rd, instr.rs1 }),
        .D => try writer.print(" R{}, {d}", .{ instr.rs1, instr.offset }),
        .E => try writer.print(" R{}, R{}, R{}", .{ instr.rd, instr.rs1, instr.rs2 }),
        .G => try writer.print(" [{} bytes]", .{instr.data.len}),
    }

    return next_offset;
}

// ── Tests ────────────────────────────────────────────────────────────────

test "decode format A: NOP" {
    const bytecode = [_]u8{0x00}; // NOP
    const instr, const next = try decodeInstruction(&bytecode, 0);
    try std.testing.expectEqual(@as(u8, 0x00), instr.opcode);
    try std.testing.expectEqual(opcodes.Format.A, instr.format);
    try std.testing.expectEqual(@as(usize, 1), instr.size);
    try std.testing.expectEqual(@as(usize, 1), next);
}

test "decode format B: INC R5" {
    const bytecode = [_]u8{ 0x0E, 0x05 }; // INC R5
    const instr, const next = try decodeInstruction(&bytecode, 0);
    try std.testing.expectEqual(@as(u8, 0x0E), instr.opcode);
    try std.testing.expectEqual(opcodes.Format.B, instr.format);
    try std.testing.expectEqual(@as(u8, 5), instr.rd);
    try std.testing.expectEqual(@as(usize, 2), next);
}

test "decode format C: MOV R1, R2" {
    const bytecode = [_]u8{ 0x01, 0x01, 0x02 }; // MOV R1, R2
    const instr, _ = try decodeInstruction(&bytecode, 0);
    try std.testing.expectEqual(@as(u8, 0x01), instr.opcode);
    try std.testing.expectEqual(opcodes.Format.C, instr.format);
    try std.testing.expectEqual(@as(u8, 1), instr.rd);
    try std.testing.expectEqual(@as(u8, 2), instr.rs1);
}

test "decode format D: JMP with negative offset" {
    const bytecode = [_]u8{ 0x04, 0x00, 0xFC, 0xFF }; // JMP -4 (little-endian)
    const instr, _ = try decodeInstruction(&bytecode, 0);
    try std.testing.expectEqual(@as(u8, 0x04), instr.opcode);
    try std.testing.expectEqual(opcodes.Format.D, instr.format);
    try std.testing.expectEqual(@as(i16, -4), instr.offset);
}

test "decode format E: IADD R0, R1, R2" {
    const bytecode = [_]u8{ 0x08, 0x00, 0x01, 0x02 }; // IADD R0, R1, R2
    const instr, _ = try decodeInstruction(&bytecode, 0);
    try std.testing.expectEqual(@as(u8, 0x08), instr.opcode);
    try std.testing.expectEqual(opcodes.Format.E, instr.format);
    try std.testing.expectEqual(@as(u8, 0), instr.rd);
    try std.testing.expectEqual(@as(u8, 1), instr.rs1);
    try std.testing.expectEqual(@as(u8, 2), instr.rs2);
}

test "decode format G: REGION_CREATE" {
    // REGION_CREATE with 5 bytes of data: "test\0"
    const bytecode = [_]u8{
        0x30,                           // opcode
        0x05, 0x00,                     // length = 5 (LE)
        't', 'e', 's', 't', 0x00,       // data
    };
    const instr, const next = try decodeInstruction(&bytecode, 0);
    try std.testing.expectEqual(@as(u8, 0x30), instr.opcode);
    try std.testing.expectEqual(opcodes.Format.G, instr.format);
    try std.testing.expectEqual(@as(usize, 5), instr.data.len);
    try std.testing.expectEqual(@as(usize, 8), next);
}

test "decode HALT" {
    const bytecode = [_]u8{0x80}; // HALT
    const instr, _ = try decodeInstruction(&bytecode, 0);
    try std.testing.expectEqual(@as(u8, 0x80), instr.opcode);
    try std.testing.expectEqual(opcodes.Format.A, instr.format);
}

test "truncated instruction returns error" {
    const bytecode = [_]u8{ 0x08, 0x00 }; // IADD without last byte
    try std.testing.expectError(error.TruncatedInstruction, decodeInstruction(&bytecode, 0));
}

test "sequential decode" {
    // MOVI R0, 42 | IADD R0, R1, R2 | HALT
    const bytecode = [_]u8{
        0x2B, 0x00, 0x2A, 0x00,   // MOVI R0, 42 (Format D: reg=0, imm16=42)
        0x08, 0x00, 0x01, 0x02,   // IADD R0, R1, R2
        0x80,                      // HALT
    };
    var offset: usize = 0;

    const instr1, const n1 = try decodeInstruction(&bytecode, offset);
    try std.testing.expectEqual(opcodes.Op.MOVI, opcodes.Op.fromByte(instr1.opcode));
    offset = n1;

    const instr2, const n2 = try decodeInstruction(&bytecode, offset);
    try std.testing.expectEqual(opcodes.Op.IADD, opcodes.Op.fromByte(instr2.opcode));
    offset = n2;

    const instr3, const n3 = try decodeInstruction(&bytecode, offset);
    try std.testing.expectEqual(opcodes.Op.HALT, opcodes.Op.fromByte(instr3.opcode));
    offset = n3;

    try std.testing.expectEqual(bytecode.len, offset);
}
