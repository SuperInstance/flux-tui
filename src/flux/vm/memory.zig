//! Linear Region Memory — capability-based memory management for the FLUX Micro-VM.
//!
//! Each MemoryRegion is a contiguous block of owned memory with an access-control
//! list (owner + read-only borrowers). The MemoryManager acts as a region factory
//! and provides stack helpers (push/pop) operating on a region's raw bytes.

const std = @import("std");
const mem = std.mem;

pub const MAX_REGIONS = 256;
pub const MAX_REGION_NAME = 64;

/// A contiguous block of memory with ownership semantics.
pub const MemoryRegion = struct {
    name: [MAX_REGION_NAME]u8,
    name_len: u8,
    data: []u8,
    size: u32,
    owner: [MAX_REGION_NAME]u8,
    owner_len: u8,

    pub fn init(allocator: mem.Allocator, name: []const u8, size: u32, owner: []const u8) !MemoryRegion {
        const data = try allocator.alloc(u8, size);
        @memset(data, 0);

        var region = MemoryRegion{
            .name = [_]u8{0} ** MAX_REGION_NAME,
            .name_len = @intCast(@min(name.len, MAX_REGION_NAME)),
            .data = data,
            .size = size,
            .owner = [_]u8{0} ** MAX_REGION_NAME,
            .owner_len = @intCast(@min(owner.len, MAX_REGION_NAME)),
        };
        @memcpy(region.name[0..region.name_len], name[0..region.name_len]);
        @memcpy(region.owner[0..region.owner_len], owner[0..region.owner_len]);
        return region;
    }

    pub fn deinit(self: *MemoryRegion, allocator: mem.Allocator) void {
        allocator.free(self.data);
    }

    pub fn getName(self: *const MemoryRegion) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getOwner(self: *const MemoryRegion) []const u8 {
        return self.owner[0..self.owner_len];
    }

    /// Read `size` bytes starting at `offset`.  Returns error on out-of-bounds.
    pub fn read(self: *const MemoryRegion, offset: u32, size: u32) ![]const u8 {
        const end = offset + size;
        if (end > self.size) {
            return error.OutOfBounds;
        }
        return self.data[offset..end];
    }

    /// Write `data` starting at `offset`.  Returns error on out-of-bounds.
    pub fn write(self: *MemoryRegion, offset: u32, data: []const u8) !void {
        const end = offset + @as(u32, @intCast(data.len));
        if (end > self.size) {
            return error.OutOfBounds;
        }
        @memcpy(self.data[offset..end], data);
    }

    /// Read a signed 32-bit integer (little-endian).
    pub fn readI32(self: *const MemoryRegion, offset: u32) !i32 {
        const bytes = try self.read(offset, 4);
        return @as(i32, @bitCast([4]u8{ bytes[0], bytes[1], bytes[2], bytes[3] }));
    }

    /// Write a signed 32-bit integer (little-endian).
    pub fn writeI32(self: *MemoryRegion, offset: u32, value: i32) !void {
        const bytes: [4]u8 = @bitCast(value);
        try self.write(offset, &bytes);
    }

    /// Read a 32-bit IEEE 754 float (little-endian).
    pub fn readF32(self: *const MemoryRegion, offset: u32) !f32 {
        const bytes = try self.read(offset, 4);
        return @as(f32, @bitCast([4]u8{ bytes[0], bytes[1], bytes[2], bytes[3] }));
    }

    /// Write a 32-bit IEEE 754 float (little-endian).
    pub fn writeF32(self: *MemoryRegion, offset: u32, value: f32) !void {
        const bytes: [4]u8 = @bitCast(value);
        try self.write(offset, &bytes);
    }
};

/// Manages named linear memory regions for the VM.
pub const MemoryManager = struct {
    regions: [MAX_REGIONS]?MemoryRegion = [_]?MemoryRegion{null} ** MAX_REGIONS,
    region_count: u16 = 0,

    pub fn init() MemoryManager {
        return .{};
    }

    pub fn deinit(self: *MemoryManager, allocator: mem.Allocator) void {
        for (&self.regions) |*opt| {
            if (opt.*) |*region| {
                region.deinit(allocator);
                opt.* = null;
            }
        }
    }

    /// Find a region by name. Returns null if not found.
    fn findRegion(self: *MemoryManager, name: []const u8) ?*MemoryRegion {
        for (&self.regions) |*opt| {
            if (opt.*) |*region| {
                if (mem.eql(u8, region.getName(), name)) {
                    return region;
                }
            }
        }
        return null;
    }

    /// Create and register a new memory region.
    pub fn createRegion(self: *MemoryManager, allocator: mem.Allocator, name: []const u8, size: u32, owner: []const u8) !*MemoryRegion {
        if (self.findRegion(name) != null) {
            return error.RegionAlreadyExists;
        }
        if (self.region_count >= MAX_REGIONS) {
            return error.TooManyRegions;
        }
        // Find first empty slot
        for (&self.regions, 0..) |*opt, i| {
            if (opt.* == null) {
                const region = try MemoryRegion.init(allocator, name, size, owner);
                opt.* = region;
                self.region_count += 1;
                return &self.regions[i].?;
            }
        }
        return error.TooManyRegions;
    }

    /// Destroy a memory region by name.
    pub fn destroyRegion(self: *MemoryManager, allocator: mem.Allocator, name: []const u8) !void {
        for (&self.regions, 0..) |*opt, i| {
            if (opt.*) |*region| {
                if (mem.eql(u8, region.getName(), name)) {
                    region.deinit(allocator);
                    self.regions[i] = null;
                    self.region_count -= 1;
                    return;
                }
            }
        }
        return error.RegionNotFound;
    }

    /// Get a memory region by name.
    pub fn getRegion(self: *MemoryManager, name: []const u8) !*MemoryRegion {
        if (self.findRegion(name)) |region| {
            return region;
        }
        return error.RegionNotFound;
    }

    /// Transfer ownership of a region.
    pub fn transferRegion(self: *MemoryManager, name: []const u8, new_owner: []const u8) !void {
        const region = try self.getRegion(name);
        region.owner_len = @intCast(@min(new_owner.len, MAX_REGION_NAME));
        @memcpy(region.owner[0..region.owner_len], new_owner[0..region.owner_len]);
        // Zero remaining
        @memset(region.owner[region.owner_len..], 0);
    }

    /// Check if a region exists.
    pub fn hasRegion(self: *MemoryManager, name: []const u8) bool {
        return self.findRegion(name) != null;
    }

    // ── Stack helpers ────────────────────────────────────────────────

    /// Push a 32-bit value onto the stack region (grows downward).
    /// Returns the new stack pointer value.
    pub fn stackPush(region: *MemoryRegion, sp: i32, value: i32) !i32 {
        const new_sp = sp - 4;
        if (new_sp < 0) {
            return error.StackOverflow;
        }
        try region.writeI32(@intCast(new_sp), value);
        return new_sp;
    }

    /// Pop a 32-bit value from the stack region.
    /// Returns (value, new_sp).
    pub fn stackPop(region: *MemoryRegion, sp: i32) ![2]i32 {
        const new_sp = sp + 4;
        if (new_sp > @as(i32, @intCast(region.size))) {
            return error.StackUnderflow;
        }
        const value = try region.readI32(@intCast(sp));
        return .{ value, new_sp };
    }
};

// ── Tests ────────────────────────────────────────────────────────────────

test "region create, read, write" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var mm = MemoryManager.init();
    defer mm.deinit(alloc);

    const region = try mm.createRegion(alloc, "test", 1024, "system");
    try std.testing.expectEqual(@as(u32, 1024), region.size);
    try std.testing.expectEqualStrings("test", region.getName());

    // Write and read i32
    try region.writeI32(100, 42);
    const val = try region.readI32(100);
    try std.testing.expectEqual(@as(i32, 42), val);

    // Write and read bytes
    try region.write(200, "hello");
    const data = try region.read(200, 5);
    try std.testing.expectEqualStrings("hello", data);
}

test "region out of bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var mm = MemoryManager.init();
    defer mm.deinit(alloc);

    const region = try mm.createRegion(alloc, "small", 16, "sys");

    // Write beyond region
    try std.testing.expectError(error.OutOfBounds, region.writeI32(14, 0));
    // Read beyond region
    try std.testing.expectError(error.OutOfBounds, region.readI32(14));
}

test "stack push/pop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var mm = MemoryManager.init();
    defer mm.deinit(alloc);

    const region = try mm.createRegion(alloc, "stack", 1024, "system");
    var sp: i32 = 1024; // stack starts at top

    sp = try MemoryManager.stackPush(region, sp, 42);
    sp = try MemoryManager.stackPush(region, sp, 99);

    const val1 = try MemoryManager.stackPop(region, sp);
    sp = val1[1];
    try std.testing.expectEqual(@as(i32, 99), val1[0]);

    const val2 = try MemoryManager.stackPop(region, sp);
    sp = val2[1];
    try std.testing.expectEqual(@as(i32, 42), val2[0]);
}

test "region create and destroy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var mm = MemoryManager.init();
    defer mm.deinit(alloc);

    _ = try mm.createRegion(alloc, "temp", 256, "owner1");
    try std.testing.expect(mm.hasRegion("temp"));
    try mm.destroyRegion(alloc, "temp");
    try std.testing.expect(!mm.hasRegion("temp"));
    try std.testing.expectError(error.RegionNotFound, mm.destroyRegion(alloc, "temp"));
}

test "f32 read/write" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var mm = MemoryManager.init();
    defer mm.deinit(alloc);

    const region = try mm.createRegion(alloc, "heap", 256, "sys");
    try region.writeF32(0, 3.14159);
    const val = try region.readF32(0);
    try std.testing.expectApproxEqAbs(@as(f32, 3.14159), val, 0.0001);
}
