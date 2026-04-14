package vm

import (
        "encoding/binary"
        "fmt"
)

// MemorySize defines the total addressable memory: 64KB.
const MemorySize = 65536

// ProgramStart is the fixed address where user programs are loaded.
const ProgramStart uint16 = 0x0100

// Memory represents a 64KB byte-addressable memory for the VM.
type Memory struct {
        data [MemorySize]byte
}

// NewMemory creates and returns a new zeroed Memory instance.
func NewMemory() *Memory {
        return &Memory{}
}

// Load reads a single byte from memory at the given address.
// Returns an error if addr is out of bounds.
func (m *Memory) Load(addr uint16) (byte, error) {
        if int(addr) >= MemorySize {
                return 0, fmt.Errorf("memory read out of bounds: addr=0x%04X", addr)
        }
        return m.data[addr], nil
}

// Store writes a single byte to memory at the given address.
// Returns an error if addr is out of bounds.
func (m *Memory) Store(addr uint16, val byte) error {
        if int(addr) >= MemorySize {
                return fmt.Errorf("memory write out of bounds: addr=0x%04X", addr)
        }
        m.data[addr] = val
        return nil
}

// LoadWord reads a 4-byte big-endian unsigned integer from memory at addr.
// Returns an error if reading 4 bytes would exceed memory bounds.
func (m *Memory) LoadWord(addr uint16) (uint32, error) {
        if int(addr)+4 > MemorySize {
                return 0, fmt.Errorf("memory word read out of bounds: addr=0x%04X", addr)
        }
        val := binary.BigEndian.Uint32(m.data[int(addr) : int(addr)+4])
        return val, nil
}

// StoreWord writes a 4-byte big-endian unsigned integer to memory at addr.
// Returns an error if writing 4 bytes would exceed memory bounds.
func (m *Memory) StoreWord(addr uint16, val uint32) error {
        if int(addr)+4 > MemorySize {
                return fmt.Errorf("memory write out of bounds: addr=0x%04X", addr)
        }
        binary.BigEndian.PutUint32(m.data[int(addr):int(addr)+4], val)
        return nil
}

// LoadProgram copies the provided bytecode into memory starting at ProgramStart (0x0100).
// Returns the entry point address (0x0100).
// Returns an error if the program exceeds available memory.
func (m *Memory) LoadProgram(data []byte) (uint16, error) {
        start := int(ProgramStart)
        end := start + len(data)
        if end > MemorySize {
                return 0, fmt.Errorf("program too large: %d bytes, max %d", len(data), MemorySize-start)
        }
        copy(m.data[start:end], data)
        return ProgramStart, nil
}

// DecodeInstruction decodes the instruction at the given address.
// It returns the opcode byte, the full operand as uint32, and the next PC value.
// For Format A instructions (PUSH), the operand is the 4-byte big-endian value.
// For Format B instructions (JMP, JZ, LOAD, STORE), the operand is the 2-byte big-endian address (upper 2 bytes zeroed).
// For no-operand instructions (NOP, POP, DUP, SWAP, ADD, SUB, MUL, AND, OR, XOR, NOT, HALT),
// the operand is 0 and next PC is addr+1.
// Returns an error for unknown opcodes.
func (m *Memory) DecodeInstruction(addr uint16) (opcode byte, operand uint32, nextPC uint16, err error) {
        op, err := m.Load(addr)
        if err != nil {
                return 0, 0, 0, err
        }

        if !ValidOpcode(op) {
                return 0, 0, 0, fmt.Errorf("invalid opcode 0x%02X at address 0x%04X", op, addr)
        }

        switch op {
        case PUSH:
                if int(addr)+5 > MemorySize {
                        return op, 0, 0, fmt.Errorf("PUSH instruction overflows memory at 0x%04X", addr)
                }
                val := binary.BigEndian.Uint32(m.data[addr+1 : addr+5])
                return op, val, addr + 5, nil

        case JMP, JZ, LOAD, STORE, CALL, JNZ, JC:
                if int(addr)+3 > MemorySize {
                        return op, 0, 0, fmt.Errorf("%s instruction overflows memory at 0x%04X", OpcodeName(op), addr)
                }
                addrVal := uint16(m.data[addr+1])<<8 | uint16(m.data[addr+2])
                return op, uint32(addrVal), addr + 3, nil

        default:
                // No-operand instructions: NOP, POP, DUP, SWAP, ADD, SUB, MUL, AND, OR, XOR, NOT, HALT
                return op, 0, addr + 1, nil
        }
}

// Raw returns a copy of the underlying memory data.
func (m *Memory) Raw() [MemorySize]byte {
        return m.data
}

// SetData replaces the entire memory contents with the provided data.
func (m *Memory) SetData(data [MemorySize]byte) {
        m.data = data
}

// LoadRange returns a slice of bytes from start for the given length.
// Clamps to memory bounds to prevent out-of-range reads.
func (m *Memory) LoadRange(start uint16, length int) []byte {
        end := int(start) + length
        if end > MemorySize {
                end = MemorySize
        }
        actualLen := end - int(start)
        if actualLen <= 0 {
                return nil
        }
        out := make([]byte, actualLen)
        copy(out, m.data[start:end])
        return out
}
