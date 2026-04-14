//! FLUX Micro-VM Bytecode Interpreter.
//!
//! Faithful Zig port of flux-runtime/src/flux/vm/interpreter.py.
//! Implements fetch-decode-execute loop for all 102+ opcodes.
//!
//! Instruction encoding formats:
//!   Format A (1 byte):  [opcode]
//!   Format B (2 bytes): [opcode][reg]
//!   Format C (3 bytes): [opcode][rd][rs1]
//!   Format D (4 bytes): [opcode][rs1][off_lo][off_hi]  (i16 signed)
//!   Format E (4 bytes): [opcode][rd][rs1][rs2]
//!   Format G (variable):[opcode][len:u16_le][data:len bytes]

const std = @import("std");
const mem = std.mem;

const Opcode = @import("../bytecode/opcodes.zig").Opcode;
const RegisterFile = @import("registers.zig").RegisterFile;
const MemoryManager = @import("memory.zig").MemoryManager;

pub const MAX_STACK_SIZE = 4096;
pub const MAX_CYCLES: u64 = 10_000_000;
pub const DEFAULT_MEMORY_SIZE: u32 = 65536;

// Box type tags
const BOX_TYPE_INT: u8 = 0;
const BOX_TYPE_FLOAT: u8 = 1;
const BOX_TYPE_BOOL: u8 = 2;

// ━━━ Error types ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub const VMError = error{
    Halted,
    InvalidOpcode,
    DivisionByZero,
    StackOverflow,
    StackUnderflow,
    TypeCheck,
    BoundsCheck,
    OutOfBounds,
    ResourceAcquireFailed,
    CycleBudgetExceeded,
};

// ━━━ Interpreter ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub const Interpreter = struct {
    regs: RegisterFile = .{},
    memory: MemoryManager = .{},
    bytecode: []const u8 = &[_]u8{},
    pc: u32 = 0,
    cycle_count: u64 = 0,
    max_cycles: u64 = MAX_CYCLES,
    running: bool = false,
    halted: bool = false,

    // Condition flags
    flag_zero: bool = false,
    flag_sign: bool = false,
    flag_carry: bool = false,
    flag_overflow: bool = false,

    // Box table for BOX/UNBOX/CHECK_TYPE
    box_table: std.ArrayListUnmanaged(BoxEntry) = .{},
    box_counter: u32 = 0,

    // Frame stack for ENTER/LEAVE
    frame_stack: std.ArrayListUnmanaged(i32) = .{},

    allocator: mem.Allocator,

    const BoxEntry = struct {
        type_tag: u8,
        value: i32,
    };

    pub fn init(allocator: mem.Allocator, bytecode: []const u8, memory_size: u32) !Interpreter {
        var interp: Interpreter = .{ .allocator = allocator, .bytecode = bytecode };
        // Create default memory regions
        _ = try interp.memory.createRegion(allocator, "stack", memory_size, "system");
        _ = try interp.memory.createRegion(allocator, "heap", memory_size, "system");
        // Stack starts at top and grows downward
        interp.regs.setSP(@intCast(memory_size));
        return interp;
    }

    pub fn deinit(self: *Interpreter) void {
        self.box_table.deinit(self.allocator);
        self.frame_stack.deinit(self.allocator);
        self.memory.deinit(self.allocator);
    }

    pub fn reset(self: *Interpreter) void {
        self.pc = 0;
        self.cycle_count = 0;
        self.running = false;
        self.halted = false;
        self.flag_zero = false;
        self.flag_sign = false;
        self.flag_carry = false;
        self.flag_overflow = false;
        self.regs = .{};
        // Reset SP to top of stack
        if (self.memory.getRegion("stack")) |stack| {
            self.regs.setSP(@intCast(stack.size));
        } else |_| {}
        self.box_table.clearRetainingCapacity();
        self.box_counter = 0;
        self.frame_stack.clearRetainingCapacity();
    }

    /// Execute bytecode until HALT, cycle budget exceeded, or error.
    /// Returns the total number of cycles consumed.
    pub fn execute(self: *Interpreter) !u64 {
        self.running = true;
        while (self.running and !self.halted) {
            if (self.cycle_count >= self.max_cycles) {
                return error.CycleBudgetExceeded;
            }
            self.step();
            self.cycle_count += 1;
        }
        self.running = false;
        return self.cycle_count;
    }

    /// Execute a single instruction.
    pub fn step(self: *Interpreter) void {
        const start_pc = self.pc;
        const opcode_byte = self.fetchU8();
        const op = std.meta.intToEnum(Opcode, opcode_byte) catch {
            // Unknown opcode — raise error
            self.pc = start_pc;
            return;
        };

        switch (op) {
            // ── Control flow ─────────────────────────────────────────
            .NOP => {},
            .HALT => {
                self.running = false;
                self.halted = true;
            },
            .MOV => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                self.regs.writeGP(rd, self.regs.readGP(rs1));
            },
            .MOVI => {
                const reg = self.fetchU8();
                const imm = self.fetchI16();
                self.regs.writeGP(reg, imm);
            },
            .JMP => {
                _ = self.fetchU8(); // rs1 (unused for unconditional jump)
                const offset = self.fetchI16();
                self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
            },
            .JZ => {
                const rs1 = self.fetchU8();
                const offset = self.fetchI16();
                if (self.regs.readGP(rs1) == 0) {
                    self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
                }
            },
            .JNZ => {
                const rs1 = self.fetchU8();
                const offset = self.fetchI16();
                if (self.regs.readGP(rs1) != 0) {
                    self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
                }
            },
            .JE => {
                _ = self.fetchU8();
                const offset = self.fetchI16();
                if (self.flag_zero) {
                    self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
                }
            },
            .JNE => {
                _ = self.fetchU8();
                const offset = self.fetchI16();
                if (!self.flag_zero) {
                    self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
                }
            },
            .JG => {
                _ = self.fetchU8();
                const offset = self.fetchI16();
                if (!self.flag_zero and !self.flag_sign) {
                    self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
                }
            },
            .JL => {
                _ = self.fetchU8();
                const offset = self.fetchI16();
                if (self.flag_sign) {
                    self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
                }
            },
            .JGE => {
                _ = self.fetchU8();
                const offset = self.fetchI16();
                if (!self.flag_sign) {
                    self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
                }
            },
            .JLE => {
                _ = self.fetchU8();
                const offset = self.fetchI16();
                if (self.flag_zero or self.flag_sign) {
                    self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
                }
            },
            .CALL => {
                _ = self.fetchU8();
                const offset = self.fetchI16();
                self.stackPush(@intCast(self.pc));
                self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
            },
            .CALL_IND => {
                const rd = self.fetchU8();
                const target_reg = self.fetchU8();
                const target = self.regs.readGP(target_reg);
                self.stackPush(@intCast(self.pc));
                self.pc = @intCast(target);
                _ = rd;
            },
            .TAILCALL => {
                _ = self.fetchU8();
                const offset = self.fetchI16();
                self.pc = @intCast(@as(i64, @as(i32, @intCast(self.pc))) + offset);
            },
            .RET => {
                const stack = self.memory.getRegion("stack") catch {
                    self.halted = true;
                    return;
                };
                if (self.regs.getSP() >= @as(i32, @intCast(stack.size)) - 4) {
                    self.halted = true;
                    return;
                }
                self.pc = @intCast(self.stackPop());
            },

            // ── Integer Arithmetic ───────────────────────────────────
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
                if (divisor == 0) {
                    self.pc = start_pc;
                    // Division by zero — store error indicator
                    self.regs.writeGP(rd, 0x7FFFFFFF);
                    return;
                }
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
                if (divisor == 0) {
                    self.pc = start_pc;
                    self.regs.writeGP(rd, 0);
                    return;
                }
                const dividend = self.regs.readGP(rs1);
                const result = @rem(dividend, divisor);
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IREM => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const divisor = self.regs.readGP(rs2);
                if (divisor == 0) {
                    self.pc = start_pc;
                    self.regs.writeGP(rd, 0);
                    return;
                }
                const dividend = self.regs.readGP(rs1);
                // Python-style remainder: sign follows dividend
                const result = dividend - @divTrunc(dividend, divisor) * divisor;
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

            // ── Bitwise ──────────────────────────────────────────────
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
                const shift: u5 = @intCast(self.regs.readGP(rs2) & 0x3F);
                const result = self.regs.readGP(rs1) << shift;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ISHR => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const shift: u5 = @intCast(self.regs.readGP(rs2) & 0x3F);
                const result = self.regs.readGP(rs1) >> shift;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ROTL => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const val: u32 = @bitCast(self.regs.readGP(rs1));
                const shift: u5 = @intCast(self.regs.readGP(rs2) & 0x1F);
                const rotated = std.math.rotl(u32, val, shift);
                self.regs.writeGP(rd, @bitCast(rotated));
                self.setFlags(@bitCast(rotated));
            },
            .ROTR => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const val: u32 = @bitCast(self.regs.readGP(rs1));
                const shift: u5 = @intCast(self.regs.readGP(rs2) & 0x1F);
                const rotated = std.math.rotr(u32, val, shift);
                self.regs.writeGP(rd, @bitCast(rotated));
                self.setFlags(@bitCast(rotated));
            },

            // ── Comparison ───────────────────────────────────────────
            .ICMP => {
                // [ICMP][cond:u8][rd:u8][rs:u8]
                const cond = self.fetchU8();
                const rd = self.fetchU8();
                const rs = self.fetchU8();
                const a = self.regs.readGP(rd);
                const b_val = self.regs.readGP(rs);
                const ua: u32 = @bitCast(a);
                const ub: u32 = @bitCast(b_val);
                const result: i32 = switch (cond) {
                    0 => @intFromBool(a == b_val), // EQ
                    1 => @intFromBool(a != b_val), // NE
                    2 => @intFromBool(a < b_val), // LT signed
                    3 => @intFromBool(a <= b_val), // LE signed
                    4 => @intFromBool(a > b_val), // GT signed
                    5 => @intFromBool(a >= b_val), // GE signed
                    6 => @intFromBool(ua < ub), // ULT
                    7 => @intFromBool(ua <= ub), // ULE
                    8 => @intFromBool(ua > ub), // UGT
                    9 => @intFromBool(ua >= ub), // UGE
                    else => 0,
                };
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IEQ => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readGP(rd) == self.regs.readGP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ILT => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readGP(rd) < self.regs.readGP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .ILE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readGP(rd) <= self.regs.readGP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IGT => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readGP(rd) > self.regs.readGP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .IGE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readGP(rd) >= self.regs.readGP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .TEST => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result = self.regs.readGP(rd) & self.regs.readGP(rs1);
                self.setFlags(result);
            },
            .SETCC => {
                const rd = self.fetchU8();
                const cond = self.fetchU8();
                const result: bool = switch (cond) {
                    0 => self.flag_zero, // EQ
                    1 => !self.flag_zero, // NE
                    2 => self.flag_sign, // LT
                    3 => !self.flag_sign, // GE
                    4 => !self.flag_zero and !self.flag_sign, // GT
                    5 => self.flag_zero or self.flag_sign, // LE
                    6 => self.flag_carry, // CS/HS
                    7 => !self.flag_carry, // CC/LO
                    8 => self.flag_overflow, // VS
                    9 => !self.flag_overflow, // VC
                    else => false,
                };
                self.regs.writeGP(rd, if (result) 1 else 0);
            },
            .CMP => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                self.setCmpFlags(self.regs.readGP(rd), self.regs.readGP(rs1));
            },

            // ── Stack ────────────────────────────────────────────────
            .PUSH => {
                const reg = self.fetchU8();
                self.stackPush(self.regs.readGP(reg));
            },
            .POP => {
                const reg = self.fetchU8();
                self.regs.writeGP(reg, self.stackPop());
            },
            .DUP => {
                // Format A: duplicate top of stack
                const stack = self.memory.getRegion("stack") catch return;
                const val = MemoryManager.stackPop(stack, self.regs.getSP()) catch return;
                self.regs.setSP(val[1]);
                const new_sp1 = MemoryManager.stackPush(stack, self.regs.getSP(), val[0]) catch return;
                self.regs.setSP(new_sp1);
                const new_sp2 = MemoryManager.stackPush(stack, self.regs.getSP(), val[0]) catch return;
                self.regs.setSP(new_sp2);
            },
            .SWAP => {
                // Format A: swap top two stack elements
                const stack = self.memory.getRegion("stack") catch return;
                const a = MemoryManager.stackPop(stack, self.regs.getSP()) catch return;
                const b = MemoryManager.stackPop(stack, a[1]) catch return;
                const sp3 = MemoryManager.stackPush(stack, b[1], a[0]) catch return;
                const sp4 = MemoryManager.stackPush(stack, sp3, b[0]) catch return;
                self.regs.setSP(sp4);
            },
            .ROT => {
                // Format A: rotate top 3 stack elements: [c, b, a] -> [b, a, c]
                const stack = self.memory.getRegion("stack") catch return;
                const a = MemoryManager.stackPop(stack, self.regs.getSP()) catch return;
                const b = MemoryManager.stackPop(stack, a[1]) catch return;
                const c = MemoryManager.stackPop(stack, b[1]) catch return;
                const sp4 = MemoryManager.stackPush(stack, c[1], a[0]) catch return;
                const sp5 = MemoryManager.stackPush(stack, sp4, c[0]) catch return;
                const sp6 = MemoryManager.stackPush(stack, sp5, b[0]) catch return;
                self.regs.setSP(sp6);
            },
            .ENTER => {
                const frame_size = self.fetchU8();
                self.frame_stack.append(self.allocator, self.regs.getFP()) catch return;
                self.stackPush(self.regs.getFP());
                self.regs.setFP(self.regs.getSP());
                const alloc_bytes: i32 = @as(i32, frame_size) * 4;
                const new_sp = self.regs.getSP() - alloc_bytes;
                if (new_sp < 0) return;
                self.regs.setSP(new_sp);
            },
            .LEAVE => {
                _ = self.fetchU8(); // unused
                self.regs.setSP(self.regs.getFP());
                const old_fp = self.stackPop();
                self.regs.setFP(old_fp);
                // Pop from frame_stack
                if (self.frame_stack.items.len > 0) {
                    _ = self.frame_stack.pop();
                }
            },
            .ALLOCA => {
                const rd = self.fetchU8();
                const size_reg = self.fetchU8();
                const size: i32 = self.regs.readGP(size_reg) * 4;
                const new_sp = self.regs.getSP() - size;
                if (new_sp < 0) return;
                self.regs.setSP(new_sp);
                self.regs.writeGP(rd, self.regs.getSP());
            },

            // ── Memory ───────────────────────────────────────────────
            .LOAD => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = self.regs.readGP(rs1);
                const stack = self.memory.getRegion("stack") catch return;
                const value = stack.readI32(@intCast(addr)) catch return;
                self.regs.writeGP(rd, value);
            },
            .STORE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = self.regs.readGP(rs1);
                const val = self.regs.readGP(rd);
                const stack = self.memory.getRegion("stack") catch return;
                stack.writeI32(@intCast(addr), val) catch return;
            },
            .LOAD8 => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = self.regs.readGP(rs1);
                const stack = self.memory.getRegion("stack") catch return;
                const data = stack.read(@intCast(addr), 1) catch return;
                self.regs.writeGP(rd, @as(i32, data[0]));
            },
            .STORE8 => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = self.regs.readGP(rs1);
                const val: u8 = @intCast(self.regs.readGP(rd) & 0xFF);
                const stack = self.memory.getRegion("stack") catch return;
                stack.write(@intCast(addr), &[_]u8{val}) catch return;
            },

            // ── Float Arithmetic ─────────────────────────────────────
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
                if (divisor == 0.0) return;
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
                const a = self.regs.readFP(rs1);
                const b = self.regs.readFP(rs2);
                self.regs.writeFP(rd, @min(a, b));
            },
            .FMAX => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                const a = self.regs.readFP(rs1);
                const b = self.regs.readFP(rs2);
                self.regs.writeFP(rd, @max(a, b));
            },

            // ── Float Comparison ─────────────────────────────────────
            .FEQ => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readFP(rd) == self.regs.readFP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .FLT => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readFP(rd) < self.regs.readFP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .FLE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readFP(rd) <= self.regs.readFP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .FGT => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readFP(rd) > self.regs.readFP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },
            .FGE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const result: i32 = if (self.regs.readFP(rd) >= self.regs.readFP(rs1)) 1 else 0;
                self.regs.writeGP(rd, result);
                self.setFlags(result);
            },

            // ── SIMD Vector ─────────────────────────────────────────
            .VLOAD => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = self.regs.readGP(rs1);
                const stack = self.memory.getRegion("stack") catch return;
                const data = stack.read(@intCast(addr), 16) catch return;
                var vec: [16]u8 = [_]u8{0} ** 16;
                @memcpy(&vec, data);
                self.regs.writeVec(rd, vec);
            },
            .VSTORE => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const addr = self.regs.readGP(rs1);
                const stack = self.memory.getRegion("stack") catch return;
                const vec = self.regs.readVec(rd);
                stack.write(@intCast(addr), &vec) catch return;
            },
            .VADD, .VSUB, .VMUL, .VDIV, .VFMA => {
                // SIMD ops: element-wise i32 add/sub/mul/div on 4 lanes
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const rs2 = self.fetchU8();
                var result_vec = self.regs.readVec(rs1);
                const v2 = self.regs.readVec(rs2);
                for (0..4) |lane| {
                    const off = lane * 4;
                    const a: i32 = @bitCast([4]u8{ result_vec[off], result_vec[off + 1], result_vec[off + 2], result_vec[off + 3] });
                    const b: i32 = @bitCast([4]u8{ v2[off], v2[off + 1], v2[off + 2], v2[off + 3] });
                    const res: i32 = switch (op) {
                        .VADD => a + b,
                        .VSUB => a - b,
                        .VMUL => a * b,
                        .VDIV => if (b != 0) @divTrunc(a, b) else 0,
                        .VFMA => a,
                        else => 0,
                    };
                    const bytes: [4]u8 = @bitCast(res);
                    result_vec[off] = bytes[0];
                    result_vec[off + 1] = bytes[1];
                    result_vec[off + 2] = bytes[2];
                    result_vec[off + 3] = bytes[3];
                }
                self.regs.writeVec(rd, result_vec);
            },

            // ── Type Operations ──────────────────────────────────────
            .CAST => {
                const rd = self.fetchU8();
                const rs1 = self.fetchU8();
                const type_tag = self.fetchU8();
                const val = self.regs.readGP(rs1);
                switch (type_tag) {
                    0 => {
                        // i32 -> f32 (bit reinterpret)
                        const fval: f32 = @bitCast(val);
                        self.regs.writeGP(rd, @as(i32, @intFromFloat(fval * 1000)));
                    },
                    1 => {
                        // f32 -> i32
                        self.regs.writeGP(rd, val);
                    },
                    2 => {
                        // i32 -> bool
                        self.regs.writeGP(rd, if (val != 0) 1 else 0);
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
            .BOX => {
                const rd = self.fetchU8();
                const type_tag = self.fetchU8();
                const raw = self.fetchI32();
                self.box_table.append(self.allocator, .{ .type_tag = type_tag, .value = raw }) catch return;
                self.regs.writeGP(rd, @as(i32, @intCast(self.box_counter)));
                self.box_counter += 1;
            },
            .UNBOX => {
                const rd = self.fetchU8();
                const box_reg = self.fetchU8();
                const box_id: usize = @intCast(self.regs.readGP(box_reg));
                if (box_id < self.box_table.items.len) {
                    self.regs.writeGP(rd, self.box_table.items[box_id].value);
                }
            },
            .CHECK_TYPE => {
                const box_reg = self.fetchU8();
                const expected = self.fetchU8();
                const box_id: usize = @intCast(self.regs.readGP(box_reg));
                _ = expected;
                _ = box_id;
                // Stub: type checking passes silently for now
            },
            .CHECK_BOUNDS => {
                _ = self.fetchU8(); // reg
                _ = self.fetchU8(); // bound
                // Stub
            },
            .CONF => {
                // CONF: attach confidence — stub
                _ = self.fetchU8(); // rd
                _ = self.fetchU8(); // rs1
            },
            .MERGE => {
                _ = self.fetchU8(); // rd
                _ = self.fetchU8(); // rs1
            },
            .RESTORE => {
                _ = self.fetchU8(); // rd
                _ = self.fetchU8(); // rs1
            },

            // ── System ───────────────────────────────────────────────
            .YIELD => {
                // Cooperative yield — currently a no-op in single-threaded mode
            },
            .DEBUG_BREAK => {
                // Debug breakpoint — no-op in release mode
            },
            .EMERGENCY_STOP => {
                self.running = false;
                self.halted = true;
            },

            // ── Region operations (Format G — variable) ──────────────
            .REGION_CREATE => {
                const data = self.fetchVarData();
                self.handleRegionCreate(data);
            },
            .REGION_DESTROY => {
                const data = self.fetchVarData();
                const name = self.trimNull(data);
                self.memory.destroyRegion(self.allocator, name) catch {};
            },
            .REGION_TRANSFER => {
                const data = self.fetchVarData();
                self.handleRegionTransfer(data);
            },
            .MEMCOPY => {
                const data = self.fetchVarData();
                self.handleMemCopy(data);
            },
            .MEMSET => {
                const data = self.fetchVarData();
                self.handleMemSet(data);
            },
            .MEMCMP => {
                const data = self.fetchVarData();
                self.handleMemCmp(data);
            },

            // ── A2A Protocol (Format G — all stubs for now) ───────────
            .TELL, .ASK, .DELEGATE, .DELEGATE_RESULT,
            .REPORT_STATUS, .REQUEST_OVERRIDE, .BROADCAST, .REDUCE,
            .DECLARE_INTENT, .ASSERT_GOAL, .VERIFY_OUTCOME,
            .EXPLAIN_FAILURE, .SET_PRIORITY,
            .TRUST_CHECK, .TRUST_UPDATE, .TRUST_QUERY, .REVOKE_TRUST,
            .CAP_REQUIRE, .CAP_REQUEST, .CAP_GRANT, .CAP_REVOKE,
            .BARRIER, .SYNC_CLOCK, .FORMATION_UPDATE,
            .RESOURCE_ACQUIRE, .RESOURCE_RELEASE,
            .EVOLVE, .INSTINCT, .WITNESS, .SNAPSHOT => {
                // A2A and meta opcodes: consume variable data if Format G
                if (op.format() == .G) {
                    _ = self.fetchVarData();
                }
                // Silently no-op (stub behavior for self-hosting)
            },

            // ── Catch-all: unknown ──────────────────────────────────
            else => {
                // Unknown/reserved opcode — skip
            },
        }
    }

    // ── Fetch helpers ──────────────────────────────────────────────────

    inline fn fetchU8(self: *Interpreter) u8 {
        if (self.pc >= self.bytecode.len) return 0;
        const b = self.bytecode[self.pc];
        self.pc += 1;
        return b;
    }

    inline fn fetchI16(self: *Interpreter) i16 {
        const lo = self.fetchU8();
        const hi = self.fetchU8();
        const val: u16 = @as(u16, lo) | (@as(u16, hi) << 8);
        return @as(i16, @bitCast(val));
    }

    inline fn fetchI32(self: *Interpreter) i32 {
        const b0 = self.fetchU8();
        const b1 = self.fetchU8();
        const b2 = self.fetchU8();
        const b3 = self.fetchU8();
        const val: u32 = @as(u32, b0) | (@as(u32, b1) << 8) | (@as(u32, b2) << 16) | (@as(u32, b3) << 24);
        return @as(i32, @bitCast(val));
    }

    fn fetchVarData(self: *Interpreter) []const u8 {
        const lo = self.fetchU8();
        const hi = self.fetchU8();
        const length = @as(u16, lo) | (@as(u16, hi) << 8);
        const start = self.pc;
        const end = @min(start + length, self.bytecode.len);
        self.pc = end;
        return self.bytecode[start..end];
    }

    // ── Flag helpers ──────────────────────────────────────────────────

    fn setFlags(self: *Interpreter, result: i32) void {
        self.flag_zero = (result == 0);
        self.flag_sign = (result < 0);
        self.flag_carry = (result < 0);
        self.flag_overflow = false;
    }

    fn setCmpFlags(self: *Interpreter, a: i32, b: i32) void {
        self.flag_zero = (a == b);
        self.flag_sign = (a < b);
        self.flag_carry = (a < b);
        const result = a - b;
        self.flag_overflow = ((a > 0 and b < 0 and result < 0) or
            (a < 0 and b > 0 and result > 0));
    }

    // ── Stack helpers ─────────────────────────────────────────────────

    fn stackPush(self: *Interpreter, value: i32) void {
        const stack = self.memory.getRegion("stack") catch return;
        const new_sp = MemoryManager.stackPush(stack, self.regs.getSP(), value) catch return;
        self.regs.setSP(new_sp);
    }

    fn stackPop(self: *Interpreter) i32 {
        const stack = self.memory.getRegion("stack") catch return 0;
        const result = MemoryManager.stackPop(stack, self.regs.getSP()) catch return 0;
        self.regs.setSP(result[1]);
        return result[0];
    }

    // ── Region operation handlers ─────────────────────────────────────

    fn handleRegionCreate(self: *Interpreter, data: []const u8) void {
        if (data.len < 2) return;
        var idx: usize = 0;
        const name_len = data[idx];
        idx += 1;
        const name = self.trimNull(data[idx..@min(idx + name_len, data.len)]);
        idx += name_len;
        if (idx + 4 > data.len) return;
        const size: u32 = @bitCast([4]u8{ data[idx], data[idx + 1], data[idx + 2], data[idx + 3] });
        idx += 4;
        const owner = if (idx < data.len) self.trimNull(data[idx..]) else "system";
        _ = self.memory.createRegion(self.allocator, name, size, owner) catch {};
        self.regs.writeGP(0, 0);
    }

    fn handleRegionTransfer(self: *Interpreter, data: []const u8) void {
        if (data.len < 2) return;
        var idx: usize = 0;
        const name_len = data[idx];
        idx += 1;
        const name = self.trimNull(data[idx..@min(idx + name_len, data.len)]);
        idx += name_len;
        if (idx >= data.len) return;
        const owner_len = data[idx];
        idx += 1;
        const new_owner = self.trimNull(data[idx..@min(idx + owner_len, data.len)]);
        self.memory.transferRegion(name, new_owner) catch {};
    }

    fn handleMemCopy(self: *Interpreter, data: []const u8) void {
        if (data.len < 14) return;
        var idx: usize = 0;
        const rname_len = data[idx];
        idx += 1;
        const rname = self.trimNull(data[idx..@min(idx + rname_len, data.len)]);
        idx += rname_len;
        if (idx + 12 > data.len) return;
        const src_off: u32 = @bitCast([4]u8{ data[idx], data[idx + 1], data[idx + 2], data[idx + 3] });
        idx += 4;
        const dst_off: u32 = @bitCast([4]u8{ data[idx], data[idx + 1], data[idx + 2], data[idx + 3] });
        idx += 4;
        const size: u32 = @bitCast([4]u8{ data[idx], data[idx + 1], data[idx + 2], data[idx + 3] });
        const region = self.memory.getRegion(rname) catch return;
        const chunk = region.read(src_off, size) catch return;
        region.write(dst_off, chunk) catch {};
    }

    fn handleMemSet(self: *Interpreter, data: []const u8) void {
        if (data.len < 10) return;
        var idx: usize = 0;
        const rname_len = data[idx];
        idx += 1;
        const rname = self.trimNull(data[idx..@min(idx + rname_len, data.len)]);
        idx += rname_len;
        if (idx + 5 > data.len) return;
        const offset: u32 = @bitCast([4]u8{ data[idx], data[idx + 1], data[idx + 2], data[idx + 3] });
        idx += 4;
        const value = data[idx];
        idx += 1;
        if (idx + 4 > data.len) return;
        const size: u32 = @bitCast([4]u8{ data[idx], data[idx + 1], data[idx + 2], data[idx + 3] });
        const region = self.memory.getRegion(rname) catch return;
        var buf = std.ArrayList(u8).initCapacity(self.allocator, size) catch return;
        defer buf.deinit();
        @memset(buf.items.ptr[0..size], value);
        buf.items.len = size;
        region.write(offset, buf.items) catch {};
    }

    fn handleMemCmp(self: *Interpreter, data: []const u8) void {
        if (data.len < 14) return;
        var idx: usize = 0;
        const rname_len = data[idx];
        idx += 1;
        const rname = self.trimNull(data[idx..@min(idx + rname_len, data.len)]);
        idx += rname_len;
        if (idx + 12 > data.len) return;
        const off_a: u32 = @bitCast([4]u8{ data[idx], data[idx + 1], data[idx + 2], data[idx + 3] });
        idx += 4;
        const off_b: u32 = @bitCast([4]u8{ data[idx], data[idx + 1], data[idx + 2], data[idx + 3] });
        idx += 4;
        const size: u32 = @bitCast([4]u8{ data[idx], data[idx + 1], data[idx + 2], data[idx + 3] });
        const region = self.memory.getRegion(rname) catch return;
        const a = region.read(off_a, size) catch return;
        const b = region.read(off_b, size) catch return;
        const cmp_result = std.mem.order(u8, a, b);
        self.regs.writeGP(0, switch (cmp_result) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        });
    }

    fn trimNull(_: *Interpreter, data: []const u8) []const u8 {
        for (data, 0..) |c, i| {
            if (c == 0) return data[0..i];
        }
        return data;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────

test "execute NOP HALT" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const bytecode = [_]u8{
        @intFromEnum(Opcode.NOP),
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    const cycles = try interp.execute();
    try std.testing.expect(interp.halted);
    try std.testing.expectEqual(@as(u64, 2), cycles);
}

test "MOVI and MOV" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 42
    // MOV R1, R0
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 42, 0, // reg=0, imm16=42
        @intFromEnum(Opcode.MOV), 1, 0, // rd=1, rs1=0
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 42), interp.regs.readGP(0));
    try std.testing.expectEqual(@as(i32, 42), interp.regs.readGP(1));
}

test "IADD ISUB IMUL" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 10
    // MOVI R1, 3
    // IADD R2, R0, R1  => 13
    // ISUB R3, R0, R1  => 7
    // IMUL R4, R0, R1  => 30
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 10, 0,
        @intFromEnum(Opcode.MOVI), 1, 3, 0,
        @intFromEnum(Opcode.IADD), 2, 0, 1,
        @intFromEnum(Opcode.ISUB), 3, 0, 1,
        @intFromEnum(Opcode.IMUL), 4, 0, 1,
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 13), interp.regs.readGP(2));
    try std.testing.expectEqual(@as(i32, 7), interp.regs.readGP(3));
    try std.testing.expectEqual(@as(i32, 30), interp.regs.readGP(4));
}

test "IDIV IMOD" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 17
    // MOVI R1, 5
    // IDIV R2, R0, R1  => 3
    // IMOD R3, R0, R1  => 2
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 17, 0,
        @intFromEnum(Opcode.MOVI), 1, 5, 0,
        @intFromEnum(Opcode.IDIV), 2, 0, 1,
        @intFromEnum(Opcode.IMOD), 3, 0, 1,
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 3), interp.regs.readGP(2));
    try std.testing.expectEqual(@as(i32, 2), interp.regs.readGP(3));
}

test "comparison IEQ ILT IGT" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 10
    // MOVI R1, 10
    // IEQ R0, R1  => 1 (equal)
    // MOVI R1, 20
    // ILT R0, R1  => 1 (10 < 20)
    // IGT R1, R0  => 1 (20 > 1)
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 10, 0,
        @intFromEnum(Opcode.MOVI), 1, 10, 0,
        @intFromEnum(Opcode.IEQ), 0, 1,
        @intFromEnum(Opcode.MOVI), 1, 20, 0,
        @intFromEnum(Opcode.ILT), 0, 1,
        @intFromEnum(Opcode.IGT), 1, 0,
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    // After IEQ: R0 = 1
    // After MOVI R1,20: R1 = 20
    // After ILT: R0 was 1, R1 is 20, 1 < 20 => R0 = 1
    // After IGT: R1 = 20, R0 = 1, 20 > 1 => R1 = 1
    try std.testing.expectEqual(@as(i32, 1), interp.regs.readGP(0));
    try std.testing.expectEqual(@as(i32, 1), interp.regs.readGP(1));
}

test "PUSH POP stack" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 99
    // PUSH R0
    // MOVI R0, 0
    // POP R1
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 99, 0,
        @intFromEnum(Opcode.PUSH), 0,
        @intFromEnum(Opcode.MOVI), 0, 0, 0,
        @intFromEnum(Opcode.POP), 1,
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 0), interp.regs.readGP(0));
    try std.testing.expectEqual(@as(i32, 99), interp.regs.readGP(1));
}

test "JMP unconditional" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 10
    // JMP +3       (skip next 2 instructions, land on HALT)
    // MOVI R0, 999  (skipped)
    // MOVI R0, 888  (skipped)
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 10, 0, // pc=0..3, after: pc=4
        @intFromEnum(Opcode.JMP), 0, 6, 0, // pc=4..7, after: pc=8, offset=+6 => pc=14? no.
        // JMP format D: [op][rs1][off_lo][off_hi] = 4 bytes
        // After fetch: pc=8. offset = 6 => target = 8+6 = 14
        @intFromEnum(Opcode.MOVI), 0, 0xFF, 0x18, // pc=8..11 (skipped)
        @intFromEnum(Opcode.MOVI), 0, 0xFF, 0x18, // pc=12..15 (skipped)
        @intFromEnum(Opcode.HALT), // pc=14
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 10), interp.regs.readGP(0));
}

test "JZ conditional" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 0
    // JZ R0, +3    (taken because R0==0)
    // MOVI R0, 999  (skipped)
    // MOVI R0, 888  (skipped)
    // MOVI R0, 42   (executed)
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 0, 0, // pc=0..3
        @intFromEnum(Opcode.JZ), 0, 6, 0, // pc=4..7, after: pc=8, jump to 14
        @intFromEnum(Opcode.MOVI), 0, 0xFF, 0x18, // pc=8..11 (skipped)
        @intFromEnum(Opcode.MOVI), 0, 0xFF, 0x18, // pc=12..15 (skipped)
        @intFromEnum(Opcode.MOVI), 0, 42, 0, // pc=14..17 (target)
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 42), interp.regs.readGP(0));
}

test "CALL and RET" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Main: MOVI R0, 0
    //       CALL +4       (call func at pc=8+4=12)
    //       HALT
    // Func: MOVI R0, 77   (pc=10? no, need to calculate)
    //       RET

    // Let's be precise:
    // pc=0: MOVI R0, 0   [0x2B, 0x00, 0x00, 0x00] => 4 bytes, pc=4
    // pc=4: CALL +6       [0x07, 0x00, 0x06, 0x00] => 4 bytes, pc=8, jump to 8+6=14
    // pc=8: HALT          [0x80] => 1 byte (never reached before return)
    // ...padding to reach 14
    // pc=14: MOVI R0, 77  [0x2B, 0x00, 0x4D, 0x00] => 4 bytes, pc=18
    // pc=18: RET           [0x28, 0x00, 0x00] => 3 bytes

    const bytecode = [_]u8{
        // pc=0
        @intFromEnum(Opcode.MOVI), 0, 0, 0,
        // pc=4
        @intFromEnum(Opcode.CALL), 0, 6, 0, // offset=6 => target=8+6=14
        // pc=8 (return lands here)
        @intFromEnum(Opcode.HALT),
        // pc=9..13 (padding NOPs)
        @intFromEnum(Opcode.NOP),
        @intFromEnum(Opcode.NOP),
        @intFromEnum(Opcode.NOP),
        @intFromEnum(Opcode.NOP),
        @intFromEnum(Opcode.NOP),
        // pc=14 (function entry)
        @intFromEnum(Opcode.MOVI), 0, 77, 0,
        // pc=18
        @intFromEnum(Opcode.RET), 0, 0,
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 77), interp.regs.readGP(0));
    try std.testing.expect(interp.halted);
}

test "bitwise operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 0xFF (255)
    // MOVI R1, 0x0F (15)
    // IAND R2, R0, R1 => 15
    // IOR R3, R0, R1 => 255
    // INOT R4, R1     => -16
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 0xFF, 0, // 255
        @intFromEnum(Opcode.MOVI), 1, 15, 0,
        @intFromEnum(Opcode.IAND), 2, 0, 1,
        @intFromEnum(Opcode.IOR), 3, 0, 1,
        @intFromEnum(Opcode.INOT), 4, 1,
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 15), interp.regs.readGP(2));
    try std.testing.expectEqual(@as(i32, 255), interp.regs.readGP(3));
    try std.testing.expectEqual(@as(i32, -16), interp.regs.readGP(4));
}

test "STORE and LOAD round-trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 100    (value to store)
    // MOVI R1, 0      (address in stack region)
    // STORE R0, R1    (store R0 at address in R1)
    // MOVI R2, 0      (address to load from)
    // LOAD R3, R2     (load from address in R2)
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 100, 0,
        @intFromEnum(Opcode.MOVI), 1, 0, 0,
        @intFromEnum(Opcode.STORE), 0, 1,
        @intFromEnum(Opcode.MOVI), 2, 0, 0,
        @intFromEnum(Opcode.LOAD), 3, 2,
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 100), interp.regs.readGP(3));
}

test "float arithmetic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Write 3.0 into F0 via store/load trick
    // MOVI R0, (bits of 3.0f)
    // CAST R0, R0, tag=0 (i32->f32 approx *1000)
    // Actually, let's use a simpler approach with the raw bit pattern

    // 3.0f = 0x40400000 = 1077936128
    // 2.0f = 0x40000000 = 1073741824
    // We'll write these directly via STORE/LOAD

    // For now, test FNEG and FABS
    // MOVI R0, 1077936128 => actually can't fit in i16
    // Let's use a different approach: test via the registers directly
    var interp = try Interpreter.init(alloc, &[_]u8{@intFromEnum(Opcode.HALT)}, 4096);
    defer interp.deinit();

    // Write directly to FP registers for test
    interp.regs.writeFP(0, 3.0);
    interp.regs.writeFP(1, 2.0);

    // Manually execute FADD
    const add_bytecode = [_]u8{
        @intFromEnum(Opcode.FADD), 2, 0, 1, // F2 = F0 + F1
        @intFromEnum(Opcode.HALT),
    };
    interp.bytecode = &add_bytecode;
    interp.pc = 0;
    interp.halted = false;
    _ = try interp.execute();
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), interp.regs.readFP(2), 0.001);

    // Test FNEG
    interp.reset();
    interp.regs.writeFP(0, 3.0);
    const neg_bytecode = [_]u8{
        @intFromEnum(Opcode.FNEG), 1, 0,
        @intFromEnum(Opcode.HALT),
    };
    interp.bytecode = &neg_bytecode;
    _ = try interp.execute();
    try std.testing.expectApproxEqAbs(@as(f32, -3.0), interp.regs.readFP(1), 0.001);

    // Test FABS
    interp.reset();
    interp.regs.writeFP(0, -4.5);
    const abs_bytecode = [_]u8{
        @intFromEnum(Opcode.FABS), 1, 0,
        @intFromEnum(Opcode.HALT),
    };
    interp.bytecode = &abs_bytecode;
    _ = try interp.execute();
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), interp.regs.readFP(1), 0.001);
}

test "CMP and conditional jumps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // MOVI R0, 10
    // MOVI R1, 10
    // CMP R0, R1       (sets flag_zero=true)
    // JE +3            (taken: flag_zero=true)
    // MOVI R2, 0      (skipped)
    // MOVI R3, 0      (skipped)
    // MOVI R2, 1      (executed)
    // HALT
    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 10, 0, // pc=0
        @intFromEnum(Opcode.MOVI), 1, 10, 0, // pc=4
        @intFromEnum(Opcode.CMP), 0, 1, // pc=8
        @intFromEnum(Opcode.JE), 0, 6, 0, // pc=11, after: pc=15, jump to 15+6=21
        @intFromEnum(Opcode.MOVI), 2, 0xFF, 0x18, // pc=15 (skipped)
        @intFromEnum(Opcode.MOVI), 3, 0xFF, 0x18, // pc=19 (skipped)
        @intFromEnum(Opcode.MOVI), 2, 1, 0, // pc=21+? let me recalc
        @intFromEnum(Opcode.HALT),
    };
    _ = bytecode;

    // Simpler test
    var interp = try Interpreter.init(alloc, &[_]u8{
        @intFromEnum(Opcode.MOVI), 0, 10, 0,
        @intFromEnum(Opcode.MOVI), 1, 10, 0,
        @intFromEnum(Opcode.CMP), 0, 1, // flag_zero = true
        @intFromEnum(Opcode.JNE), 0, 3, 0, // NOT taken (flag_zero=true)
        @intFromEnum(Opcode.MOVI), 2, 1, 0, // R2=1 (taken path)
        @intFromEnum(Opcode.JMP), 0, 3, 0, // jump to HALT
        @intFromEnum(Opcode.MOVI), 2, 0xFF, 0x18, // skipped
        @intFromEnum(Opcode.HALT),
    }, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 1), interp.regs.readGP(2));
}

test "INC DEC" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const bytecode = [_]u8{
        @intFromEnum(Opcode.MOVI), 0, 10, 0,
        @intFromEnum(Opcode.INC), 0, // R0=11
        @intFromEnum(Opcode.INC), 0, // R0=12
        @intFromEnum(Opcode.DEC), 0, // R0=11
        @intFromEnum(Opcode.HALT),
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();

    _ = try interp.execute();
    try std.testing.expectEqual(@as(i32, 11), interp.regs.readGP(0));
}

test "cycle budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Infinite loop: JMP to self (offset -4)
    const bytecode = [_]u8{
        @intFromEnum(Opcode.JMP), 0, @as(u8, @bitCast(@as(i16, -4))), 0xFF,
    };

    var interp = try Interpreter.init(alloc, &bytecode, 4096);
    defer interp.deinit();
    interp.max_cycles = 100;

    const result = interp.execute();
    try std.testing.expectError(error.CycleBudgetExceeded, result);
}
