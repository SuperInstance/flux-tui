//! FLUX Linear Region Memory — Capability-based memory management
//!
//! Each `MemoryRegion` is a contiguous block of owned memory with an
//! access-control list (owner + read-only borrowers).  The `MemoryManager`
//! acts as a region factory and provides stack helpers (push/pop) that
//! operate on a region's raw byte buffer.

const std = @import("std");
const mem = std.mem;

pub const MAX_REGION_NAME: usize = 64;
pub const MAX_OWNER_NAME: usize = 64;
pub const MAX_REGIONS: usize = 256;

/// A contiguous block of memory with ownership semantics.
pub const MemoryRegion = struct {
    name: [MAX_REGION_NAME]u8,
    name_len: usize,
    data: []u8, // heap-allocated, owned
    size: usize,
    owner: [MAX_OWNER_NAME]u8,
    owner_len: usize,

    pub fn init(allocator: mem.Allocator, name: []const u8, size: usize, owner: []const u8) !MemoryRegion {
        const data = try allocator.alloc(u8, size);
        @memset(data, 0);

        var self = MemoryRegion{
            .name = [_]u8{0} ** MAX_REGION_NAME,
            .name_len = @min(name.len, MAX_REGION_NAME),
            .data = data,
            .size = size,
            .owner = [_]u8{0} ** MAX_OWNER_NAME,
            .owner_len = @min(owner.len, MAX_OWNER_NAME),
        };
        @memcpy(self.name[0..self.name_len], name[0..self.name_len]);
        @memcpy(self.owner[0..self.owner_len], owner[0..self.owner_len]);
        return self;
    }

    pub fn deinit(self: *MemoryRegion, allocator: mem.Allocator) void {
        allocator.free(self.data);
    }

    /// Read `size` bytes starting at `offset`.  Returns a slice into the region.
    pub fn read(self: *const MemoryRegion, offset: usize, size: usize) []const u8 {
        const end = offset + size;
        if (offset >= self.size or end > self.size) {
            std.debug.panic("MemoryRegion[{s}] read out of bounds: offset={d}, size={d}, region_size={d}", .{
                self.nameSlice(), offset, size, self.size,
            });
        }
        return self.data[offset..end];
    }

    /// Write `data` starting at `offset`.
    pub fn write(self: *MemoryRegion, offset: usize, data: []const u8) void {
        const end = offset + data.len;
        if (offset >= self.size or end > self.size) {
            std.debug.panic("MemoryRegion[{s}] write out of bounds: offset={d}, size={d}, region_size={d}", .{
                self.nameSlice(), offset, data.len, self.size,
            });
        }
        @memcpy(self.data[offset..end], data);
    }

    /// Read a signed 32-bit integer (little-endian).
    pub fn readI32(self: *const MemoryRegion, offset: usize) i32 {
        const b = self.read(offset, 4);
        const val: u32 = @as(u32, b[0]) | (@as(u32, b[1]) << 8) | (@as(u32, b[2]) << 16) | (@as(u32, b[3]) << 24);
        return @as(i32, @bitCast(val));
    }

    /// Write a signed 32-bit integer (little-endian).
    pub fn writeI32(self: *MemoryRegion, offset: usize, value: i32) void {
        const bits: u32 = @bitCast(value);
        const bytes = [_]u8{
            @truncate(bits),
            @truncate(bits >> 8),
            @truncate(bits >> 16),
            @truncate(bits >> 24),
        };
        self.write(offset, &bytes);
    }

    /// Read a 32-bit IEEE 754 float (little-endian).
    pub fn readF32(self: *const MemoryRegion, offset: usize) f32 {
        const bytes: *const [4]u8 = self.read(offset, 4).ptr[0..4][0..4];
        return @as(f32, @bitCast(@as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16) | (@as(u32, bytes[3]) << 24)));
    }

    /// Write a 32-bit IEEE 754 float (little-endian).
    pub fn writeF32(self: *MemoryRegion, offset: usize, value: f32) void {
        const bits: u32 = @bitCast(value);
        const bytes = [_]u8{
            @truncate(bits),
            @truncate(bits >> 8),
            @truncate(bits >> 16),
            @truncate(bits >> 24),
        };
        self.write(offset, &bytes);
    }

    pub fn nameSlice(self: *const MemoryRegion) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn ownerSlice(self: *const MemoryRegion) []const u8 {
        return self.owner[0..self.owner_len];
    }
};

/// Manages linear memory regions for the VM.
pub const MemoryManager = struct {
    regions: [MAX_REGIONS]?MemoryRegion = [_]?MemoryRegion{null} ** MAX_REGIONS,
    region_count: usize = 0,

    /// Create and register a new memory region. Returns a pointer to it.
    pub fn createRegion(self: *MemoryManager, allocator: mem.Allocator, name: []const u8, size: usize, owner: []const u8) !*MemoryRegion {
        // Check for duplicate name
        if (self.findRegion(name) != null) {
            std.debug.panic("Region '{s}' already exists", .{name});
        }
        if (self.region_count >= MAX_REGIONS) {
            std.debug.panic("Maximum number of regions ({d}) exceeded", .{MAX_REGIONS});
        }

        // Find a free slot
        var slot: ?usize = null;
        for (0..MAX_REGIONS) |i| {
            if (self.regions[i] == null) {
                slot = i;
                break;
            }
        }
        if (slot == null) {
            std.debug.panic("No free region slot", .{});
        }

        self.regions[slot.?] = try MemoryRegion.init(allocator, name, size, owner);
        self.region_count += 1;
        return &self.regions[slot.?].?;
    }

    /// Destroy a memory region by name.
    pub fn destroyRegion(self: *MemoryManager, allocator: mem.Allocator, name: []const u8) void {
        const idx = self.findRegionIndex(name) orelse {
            std.debug.panic("Region '{s}' does not exist", .{name});
        };
        self.regions[idx].?.deinit(allocator);
        self.regions[idx] = null;
        self.region_count -= 1;
    }

    /// Get a memory region by name.
    pub fn getRegion(self: *MemoryManager, name: []const u8) *MemoryRegion {
        return self.findRegion(name) orelse {
            std.debug.panic("Region '{s}' does not exist", .{name});
        };
    }

    /// Transfer ownership of a region to a new owner.
    pub fn transferRegion(self: *MemoryManager, name: []const u8, new_owner: []const u8) void {
        const region = self.getRegion(name);
        region.owner_len = @min(new_owner.len, MAX_OWNER_NAME);
        @memcpy(region.owner[0..region.owner_len], new_owner[0..region.owner_len]);
        // Clear remaining bytes
        @memset(region.owner[region.owner_len..], 0);
    }

    /// Check if a region exists.
    pub fn hasRegion(self: *const MemoryManager, name: []const u8) bool {
        for (&self.regions) |*slot| {
            if (slot.*) |*region| {
                if (mem.eql(u8, region.nameSlice(), name)) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Push a 32-bit value onto the stack region. Stack grows downward.
    /// Returns the new stack pointer value.
    pub fn stackPush(region: *MemoryRegion, sp: i32, value: i32) i32 {
        const new_sp = sp - 4;
        if (new_sp < 0) {
            std.debug.panic("Stack overflow", .{});
        }
        region.writeI32(@intCast(new_sp), value);
        return new_sp;
    }

    /// Pop a 32-bit value from the stack region.
    /// Returns .{ .value, .new_sp }.
    pub const StackPopResult = struct { value: i32, new_sp: i32 };
    pub fn stackPop(region: *MemoryRegion, sp: i32) StackPopResult {
        const new_sp = sp + 4;
        if (new_sp > @as(i32, @intCast(region.size))) {
            std.debug.panic("Stack underflow", .{});
        }
        const value = region.readI32(@intCast(sp));
        return .{ .value = value, .new_sp = new_sp };
    }

    // ── Internal ───────────────────────────────────────────────────

    fn findRegion(self: *MemoryManager, name: []const u8) ?*MemoryRegion {
        for (&self.regions) |*slot| {
            if (slot.*) |*region| {
                if (mem.eql(u8, region.nameSlice(), name)) {
                    return region;
                }
            }
        }
        return null;
    }

    fn findRegionIndex(self: *MemoryManager, name: []const u8) ?usize {
        for (0..MAX_REGIONS) |i| {
            if (self.regions[i]) |*region| {
                if (mem.eql(u8, region.nameSlice(), name)) {
                    return i;
                }
            }
        }
        return null;
    }

    pub fn deinitAll(self: *MemoryManager, allocator: mem.Allocator) void {
        for (&self.regions) |*slot| {
            if (slot.*) |*region| {
                region.deinit(allocator);
                slot.* = null;
            }
        }
        self.region_count = 0;
    }
};

// ═══════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════

test "MemoryRegion read/write i32" {
    const allocator = std.testing.allocator;
    var region = try MemoryRegion.init(allocator, "test", 256, "system");
    defer region.deinit(allocator);

    region.writeI32(0, 42);
    region.writeI32(4, -1);
    try std.testing.expectEqual(@as(i32, 42), region.readI32(0));
    try std.testing.expectEqual(@as(i32, -1), region.readI32(4));
}

test "MemoryRegion read/write f32" {
    const allocator = std.testing.allocator;
    var region = try MemoryRegion.init(allocator, "floats", 256, "system");
    defer region.deinit(allocator);

    region.writeF32(0, 3.14);
    const val = region.readF32(0);
    try std.testing.expectApproxEqAbs(@as(f32, 3.14), val, 0.001);
}

test "MemoryRegion read/write raw bytes" {
    const allocator = std.testing.allocator;
    var region = try MemoryRegion.init(allocator, "raw", 256, "system");
    defer region.deinit(allocator);

    const data = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    region.write(10, &data);
    const read = region.read(10, 4);
    try std.testing.expectEqualSlices(u8, &data, read);
}

test "MemoryManager create and get region" {
    const allocator = std.testing.allocator;
    var mm = MemoryManager{};
    defer mm.deinitAll(allocator);

    _ = try mm.createRegion(allocator, "stack", 1024, "system");
    _ = try mm.createRegion(allocator, "heap", 2048, "system");
    try std.testing.expectEqual(@as(usize, 2), mm.region_count);

    const stack = mm.getRegion("stack");
    try std.testing.expectEqual(@as(usize, 1024), stack.size);
}

test "MemoryManager destroy region" {
    const allocator = std.testing.allocator;
    var mm = MemoryManager{};
    defer mm.deinitAll(allocator);

    _ = try mm.createRegion(allocator, "temp", 512, "test");
    try std.testing.expect(mm.hasRegion("temp"));
    mm.destroyRegion(allocator, "temp");
    try std.testing.expect(!mm.hasRegion("temp"));
}

test "MemoryManager transfer region" {
    const allocator = std.testing.allocator;
    var mm = MemoryManager{};
    defer mm.deinitAll(allocator);

    _ = try mm.createRegion(allocator, "data", 256, "agent1");
    mm.transferRegion("data", "agent2");
    const region = mm.getRegion("data");
    try std.testing.expectEqualStrings("agent2", region.ownerSlice());
}

test "stack push and pop" {
    const allocator = std.testing.allocator;
    var region = try MemoryRegion.init(allocator, "stack", 1024, "system");
    defer region.deinit(allocator);

    var sp: i32 = 1024;
    sp = MemoryManager.stackPush(&region, sp, 42);
    sp = MemoryManager.stackPush(&region, sp, 99);
    const r1 = MemoryManager.stackPop(&region, sp);
    try std.testing.expectEqual(@as(i32, 99), r1.value);
    const r2 = MemoryManager.stackPop(&region, r1.new_sp);
    try std.testing.expectEqual(@as(i32, 42), r2.value);
    try std.testing.expectEqual(@as(i32, 1024), r2.new_sp);
}
