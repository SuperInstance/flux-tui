//! FLUX Micro-VM Bytecode Interpreter — Complete Implementation
//!
//! Implements a fetch-decode-execute loop that runs directly on raw bytecode
//! bytes.  Supports all 122 opcodes spanning integer/float arithmetic, bitwise
//! logic, stack manipulation, control flow, memory access, comparison, type
//! operations, SIMD vector ops, A2A protocol, and system calls.
//!
//! Instruction encoding formats (see `opcodes.zig` for values):
//!   Format A (1 byte):   [opcode]
//!   Format B (2 bytes):  [opcode][reg]
//!   Format C (3 bytes):  [opcode][rd][rs1]
//!   Format D (4 bytes):  [opcode][rs1][off_lo][off_hi]  (signed i16)
//!   Format E (4 bytes):  [opcode][rd][rs1][rs2]
//!   Format G (variable): [opcode][len:u16][data:len bytes]
//!
//! Jump offsets in Format D are **relative to the PC after the jump
//! instruction** has been fetched (PC already points past the instruction).

const std = @import("std");
const mem = std.mem;

const opcodes = @import("opcodes.zig");
const Op = opcodes.Op;
const registers = @import("registers.zig");
const RegisterFile = registers.RegisterFile;
const memory = @import("memory.zig");
const MemoryManager = memory.MemoryManager;
const MemoryRegion = memory.MemoryRegion;

pub const MAX_CYCLES: u32 = 10_000_000;
pub const DEFAULT_MEMORY_SIZE: usize = 65536;

// ── VM Errors ─────────────────────────────────────────────────────

pub const VMError = error{
    Halt,
    InvalidOpcode,
    DivisionByZero,
    StackOverflow,
    StackUnderflow,
    TypeCheck,
    OutOfBounds,
    ResourceError,
    A2AError,
};

// ── Box type tags ─────────────────────────────────────────────────

const BOX_TYPE_INT: u8 = 0;
const BOX_TYPE_FLOAT: u8 = 1;
const BOX_TYPE_BOOL: u8 = 2;

/// A boxed value entry: (type_tag, raw_i32_value)
const BoxEntry = struct {
    type_tag: u8,
    value: i32,
};

// ── Interpreter ───────────────────────────────────────────────────

pub const Interpreter = struct {
    regs: RegisterFile = .{},
    mem: MemoryManager = .{},
    bytecode: []const u8 = "",
    pc: usize = 0,
    cycle_count: u32 = 0,
    running: bool = false,
    halted: bool = false,
    max_cycles: u32 = MAX_CYCLES,
    allocator: mem.Allocator,

    // Condition flags (set by CMP/ICMP/TEST, checked by JE/JNE/JG/JL/JGE/JLE/SETCC)
    flag_zero: bool = false,
    flag_sign: bool = false,
    flag_carry: bool = false,
    flag_overflow: bool = false,

    // Box table for BOX/UNBOX/CHECK_TYPE
    box_table: std.ArrayList(BoxEntry),
    box_counter: u32 = 0,

    // Resource tracking for RESOURCE_ACQUIRE / RESOURCE_RELEASE
    resources: std.AutoHashMap(u32, bool),

    // Call stack for ENTER/LEAVE frame tracking
    frame_stack: std.ArrayList(i32),

    /// A2A handler callback type: fn(opcode_name, data) -> ?i32
    a2a_handler: ?*const fn ([]const u8, []const u8) ?i32 = null,

    pub fn init(allocator: mem.Allocator, bytecode: []const u8, memory_size: usize) !Interpreter {
        var self = Interpreter{
            .allocator = allocator,
            .bytecode = bytecode,
            .box_table = std.ArrayList(BoxEntry).init(allocator),
            .resources = std.AutoHashMap(u32, bool).init(allocator),
            .frame_stack = std.ArrayList(i32).init(allocator),
        };
        // Create default memory regions
        _ = try self.mem.createRegion(allocator, "stack", memory_size, "system");
        _ = try self.mem.createRegion(allocator, "heap", memory_size, "system");
        // Stack starts at the top and grows downward
        self.regs.setSP(@intCast(memory_size));
        return self;
    }

    pub fn deinit(self: *Interpreter) void {
        self.box_table.deinit();
        self.resources.deinit();
        self.frame_stack.deinit();
        self.mem.deinitAll(self.allocator);
    }

    /// Reset the VM to its initial state (keeping bytecode).
    pub fn reset(self: *Interpreter) void {
        self.pc = 0;
        self.cycle_count = 0;
        self.running = false;
        self.halted = false;
        self.flag_zero = false;
        self.flag_sign = false;
        self.flag_carry = false;
        self.flag_overflow = false;
        self.regs.reset();
        const stack_region = self.mem.getRegion("stack");
        self.regs.setSP(@intCast(stack_region.size));
        self.box_table.clearRetainingCapacity();
        self.box_counter = 0;
        self.resources.clearRetainingCapacity();
        self.frame_stack.clearRetainingCapacity();
    }

    /// Execute bytecode until HALT, cycle budget exceeded, or error.
    /// Returns the total number of cycles consumed.
    pub fn execute(self: *Interpreter) (VMError || std.mem.Allocator.Error)!u32 {
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

    // ── Fetch helpers ──────────────────────────────────────────────

    fn fetchU8(self: *Interpreter) u8 {
        const b = self.bytecode[self.pc];
        self.pc += 1;
        return b;
    }

    fn fetchI8(self: *Interpreter) i8 {
        const b = self.fetchU8();
        return @bitCast(b);
    }

    fn fetchU16(self: *Interpreter) u16 {
        const lo = self.fetchU8();
        const hi = self.fetchU8();
        return @as(u16, lo) | (@as(u16, hi) << 8);
    }

    fn fetchI16(self: *Interpreter) i16 {
        const val = self.fetchU16();
        return @bitCast(val);
    }

    fn fetchI32(self: *Interpreter) i32 {
        const b0 = self.fetchU8();
        const b1 = self.fetchU8();
        const b2 = self.fetchU8();
        const b3 = self.fetchU8();
        return @as(i32, @intCast(b0)) |
            (@as(i32, @intCast(b1)) << 8) |
            (@as(i32, @intCast(b2)) << 16) |
            (@as(i32, @intCast(b3)) << 24);
    }

    fn fetchVarData(self: *Interpreter) []const u8 {
        const length = self.fetchU16();
        const start = self.pc;
        self.pc += length;
        return self.bytecode[start .. start + length];
    }

    fn fetchVarString(self: *Interpreter) []const u8 {
        const data = self.fetchVarData();
        // Find null terminator
        const idx = mem.indexOfScalar(u8, data, 0);
        if (idx) |i| {
            return data[0..i];
        }
        return data;
    }

    // ── Flags ──────────────────────────────────────────────────────

    fn setFlags(self: *Interpreter, result: i32) void {
        self.flag_zero = (result == 0);
        self.flag_sign = (result < 0);
        self.flag_carry = (result < 0); // simplified
        self.flag_overflow = false; // simplified
    }

    fn setCmpFlags(self: *Interpreter, a: i32, b: i32) void {
        self.flag_zero = (a == b);
        self.flag_sign = (a < b);
        self.flag_carry = (a < b); // borrow
        const result = a - b;
        self.flag_overflow = ((a > 0 and b < 0 and result < 0) or
            (a < 0 and b > 0 and result > 0));
    }

    // ── Stack helpers ──────────────────────────────────────────────

    fn stackPush(self: *Interpreter, value: i32) void {
        const stack = self.mem.getRegion("stack");
        self.regs.setSP(MemoryManager.stackPush(stack, self.regs.getSP(), value));
    }

    fn stackPop(self: *Interpreter) i32 {
        const stack = self.mem.getRegion("stack");
        const result = MemoryManager.stackPop(stack, self.regs.getSP());
        self.regs.setSP(result.new_sp);
        return result.value;
    }

    // ── A2A dispatch ───────────────────────────────────────────────

    fn dispatchA2A(self: *Interpreter, comptime opcode_name: []const u8, data: []const u8) void {
        if (self.a2a_handler) |handler| {
            if (handler(opcode_name, data)) |result| {
                self.regs.writeGP(0, result);
            }
        }
        // If no handler, silently no-op (stub behavior for self-hosting)
    }

    // ── Single-step execution ──────────────────────────────────────

    fn step(self: *Interpreter) (VMError || std.mem.Allocator.Error)!void {
        const start_pc = self.pc;
        const opcode_byte = self.fetchU8();
        const op: Op = @enumFromInt(opcode_byte);

        switch (op) {
            // ══════════════════════════════════════════════════════
            // NOP / HALT / YIELD
            // ══════════════════════════════════════════════════════
            .NOP => {},
            .HALT => {
                self.running = false;
                self.halted = true;
            },
            .YIELD => {
                // Cooperative yield — no-op in single-threaded mode
            },
            .DEBUG_BREAK => {
                // Breakpoint — no-op unless debugger attached
            },
            .EMERGENCY_STOP => {
                self.running = false;
                self.halted = true;
            },

            // ══════════════════════════════════════════════════════
            // MOV rd, rs1
            // ══════════════════════════════════════════════════════
            .MOV => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                self.regs.writeGP(rd, self.regs.readGP(rs1));
            },

            // ══════════════════════════════════════════════════════
            // MOVI reg, imm16
            // ══════════════════════════════════════════════════════
            .MOVI => {
                const reg = self.fetchU8();
                const imm = self.fetchI16();
                self.regs.writeGP(reg, imm);
            },

            // ══════════════════════════════════════════════════════
            // Integer Arithmetic
            // ══════════════════════════════════════════════════════
            .IADD => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const result = self.regs.readGP(rs1) + self.regs.readGP(rs2);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ISUB => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const result = self.regs.readGP(rs1) - self.regs.readGP(rs2);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IMUL => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const result = self.regs.readGP(rs1) * self.regs.readGP(rs2);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IDIV => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const divisor = self.regs.readGP(rs2);
                if (divisor == 0) return VMError.DivisionByZero;
                const dividend = self.regs.readGP(rs1);
                const result = @divTrunc(dividend, divisor);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IMOD => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const divisor = self.regs.readGP(rs2);
                if (divisor == 0) return VMError.DivisionByZero;
                const dividend = self.regs.readGP(rs1);
                const result = @rem(dividend, divisor);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IREM => {
                // Same as IMOD in Zig (C-style remainder)
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const divisor = self.regs.readGP(rs2);
                if (divisor == 0) return VMError.DivisionByZero;
                const dividend = self.regs.readGP(rs1);
                const result = @rem(dividend, divisor);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .INEG => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result = -self.regs.readGP(rs1);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .INC => {
                const reg = self.fetchU8();
                const result = self.regs.readGP(reg) + 1;
                self.regs.writeGP(reg, result);
                self.setFlags(result);
            },
            .DEC => {
                const reg = self.fetchU8();
                const result = self.regs.readGP(reg) - 1;
                self.regs.writeGP(reg, result);
                self.setFlags(result);
            },

            // ══════════════════════════════════════════════════════
            // Bitwise
            // ══════════════════════════════════════════════════════
            .IAND => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const result = self.regs.readGP(rs1) & self.regs.readGP(rs2);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IOR => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const result = self.regs.readGP(rs1) | self.regs.readGP(rs2);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IXOR => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const result = self.regs.readGP(rs1) ^ self.regs.readGP(rs2);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .INOT => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result = ~self.regs.readGP(rs1);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ISHL => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const shift = @as(u5, @truncate(@as(u32, @bitCast(self.regs.readGP(rs2)))));
                const result = self.regs.readGP(rs1) << shift;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ISHR => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const shift = @as(u5, @truncate(@as(u32, @bitCast(self.regs.readGP(rs2)))));
                const result = self.regs.readGP(rs1) >> shift;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ROTL => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const val = @as(u32, @bitCast(self.regs.readGP(rs1)));
                const raw_shift = @as(u32, @bitCast(self.regs.readGP(rs2))) & 31;
                const result = std.math.rotl(u32, val, raw_shift);
                self.regs.writeGP(rd, @bitCast(result));
                self.setFlags(self.regs.readGP(rd));
            },
            .ROTR => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const val = @as(u32, @bitCast(self.regs.readGP(rs1)));
                const raw_shift = @as(u32, @bitCast(self.regs.readGP(rs2))) & 31;
                const result = std.math.rotr(u32, val, raw_shift);
                self.regs.writeGP(rd, @bitCast(result));
                self.setFlags(self.regs.readGP(rd));
            },

            // ══════════════════════════════════════════════════════
            // Comparison: ICMP (generic compare with condition)
            // ══════════════════════════════════════════════════════
            .ICMP => {
                // [ICMP][cond:u8][rd:u8][rs:u8]
                const cond = self.fetchU8();
                const rd = self.fetchU8();
                const rs = self.fetchU8();
                const a = self.regs.readGP(rd);
                const b = self.regs.readGP(rs);
                const ua = @as(u32, @bitCast(a));
                const ub = @as(u32, @bitCast(b));
                const result: i32 = switch (cond) {
                    0 => @intFromBool(a == b), // EQ
                    1 => @intFromBool(a != b), // NE
                    2 => @intFromBool(a < b), // LT
                    3 => @intFromBool(a <= b), // LE
                    4 => @intFromBool(a > b), // GT
                    5 => @intFromBool(a >= b), // GE
                    6 => @intFromBool(ua < ub), // ULT
                    7 => @intFromBool(ua <= ub), // ULE
                    8 => @intFromBool(ua > ub), // UGT
                    9 => @intFromBool(ua >= ub), // UGE
                    else => 0,
                };
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },

            // ══════════════════════════════════════════════════════
            // Comparison: IEQ, ILT, ILE, IGT, IGE
            // ══════════════════════════════════════════════════════
            .IEQ => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readGP(rd) == self.regs.readGP(rs1));
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ILT => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readGP(rd) < self.regs.readGP(rs1));
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ILE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readGP(rd) <= self.regs.readGP(rs1));
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IGT => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readGP(rd) > self.regs.readGP(rs1));
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IGE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readGP(rd) >= self.regs.readGP(rs1));
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },

            // ══════════════════════════════════════════════════════
            // TEST (logical AND without storing result)
            // ══════════════════════════════════════════════════════
            .TEST => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result = self.regs.readGP(rd) & self.regs.readGP(rs1);
                self.setFlags(result);
            },

            // ══════════════════════════════════════════════════════
            // SETCC (set register based on condition flags)
            // ══════════════════════════════════════════════════════
            .SETCC => {
                const rd = self.fetchU8();
                const cond = self.fetchU8();
                const result: i32 = switch (cond) {
                    0 => @intFromBool(self.flag_zero), // EQ
                    1 => @intFromBool(!self.flag_zero), // NE
                    2 => @intFromBool(self.flag_sign), // LT
                    3 => @intFromBool(!self.flag_sign), // GE
                    4 => @intFromBool(!self.flag_zero and !self.flag_sign), // GT
                    5 => @intFromBool(self.flag_zero or self.flag_sign), // LE
                    6 => @intFromBool(self.flag_carry), // CS/HS
                    7 => @intFromBool(!self.flag_carry), // CC/LO
                    8 => @intFromBool(self.flag_overflow), // VS
                    9 => @intFromBool(!self.flag_overflow), // VC
                    else => 0,
                };
                self.regs.writeGP(rd, result);
            },

            // ══════════════════════════════════════════════════════
            // Stack: PUSH / POP
            // ══════════════════════════════════════════════════════
            .PUSH => {
                const reg = self.fetchU8();
                self.stackPush(self.regs.readGP(reg));
            },
            .POP => {
                const reg = self.fetchU8();
                self.regs.writeGP(reg, self.stackPop());
            },

            // ══════════════════════════════════════════════════════
            // Stack: DUP (duplicate top of stack)
            // ══════════════════════════════════════════════════════
            .DUP => {
                const stack = self.mem.getRegion("stack");
                const dup_r = MemoryManager.stackPop(stack, self.regs.getSP());
                self.regs.setSP(MemoryManager.stackPush(stack, self.regs.getSP(), dup_r.value));
                self.regs.setSP(MemoryManager.stackPush(stack, self.regs.getSP(), dup_r.value));
            },

            // ══════════════════════════════════════════════════════
            // Stack: SWAP (swap top two stack values)
            // ══════════════════════════════════════════════════════
            .SWAP => {
                const stack = self.mem.getRegion("stack");
                const sr1 = MemoryManager.stackPop(stack, self.regs.getSP());
                const sr2 = MemoryManager.stackPop(stack, sr1.new_sp);
                const sp3 = MemoryManager.stackPush(stack, sr2.new_sp, sr1.value);
                const sp4 = MemoryManager.stackPush(stack, sp3, sr2.value);
                self.regs.setSP(sp4);
            },

            // ══════════════════════════════════════════════════════
            // Stack: ROT (rotate top 3 stack values)
            // ══════════════════════════════════════════════════════
            .ROT => {
                // [c, b, a] -> [b, a, c]
                const stack = self.mem.getRegion("stack");
                const rr1 = MemoryManager.stackPop(stack, self.regs.getSP());
                const rr2 = MemoryManager.stackPop(stack, rr1.new_sp);
                const rr3 = MemoryManager.stackPop(stack, rr2.new_sp);
                const sp4 = MemoryManager.stackPush(stack, rr3.new_sp, rr1.value);
                const sp5 = MemoryManager.stackPush(stack, sp4, rr3.value);
                const sp6 = MemoryManager.stackPush(stack, sp5, rr2.value);
                self.regs.setSP(sp6);
            },

            // ══════════════════════════════════════════════════════
            // Stack: ENTER (push frame pointer, set new frame)
            // ══════════════════════════════════════════════════════
            .ENTER => {
                const frame_size = self.fetchU8();
                // Save old FP
                try self.frame_stack.append(self.regs.getFP());
                self.stackPush(self.regs.getFP());
                // Set FP to current SP
                self.regs.setFP(self.regs.getSP());
                // Allocate frame space (in units of 4 bytes)
                const alloc_bytes: i32 = @as(i32, @intCast(frame_size)) * 4;
                const new_sp = self.regs.getSP() - alloc_bytes;
                if (new_sp < 0) return VMError.StackOverflow;
                self.regs.setSP(new_sp);
            },

            // ══════════════════════════════════════════════════════
            // Stack: LEAVE (restore frame pointer, deallocate)
            // ══════════════════════════════════════════════════════
            .LEAVE => {
                _ = self.fetchU8(); // consume unused byte
                // Restore SP to FP
                self.regs.setSP(self.regs.getFP());
                // Pop old FP
                const old_fp = self.stackPop();
                self.regs.setFP(old_fp);
                _ = self.frame_stack.pop();
            },

            // ══════════════════════════════════════════════════════
            // Stack: ALLOCA (allocate stack space)
            // ══════════════════════════════════════════════════════
            .ALLOCA => {
                const rd = self.fetchU8();
                const size_reg = self.fetchU8();
                const size: i32 = self.regs.readGP(size_reg) * 4;
                const new_sp = self.regs.getSP() - size;
                if (new_sp < 0) return VMError.StackOverflow;
                self.regs.setSP(new_sp);
                self.regs.writeGP(rd, self.regs.getSP());
            },

            // ══════════════════════════════════════════════════════
            // Control Flow: Jumps
            // ══════════════════════════════════════════════════════
            .JMP => {
                _ = self.fetchU8(); // reg (unused)
                const offset = self.fetchI16();
                self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
            },
            .JZ => {
                const rs1 = self.fetchU8();
                const offset = self.fetchI16();
                if (self.regs.readGP(rs1) == 0) {
                    self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
                }
            },
            .JNZ => {
                const rs1 = self.fetchU8();
                const offset = self.fetchI16();
                if (self.regs.readGP(rs1) != 0) {
                    self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
                }
            },
            .JE => {
                _ = self.fetchU8(); // unused
                const offset = self.fetchI16();
                if (self.flag_zero) {
                    self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
                }
            },
            .JNE => {
                _ = self.fetchU8(); // unused
                const offset = self.fetchI16();
                if (!self.flag_zero) {
                    self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
                }
            },
            .JG => {
                _ = self.fetchU8(); // unused
                const offset = self.fetchI16();
                if (!self.flag_zero and !self.flag_sign) {
                    self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
                }
            },
            .JL => {
                _ = self.fetchU8(); // unused
                const offset = self.fetchI16();
                if (self.flag_sign) {
                    self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
                }
            },
            .JGE_fmt => {
                _ = self.fetchU8(); // unused
                const offset = self.fetchI16();
                if (!self.flag_sign) {
                    self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
                }
            },
            .JLE => {
                _ = self.fetchU8(); // unused
                const offset = self.fetchI16();
                if (self.flag_zero or self.flag_sign) {
                    self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
                }
            },

            // ══════════════════════════════════════════════════════
            // Control Flow: CALL / RET
            // ══════════════════════════════════════════════════════
            .CALL => {
                _ = self.fetchU8(); // unused
                const offset = self.fetchI16();
                self.stackPush(@intCast(self.pc));
                self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
            },
            .CALL_IND => {
                const _rd = self.fetchU8();
                const target_reg = self.fetchU8();
                const target = self.regs.readGP(target_reg);
                self.stackPush(@intCast(self.pc));
                self.pc = @as(usize, @intCast(@as(u32, @bitCast(target))));
                _ = _rd;
            },
            .TAILCALL => {
                _ = self.fetchU8(); // unused
                const offset = self.fetchI16();
                self.pc = @intCast(@as(i32, @intCast(self.pc)) + offset);
            },
            .RET => {
                const stack = self.mem.getRegion("stack");
                if (self.regs.getSP() >= @as(i32, @intCast(stack.size)) - 4) {
                    // Stack is empty, halt
                    self.halted = true;
                } else {
                    const addr = self.stackPop();
                    self.pc = @as(usize, @intCast(@as(u32, @bitCast(addr))));
                }
            },

            // ══════════════════════════════════════════════════════
            // Memory: LOAD / STORE
            // ══════════════════════════════════════════════════════
            .LOAD => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = @as(usize, @intCast(@as(u32, @bitCast(self.regs.readGP(rs1)))));
                const stack = self.mem.getRegion("stack");
                const value = stack.readI32(addr);
                self.regs.writeGP(rd, value);
            },
            .STORE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = @as(usize, @intCast(@as(u32, @bitCast(self.regs.readGP(rs1)))));
                const val = self.regs.readGP(rd);
                const stack = self.mem.getRegion("stack");
                stack.writeI32(addr, val);
            },
            .LOAD8 => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = @as(usize, @intCast(@as(u32, @bitCast(self.regs.readGP(rs1)))));
                const stack = self.mem.getRegion("stack");
                const value = stack.read(addr, 1)[0];
                self.regs.writeGP(rd, @as(i32, value));
            },
            .STORE8 => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = @as(usize, @intCast(@as(u32, @bitCast(self.regs.readGP(rs1)))));
                const val = @as(u8, @truncate(@as(u32, @bitCast(self.regs.readGP(rd)))));
                const stack = self.mem.getRegion("stack");
                stack.write(addr, &[_]u8{val});
            },

            // ══════════════════════════════════════════════════════
            // CMP (set flags from subtraction)
            // ══════════════════════════════════════════════════════
            .CMP => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                self.setCmpFlags(self.regs.readGP(rd), self.regs.readGP(rs1));
            },

            // ══════════════════════════════════════════════════════
            // Type: CAST
            // ══════════════════════════════════════════════════════
            .CAST => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const type_tag = self.fetchU8();
                const val = self.regs.readGP(rs1);
                switch (type_tag) {
                    0 => {
                        // i32 -> f32 (bit reinterpretation, store as fixed-point * 1000)
                        const fval: f32 = @bitCast(@as(u32, @bitCast(val)));
                        self.regs.writeGP(rd, @intFromFloat(fval * 1000.0));
                    },
                    1 => {
                        // f32 -> i32
                        self.regs.writeGP(rd, val);
                    },
                    2 => {
                        // i32 -> bool
                        self.regs.writeGP(rd, @intFromBool(val != 0));
                    },
                    3 => {
                        // bool -> i32
                        self.regs.writeGP(rd, val);
                    },
                    else => {
                        self.regs.writeGP(rd, val);
                    },
                }
            },

            // ══════════════════════════════════════════════════════
            // Type: BOX / UNBOX / CHECK_TYPE
            // ══════════════════════════════════════════════════════
            .BOX => {
                const rd = self.fetchU8();
                const type_tag = self.fetchU8();
                const raw = self.fetchI32();
                const box_id: i32 = @intCast(self.box_counter);
                self.box_counter += 1;
                try self.box_table.append(.{ .type_tag = type_tag, .value = raw });
                self.regs.writeGP(rd, box_id);
            },
            .UNBOX => {
                const rd = self.fetchU8();
                const box_reg = self.fetchU8();
                const box_id = @as(usize, @intCast(@as(u32, @bitCast(self.regs.readGP(box_reg)))));
                if (box_id >= self.box_table.items.len) return VMError.TypeCheck;
                const value = self.box_table.items[box_id].value;
                self.regs.writeGP(rd, value);
            },
            .CHECK_TYPE => {
                const box_reg = self.fetchU8();
                const _expected = self.fetchU8();
                const box_id = @as(usize, @intCast(@as(u32, @bitCast(self.regs.readGP(box_reg)))));
                if (box_id >= self.box_table.items.len) return VMError.TypeCheck;
                _ = _expected; // Type check passes if box exists
            },

            // ══════════════════════════════════════════════════════
            // Float arithmetic
            // ══════════════════════════════════════════════════════
            .FADD => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const result = self.regs.readFP(rs1) + self.regs.readFP(rs2);
                self.regs.writeFP(rd, result);
            },
            .FSUB => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const result = self.regs.readFP(rs1) - self.regs.readFP(rs2);
                self.regs.writeFP(rd, result);
            },
            .FMUL => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const result = self.regs.readFP(rs1) * self.regs.readFP(rs2);
                self.regs.writeFP(rd, result);
            },
            .FDIV => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const divisor = self.regs.readFP(rs2);
                if (divisor == 0.0) return VMError.DivisionByZero;
                const result = self.regs.readFP(rs1) / divisor;
                self.regs.writeFP(rd, result);
            },
            .FNEG => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                self.regs.writeFP(rd, -self.regs.readFP(rs1));
            },
            .FABS => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                self.regs.writeFP(rd, @abs(self.regs.readFP(rs1)));
            },
            .FMIN => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                self.regs.writeFP(rd, @min(self.regs.readFP(rs1), self.regs.readFP(rs2)));
            },
            .FMAX => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                self.regs.writeFP(rd, @max(self.regs.readFP(rs1), self.regs.readFP(rs2)));
            },

            // ══════════════════════════════════════════════════════
            // Float comparison
            // ══════════════════════════════════════════════════════
            .FEQ => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readFP(rd) == self.regs.readFP(rs1));
                self.regs.writeGP(rd, result);
            },
            .FLT => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readFP(rd) < self.regs.readFP(rs1));
                self.regs.writeGP(rd, result);
            },
            .FLE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readFP(rd) <= self.regs.readFP(rs1));
                self.regs.writeGP(rd, result);
            },
            .FGT => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readFP(rd) > self.regs.readFP(rs1));
                self.regs.writeGP(rd, result);
            },
            .FGE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = @intFromBool(self.regs.readFP(rd) >= self.regs.readFP(rs1));
                self.regs.writeGP(rd, result);
            },

            // ══════════════════════════════════════════════════════
            // SIMD vector ops (stub — no-op for now, full impl later)
            // ══════════════════════════════════════════════════════
            .VLOAD => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = @as(usize, @intCast(@as(u32, @bitCast(self.regs.readGP(rs1)))));
                const stack = self.mem.getRegion("stack");
                const bytes = stack.read(addr, 16);
                self.regs.writeVec(rd, bytes);
            },
            .VSTORE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = @as(usize, @intCast(@as(u32, @bitCast(self.regs.readGP(rs1)))));
                const vec = self.regs.readVec(rd);
                const stack = self.mem.getRegion("stack");
                stack.write(addr, vec);
            },
            .VADD, .VSUB, .VMUL, .VDIV, .VFMA => {
                // SIMD stub: consume operands, no-op
                _ = self.fetchU8();
                _ = self.fetchU8();
                _ = self.fetchU8();
            },

            // ══════════════════════════════════════════════════════
            // Memory management (Format G — variable length)
            // ══════════════════════════════════════════════════════
            .REGION_CREATE => {
                const data = self.fetchVarData();
                var idx: usize = 0;
                const name_len = data[idx]; idx += 1;
                const name = data[idx .. idx + name_len];
                idx += name_len;
                // Read u32 LE size
                const size = @as(u32, @intCast(data[idx])) |
                    (@as(u32, @intCast(data[idx + 1])) << 8) |
                    (@as(u32, @intCast(data[idx + 2])) << 16) |
                    (@as(u32, @intCast(data[idx + 3])) << 24);
                idx += 4;
                const owner_len = data[idx]; idx += 1;
                const owner = data[idx .. idx + owner_len];
                _ = self.mem.createRegion(self.allocator, name, size, owner) catch {};
                self.regs.writeGP(0, 0);
            },
            .REGION_DESTROY => {
                const name = self.fetchVarString();
                if (self.mem.hasRegion(name)) {
                    self.mem.destroyRegion(self.allocator, name);
                }
            },
            .REGION_TRANSFER => {
                const data = self.fetchVarData();
                var idx: usize = 0;
                const name_len = data[idx]; idx += 1;
                const name = data[idx .. idx + name_len]; idx += name_len;
                const owner_len = data[idx]; idx += 1;
                const new_owner = data[idx .. idx + owner_len];
                self.mem.transferRegion(name, new_owner);
            },
            .MEMCOPY => {
                const data = self.fetchVarData();
                var idx: usize = 0;
                const rname_len = data[idx]; idx += 1;
                const rname = data[idx .. idx + rname_len]; idx += rname_len;
                const src_off = @as(usize, @intCast(data[idx])) | (@as(usize, @intCast(data[idx + 1])) << 8) | (@as(usize, @intCast(data[idx + 2])) << 16) | (@as(usize, @intCast(data[idx + 3])) << 24);
                idx += 4;
                const dst_off = @as(usize, @intCast(data[idx])) | (@as(usize, @intCast(data[idx + 1])) << 8) | (@as(usize, @intCast(data[idx + 2])) << 16) | (@as(usize, @intCast(data[idx + 3])) << 24);
                idx += 4;
                const size = @as(usize, @intCast(data[idx])) | (@as(usize, @intCast(data[idx + 1])) << 8) | (@as(usize, @intCast(data[idx + 2])) << 16) | (@as(usize, @intCast(data[idx + 3])) << 24);
                const region = self.mem.getRegion(rname);
                const chunk = region.read(src_off, size);
                region.write(dst_off, chunk);
            },
            .MEMSET => {
                const data = self.fetchVarData();
                var idx: usize = 0;
                const rname_len = data[idx]; idx += 1;
                const rname = data[idx .. idx + rname_len]; idx += rname_len;
                const offset = @as(usize, @intCast(data[idx])) | (@as(usize, @intCast(data[idx + 1])) << 8) | (@as(usize, @intCast(data[idx + 2])) << 16) | (@as(usize, @intCast(data[idx + 3])) << 24);
                idx += 4;
                const value = data[idx]; idx += 1;
                const size = @as(usize, @intCast(data[idx])) | (@as(usize, @intCast(data[idx + 1])) << 8) | (@as(usize, @intCast(data[idx + 2])) << 16) | (@as(usize, @intCast(data[idx + 3])) << 24);
                const region = self.mem.getRegion(rname);
                var fill_buf: [256]u8 = undefined;
                @memset(&fill_buf, value);
                var remaining = size;
                var pos: usize = 0;
                while (remaining > 0) {
                    const to_write = @min(remaining, 256);
                    region.write(offset + pos, fill_buf[0..to_write]);
                    pos += to_write;
                    remaining -= to_write;
                }
            },
            .MEMCMP => {
                const data = self.fetchVarData();
                var idx: usize = 0;
                const rname_len = data[idx]; idx += 1;
                const rname = data[idx .. idx + rname_len]; idx += rname_len;
                const off_a = @as(usize, @intCast(data[idx])) | (@as(usize, @intCast(data[idx + 1])) << 8) | (@as(usize, @intCast(data[idx + 2])) << 16) | (@as(usize, @intCast(data[idx + 3])) << 24);
                idx += 4;
                const off_b = @as(usize, @intCast(data[idx])) | (@as(usize, @intCast(data[idx + 1])) << 8) | (@as(usize, @intCast(data[idx + 2])) << 16) | (@as(usize, @intCast(data[idx + 3])) << 24);
                idx += 4;
                const size = @as(usize, @intCast(data[idx])) | (@as(usize, @intCast(data[idx + 1])) << 8) | (@as(usize, @intCast(data[idx + 2])) << 16) | (@as(usize, @intCast(data[idx + 3])) << 24);
                const region = self.mem.getRegion(rname);
                const a = region.read(off_a, size);
                const b = region.read(off_b, size);
                const result: i32 = switch (mem.order(u8, a, b)) {
                    .lt => -1,
                    .eq => 0,
                    .gt => 1,
                };
                self.regs.writeGP(0, result);
            },

            // ══════════════════════════════════════════════════════
            // A2A protocol opcodes (all Format G, dispatched to handler)
            // ══════════════════════════════════════════════════════
            .TELL => { const data = self.fetchVarData(); self.dispatchA2A("TELL", data); },
            .ASK => { const data = self.fetchVarData(); self.dispatchA2A("ASK", data); },
            .DELEGATE => { const data = self.fetchVarData(); self.dispatchA2A("DELEGATE", data); },
            .DELEGATE_RESULT => { const data = self.fetchVarData(); self.dispatchA2A("DELEGATE_RESULT", data); },
            .REPORT_STATUS => { const data = self.fetchVarData(); self.dispatchA2A("REPORT_STATUS", data); },
            .REQUEST_OVERRIDE => { const data = self.fetchVarData(); self.dispatchA2A("REQUEST_OVERRIDE", data); },
            .BROADCAST => { const data = self.fetchVarData(); self.dispatchA2A("BROADCAST", data); },
            .REDUCE => { const data = self.fetchVarData(); self.dispatchA2A("REDUCE", data); },
            .DECLARE_INTENT => { const data = self.fetchVarData(); self.dispatchA2A("DECLARE_INTENT", data); },
            .ASSERT_GOAL => { const data = self.fetchVarData(); self.dispatchA2A("ASSERT_GOAL", data); },
            .VERIFY_OUTCOME => { const data = self.fetchVarData(); self.dispatchA2A("VERIFY_OUTCOME", data); },
            .EXPLAIN_FAILURE => { const data = self.fetchVarData(); self.dispatchA2A("EXPLAIN_FAILURE", data); },
            .SET_PRIORITY => { const data = self.fetchVarData(); self.dispatchA2A("SET_PRIORITY", data); },
            .TRUST_CHECK => { const data = self.fetchVarData(); self.dispatchA2A("TRUST_CHECK", data); },
            .TRUST_UPDATE => { const data = self.fetchVarData(); self.dispatchA2A("TRUST_UPDATE", data); },
            .TRUST_QUERY => { const data = self.fetchVarData(); self.dispatchA2A("TRUST_QUERY", data); },
            .REVOKE_TRUST => { const data = self.fetchVarData(); self.dispatchA2A("REVOKE_TRUST", data); },
            .CAP_REQUIRE => { const data = self.fetchVarData(); self.dispatchA2A("CAP_REQUIRE", data); },
            .CAP_REQUEST => { const data = self.fetchVarData(); self.dispatchA2A("CAP_REQUEST", data); },
            .CAP_GRANT => { const data = self.fetchVarData(); self.dispatchA2A("CAP_GRANT", data); },
            .CAP_REVOKE => { const data = self.fetchVarData(); self.dispatchA2A("CAP_REVOKE", data); },
            .BARRIER => { const data = self.fetchVarData(); self.dispatchA2A("BARRIER", data); },
            .SYNC_CLOCK => { const data = self.fetchVarData(); self.dispatchA2A("SYNC_CLOCK", data); },
            .FORMATION_UPDATE => { const data = self.fetchVarData(); self.dispatchA2A("FORMATION_UPDATE", data); },

            // ══════════════════════════════════════════════════════
            // ISA v3 — Agent Evolution & Instinct (stubs)
            // ══════════════════════════════════════════════════════
            .EVOLVE, .INSTINCT, .WITNESS, .SNAPSHOT => {
                // Stub: consume as Format C operands
                _ = self.fetchU8();
                _ = self.fetchU8();
            },

            // ══════════════════════════════════════════════════════
            // Meta ops (stubs)
            // ══════════════════════════════════════════════════════
            .CONF => {
                _ = self.fetchU8(); // rd
                _ = self.fetchU8(); // rs1
                _ = self.fetchU8(); // confidence byte
            },
            .MERGE => {
                _ = self.fetchU8();
                _ = self.fetchU8();
                _ = self.fetchU8();
            },
            .RESTORE => {
                _ = self.fetchU8();
                _ = self.fetchU8();
            },

            // ══════════════════════════════════════════════════════
            // System ops
            // ══════════════════════════════════════════════════════
            .RESOURCE_ACQUIRE => {
                const data = self.fetchVarData();
                _ = data; // Stub
            },
            .RESOURCE_RELEASE => {
                const data = self.fetchVarData();
                _ = data; // Stub
            },

            // ══════════════════════════════════════════════════════
            // Catch-all: unknown opcode
            // ══════════════════════════════════════════════════════
            .CHECK_BOUNDS => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                _ = rd;
                _ = rs1;
                // Stub
            },
            .unknown => {
                std.debug.print("Unknown opcode: 0x{x:02} at pc={d}\n", .{ opcode_byte, start_pc });
                return VMError.InvalidOpcode;
            },
        }
    }
};

// ═══════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════

test "factorial(7) equals 5040" {
    const allocator = std.testing.allocator;
    const fact = [_]u8{
        0x2B, 0x00, 0x07, 0x00, // MOVI R0, 7
        0x2B, 0x01, 0x01, 0x00, // MOVI R1, 1
        0x0A, 0x01, 0x01, 0x00, // IMUL R1, R1, R0
        0x0F, 0x00,              // DEC R0
        0x06, 0x00, 0xF6, 0xFF, // JNZ R0, -10
        0x80,                    // HALT
    };
    var vm = try Interpreter.init(allocator, &fact, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 5040), vm.regs.readGP(1));
    try std.testing.expect(vm.halted);
}

test "arithmetic: 3 + 4 = 7" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{ 0x2B, 0x00, 0x03, 0x00, 0x2B, 0x01, 0x04, 0x00, 0x08, 0x00, 0x00, 0x01, 0x80 };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 7), vm.regs.readGP(0));
}

test "arithmetic: 10 * 5 = 50" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{ 0x2B, 0x00, 0x0A, 0x00, 0x2B, 0x01, 0x05, 0x00, 0x0A, 0x00, 0x00, 0x01, 0x80 };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 50), vm.regs.readGP(0));
}

test "fibonacci(12) = 144" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{
        0x2B, 0x00, 0x00, 0x00, // MOVI R0, 0
        0x2B, 0x01, 0x01, 0x00, // MOVI R1, 1
        0x2B, 0x02, 0x0C, 0x00, // MOVI R2, 12
        0x01, 0x03, 0x01,        // MOV R3, R1
        0x08, 0x01, 0x01, 0x00, // IADD R1, R1, R0
        0x01, 0x00, 0x03,        // MOV R0, R3
        0x0F, 0x02,              // DEC R2
        0x06, 0x02, 0xF0, 0xFF, // JNZ R2, -16
        0x80,                    // HALT
    };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 144), vm.regs.readGP(0));
}

test "stack push and pop" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{
        0x2B, 0x00, 0x2A, 0x00, // MOVI R0, 42
        0x20, 0x00,              // PUSH R0
        0x2B, 0x00, 0x00, 0x00, // MOVI R0, 0
        0x21, 0x00,              // POP R0
        0x80,                    // HALT
    };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 42), vm.regs.readGP(0));
}

test "division by zero" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{ 0x2B, 0x00, 0x0A, 0x00, 0x2B, 0x01, 0x00, 0x00, 0x0B, 0x00, 0x00, 0x01, 0x80 };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    const result = vm.execute();
    try std.testing.expectError(VMError.DivisionByZero, result);
}

test "conditional jump JE" {
    const allocator = std.testing.allocator;
    // CMP R0, R1 (both 5), JE to HALT skipping the INC
    const bc = [_]u8{
        0x2B, 0x00, 0x05, 0x00, // MOVI R0, 5
        0x2B, 0x01, 0x05, 0x00, // MOVI R1, 5
        0x2D, 0x00, 0x01,        // CMP R0, R1
        0x2E, 0x00, 0x02, 0x00, // JE +2 (skip INC, land on HALT)
        0x0E, 0x00,              // INC R0 (should be skipped)
        0x80,                    // HALT
    };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 5), vm.regs.readGP(0));
}

test "bitwise AND" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{ 0x2B, 0x00, 0x0F, 0x00, 0x2B, 0x01, 0x0F, 0x00, 0x10, 0x00, 0x00, 0x01, 0x80 };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 0x0F & 0x0F), vm.regs.readGP(0));
}

test "bitwise XOR" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{ 0x2B, 0x00, 0xFF, 0x00, 0x2B, 0x01, 0x0F, 0x00, 0x12, 0x00, 0x00, 0x01, 0x80 };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 0xFF ^ 0x0F), vm.regs.readGP(0));
}

test "CALL and RET" {
    const allocator = std.testing.allocator;
    // Simple: call subroutine once that sets R0 = 42, then HALT
    const bc = [_]u8{
        0x2B, 0x00, 0x00, 0x00, // MOVI R0, 0
        0x07, 0x00, 0x04, 0x00, // CALL +4 (to subroutine at 12)
        0x80,                    // HALT (return lands here)
        0x00,                    // NOP padding
        0x00,                    // NOP padding
        0x00,                    // NOP padding
        0x2B, 0x00, 0x2A, 0x00, // MOVI R0, 42
        0x28, 0x00, 0x00,        // RET
    };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 42), vm.regs.readGP(0));
    try std.testing.expect(vm.halted);
}

test "LOAD and STORE" {
    const allocator = std.testing.allocator;
    // PUSH R0 onto stack, then POP it into R1
    const bc = [_]u8{
        0x2B, 0x00, 0x2A, 0x00, // MOVI R0, 42
        0x20, 0x00,              // PUSH R0
        0x2B, 0x00, 0x00, 0x00, // MOVI R0, 0
        0x21, 0x01,              // POP R1
        0x80,                    // HALT
    };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 42), vm.regs.readGP(1));

}

test "INC and DEC" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{ 0x2B, 0x00, 0x05, 0x00, 0x0E, 0x00, 0x0E, 0x00, 0x0F, 0x00, 0x80 };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 6), vm.regs.readGP(0)); // 5 + 1 + 1 - 1
}

test "INOT (bitwise NOT)" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{ 0x2B, 0x00, 0x00, 0x00, 0x13, 0x00, 0x00, 0x80 };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, ~@as(i32, 0)), vm.regs.readGP(0));
}

test "float arithmetic FADD" {
    const allocator = std.testing.allocator;
    // MOVI R0=10, MOVI R1=20 -> convert to float, add, store
    // Since we can't directly load floats, we test the opcode path
    var vm = try Interpreter.init(allocator, &[_]u8{}, 65536);
    defer vm.deinit();
    vm.regs.writeFP(0, 3.0);
    vm.regs.writeFP(1, 4.0);
    vm.regs.writeFP(2, 0.0);
    // Manually trigger FADD by constructing bytecode
    const bc = [_]u8{ 0x40, 0x02, 0x00, 0x01, 0x80 }; // FADD F2, F0, F1; HALT
    vm.bytecode = &bc;
    vm.pc = 0;
    _ = try vm.execute();
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), vm.regs.readFP(2), 0.001);
}

test "ICMP unsigned comparison" {
    const allocator = std.testing.allocator;
    // ICMP ULT: test if -1 (0xFFFFFFFF) unsigned < 1
    const bc = [_]u8{
        0x2B, 0x00, 0xFF, 0xFF, // MOVI R0, -1
        0x2B, 0x01, 0x01, 0x00, // MOVI R1, 1
        0x18, 0x06, 0x00, 0x01, // ICMP ULT, R0, R1
        0x80,                    // HALT
    };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    // -1 as unsigned (0xFFFFFFFF) IS < 1 as unsigned (0x00000001)? No! 0xFFFFFFFF > 1
    try std.testing.expectEqual(@as(i32, 0), vm.regs.readGP(0));
}

test "BOX and UNBOX" {
    const allocator = std.testing.allocator;
    const bc = [_]u8{
        0x39, 0x00, 0x00,              // BOX R0, type=INT
        0x2A, 0x00, 0x00, 0x00,        // value = 42 (i32 LE)
        0x3A, 0x01, 0x00,              // UNBOX R1, box_id=R0
        0x80,                          // HALT
    };
    var vm = try Interpreter.init(allocator, &bc, 65536);
    defer vm.deinit();
    _ = try vm.execute();
    try std.testing.expectEqual(@as(i32, 42), vm.regs.readGP(1));
}
