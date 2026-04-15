package vm

import (
        "encoding/binary"
        "fmt"
)

// ReturnStackSize is the max depth for the call return stack.
const ReturnStackSize = 64

// EngineSnapshot captures the complete VM state for snapshot/restore.
type EngineSnapshot struct {
        StepCount    int
        PC           uint16
        Flags        uint8
        Zero         bool
        Carry        bool
        Overflow     bool
        StackData    []uint32
        ReturnStack  []uint32
        Memory       [MemorySize]byte
        Halted       bool
}

// Engine is the FLUX bytecode virtual machine.
type Engine struct {
        mem         *Memory
        stack       *Stack
        returnStack *Stack // separate call stack for CALL/RET
        regs        *Registers
        stepCount   int
        halted      bool
        progLen     int
        breakpoints *BreakpointManager

        // Public convenience fields (synced by syncFields).
        // These provide quick access for TUI rendering and compatibility
        // with existing screen code.
        PC     uint16
        Cycles int
}

// NewEngine creates a new VM engine with zeroed state.
func NewEngine() *Engine {
        return &Engine{
                mem:         NewMemory(),
                stack:       NewStack(),
                returnStack: NewStack(),
                regs:        NewRegisters(),
                breakpoints: NewBreakpointManager(),
        }
}

// syncFields updates the public convenience fields from internal state.
func (e *Engine) syncFields() {
        e.PC = e.regs.PC
        e.Cycles = e.stepCount
}

// IsHalted returns whether the VM has halted.
func (e *Engine) IsHalted() bool {
        return e.halted
}

// LoadProgram copies program bytes into memory starting at ProgramStart.
// Returns the entry point address and any error.
func (e *Engine) LoadProgram(data []byte) (uint16, error) {
        e.progLen = len(data)
        e.halted = false
        e.stepCount = 0
        e.stack.Clear()
        e.returnStack.Clear()
        e.regs = NewRegisters()
        _, err := e.mem.LoadProgram(data)
        e.syncFields()
        return ProgramStart, err
}

// Reset restores the engine to its initial state (memory is not cleared
// until LoadProgram is called again).
func (e *Engine) Reset() {
        e.stack.Clear()
        e.returnStack.Clear()
        e.regs = NewRegisters()
        e.stepCount = 0
        e.halted = false
        e.syncFields()
}

// Breakpoints returns the breakpoint manager.
func (e *Engine) Breakpoints() *BreakpointManager {
        return e.breakpoints
}

// Stack returns the current operand stack.
func (e *Engine) Stack() *Stack {
        return e.stack
}

// ReturnStack returns the call return stack.
func (e *Engine) ReturnStack() *Stack {
        return e.returnStack
}

// Memory returns the current memory (pointer to the underlying Memory struct).
func (e *Engine) Mem() *Memory {
        return e.mem
}

// Registers returns the current registers.
func (e *Engine) Registers() *Registers {
        return e.regs
}

// StepCount returns the number of instructions executed.
func (e *Engine) StepCount() int {
        return e.stepCount
}

// ProgramLength returns the number of bytes in the loaded program.
func (e *Engine) ProgramLength() int {
        return e.progLen
}

// StackValues returns the current stack items for TUI rendering.
func (e *Engine) StackValues() []uint32 {
        return e.stack.Items()
}

// Snapshot captures the current engine state.
func (e *Engine) Snapshot() *EngineSnapshot {
        return &EngineSnapshot{
                StepCount:   e.stepCount,
                PC:          e.regs.PC,
                Flags:       e.regs.Flags,
                Zero:        e.regs.Zero(),
                Carry:       e.regs.Carry(),
                Overflow:    e.regs.Overflow(),
                StackData:   e.stack.Items(),
                ReturnStack: e.returnStack.Items(),
                Memory:      e.mem.Raw(),
                Halted:      e.halted,
        }
}

// Restore sets the engine state from a snapshot.
func (e *Engine) Restore(snap *EngineSnapshot) {
        e.stepCount = snap.StepCount
        e.regs.PC = snap.PC
        e.regs.Flags = snap.Flags
        e.halted = snap.Halted
        e.mem.SetData(snap.Memory)
        // Reconstruct stacks from snapshot data
        e.stack.Clear()
        for _, v := range snap.StackData {
                _ = e.stack.Push(v)
        }
        e.returnStack.Clear()
        for _, v := range snap.ReturnStack {
                _ = e.returnStack.Push(v)
        }
        e.syncFields()
}

// Run executes instructions until the VM halts, a breakpoint is hit, or maxSteps is reached.
// Returns true if execution stopped due to a breakpoint (rather than halt or step limit).
func (e *Engine) Run(maxSteps ...int) bool {
        limit := 1000000
        if len(maxSteps) > 0 && maxSteps[0] > 0 {
                limit = maxSteps[0]
        }
        for !e.halted && e.stepCount < limit {
                _ = e.Step()
                if e.breakpoints.CheckHit(e.PC) {
                        return true
                }
        }
        return false
}

// Step executes a single instruction and returns any error.
func (e *Engine) Step() error {
        if e.halted {
                return fmt.Errorf("engine is halted")
        }

        defer e.syncFields()

        opcode, err := e.mem.Load(e.regs.PC)
        if err != nil {
                e.halted = true
                return fmt.Errorf("failed to read opcode: %w", err)
        }

        e.regs.PC++

        switch opcode {
        case NOP:
                // no operation

        case PUSH:
                if int(e.regs.PC)+4 > MemorySize {
                        e.halted = true
                        return fmt.Errorf("PUSH reads beyond memory at 0x%04X", e.regs.PC)
                }
                val := binary.BigEndian.Uint32(e.mem.data[e.regs.PC : e.regs.PC+4])
                e.regs.PC += 4
                if err := e.stack.Push(val); err != nil {
                        e.halted = true
                        return err
                }

        case POP:
                if _, err := e.stack.Pop(); err != nil {
                        e.halted = true
                        return err
                }

        case DUP:
                if err := e.stack.Dup(); err != nil {
                        e.halted = true
                        return err
                }

        case SWAP:
                if err := e.stack.Swap(); err != nil {
                        e.halted = true
                        return err
                }

        case ADD:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("ADD: stack underflow")
                }
                result := a + b
                e.regs.SetFlags(result, result < a, false)
                if err := e.stack.Push(result); err != nil {
                        e.halted = true
                        return err
                }

        case SUB:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("SUB: stack underflow")
                }
                result := b - a
                carry := b < a
                e.regs.SetFlags(result, carry, false)
                if err := e.stack.Push(result); err != nil {
                        e.halted = true
                        return err
                }

        case MUL:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("MUL: stack underflow")
                }
                result := b * a
                // Detect multiplication overflow: if a != 0 and result/a != b, we overflowed
                carry := a != 0 && result/a != b
                e.regs.SetFlags(result, carry, false)
                if err := e.stack.Push(result); err != nil {
                        e.halted = true
                        return err
                }

        case AND:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("AND: stack underflow")
                }
                e.regs.SetFlags(b&a, false, false)
                if err := e.stack.Push(b & a); err != nil {
                        e.halted = true
                        return err
                }

        case OR:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("OR: stack underflow")
                }
                e.regs.SetFlags(b|a, false, false)
                if err := e.stack.Push(b | a); err != nil {
                        e.halted = true
                        return err
                }

        case XOR:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("XOR: stack underflow")
                }
                e.regs.SetFlags(b^a, false, false)
                if err := e.stack.Push(b ^ a); err != nil {
                        e.halted = true
                        return err
                }

        case NOT:
                a, err := e.stack.Pop()
                if err != nil {
                        e.halted = true
                        return fmt.Errorf("NOT: stack underflow")
                }
                result := ^a
                e.regs.SetFlags(result, false, false)
                if err := e.stack.Push(result); err != nil {
                        e.halted = true
                        return err
                }

        case JMP:
                if int(e.regs.PC)+2 > MemorySize {
                        e.halted = true
                        return fmt.Errorf("JMP reads beyond memory at 0x%04X", e.regs.PC)
                }
                addr := uint16(e.mem.data[e.regs.PC])<<8 | uint16(e.mem.data[e.regs.PC+1])
                e.regs.PC = addr

        case JZ:
                val, err := e.stack.Pop()
                if err != nil {
                        e.halted = true
                        return fmt.Errorf("JZ: stack underflow")
                }
                if int(e.regs.PC)+2 > MemorySize {
                        e.halted = true
                        return fmt.Errorf("JZ reads beyond memory at 0x%04X", e.regs.PC)
                }
                addr := uint16(e.mem.data[e.regs.PC])<<8 | uint16(e.mem.data[e.regs.PC+1])
                e.regs.PC += 2
                if val == 0 {
                        e.regs.PC = addr
                }

        case LOAD:
                if int(e.regs.PC)+2 > MemorySize {
                        e.halted = true
                        return fmt.Errorf("LOAD reads beyond memory at 0x%04X", e.regs.PC)
                }
                addr := uint16(e.mem.data[e.regs.PC])<<8 | uint16(e.mem.data[e.regs.PC+1])
                e.regs.PC += 2
                val, err := e.mem.LoadWord(addr)
                if err != nil {
                        e.halted = true
                        return fmt.Errorf("LOAD: %w", err)
                }
                if err := e.stack.Push(val); err != nil {
                        e.halted = true
                        return err
                }

        case STORE:
                val, err := e.stack.Pop()
                if err != nil {
                        e.halted = true
                        return fmt.Errorf("STORE: stack underflow")
                }
                if int(e.regs.PC)+2 > MemorySize {
                        e.halted = true
                        return fmt.Errorf("STORE reads beyond memory at 0x%04X", e.regs.PC)
                }
                addr := uint16(e.mem.data[e.regs.PC])<<8 | uint16(e.mem.data[e.regs.PC+1])
                e.regs.PC += 2
                if err := e.mem.StoreWord(addr, val); err != nil {
                        e.halted = true
                        return fmt.Errorf("STORE: %w", err)
                }

        case HALT:
                e.halted = true

        case CALL:
                if int(e.regs.PC)+2 > MemorySize {
                        e.halted = true
                        return fmt.Errorf("CALL reads beyond memory at 0x%04X", e.regs.PC)
                }
                addr := uint16(e.mem.data[e.regs.PC])<<8 | uint16(e.mem.data[e.regs.PC+1])
                nextPC := e.regs.PC + 2
                if err := e.returnStack.Push(uint32(nextPC)); err != nil {
                        e.halted = true
                        return fmt.Errorf("CALL: return stack overflow")
                }
                e.regs.PC = addr

        case RET:
                val, err := e.returnStack.Pop()
                if err != nil {
                        e.halted = true
                        return fmt.Errorf("RET: return stack underflow")
                }
                e.regs.PC = uint16(val)

        case CMP:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("CMP: stack underflow")
                }
                result := b - a
                carry := b < a
                e.regs.SetFlags(result, carry, false)

        case JNZ:
                val, err := e.stack.Pop()
                if err != nil {
                        e.halted = true
                        return fmt.Errorf("JNZ: stack underflow")
                }
                if int(e.regs.PC)+2 > MemorySize {
                        e.halted = true
                        return fmt.Errorf("JNZ reads beyond memory at 0x%04X", e.regs.PC)
                }
                addr := uint16(e.mem.data[e.regs.PC])<<8 | uint16(e.mem.data[e.regs.PC+1])
                e.regs.PC += 2
                if val != 0 {
                        e.regs.PC = addr
                }

        case JC:
                if int(e.regs.PC)+2 > MemorySize {
                        e.halted = true
                        return fmt.Errorf("JC reads beyond memory at 0x%04X", e.regs.PC)
                }
                addr := uint16(e.mem.data[e.regs.PC])<<8 | uint16(e.mem.data[e.regs.PC+1])
                e.regs.PC += 2
                if e.regs.Carry() {
                        e.regs.PC = addr
                }

        case SHL:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("SHL: stack underflow")
                }
                shift := a & 31
                // Detect if any bits were shifted out (carry = bits lost)
                carry := shift > 0 && (b>>(32-shift)) != 0
                result := b << shift
                e.regs.SetFlags(result, carry, false)
                if err := e.stack.Push(result); err != nil {
                        e.halted = true
                        return err
                }

        case SHR:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("SHR: stack underflow")
                }
                shift := a & 31
                // Carry = bits were shifted out (any of the lower 'shift' bits were 1)
                carry := shift > 0 && (b & ((1<<shift)-1)) != 0
                result := b >> shift
                e.regs.SetFlags(result, carry, false)
                if err := e.stack.Push(result); err != nil {
                        e.halted = true
                        return err
                }

        case DIV:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("DIV: stack underflow")
                }
                if a == 0 {
                        e.halted = true
                        return fmt.Errorf("DIV: division by zero")
                }
                quotient := b / a
                remainder := b % a
                // Carry = non-zero remainder
                carry := remainder != 0
                e.regs.SetFlags(quotient, carry, false)
                if err := e.stack.Push(quotient); err != nil {
                        e.halted = true
                        return err
                }

        case MOD:
                a, err1 := e.stack.Pop()
                b, err2 := e.stack.Pop()
                if err1 != nil || err2 != nil {
                        e.halted = true
                        return fmt.Errorf("MOD: stack underflow")
                }
                if a == 0 {
                        e.halted = true
                        return fmt.Errorf("MOD: division by zero")
                }
                result := b % a
                e.regs.SetFlags(result, false, false)
                if err := e.stack.Push(result); err != nil {
                        e.halted = true
                        return err
                }

        default:
                e.halted = true
                return fmt.Errorf("invalid opcode 0x%02X at 0x%04X", opcode, e.regs.PC-1)
        }

        e.stepCount++
        e.syncFields()
        return nil
}
