//! Register File — 64-register file for the FLUX Micro-VM.
//!
//! Layout:
//!   R0–R15  : 16 general-purpose integer registers (i32)
//!   F0–F15  : 16 floating-point registers (f32)
//!   V0–V15  : 16 SIMD/vector registers (128-bit = 16 bytes each)
//!
//! Special ABI aliases:
//!   R11 (SP)    : Stack pointer
//!   R12         : Region ID (implicit ABI)
//!   R13         : Trust token (implicit ABI)
//!   R14 (FP)    : Frame pointer
//!   R15 (LR)    : Link register (return address)

const std = @import("std");
const mem = std.mem;

pub const GP_COUNT = 16;
pub const FP_COUNT = 16;
pub const VEC_COUNT = 16;
pub const VEC_SIZE = 16; // 128-bit SIMD lanes

// Special register indices
pub const SP_IDX = 11;
pub const FP_IDX = 14;
pub const LR_IDX = 15;

pub const RegisterFile = struct {
    gp: [GP_COUNT]i32 = [_]i32{0} ** GP_COUNT,
    fp: [FP_COUNT]f32 = [_]f32{0.0} ** FP_COUNT,
    vec: [VEC_COUNT][VEC_SIZE]u8 = [_][VEC_SIZE]u8{[_]u8{0} ** VEC_SIZE} ** VEC_COUNT,

    pub inline fn readGP(self: *const RegisterFile, idx: u8) i32 {
        if (idx >= GP_COUNT) {
            std.debug.panic("GP register index out of range: {d}", .{idx});
        }
        return self.gp[idx];
    }

    pub inline fn writeGP(self: *RegisterFile, idx: u8, value: i32) void {
        if (idx >= GP_COUNT) {
            std.debug.panic("GP register index out of range: {d}", .{idx});
        }
        self.gp[idx] = value;
    }

    pub inline fn readFP(self: *const RegisterFile, idx: u8) f32 {
        if (idx >= FP_COUNT) {
            std.debug.panic("FP register index out of range: {d}", .{idx});
        }
        return self.fp[idx];
    }

    pub inline fn writeFP(self: *RegisterFile, idx: u8, value: f32) void {
        if (idx >= FP_COUNT) {
            std.debug.panic("FP register index out of range: {d}", .{idx});
        }
        self.fp[idx] = value;
    }

    pub inline fn readVec(self: *const RegisterFile, idx: u8) [VEC_SIZE]u8 {
        if (idx >= VEC_COUNT) {
            std.debug.panic("VEC register index out of range: {d}", .{idx});
        }
        return self.vec[idx];
    }

    pub inline fn writeVec(self: *RegisterFile, idx: u8, value: [VEC_SIZE]u8) void {
        if (idx >= VEC_COUNT) {
            std.debug.panic("VEC register index out of range: {d}", .{idx});
        }
        self.vec[idx] = value;
    }

    // ── SP / FP / LR convenience ──────────────────────────────────────

    pub inline fn getSP(self: *const RegisterFile) i32 {
        return self.gp[SP_IDX];
    }

    pub inline fn setSP(self: *RegisterFile, val: i32) void {
        self.gp[SP_IDX] = val;
    }

    pub inline fn getFP(self: *const RegisterFile) i32 {
        return self.gp[FP_IDX];
    }

    pub inline fn setFP(self: *RegisterFile, val: i32) void {
        self.gp[FP_IDX] = val;
    }

    pub inline fn getLR(self: *const RegisterFile) i32 {
        return self.gp[LR_IDX];
    }

    pub inline fn setLR(self: *RegisterFile, val: i32) void {
        self.gp[LR_IDX] = val;
    }

    // ── Snapshot / Restore ────────────────────────────────────────────

    pub fn snapshot(self: *const RegisterFile, allocator: mem.Allocator) !Snapshot {
        return Snapshot{
            .gp = try allocator.dupe(i32, &self.gp),
            .fp = try allocator.dupe(f32, &self.fp),
            .vec = try allocator.dupe([VEC_SIZE]u8, &self.vec),
        };
    }

    pub fn restore(self: *RegisterFile, snap: *const Snapshot) void {
        @memcpy(&self.gp, snap.gp);
        @memcpy(&self.fp, snap.fp);
        @memcpy(&self.vec, snap.vec);
    }

    pub fn deinitSnapshot(_: *RegisterFile, allocator: mem.Allocator, snap: *Snapshot) void {
        allocator.free(snap.gp);
        allocator.free(snap.fp);
        allocator.free(snap.vec);
    }
};

pub const Snapshot = struct {
    gp: []i32,
    fp: []f32,
    vec: [][VEC_SIZE]u8,
};

// ── Tests ────────────────────────────────────────────────────────────────

test "register read/write GP" {
    var rf = RegisterFile{};
    rf.writeGP(0, 42);
    rf.writeGP(15, -1);
    try std.testing.expectEqual(@as(i32, 42), rf.readGP(0));
    try std.testing.expectEqual(@as(i32, -1), rf.readGP(15));
    try std.testing.expectEqual(@as(i32, 0), rf.readGP(1));
}

test "register read/write FP" {
    var rf = RegisterFile{};
    rf.writeFP(0, 3.14);
    try std.testing.expectApproxEqAbs(@as(f32, 3.14), rf.readFP(0), 0.001);
}

test "register read/write Vec" {
    var rf = RegisterFile{};
    var v = [_]u8{0} ** VEC_SIZE;
    v[0] = 0xDE;
    v[15] = 0xAD;
    rf.writeVec(3, v);
    const result = rf.readVec(3);
    try std.testing.expectEqual(@as(u8, 0xDE), result[0]);
    try std.testing.expectEqual(@as(u8, 0xAD), result[15]);
}

test "SP/FP/LR aliases" {
    var rf = RegisterFile{};
    rf.setSP(1000);
    rf.setFP(900);
    rf.setLR(0xDEAD);
    try std.testing.expectEqual(@as(i32, 1000), rf.getSP());
    try std.testing.expectEqual(@as(i32, 900), rf.getFP());
    try std.testing.expectEqual(@as(i32, 0xDEAD), rf.getLR());
    // Verify they map to the right GP slots
    try std.testing.expectEqual(rf.getSP(), rf.readGP(SP_IDX));
    try std.testing.expectEqual(rf.getFP(), rf.readGP(FP_IDX));
    try std.testing.expectEqual(rf.getLR(), rf.readGP(LR_IDX));
}

test "snapshot and restore" {
    var rf = RegisterFile{};
    rf.writeGP(0, 100);
    rf.writeGP(1, 200);
    rf.writeFP(0, 1.5);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var snap = try rf.snapshot(arena.allocator());

    // Modify
    rf.writeGP(0, 999);
    rf.writeGP(1, 888);

    // Restore
    rf.restore(&snap);
    try std.testing.expectEqual(@as(i32, 100), rf.readGP(0));
    try std.testing.expectEqual(@as(i32, 200), rf.readGP(1));
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), rf.readFP(0), 0.001);
}
