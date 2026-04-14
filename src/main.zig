//! FLUX Bytecode VM — Zig Implementation
//!
//! Main entry point. Wires together VM core modules and provides CLI interface.

const std = @import("std");

const opcodes = @import("vm/opcodes.zig");
const Op = opcodes.Op;
const interpreter = @import("vm/interpreter.zig");
const Interpreter = interpreter.Interpreter;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const allocator = std.heap.page_allocator;

    try stdout.print("FLUX Zig - High-Performance Bytecode VM\n", .{});
    try stdout.print("  SuperInstance / Oracle1\n", .{});
    try stdout.print("  {} opcodes | 64 registers | comptime dispatch\n\n", .{countOpcodes()});

    // Demo: Factorial(7)
    const fact = [_]u8{
        0x2B, 0x00, 0x07, 0x00, 0x2B, 0x01, 0x01, 0x00,
        0x0A, 0x01, 0x01, 0x00, 0x0F, 0x00, 0x06, 0x00,
        0xF6, 0xFF, 0x80,
    };
    var vm = try Interpreter.init(allocator, &fact, 65536);
    defer vm.deinit();
    const cycles = try vm.execute();
    try stdout.print("Factorial(7): R1 = {} (cycles: {})\n", .{vm.regs.readGP(1), cycles});

    // Demo: Fibonacci(12)
    const fib = [_]u8{
        0x2B, 0x00, 0x00, 0x00, 0x2B, 0x01, 0x01, 0x00,
        0x2B, 0x02, 0x0C, 0x00, 0x01, 0x03, 0x01, 0x08, 0x01,
        0x01, 0x00, 0x03, 0x0F, 0x02, 0x06, 0x02, 0xF0, 0xFF, 0x80,
    };
    var vm2 = try Interpreter.init(allocator, &fib, 65536);
    defer vm2.deinit();
    const cycles2 = try vm2.execute();
    try stdout.print("Fibonacci(12): R0 = {} (cycles: {})\n", .{vm2.regs.readGP(0), cycles2});

    // Demo: Conditional branch (10 != 5, JE should not fire, INC runs)
    const branch_demo = [_]u8{
        0x2B, 0x00, 0x0A, 0x00, 0x2B, 0x01, 0x05, 0x00,
        0x2D, 0x00, 0x01, 0x2E, 0x00, 0x02, 0x00, 0x0E, 0x00, 0x80,
    };
    var vm3 = try Interpreter.init(allocator, &branch_demo, 65536);
    defer vm3.deinit();
    _ = try vm3.execute();
    try stdout.print("Branch (10!=5): R0 = {} (expected 11)\n", .{vm3.regs.readGP(0)});

    // Demo: Stack PUSH/POP
    const stack_demo = [_]u8{
        0x2B, 0x00, 0x2A, 0x00, 0x20, 0x00, 0x2B, 0x00, 0x00, 0x00, 0x21, 0x00, 0x80,
    };
    var vm4 = try Interpreter.init(allocator, &stack_demo, 65536);
    defer vm4.deinit();
    _ = try vm4.execute();
    try stdout.print("Stack push/pop: R0 = {} (expected 42)\n", .{vm4.regs.readGP(0)});

    // Benchmark
    const iters = 100_000;
    const start = std.time.nanoTimestamp();
    for (0..iters) |_| {
        var bvm = try Interpreter.init(allocator, &fact, 65536);
        _ = try bvm.execute();
        bvm.deinit();
    }
    const end = std.time.nanoTimestamp();
    const elapsed_ns: f64 = @floatFromInt(end - start);
    try stdout.print("\nBenchmark ({} iterations): {:.0} ns/iter, {:.0} iter/sec\n", .{iters, elapsed_ns / @as(f64, @floatFromInt(iters)), @as(f64, @floatFromInt(iters)) / (elapsed_ns / 1_000_000_000.0)});
    try stdout.print("All {} opcodes loaded.\n", .{countOpcodes()});
}

fn countOpcodes() usize {
    return comptime blk: {
        var count: usize = 0;
        @setEvalBranchQuota(2000);
        for (std.meta.fields(Op)) |field| {
            if (!std.mem.eql(u8, field.name, "unknown")) count += 1;
        }
        break :blk count;
    };
}

test "countOpcodes returns expected number" {
    try std.testing.expectEqual(@as(usize, 123), countOpcodes());
}
