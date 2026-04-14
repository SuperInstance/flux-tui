//! flux-tui — Standalone FLUX Micro-VM runtime (Zig port).
//!
//! Usage:
//!   flux-tui run <bytecode.bin>          Run a bytecode file
//!   flux-tui disasm <bytecode.bin>       Disassemble bytecode
//!   flux-tui version                     Print version

const std = @import("std");

const Interpreter = @import("flux/vm/interpreter.zig").Interpreter;
const Opcode = @import("flux/bytecode/opcodes.zig").Opcode;

pub const VERSION = "0.1.0-alpha";
pub const ISA_VERSION = "v3";

fn printUsage(prog: []const u8) void {
    std.debug.print(
        \\flux-tui {s} (ISA {s}) — FLUX Micro-VM Runtime
        \\
        \\Usage: {s} <command> [options]
        \\
        \\Commands:
        \\  run <file>       Execute a FLUX bytecode binary
        \\  disasm <file>    Disassemble a FLUX bytecode binary
        \\  version          Print version and ISA info
        \\  help             Show this help message
        \\
        \\Opcodes: 102 defined across 9 categories
        \\
    , .{ VERSION, ISA_VERSION, prog });
}

fn printVersion() void {
    std.debug.print(
        \\flux-tui {s}
        \\ISA:     FLUX {s}
        \\Opcodes: 102
        \\Regs:    64 (R0-R15, F0-F15, V0-V15)
        \\Memory:  Linear regions with capability-based access
        \\
    , .{ VERSION, ISA_VERSION });
}

fn disassemble(bytecode: []const u8) void {
    var pc: u32 = 0;
    std.debug.print("ADDR  OPCODE        MNEMONIC\n", .{});
    std.debug.print("────  ──────        ────────\n", .{});

    while (pc < bytecode.len) {
        const addr = pc;
        const op_byte = bytecode[pc];
        pc += 1;

        const op = std.meta.intToEnum(Opcode, op_byte) catch {
            std.debug.print("0x{X:0>4}  0x{X:0>2}          ???\n", .{ addr, op_byte });
            continue;
        };

        const name = op.name();
        const fmt = op.format();

        switch (fmt) {
            .A => {
                std.debug.print("0x{X:0>4}  0x{X:0>2}          {s}\n", .{ addr, op_byte, name });
            },
            .B => {
                if (pc < bytecode.len) {
                    const reg = bytecode[pc];
                    pc += 1;
                    std.debug.print("0x{X:0>4}  0x{X:0>2} {X:0>2}       {s} R{d}\n", .{ addr, op_byte, reg, name, reg });
                }
            },
            .C => {
                if (pc + 1 < bytecode.len) {
                    const rd = bytecode[pc];
                    const rs1 = bytecode[pc + 1];
                    pc += 2;
                    std.debug.print("0x{X:0>4}  0x{X:0>2} {X:0>2} {X:0>2}    {s} R{d}, R{d}\n", .{ addr, op_byte, rd, rs1, name, rd, rs1 });
                }
            },
            .D => {
                if (pc + 2 < bytecode.len) {
                    const rs1 = bytecode[pc];
                    const lo = bytecode[pc + 1];
                    const hi = bytecode[pc + 2];
                    pc += 3;
                    const offset: i16 = @bitCast(@as(u16, lo) | (@as(u16, hi) << 8));
                    if (op == .MOVI or op == .CALL or op == .TAILCALL) {
                        std.debug.print("0x{X:0>4}  0x{X:0>2} {X:0>2} {X:0>2} {X:0>2}  {s} R{d}, {d}\n", .{ addr, op_byte, rs1, lo, hi, name, rs1, offset });
                    } else {
                        std.debug.print("0x{X:0>4}  0x{X:0>2} {X:0>2} {X:0>2} {X:0>2}  {s} R{d}, {d}\n", .{ addr, op_byte, rs1, lo, hi, name, rs1, offset });
                    }
                }
            },
            .E => {
                if (pc + 2 < bytecode.len) {
                    const rd = bytecode[pc];
                    const rs1 = bytecode[pc + 1];
                    const rs2 = bytecode[pc + 2];
                    pc += 3;
                    std.debug.print("0x{X:0>4}  0x{X:0>2} {X:0>2} {X:0>2} {X:0>2}  {s} R{d}, R{d}, R{d}\n", .{ addr, op_byte, rd, rs1, rs2, name, rd, rs1, rs2 });
                }
            },
            .G => {
                if (pc + 1 < bytecode.len) {
                    const lo = bytecode[pc];
                    const hi = bytecode[pc + 1];
                    pc += 2;
                    const len: u16 = @as(u16, lo) | (@as(u16, hi) << 8);
                    const end = @min(pc + len, bytecode.len);
                    std.debug.print("0x{X:0>4}  0x{X:0>2} {X:0>2} {X:0>2}       {s} (len={d})\n", .{ addr, op_byte, lo, hi, name, len });
                    pc = end;
                }
            },
        }
    }
}

fn runBytecode(allocator: std.mem.Allocator, path: []const u8) !void {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const bytecode = try allocator.alloc(u8, @as(usize, stat.size));
    defer allocator.free(bytecode);

    const bytes_read = try file.readAll(bytecode);
    if (bytes_read != stat.size) {
        std.debug.print("Error: could not read entire file\n", .{});
        return error.ReadFailed;
    }

    std.debug.print("FLUX VM — executing {d} bytes of bytecode\n", .{bytecode.len});
    std.debug.print("ISA {s} | 102 opcodes | 64 registers\n\n", .{ISA_VERSION});

    var interp = try Interpreter.init(allocator, bytecode, 65536);
    defer interp.deinit();

    const cycles = interp.execute() catch |err| switch (err) {
        error.CycleBudgetExceeded => {
            std.debug.print("\nCycle budget exceeded ({d} cycles)\n", .{interp.cycle_count});
            std.debug.print("PC=0x{X:0>4} | halted={any}\n", .{ interp.pc, interp.halted });
            return;
        },
        else => return err,
    };

    std.debug.print("\nExecution complete: {d} cycles\n", .{cycles});
    std.debug.print("PC=0x{X:0>4} | halted={any}\n\n", .{ interp.pc, interp.halted });

    // Dump register state
    std.debug.print("General Purpose Registers:\n", .{});
    for (0..16) |i| {
        std.debug.print("  R{d:<2} = {d:>12}", .{ i, interp.regs.readGP(@intCast(i)) });
        if (i == 11) std.debug.print("  (SP)", .{});
        if (i == 14) std.debug.print("  (FP)", .{});
        if (i == 15) std.debug.print("  (LR)", .{});
        std.debug.print("\n", .{});
    }

    std.debug.print("\nFlags: zero={any} sign={any} carry={any} overflow={any}\n", .{
        interp.flag_zero,
        interp.flag_sign,
        interp.flag_carry,
        interp.flag_overflow,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        const prog = if (args.len > 0) args[0] else "flux-tui";
        printUsage(prog);
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "help")) {
        const prog = if (args.len > 0) args[0] else "flux-tui";
        printUsage(prog);
    } else if (std.mem.eql(u8, cmd, "version")) {
        printVersion();
    } else if (std.mem.eql(u8, cmd, "disasm")) {
        if (args.len < 3) {
            std.debug.print("Error: disasm requires a file argument\n", .{});
            return;
        }
        const path = args[2];
        const cwd = std.fs.cwd();
        const file = try cwd.openFile(path, .{});
        defer file.close();
        const stat = try file.stat();
        const buf = try allocator.alloc(u8, @as(usize, stat.size));
        defer allocator.free(buf);
        _ = try file.readAll(buf);
        disassemble(buf);
    } else if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 3) {
            std.debug.print("Error: run requires a file argument\n", .{});
            return;
        }
        try runBytecode(allocator, args[2]);
    } else {
        std.debug.print("Unknown command: {s}\n", .{cmd});
        const prog = if (args.len > 0) args[0] else "flux-tui";
        printUsage(prog);
    }
}
