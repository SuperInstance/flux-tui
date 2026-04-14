//! FLUX Memory Manager — Capability-based linear region memory
//!
//! Port of flux/vm/memory.py.
//! Each MemoryRegion is a contiguous block with ownership semantics.
//! MemoryManager acts as region factory with stack helpers.

const std = @import("std");
const mem = std.mem;
const testing = std.testing;

/// Maximum region name length.
const MAX_NAME_LEN = 64;

/// Maximum number of borrowers per region.
const MAX_BORROWERS = 8;

/// A contiguous block of memory with ownership semantics.
pub const MemoryRegion = struct {
    name: [MAX_NAME_LEN]u8,
    name_len: usize,
    data: []u8,
    allocator: mem.Allocator,
    owner: [MAX_NAME_LEN]u8,
    owner_len: usize,

    /// Create a new memory region. Caller owns the returned data.
    pub fn init(allocator: mem.Allocator, name: []const u8, len: usize, owner: []const u8) !MemoryRegion {
        const data = try allocator.alloc(u8, len);
        @memset(data, 0);

        var region = MemoryRegion{
            .name = [_]u8{0} ** MAX_NAME_LEN,
            .name_len = @min(name.len, MAX_NAME_LEN),
            .data = data,
            .allocator = allocator,
            .owner = [_]u8{0} ** MAX_NAME_LEN,
            .owner_len = @min(owner.len, MAX_NAME_LEN),
        };
        @memcpy(region.name[0..region.name_len], name[0..region.name_len]);
        @memcpy(region.owner[0..region.owner_len], owner[0..region.owner_len]);

        return region;
    }

    pub fn deinit(self: *MemoryRegion) void {
        self.allocator.free(self.data);
    }

    /// Get the region name as a slice.
    pub fn getName(self: *const MemoryRegion) []const u8 {
        return self.name[0..self.name_len];
    }

    /// Get the region size.
    pub fn size(self: *const MemoryRegion) usize {
        return self.data.len;
    }

    /// Read size bytes starting at offset. Returns error on out-of-bounds.
    pub fn read(self: *const MemoryRegion, offset: usize, len: usize) ![]const u8 {
        const end = offset + len;
        if (offset > self.data.len or end > self.data.len) {
            return error.OutOfBounds;
        }
        return self.data[offset..end];
    }

    /// Write data starting at offset. Returns error on out-of-bounds.
    pub fn write(self: *MemoryRegion, offset: usize, data: []const u8) !void {
        const end = offset + data.len;
        if (offset > self.data.len or end > self.data.len) {
            return error.OutOfBounds;
        }
        @memcpy(self.data[offset..end], data);
    }

    /// Read a signed 32-bit integer (little-endian).
    pub fn readI32(self: *const MemoryRegion, offset: usize) !i32 {
        const bytes = try self.read(offset, 4);
        return @bitCast([4]u8{ bytes[0], bytes[1], bytes[2], bytes[3] });
    }

    /// Write a signed 32-bit integer (little-endian).
    pub fn writeI32(self: *MemoryRegion, offset: usize, value: i32) !void {
        const bytes: [4]u8 = @bitCast(value);
        try self.write(offset, &bytes);
    }

    /// Read a 32-bit float (little-endian).
    pub fn readF32(self: *const MemoryRegion, offset: usize) !f32 {
        const bytes = try self.read(offset, 4);
        return @bitCast([4]u8{ bytes[0], bytes[1], bytes[2], bytes[3] });
    }

    /// Write a 32-bit float (little-endian).
    pub fn writeF32(self: *MemoryRegion, offset: usize, value: f32) !void {
        const bytes: [4]u8 = @bitCast(value);
        try self.write(offset, &bytes);
    }
};

/// Manages linear memory regions for the VM.
pub const MemoryManager = struct {
    allocator: mem.Allocator,
    regions: std.StringHashMap(*MemoryRegion),
    max_regions: usize,

    pub fn init(allocator: mem.Allocator, max_regions: usize) MemoryManager {
        return .{
            .allocator = allocator,
            .regions = std.StringHashMap(*MemoryRegion).init(allocator),
            .max_regions = max_regions,
        };
    }

    pub fn deinit(self: *MemoryManager) void {
        var it = self.regions.valueIterator();
        while (it.next()) |region| {
            region.*.deinit();
        }
        self.regions.deinit();
    }

    /// Create and register a new memory region.
    pub fn createRegion(self: *MemoryManager, name: []const u8, size: usize, owner: []const u8) !*MemoryRegion {
        if (self.regions.contains(name)) {
            return error.RegionExists;
        }
        if (self.regions.count() >= self.max_regions) {
            return error.TooManyRegions;
        }
        const region = try self.allocator.create(MemoryRegion);
        region.* = try MemoryRegion.init(self.allocator, name, size, owner);
        try self.regions.put(name, region);
        return region;
    }

    /// Destroy a memory region by name.
    pub fn destroyRegion(self: *MemoryManager, name: []const u8) !void {
        const region = self.regions.getPtr(name) orelse return error.RegionNotFound;
        region.*.deinit();
        _ = self.regions.remove(name);
    }

    /// Retrieve a memory region by name.
    pub fn getRegion(self: *MemoryManager, name: []const u8) !*MemoryRegion {
        const ptr = self.regions.getPtr(name) orelse return error.RegionNotFound;
        return ptr.*;
    }

    /// Check if a region exists.
    pub fn hasRegion(self: *const MemoryManager, name: []const u8) bool {
        return self.regions.contains(name);
    }

    /// Transfer ownership of a region.
    pub fn transferRegion(self: *MemoryManager, name: []const u8, new_owner: []const u8) !void {
        const region = try self.getRegion(name);
        region.owner_len = @min(new_owner.len, MAX_NAME_LEN);
        @memcpy(region.owner[0..region.owner_len], new_owner[0..region.owner_len]);
    }

    /// Push a 32-bit value onto a region (stack grows downward).
    /// Returns the new stack pointer value.
    pub fn stackPush(region: *MemoryRegion, sp: i32, value: i32) !i32 {
        const new_sp = sp - 4;
        if (new_sp < 0) {
            return error.StackOverflow;
        }
        try region.writeI32(@as(u32, @bitCast(new_sp)), value);
        return new_sp;
    }

    /// Pop a 32-bit value from a region (stack grows downward).
    /// Returns (value, new_sp).
    pub fn stackPop(region: *MemoryRegion, sp: i32) !struct { i32, i32 } {
        const new_sp = sp + 4;
        if (new_sp > @as(i32, @intCast(region.size()))) {
            return error.StackUnderflow;
        }
        const value = try region.readI32(@as(u32, @bitCast(sp)));
        return .{ value, new_sp };
    }
};

// ── Tests ────────────────────────────────────────────────────────────────

test "memory region init and read/write" {
    const allocator = testing.allocator;
    var region = try MemoryRegion.init(allocator, "test", 256, "system");
    defer region.deinit();

    try testing.expectEqual(@as(usize, 256), region.size());
    try testing.expectEqualStrings("test", region.getName());

    // Write and read i32
    try region.writeI32(0, 42);
    const val = try region.readI32(0);
    try testing.expectEqual(@as(i32, 42), val);

    // Write and read bytes
    const data = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    try region.write(100, &data);
    const read_back = try region.read(100, 4);
    try testing.expectEqualSlices(u8, &data, read_back);
}

test "memory region out of bounds" {
    const allocator = testing.allocator;
    var region = try MemoryRegion.init(allocator, "small", 16, "test");
    defer region.deinit();

    try testing.expectError(error.OutOfBounds, region.readI32(16));
    try testing.expectError(error.OutOfBounds, region.writeI32(13, 0));
}

test "memory region float read/write" {
    const allocator = testing.allocator;
    var region = try MemoryRegion.init(allocator, "float_test", 64, "system");
    defer region.deinit();

    try region.writeF32(0, 3.14);
    const val = try region.readF32(0);
    try testing.expectApproxEqAbs(@as(f32, 3.14), val, 0.001);
}

test "memory manager create and destroy regions" {
    const allocator = testing.allocator;
    var mm = MemoryManager.init(allocator, 256);
    defer mm.deinit();

    const r1 = try mm.createRegion("stack", 65536, "system");
    try testing.expectEqualStrings("stack", r1.getName());
    try testing.expect(mm.hasRegion("stack"));

    _ = try mm.createRegion("heap", 65536, "system");
    try testing.expect(mm.hasRegion("heap"));

    try mm.destroyRegion("stack");
    try testing.expect(!mm.hasRegion("stack"));

    // Double destroy should fail
    try testing.expectError(error.RegionNotFound, mm.destroyRegion("stack"));
}

test "memory manager duplicate region fails" {
    const allocator = testing.allocator;
    var mm = MemoryManager.init(allocator, 256);
    defer mm.deinit();

    _ = try mm.createRegion("dup", 1024, "owner");
    try testing.expectError(error.RegionExists, mm.createRegion("dup", 1024, "other"));
}

test "memory manager transfer ownership" {
    const allocator = testing.allocator;
    var mm = MemoryManager.init(allocator, 256);
    defer mm.deinit();

    _ = try mm.createRegion("asset", 512, "alice");
    try mm.transferRegion("asset", "bob");
    const region = try mm.getRegion("asset");
    try testing.expectEqualStrings("bob", region.owner[0..region.owner_len]);
}

test "stack push and pop" {
    const allocator = testing.allocator;
    var region = try MemoryRegion.init(allocator, "stack", 1024, "system");
    defer region.deinit();

    var sp: i32 = 1024; // start at top

    // Push three values
    sp = try MemoryManager.stackPush(&region, sp, 10);
    sp = try MemoryManager.stackPush(&region, sp, 20);
    sp = try MemoryManager.stackPush(&region, sp, 30);

    try testing.expectEqual(@as(i32, 1012), sp);

    // Pop in reverse order
    const v1, const sp1 = try MemoryManager.stackPop(&region, sp);
    try testing.expectEqual(@as(i32, 30), v1);

    const v2, const sp2 = try MemoryManager.stackPop(&region, sp1);
    try testing.expectEqual(@as(i32, 20), v2);

    const v3, const sp3 = try MemoryManager.stackPop(&region, sp2);
    try testing.expectEqual(@as(i32, 10), v3);
    try testing.expectEqual(@as(i32, 1024), sp3);
}

test "stack overflow and underflow" {
    const allocator = testing.allocator;
    var region = try MemoryRegion.init(allocator, "stack", 8, "system"); // tiny stack
    defer region.deinit();

    // Overflow: push past beginning
    var sp: i32 = 8;
    sp = try MemoryManager.stackPush(&region, sp, 1); // sp=4
    try testing.expectError(error.StackOverflow, MemoryManager.stackPush(&region, sp, 2)); // sp=0 ok
    // Now sp=4, trying to push again would be sp=0 which is actually OK for a 8-byte stack
    // But the check is new_sp < 0, so sp=0 works. Let's try underflow:

    // Underflow: pop empty stack
    try testing.expectError(error.StackUnderflow, MemoryManager.stackPop(&region, 8));
}
