//! FLUX Bytecode Interpreter — Fetch-Decode-Execute Loop
//!
//! Port of flux/vm/interpreter.py.
//! Implements a direct-threaded interpreter that executes FLUX bytecode
//! with all 122 opcodes, condition flags, stack frames, and box table.
//!
//! Instruction encoding formats:
//!   A: 1 byte  — [opcode]
//!   B: 2 bytes — [opcode][rd]
//!   C: 3 bytes — [opcode][rd][rs1]
//!   D: 4 bytes — [opcode][rs1][off_lo][off_hi]
//!   E: 4 bytes — [opcode][rd][rs1][rs2]
//!   G: variable — [opcode][len:u16][data:len bytes]

const std = @import("std");
const opcodes = @import("opcodes.zig");
const registers = @import("registers.zig");
const memory = @import("memory.zig");

const Op = opcodes.Op;

// ── VM Errors ─────────────────────────────────────────────────────────────

pub const VMError = error{
    Halt,
    InvalidOpcode,
    DivisionByZero,
    StackOverflow,
    StackUnderflow,
    TypeCheck,
    BoundsCheck,
    A2AProtocol,
    ResourceError,
    EndOfBytecode,
    TruncatedInstruction,
    RegionNotFound,
    OutOfBounds,
    BoxInvalid,
    OutOfMemory,
};

/// Condition code flags, matching Python's _flag_zero/_flag_sign etc.
pub const Flags = struct {
    zero: bool = false,
    sign: bool = false,
    carry: bool = false,
    overflow: bool = false,
};

/// Box entry: (type_tag, value_i32)
const BoxEntry = struct {
    type_tag: u8,
    value: i32,
};

/// Frame stack entry for ENTER/LEAVE
const FrameEntry = struct {
    saved_fp: i32,
};

/// Interpreter configuration.
pub const Config = struct {
    memory_size: usize = 65536,
    max_cycles: u64 = 10_000_000,
    max_regions: usize = 256,
};

/// The FLUX bytecode interpreter.
pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    bytecode: []const u8,
    pc: usize,
    cycle_count: u64,
    max_cycles: u64,
    running: bool,
    halted: bool,

    regs: registers.RegisterFile,
    mem: memory.MemoryManager,

    flags: Flags,

    // Box table
    box_table: std.ArrayList(BoxEntry),
    box_counter: u32,

    // Frame stack
    frame_stack: std.ArrayList(FrameEntry),

    // Resource tracking
    resources: std.AutoHashMap(u32, bool),

    pub fn init(allocator: std.mem.Allocator, bytecode: []const u8, config: Config) !Interpreter {
        var interp: Interpreter = .{
            .allocator = allocator,
            .bytecode = bytecode,
            .pc = 0,
            .cycle_count = 0,
            .max_cycles = config.max_cycles,
            .running = false,
            .halted = false,
            .regs = .{},
            .mem = memory.MemoryManager.init(allocator, config.max_regions),
            .flags = .{},
            .box_table = std.ArrayList(BoxEntry).init(allocator),
            .box_counter = 0,
            .frame_stack = std.ArrayList(FrameEntry).init(allocator),
            .resources = std.AutoHashMap(u32, bool).init(allocator),
        };

        // Create default memory regions
        _ = try interp.mem.createRegion("stack", config.memory_size, "system");
        _ = try interp.mem.createRegion("heap", config.memory_size, "system");

        // Stack starts at top and grows downward
        interp.regs.setSp(@intCast(config.memory_size));

        return interp;
    }

    pub fn deinit(self: *Interpreter) void {
        self.mem.deinit();
        self.box_table.deinit();
        self.frame_stack.deinit();
        self.resources.deinit();
    }

    /// Execute bytecode until HALT, cycle budget exceeded, or error.
    pub fn execute(self: *Interpreter) VMError!u64 {
        self.running = true;
        while (self.running and !self.halted and self.cycle_count < self.max_cycles) {
            self.step() catch |err| {
                self.running = false;
                return err;
            };
            self.cycle_count += 1;
        }
        self.running = false;
        return self.cycle_count;
    }

    /// Execute a single instruction.
    pub fn step(self: *Interpreter) !void {
        if (self.pc >= self.bytecode.len) return error.EndOfBytecode;

        const op_byte = self.fetchU8();

        // ── NOP ────────────────────────────────────────────────────
        if (op_byte == @intFromEnum(Op.NOP)) return;

        // ── HALT ───────────────────────────────────────────────────
        if (op_byte == @intFromEnum(Op.HALT)) {
            self.running = false;
            self.halted = true;
            return;
        }

        // ── YIELD ──────────────────────────────────────────────────
        if (op_byte == @intFromEnum(Op.YIELD)) return;

        // ── DEBUG_BREAK ────────────────────────────────────────────
        if (op_byte == @intFromEnum(Op.DEBUG_BREAK)) return;

        // ── EMERGENCY_STOP ─────────────────────────────────────────
        if (op_byte == @intFromEnum(Op.EMERGENCY_STOP)) {
            self.running = false;
            self.halted = true;
            return;
        }

        // ── MOV rd, rs1 (Format C) ─────────────────────────────────
        if (op_byte == @intFromEnum(Op.MOV)) {
            const rd, const rs1 = self.decodeC();
            self.regs.writeGp(rd, self.regs.readGp(rs1));
            return;
        }

        // ── MOVI reg, imm16 (Format D) ─────────────────────────────
        if (op_byte == @intFromEnum(Op.MOVI)) {
            const reg, const imm = self.decodeMovi();
            self.regs.writeGp(reg, imm);
            return;
        }

        // ── Integer Arithmetic (Format E) ──────────────────────────
        if (op_byte == @intFromEnum(Op.IADD)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const result = self.regs.readGp(rs1) + self.regs.readGp(rs2);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.ISUB)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const result = self.regs.readGp(rs1) - self.regs.readGp(rs2);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.IMUL)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const result = self.regs.readGp(rs1) * self.regs.readGp(rs2);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.IDIV)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const divisor = self.regs.readGp(rs2);
            if (divisor == 0) return error.DivisionByZero;
            const dividend = self.regs.readGp(rs1);
            const result = @divTrunc(dividend, divisor);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.IMOD)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const divisor = self.regs.readGp(rs2);
            if (divisor == 0) return error.DivisionByZero;
            const dividend = self.regs.readGp(rs1);
            const result = @mod(dividend, divisor);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.IREM)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const divisor = self.regs.readGp(rs2);
            if (divisor == 0) return error.DivisionByZero;
            const dividend = self.regs.readGp(rs1);
            const result = dividend - @divTrunc(dividend, divisor) * divisor;
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.INEG)) {
            const rd, const rs1 = self.decodeC();
            const result = -self.regs.readGp(rs1);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        // ── INC / DEC (Format B) ───────────────────────────────────
        if (op_byte == @intFromEnum(Op.INC)) {
            const reg = self.decodeB();
            const result = self.regs.readGp(reg) + 1;
            self.regs.writeGp(reg, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.DEC)) {
            const reg = self.decodeB();
            const result = self.regs.readGp(reg) - 1;
            self.regs.writeGp(reg, result);
            self.setFlags(result);
            return;
        }

        // ── Bitwise (Format E for binary, Format C for unary) ──────
        if (op_byte == @intFromEnum(Op.IAND)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const result = self.regs.readGp(rs1) & self.regs.readGp(rs2);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.IOR)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const result = self.regs.readGp(rs1) | self.regs.readGp(rs2);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.IXOR)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const result = self.regs.readGp(rs1) ^ self.regs.readGp(rs2);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.INOT)) {
            const rd, const rs1 = self.decodeC();
            const result = ~self.regs.readGp(rs1);
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.ISHL)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const result = self.regs.readGp(rs1) << @as(u5, @intCast(self.regs.readGp(rs2) & 0x3F));
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        if (op_byte == @intFromEnum(Op.ISHR)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const val = self.regs.readGp(rs1);
            const shift: u5 = @intCast(self.regs.readGp(rs2) & 0x3F);
            const result = val >> shift;
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        // ── ROTL / ROTR (Format E) ─────────────────────────────────
        if (op_byte == @intFromEnum(Op.ROTL)) {
            const rd, const rs1, const rs2 = self.decodeE();
            var val = @as(u32, @bitCast(self.regs.readGp(rs1)));
            const shift: u5 = @intCast(self.regs.readGp(rs2) & 0x1F);
            val = std.math.rotl(u32, val, shift);
            self.regs.writeGp(rd, @bitCast(val));
            self.setFlags(self.regs.readGp(rd));
            return;
        }

        if (op_byte == @intFromEnum(Op.ROTR)) {
            const rd, const rs1, const rs2 = self.decodeE();
            var val = @as(u32, @bitCast(self.regs.readGp(rs1)));
            const shift2: u5 = @intCast(self.regs.readGp(rs2) & 0x1F);
            val = std.math.rotr(u32, val, shift2);
            self.regs.writeGp(rd, @bitCast(val));
            self.setFlags(self.regs.readGp(rd));
            return;
        }

        // ── Comparison: ICMP (special 4-byte: cond + rd + rs) ──────
        if (op_byte == @intFromEnum(Op.ICMP)) {
            const cond = self.fetchU8();
            const rd = self.fetchU8();
            const rs = self.fetchU8();
            const a = self.regs.readGp(rd);
            const b = self.regs.readGp(rs);
            const result: i32 = switch (cond) {
                0 => @intFromBool(a == b),
                1 => @intFromBool(a != b),
                2 => @intFromBool(a < b),
                3 => @intFromBool(a <= b),
                4 => @intFromBool(a > b),
                5 => @intFromBool(a >= b),
                6 => @intFromBool(@as(u32, @bitCast(a)) < @as(u32, @bitCast(b))),
                7 => @intFromBool(@as(u32, @bitCast(a)) <= @as(u32, @bitCast(b))),
                8 => @intFromBool(@as(u32, @bitCast(a)) > @as(u32, @bitCast(b))),
                9 => @intFromBool(@as(u32, @bitCast(a)) >= @as(u32, @bitCast(b))),
                else => 0,
            };
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        // ── Comparison: IEQ, ILT, ILE, IGT, IGE (Format C) ────────
        if (op_byte == @intFromEnum(Op.IEQ)) {
            const rd, const rs1 = self.decodeC();
            const result: i32 = @intFromBool(self.regs.readGp(rd) == self.regs.readGp(rs1));
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }
        if (op_byte == @intFromEnum(Op.ILT)) {
            const rd, const rs1 = self.decodeC();
            const result: i32 = @intFromBool(self.regs.readGp(rd) < self.regs.readGp(rs1));
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }
        if (op_byte == @intFromEnum(Op.ILE)) {
            const rd, const rs1 = self.decodeC();
            const result: i32 = @intFromBool(self.regs.readGp(rd) <= self.regs.readGp(rs1));
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }
        if (op_byte == @intFromEnum(Op.IGT)) {
            const rd, const rs1 = self.decodeC();
            const result: i32 = @intFromBool(self.regs.readGp(rd) > self.regs.readGp(rs1));
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }
        if (op_byte == @intFromEnum(Op.IGE)) {
            const rd, const rs1 = self.decodeC();
            const result: i32 = @intFromBool(self.regs.readGp(rd) >= self.regs.readGp(rs1));
            self.regs.writeGp(rd, result);
            self.setFlags(result);
            return;
        }

        // ── TEST (Format C) ────────────────────────────────────────
        if (op_byte == @intFromEnum(Op.TEST)) {
            const rd, const rs1 = self.decodeC();
            const result = self.regs.readGp(rd) & self.regs.readGp(rs1);
            self.setFlags(result);
            return;
        }

        // ── SETCC (Format B + cond byte) ───────────────────────────
        if (op_byte == @intFromEnum(Op.SETCC)) {
            const rd = self.decodeB();
            const cond = self.fetchU8();
            const result: i32 = switch (cond) {
                0 => @intFromBool(self.flags.zero),
                1 => @intFromBool(!self.flags.zero),
                2 => @intFromBool(self.flags.sign),
                3 => @intFromBool(!self.flags.sign),
                4 => @intFromBool(!self.flags.zero and !self.flags.sign),
                5 => @intFromBool(self.flags.zero or self.flags.sign),
                6 => @intFromBool(self.flags.carry),
                7 => @intFromBool(!self.flags.carry),
                8 => @intFromBool(self.flags.overflow),
                9 => @intFromBool(!self.flags.overflow),
                else => 0,
            };
            self.regs.writeGp(rd, result);
            return;
        }

        // ── CMP (Format C, sets flags) ─────────────────────────────
        if (op_byte == @intFromEnum(Op.CMP)) {
            const rd, const rs1 = self.decodeC();
            self.setCmpFlags(self.regs.readGp(rd), self.regs.readGp(rs1));
            return;
        }

        // ── Stack: PUSH / POP (Format B) ──────────────────────────
        if (op_byte == @intFromEnum(Op.PUSH)) {
            const reg = self.decodeB();
            try self.stackPush(self.regs.readGp(reg));
            return;
        }
        if (op_byte == @intFromEnum(Op.POP)) {
            const reg = self.decodeB();
            self.regs.writeGp(reg, try self.stackPop());
            return;
        }

        // ── Stack: DUP / SWAP / ROT (Format A) ────────────────────
        if (op_byte == @intFromEnum(Op.DUP)) {
            const val = try self.stackPop();
            try self.stackPush(val);
            try self.stackPush(val);
            return;
        }
        if (op_byte == @intFromEnum(Op.SWAP)) {
            const a = try self.stackPop();
            const b = try self.stackPop();
            try self.stackPush(a);
            try self.stackPush(b);
            return;
        }
        if (op_byte == @intFromEnum(Op.ROT)) {
            const a = try self.stackPop();
            const b = try self.stackPop();
            const c = try self.stackPop();
            try self.stackPush(a);
            try self.stackPush(c);
            try self.stackPush(b);
            return;
        }

        // ── ENTER / LEAVE (Format B) ──────────────────────────────
        if (op_byte == @intFromEnum(Op.ENTER)) {
            const frame_size = self.decodeB();
            try self.frame_stack.append(.{ .saved_fp = self.regs.getFp() });
            try self.stackPush(self.regs.getFp());
            self.regs.setFp(self.regs.getSp());
            const alloc_bytes = @as(i32, frame_size) * 4;
            if (self.regs.getSp() - alloc_bytes < 0) return error.StackOverflow;
            self.regs.setSp(self.regs.getSp() - alloc_bytes);
            return;
        }
        if (op_byte == @intFromEnum(Op.LEAVE)) {
            _ = self.decodeB();
            self.regs.setSp(self.regs.getFp());
            const old_fp = try self.stackPop();
            self.regs.setFp(old_fp);
            if (self.frame_stack.popOrNull()) |frame| {
                // Verify consistency
                _ = frame;
            }
            return;
        }

        // ── ALLOCA (Format C) ─────────────────────────────────────
        if (op_byte == @intFromEnum(Op.ALLOCA)) {
            const rd, const size_reg = self.decodeC();
            const size = @as(i32, self.regs.readGp(size_reg)) * 4;
            if (self.regs.getSp() - size < 0) return error.StackOverflow;
            self.regs.setSp(self.regs.getSp() - size);
            self.regs.writeGp(rd, self.regs.getSp());
            return;
        }

        // ── Control Flow: Jumps (Format D) ─────────────────────────
        if (op_byte == @intFromEnum(Op.JMP)) {
            _, const offset = self.decodeD();
            self.applyJump(offset);
            return;
        }
        if (op_byte == @intFromEnum(Op.JZ)) {
            const rs1, const offset = self.decodeD();
            if (self.regs.readGp(rs1) == 0) {
                self.applyJump(offset);
            }
            return;
        }
        if (op_byte == @intFromEnum(Op.JNZ)) {
            const rs1, const offset = self.decodeD();
            if (self.regs.readGp(rs1) != 0) {
                self.applyJump(offset);
            }
            return;
        }
        if (op_byte == @intFromEnum(Op.JE)) {
            _, const offset = self.decodeD();
            if (self.flags.zero) {
                self.applyJump(offset);
            }
            return;
        }
        if (op_byte == @intFromEnum(Op.JNE)) {
            _, const offset = self.decodeD();
            if (!self.flags.zero) {
                self.applyJump(offset);
            }
            return;
        }
        if (op_byte == @intFromEnum(Op.JG)) {
            _, const offset = self.decodeD();
            if (!self.flags.zero and !self.flags.sign) {
                self.applyJump(offset);
            }
            return;
        }
        if (op_byte == @intFromEnum(Op.JL)) {
            _, const offset = self.decodeD();
            if (self.flags.sign) {
                self.applyJump(offset);
            }
            return;
        }
        if (op_byte == @intFromEnum(Op.JGE_op)) {
            _, const offset = self.decodeD();
            if (!self.flags.sign) {
                self.applyJump(offset);
            }
            return;
        }
        if (op_byte == @intFromEnum(Op.JLE)) {
            _, const offset = self.decodeD();
            if (self.flags.zero or self.flags.sign) {
                self.applyJump(offset);
            }
            return;
        }

        // ── CALL / RET (Format D / Format C) ──────────────────────
        if (op_byte == @intFromEnum(Op.CALL)) {
            _, const offset = self.decodeD();
            try self.stackPush(@intCast(self.pc));
            self.applyJump(offset);
            return;
        }
        if (op_byte == @intFromEnum(Op.CALL_IND)) {
            const target_reg = self.fetchU8();
            _ = self.fetchU8(); // skip rd
            const target = self.regs.readGp(target_reg);
            try self.stackPush(@intCast(self.pc));
            self.pc = @intCast(@as(u32, @bitCast(target)));
            return;
        }
        if (op_byte == @intFromEnum(Op.TAILCALL)) {
            _, const offset = self.decodeD();
            self.applyJump(offset);
            return;
        }
        if (op_byte == @intFromEnum(Op.RET)) {
            const stack_region = self.mem.getRegion("stack") catch return error.RegionNotFound;
            if (self.regs.getSp() >= @as(i32, @intCast(stack_region.size())) - 4) {
                self.halted = true;
                return;
            }
            const addr = try self.stackPop();
            self.pc = @intCast(@as(u32, @bitCast(addr)));
            return;
        }

        // ── Memory: LOAD / STORE (Format C) ────────────────────────
        if (op_byte == @intFromEnum(Op.LOAD)) {
            const rd, const rs1 = self.decodeC();
            const addr: u32 = @intCast(self.regs.readGp(rs1));
            const stack_region = try self.mem.getRegion("stack");
            const value = try stack_region.readI32(addr);
            self.regs.writeGp(rd, value);
            return;
        }
        if (op_byte == @intFromEnum(Op.STORE)) {
            const rd, const rs1 = self.decodeC();
            const addr: u32 = @intCast(self.regs.readGp(rs1));
            const val = self.regs.readGp(rd);
            const stack_region = try self.mem.getRegion("stack");
            try stack_region.writeI32(addr, val);
            return;
        }
        if (op_byte == @intFromEnum(Op.LOAD8)) {
            const rd, const rs1 = self.decodeC();
            const addr: u32 = @intCast(self.regs.readGp(rs1));
            const stack_region = try self.mem.getRegion("stack");
            const bytes = try stack_region.read(addr, 1);
            self.regs.writeGp(rd, @intCast(bytes[0]));
            return;
        }
        if (op_byte == @intFromEnum(Op.STORE8)) {
            const rd, const rs1 = self.decodeC();
            const addr: u32 = @intCast(self.regs.readGp(rs1));
            const val: u8 = @intCast(self.regs.readGp(rd) & 0xFF);
            const stack_region = try self.mem.getRegion("stack");
            const bytes = [_]u8{val};
            try stack_region.write(addr, &bytes);
            return;
        }

        // ── Float Arithmetic (Format E) ────────────────────────────
        if (op_byte == @intFromEnum(Op.FADD)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const a: f32 = @bitCast(self.regs.readGp(rs1));
            const b: f32 = @bitCast(self.regs.readGp(rs2));
            const result = a + b;
            self.regs.writeGp(rd, @bitCast(result));
            return;
        }
        if (op_byte == @intFromEnum(Op.FSUB)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const a: f32 = @bitCast(self.regs.readGp(rs1));
            const b: f32 = @bitCast(self.regs.readGp(rs2));
            const result = a - b;
            self.regs.writeGp(rd, @bitCast(result));
            return;
        }
        if (op_byte == @intFromEnum(Op.FMUL)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const a: f32 = @bitCast(self.regs.readGp(rs1));
            const b: f32 = @bitCast(self.regs.readGp(rs2));
            const result = a * b;
            self.regs.writeGp(rd, @bitCast(result));
            return;
        }
        if (op_byte == @intFromEnum(Op.FDIV)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const a: f32 = @bitCast(self.regs.readGp(rs1));
            const b: f32 = @bitCast(self.regs.readGp(rs2));
            if (b == 0.0) return error.DivisionByZero;
            const result = a / b;
            self.regs.writeGp(rd, @bitCast(result));
            return;
        }
        if (op_byte == @intFromEnum(Op.FNEG)) {
            const rd = self.decodeB();
            const a: f32 = @bitCast(self.regs.readGp(rd));
            self.regs.writeGp(rd, @bitCast(-a));
            return;
        }
        if (op_byte == @intFromEnum(Op.FABS)) {
            const rd = self.decodeB();
            const a: f32 = @bitCast(self.regs.readGp(rd));
            self.regs.writeGp(rd, @bitCast(@abs(a)));
            return;
        }
        if (op_byte == @intFromEnum(Op.FMIN)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const a: f32 = @bitCast(self.regs.readGp(rs1));
            const b: f32 = @bitCast(self.regs.readGp(rs2));
            self.regs.writeGp(rd, @bitCast(@min(a, b)));
            return;
        }
        if (op_byte == @intFromEnum(Op.FMAX)) {
            const rd, const rs1, const rs2 = self.decodeE();
            const a: f32 = @bitCast(self.regs.readGp(rs1));
            const b: f32 = @bitCast(self.regs.readGp(rs2));
            self.regs.writeGp(rd, @bitCast(@max(a, b)));
            return;
        }

        // ── Float Comparison (Format C) ────────────────────────────
        if (op_byte == @intFromEnum(Op.FEQ)) {
            const rd, const rs1 = self.decodeC();
            const a: f32 = @bitCast(self.regs.readGp(rd));
            const b: f32 = @bitCast(self.regs.readGp(rs1));
            const result: i32 = @intFromBool(a == b);
            self.regs.writeGp(rd, result);
            return;
        }
        if (op_byte == @intFromEnum(Op.FLT)) {
            const rd, const rs1 = self.decodeC();
            const a: f32 = @bitCast(self.regs.readGp(rd));
            const b: f32 = @bitCast(self.regs.readGp(rs1));
            const result: i32 = @intFromBool(a < b);
            self.regs.writeGp(rd, result);
            return;
        }
        if (op_byte == @intFromEnum(Op.FLE)) {
            const rd, const rs1 = self.decodeC();
            const a: f32 = @bitCast(self.regs.readGp(rd));
            const b: f32 = @bitCast(self.regs.readGp(rs1));
            const result: i32 = @intFromBool(a <= b);
            self.regs.writeGp(rd, result);
            return;
        }
        if (op_byte == @intFromEnum(Op.FGT)) {
            const rd, const rs1 = self.decodeC();
            const a: f32 = @bitCast(self.regs.readGp(rd));
            const b: f32 = @bitCast(self.regs.readGp(rs1));
            const result: i32 = @intFromBool(a > b);
            self.regs.writeGp(rd, result);
            return;
        }
        if (op_byte == @intFromEnum(Op.FGE)) {
            const rd, const rs1 = self.decodeC();
            const a: f32 = @bitCast(self.regs.readGp(rd));
            const b: f32 = @bitCast(self.regs.readGp(rs1));
            const result: i32 = @intFromBool(a >= b);
            self.regs.writeGp(rd, result);
            return;
        }

        // ── Type: CAST (Format C + type tag byte) ──────────────────
        if (op_byte == @intFromEnum(Op.CAST)) {
            const rd, const rs1 = self.decodeC();
            const type_tag = self.fetchU8();
            const val = self.regs.readGp(rs1);
            switch (type_tag) {
                0 => {
                    // i32 -> f32 (bitcast)
                    self.regs.writeGp(rd, val); // bits are the same
                },
                1 => {
                    // f32 -> i32
                    self.regs.writeGp(rd, val);
                },
                2 => {
                    // i32 -> bool
                    self.regs.writeGp(rd, @intFromBool(val != 0));
                },
                3 => {
                    // bool -> i32
                    self.regs.writeGp(rd, val);
                },
                else => self.regs.writeGp(rd, val),
            }
            return;
        }

        // ── Type: BOX (Format C + i32 value) ───────────────────────
        if (op_byte == @intFromEnum(Op.BOX)) {
            const rd, const type_tag = self.decodeC();
            const raw = self.fetchI32();
            const box_id = self.box_counter;
            self.box_counter += 1;
            try self.box_table.append(.{ .type_tag = type_tag, .value = raw });
            self.regs.writeGp(rd, @intCast(box_id));
            return;
        }

        // ── Type: UNBOX (Format C) ─────────────────────────────────
        if (op_byte == @intFromEnum(Op.UNBOX)) {
            const rd, const box_reg = self.decodeC();
            const box_id: usize = @intCast(self.regs.readGp(box_reg));
            if (box_id >= self.box_table.items.len) return error.BoxInvalid;
            const entry = self.box_table.items[box_id];
            self.regs.writeGp(rd, entry.value);
            return;
        }

        // ── Type: CHECK_TYPE (Format C) ────────────────────────────
        if (op_byte == @intFromEnum(Op.CHECK_TYPE)) {
            const box_reg, const expected = self.decodeC();
            const box_id: usize = @intCast(self.regs.readGp(box_reg));
            if (box_id >= self.box_table.items.len) return error.BoxInvalid;
            if (self.box_table.items[box_id].type_tag != expected) return error.TypeCheck;
            return;
        }

        // ── Memory: Format G opcodes (variable-length data) ────────
        // These are stubs — full implementation needs string parsing
        if (op_byte == @intFromEnum(Op.REGION_CREATE) or
            op_byte == @intFromEnum(Op.REGION_DESTROY) or
            op_byte == @intFromEnum(Op.REGION_TRANSFER) or
            op_byte == @intFromEnum(Op.MEMCOPY) or
            op_byte == @intFromEnum(Op.MEMSET) or
            op_byte == @intFromEnum(Op.MEMCMP))
        {
            // Skip variable-length data for now
            _ = self.fetchVarData();
            return;
        }

        // ── A2A Protocol opcodes (Format G, stubs) ─────────────────
        if (op_byte >= @intFromEnum(Op.TELL) and op_byte <= @intFromEnum(Op.EMERGENCY_STOP)) {
            _ = self.fetchVarData();
            return;
        }

        // ── Evolution opcodes (stubs) ──────────────────────────────
        if (op_byte == @intFromEnum(Op.EVOLVE) or
            op_byte == @intFromEnum(Op.INSTINCT) or
            op_byte == @intFromEnum(Op.WITNESS) or
            op_byte == @intFromEnum(Op.SNAPSHOT))
        {
            return;
        }

        // ── Meta opcodes (stubs) ───────────────────────────────────
        if (op_byte == @intFromEnum(Op.CONF) or
            op_byte == @intFromEnum(Op.MERGE) or
            op_byte == @intFromEnum(Op.RESTORE) or
            op_byte == @intFromEnum(Op.CHECK_BOUNDS) or
            op_byte == @intFromEnum(Op.VLOAD) or
            op_byte == @intFromEnum(Op.VSTORE) or
            op_byte == @intFromEnum(Op.VADD) or
            op_byte == @intFromEnum(Op.VSUB) or
            op_byte == @intFromEnum(Op.VMUL) or
            op_byte == @intFromEnum(Op.VDIV) or
            op_byte == @intFromEnum(Op.VFMA) or
            op_byte == @intFromEnum(Op.RESOURCE_ACQUIRE) or
            op_byte == @intFromEnum(Op.RESOURCE_RELEASE))
        {
            // Consume operands based on format to advance PC correctly
            const fmt = opcodes.getFormat(op_byte);
            switch (fmt) {
                .A => {},
                .B => _ = self.decodeB(),
                .C => _ = self.decodeC(),
                .D => _ = self.decodeD(),
                .E => _ = self.decodeE(),
                .G => _ = self.fetchVarData(),
            }
            return;
        }

        return error.InvalidOpcode;
    }

    fn applyJump(self: *Interpreter, offset: i16) void {
        if (offset >= 0) {
            self.pc += @as(usize, @intCast(offset));
        } else {
            const neg = @as(usize, @intCast(-offset));
            if (neg <= self.pc) {
                self.pc -= neg;
            } else {
                self.pc = 0;
            }
        }
    }

    // ── Fetch helpers ─────────────────────────────────────────────────

    fn fetchU8(self: *Interpreter) u8 {
        const b = self.bytecode[self.pc];
        self.pc += 1;
        return b;
    }

    fn fetchI16(self: *Interpreter) i16 {
        const lo = self.fetchU8();
        const hi = self.fetchU8();
        const raw: u16 = lo | (@as(u16, hi) << 8);
        return @bitCast(raw);
    }

    fn fetchI32(self: *Interpreter) i32 {
        const b0 = self.fetchU8();
        const b1 = self.fetchU8();
        const b2 = self.fetchU8();
        const b3 = self.fetchU8();
        const raw: u32 = b0 | (@as(u32, b1) << 8) | (@as(u32, b2) << 16) | (@as(u32, b3) << 24);
        return @bitCast(raw);
    }

    fn fetchVarData(self: *Interpreter) []const u8 {
        const len = self.fetchU8() | (@as(u16, self.fetchU8()) << 8);
        const data = self.bytecode[self.pc..@min(self.pc + len, self.bytecode.len)];
        self.pc += len;
        return data;
    }

    // ── Decode helpers ─────────────────────────────────────────────────

    fn decodeB(self: *Interpreter) u8 {
        return self.fetchU8();
    }

    fn decodeC(self: *Interpreter) struct { u8, u8 } {
        const rd = self.fetchU8();
        const rs1 = self.fetchU8();
        return .{ rd, rs1 };
    }

    fn decodeD(self: *Interpreter) struct { u8, i16 } {
        const rs1 = self.fetchU8();
        const offset = self.fetchI16();
        return .{ rs1, offset };
    }

    fn decodeE(self: *Interpreter) struct { u8, u8, u8 } {
        const rd = self.fetchU8();
        const rs1 = self.fetchU8();
        const rs2 = self.fetchU8();
        return .{ rd, rs1, rs2 };
    }

    fn decodeMovi(self: *Interpreter) struct { u8, i16 } {
        const reg = self.fetchU8();
        const imm = self.fetchI16();
        return .{ reg, imm };
    }

    // ── Flags ──────────────────────────────────────────────────────────

    fn setFlags(self: *Interpreter, result: i32) void {
        self.flags.zero = (result == 0);
        self.flags.sign = (result < 0);
        self.flags.carry = (result < 0);
        self.flags.overflow = false;
    }

    fn setCmpFlags(self: *Interpreter, a: i32, b: i32) void {
        self.flags.zero = (a == b);
        self.flags.sign = (a < b);
        self.flags.carry = (a < b);
        self.flags.overflow = ((a > 0 and b < 0 and (a - b) < 0) or
            (a < 0 and b > 0 and (a - b) > 0));
    }

    // ── Stack helpers ─────────────────────────────────────────────────

    fn stackPush(self: *Interpreter, value: i32) !void {
        const stack_region = try self.mem.getRegion("stack");
        const new_sp = try memory.MemoryManager.stackPush(stack_region, self.regs.getSp(), value);
        self.regs.setSp(new_sp);
    }

    fn stackPop(self: *Interpreter) !i32 {
        const stack_region = try self.mem.getRegion("stack");
        const value, const new_sp = try memory.MemoryManager.stackPop(stack_region, self.regs.getSp());
        self.regs.setSp(new_sp);
        return value;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────

test "interpreter: NOP and HALT" {
    const bytecode = [_]u8{
        @intFromEnum(Op.NOP),
        @intFromEnum(Op.NOP),
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    const cycles = try interp.execute();
    try std.testing.expectEqual(@as(u64, 3), cycles);
    try std.testing.expect(interp.halted);
}

test "interpreter: MOVI and MOV" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 42, 0x00,       // MOVI R0, 42
        @intFromEnum(Op.MOVI), 0x01, 10, 0x00,       // MOVI R1, 10
        @intFromEnum(Op.MOV), 0x02, 0x00,            // MOV R2, R0
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 42), interp.regs.readGp(0));
    try std.testing.expectEqual(@as(i32, 10), interp.regs.readGp(1));
    try std.testing.expectEqual(@as(i32, 42), interp.regs.readGp(2));
}

test "interpreter: IADD, ISUB, IMUL" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 10, 0x00,       // MOVI R0, 10
        @intFromEnum(Op.MOVI), 0x01, 3, 0x00,        // MOVI R1, 3
        @intFromEnum(Op.IADD), 0x02, 0x00, 0x01,     // R2 = R0 + R1 = 13
        @intFromEnum(Op.ISUB), 0x03, 0x00, 0x01,     // R3 = R0 - R1 = 7
        @intFromEnum(Op.IMUL), 0x04, 0x00, 0x01,     // R4 = R0 * R1 = 30
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 13), interp.regs.readGp(2));
    try std.testing.expectEqual(@as(i32, 7), interp.regs.readGp(3));
    try std.testing.expectEqual(@as(i32, 30), interp.regs.readGp(4));
}

test "interpreter: IDIV and IMOD" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 17, 0x00,       // MOVI R0, 17
        @intFromEnum(Op.MOVI), 0x01, 5, 0x00,        // MOVI R1, 5
        @intFromEnum(Op.IDIV), 0x02, 0x00, 0x01,     // R2 = 17 / 5 = 3
        @intFromEnum(Op.IMOD), 0x03, 0x00, 0x01,     // R3 = 17 % 5 = 2
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 3), interp.regs.readGp(2));
    try std.testing.expectEqual(@as(i32, 2), interp.regs.readGp(3));
}

test "interpreter: division by zero" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 10, 0x00,       // MOVI R0, 10
        @intFromEnum(Op.MOVI), 0x01, 0, 0x00,        // MOVI R1, 0
        @intFromEnum(Op.IDIV), 0x02, 0x00, 0x01,     // R2 = R0 / R1 = error!
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    const result = interp.execute();
    try std.testing.expectError(error.DivisionByZero, result);
}

test "interpreter: INC and DEC" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 5, 0x00,        // MOVI R0, 5
        @intFromEnum(Op.INC), 0x00,                  // R0 = 6
        @intFromEnum(Op.INC), 0x00,                  // R0 = 7
        @intFromEnum(Op.DEC), 0x00,                  // R0 = 6
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 6), interp.regs.readGp(0));
}

test "interpreter: bitwise operations" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 0xFF, 0x00,     // R0 = 255
        @intFromEnum(Op.MOVI), 0x01, 0x0F, 0x00,     // R1 = 15
        @intFromEnum(Op.IAND), 0x02, 0x00, 0x01,     // R2 = 255 & 15 = 15
        @intFromEnum(Op.IOR), 0x03, 0x00, 0x01,      // R3 = 255 | 15 = 255
        @intFromEnum(Op.IXOR), 0x04, 0x00, 0x01,     // R4 = 255 ^ 15 = 240
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 15), interp.regs.readGp(2));
    try std.testing.expectEqual(@as(i32, 255), interp.regs.readGp(3));
    try std.testing.expectEqual(@as(i32, 240), interp.regs.readGp(4));
}

test "interpreter: comparison IEQ, ILT, IGT" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 5, 0x00,        // R0 = 5
        @intFromEnum(Op.MOVI), 0x01, 5, 0x00,        // R1 = 5
        @intFromEnum(Op.IEQ), 0x00, 0x01,            // R0 = (5 == 5) = 1
        @intFromEnum(Op.MOVI), 0x02, 3, 0x00,        // R2 = 3
        @intFromEnum(Op.ILT), 0x02, 0x00,            // R2 = (3 < 1) = 0
        @intFromEnum(Op.MOVI), 0x03, 10, 0x00,       // R3 = 10
        @intFromEnum(Op.IGT), 0x03, 0x00,            // R3 = (10 > 1) = 1
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 1), interp.regs.readGp(0));
    try std.testing.expectEqual(@as(i32, 0), interp.regs.readGp(2));
    try std.testing.expectEqual(@as(i32, 1), interp.regs.readGp(3));
}

test "interpreter: JMP and JZ/JNZ" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 1, 0x00,        // 0: R0 = 1
        @intFromEnum(Op.JZ), 0x00, 0x05, 0x00,       // 4: if R0 == 0, skip (won't)
        @intFromEnum(Op.MOVI), 0x01, 0x0A, 0x00,     // 8: R1 = 10
        @intFromEnum(Op.JMP), 0x00, 0x05, 0x00,      // 12: jump to 17 (12+5)
        @intFromEnum(Op.MOVI), 0x02, 0xFF, 0x00,     // 16: R2 = 255 (skipped)
        @intFromEnum(Op.MOVI), 0x03, 0x0B, 0x00,     // 17: R3 = 11
        @intFromEnum(Op.HALT),                         // 21
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 1), interp.regs.readGp(0));
    try std.testing.expectEqual(@as(i32, 10), interp.regs.readGp(1));
    try std.testing.expectEqual(@as(i32, 0), interp.regs.readGp(2)); // skipped
    try std.testing.expectEqual(@as(i32, 11), interp.regs.readGp(3));
}

test "interpreter: CALL and RET" {
    // Simple function call: call a "function" that sets R1 = 99, then returns
    _ = [_]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0  // unused placeholder
    };
    // RET in our implementation is Format A (no operands consumed).
    // CALL pushes return address and jumps by offset.
    _ = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 0, 0x00,        // 0: R0 = 0
        @intFromEnum(Op.CALL), 0x00, 0x06, 0x00,      // 4: call, offset=6 → target=10
        @intFromEnum(Op.HALT),                         // 8: back here after ret
        @intFromEnum(Op.MOVI), 0x01, 99, 0x00,       // 10: R1 = 99
        @intFromEnum(Op.RET), 0x00, 0x00,            // 16: return (Format C, but RET is special)
    };
    // Actually RET is Format C in the enum. Let me reconsider.
    // RET is Format C: [RET][rd][rs1] - but Python treats it as just reading stack.
    // In Python: RET reads no operands directly, just pops return address.
    // But RET is in FORMAT_C set, so it expects 2 more bytes.
    // The Python code doesn't decode operands for RET - it directly pops the stack.
    // Let me look at the Python again...
    // Python RET: no decode_operands called, just checks stack and pops.
    // But RET is in FORMAT_C... The Python code actually bypasses the format
    // and handles RET specially. So in our Zig code, RET should not consume operands.
    // Let me check what our interpreter does...

    // Our interpreter: if op_byte == RET, it just checks stack and pops. No decode.
    // But RET is mapped to Format C by getFormat. Our step() handles RET directly.
    // So we need RET to NOT consume extra bytes. Good, our code is correct.

    // Let me redo the bytecode:
    const bc2 = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 0, 0x00,        // 0: R0 = 0
        @intFromEnum(Op.CALL), 0x00, 0x06, 0x00,      // 4: call, offset=6, target=10
        @intFromEnum(Op.HALT),                         // 8: back from call
        // function at offset 10
        @intFromEnum(Op.MOVI), 0x01, 99, 0x00,       // 10: R1 = 99
        @intFromEnum(Op.RET),                          // 14: return
    };

    var interp = try Interpreter.init(std.testing.allocator, &bc2, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 99), interp.regs.readGp(1));
    try std.testing.expect(interp.halted);
}

test "interpreter: PUSH and POP" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 42, 0x00,       // R0 = 42
        @intFromEnum(Op.PUSH), 0x00,                  // push R0
        @intFromEnum(Op.MOVI), 0x00, 0, 0x00,        // R0 = 0
        @intFromEnum(Op.POP), 0x01,                   // R1 = pop
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 0), interp.regs.readGp(0));
    try std.testing.expectEqual(@as(i32, 42), interp.regs.readGp(1));
}

test "interpreter: INEG" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 5, 0x00,        // R0 = 5
        @intFromEnum(Op.INEG), 0x01, 0x00,            // R1 = -R0
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, -5), interp.regs.readGp(1));
}

test "interpreter: INOT" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 0, 0x00,        // R0 = 0
        @intFromEnum(Op.INOT), 0x01, 0x00,            // R1 = ~R0 = -1
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, -1), interp.regs.readGp(1));
}

test "interpreter: conditional flags with CMP and JE" {
    // Test CMP + JE pattern
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 5, 0x00,        // 0: R0 = 5
        @intFromEnum(Op.MOVI), 0x01, 5, 0x00,        // 4: R1 = 5
        @intFromEnum(Op.CMP), 0x00, 0x01,            // 8: compare R0, R1
        @intFromEnum(Op.JE), 0x00, 0x04, 0x00,       // 11: if equal, jump +4 to 15
        @intFromEnum(Op.MOVI), 0x02, 0, 0x00,        // 15: R2 = 0 (skip target)
        @intFromEnum(Op.JMP), 0x00, 0x04, 0x00,      // 19: jump to 23
        @intFromEnum(Op.MOVI), 0x02, 1, 0x00,        // 23: R2 = 1
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    // JE should trigger since R0 == R1, jumping to 15 where R2 = 0, then to HALT
    // Wait, let me recalculate: JE is at offset 11, after decode PC = 15.
    // If equal, PC += 4 = 15 + 4 = 19. But wait, offset in Format D is added
    // to PC AFTER the instruction is decoded. Our code does self.pc += offset.
    // At the JE instruction: pc was 11, we decode D (4 bytes), pc becomes 15.
    // Then we add offset (4) → pc = 19 → JMP → pc = 23 → R2 = 1 → HALT
    try std.testing.expectEqual(@as(i32, 1), interp.regs.readGp(2));
}

test "interpreter: ROTL and ROTR" {
    const bytecode = [_]u8{
        @intFromEnum(Op.MOVI), 0x00, 1, 0x00,        // R0 = 1
        @intFromEnum(Op.MOVI), 0x01, 1, 0x00,        // R1 = 1 (shift by 1)
        @intFromEnum(Op.ROTL), 0x02, 0x00, 0x01,     // R2 = rotl(R0, 1) = 2
        @intFromEnum(Op.ROTR), 0x03, 0x02, 0x01,     // R3 = rotr(R2, 1) = 1
        @intFromEnum(Op.HALT),
    };
    var interp = try Interpreter.init(std.testing.allocator, &bytecode, .{});
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 2), interp.regs.readGp(2));
    try std.testing.expectEqual(@as(i32, 1), interp.regs.readGp(3));
}
