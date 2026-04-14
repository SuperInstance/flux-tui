//! FLUX Register File — 64-register architecture
//!
//! Layout:
//!   R0–R15 : 16 general-purpose integer registers
//!   F0–F15 : 16 floating-point registers
//!   V0–V15 : 16 SIMD/vector registers (128-bit / 16 bytes each)
//!
//! Special ABI aliases (indices into the GP bank):
//!   R11 (SP)    : Stack pointer
//!   R12         : Region ID (implicit ABI)
//!   R13         : Trust token (implicit ABI)
//!   R14 (FP)    : Frame pointer
//!   R15 (LR)    : Link register (return address)

const std = @import("std");

pub const GP_COUNT: usize = 16;
pub const FP_COUNT: usize = 16;
pub const VEC_COUNT: usize = 16;
pub const VEC_SIZE: usize = 16; // 128-bit SIMD lanes

// Special register aliases
pub const SP_INDEX: usize = 11;
pub const R12_INDEX: usize = 12;
pub const R13_INDEX: usize = 13;
pub const FP_INDEX: usize = 14;
pub const LR_INDEX: usize = 15;

/// 64-register file: R0–R15 (integer), F0–F15 (float), V0–V15 (vector).
/// All registers are stored inline for cache-friendly access.
pub const RegisterFile = struct {
    gp: [GP_COUNT]i32 = [_]i32{0} ** GP_COUNT,
    fp: [FP_COUNT]f32 = [_]f32{0.0} ** FP_COUNT,
    vec: [VEC_COUNT][VEC_SIZE]u8 = [_][VEC_SIZE]u8{[_]u8{0} ** VEC_SIZE} ** VEC_COUNT,

    // ── General-purpose registers ──────────────────────────────────

    pub fn readGP(self: *const RegisterFile, idx: usize) i32 {
        if (idx >= GP_COUNT) {
            std.debug.panic("GP register index out of range: {d}", .{idx});
        }
        return self.gp[idx];
    }

    pub fn writeGP(self: *RegisterFile, idx: usize, value: i32) void {
        if (idx >= GP_COUNT) {
            std.debug.panic("GP register index out of range: {d}", .{idx});
        }
        self.gp[idx] = value;
    }

    // ── Floating-point registers ───────────────────────────────────

    pub fn readFP(self: *const RegisterFile, idx: usize) f32 {
        if (idx >= FP_COUNT) {
            std.debug.panic("FP register index out of range: {d}", .{idx});
        }
        return self.fp[idx];
    }

    pub fn writeFP(self: *RegisterFile, idx: usize, value: f32) void {
        if (idx >= FP_COUNT) {
            std.debug.panic("FP register index out of range: {d}", .{idx});
        }
        self.fp[idx] = value;
    }

    // ── Vector registers ───────────────────────────────────────────

    /// Read a SIMD vector register as a reference to the 16-byte array.
    pub fn readVec(self: *const RegisterFile, idx: usize) *const [VEC_SIZE]u8 {
        if (idx >= VEC_COUNT) {
            std.debug.panic("VEC register index out of range: {d}", .{idx});
        }
        return &self.vec[idx];
    }

    /// Write to a SIMD vector register (padded/truncated to 16 bytes).
    pub fn writeVec(self: *RegisterFile, idx: usize, value: []const u8) void {
        if (idx >= VEC_COUNT) {
            std.debug.panic("VEC register index out of range: {d}", .{idx});
        }
        const len = @min(value.len, VEC_SIZE);
        @memset(&self.vec[idx], 0);
        @memcpy(self.vec[idx][0..len], value[0..len]);
    }

    // ── SP / FP / LR convenience ──────────────────────────────────

    pub fn getSP(self: *const RegisterFile) i32 {
        return self.gp[SP_INDEX];
    }

    pub fn setSP(self: *RegisterFile, val: i32) void {
        self.gp[SP_INDEX] = val;
    }

    pub fn getFP(self: *const RegisterFile) i32 {
        return self.gp[FP_INDEX];
    }

    pub fn setFP(self: *RegisterFile, val: i32) void {
        self.gp[FP_INDEX] = val;
    }

    pub fn getLR(self: *const RegisterFile) i32 {
        return self.gp[LR_INDEX];
    }

    pub fn setLR(self: *RegisterFile, val: i32) void {
        self.gp[LR_INDEX] = val;
    }

    /// Reset all registers to zero.
    pub fn reset(self: *RegisterFile) void {
        @memset(&self.gp, 0);
        @memset(&self.fp, 0);
        for (&self.vec) |*v| @memset(v, 0);
    }
};

// ═══════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════

test "GP read/write" {
    var regs = RegisterFile{};
    regs.writeGP(0, 42);
    try std.testing.expectEqual(@as(i32, 42), regs.readGP(0));
    regs.writeGP(15, -1);
    try std.testing.expectEqual(@as(i32, -1), regs.readGP(15));
}

test "FP read/write" {
    var regs = RegisterFile{};
    regs.writeFP(0, 3.14);
    try std.testing.expectEqual(@as(f32, 3.14), regs.readFP(0));
}

test "Vec read/write" {
    var regs = RegisterFile{};
    const data = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C };
    regs.writeVec(0, &data);
    const v = regs.readVec(0);
    try std.testing.expectEqualSlices(u8, &data, v);
}

test "Vec write truncates to 16 bytes" {
    var regs = RegisterFile{};
    const long = [_]u8{1} ** 32;
    regs.writeVec(0, &long);
    try std.testing.expectEqual(@as(usize, 16), regs.readVec(0).len);
    try std.testing.expectEqual(@as(u8, 1), regs.readVec(0)[15]);
}

test "Vec write pads short data" {
    var regs = RegisterFile{};
    const short = [_]u8{ 0xFF, 0xFF };
    regs.writeVec(0, &short);
    try std.testing.expectEqual(@as(u8, 0xFF), regs.readVec(0)[0]);
    try std.testing.expectEqual(@as(u8, 0xFF), regs.readVec(0)[1]);
    try std.testing.expectEqual(@as(u8, 0), regs.readVec(0)[2]);
}

test "SP/FP/LR convenience" {
    var regs = RegisterFile{};
    regs.setSP(65536);
    try std.testing.expectEqual(@as(i32, 65536), regs.getSP());
    regs.setFP(32000);
    try std.testing.expectEqual(@as(i32, 32000), regs.getFP());
    regs.setLR(100);
    try std.testing.expectEqual(@as(i32, 100), regs.getLR());
}

test "reset clears all registers" {
    var regs = RegisterFile{};
    regs.writeGP(0, 999);
    regs.writeFP(0, 1.5);
    regs.writeVec(0, &[_]u8{0xFF} ** 16);
    regs.reset();
    try std.testing.expectEqual(@as(i32, 0), regs.readGP(0));
    try std.testing.expectEqual(@as(f32, 0.0), regs.readFP(0));
    try std.testing.expectEqual(@as(u8, 0), regs.readVec(0)[0]);
}
