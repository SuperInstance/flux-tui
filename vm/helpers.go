package vm

// OpcodeNames maps opcode byte values to their mnemonic names.
// This is the canonical lookup table. OpcodeTable also contains this data
// but as an array; this map provides O(1) reverse lookup by value.
var OpcodeNames = map[byte]string{
	NOP:   "NOP",
	PUSH:  "PUSH",
	POP:   "POP",
	DUP:   "DUP",
	SWAP:  "SWAP",
	ADD:   "ADD",
	SUB:   "SUB",
	MUL:   "MUL",
	AND:   "AND",
	OR:    "OR",
	XOR:   "XOR",
	NOT:   "NOT",
	JMP:   "JMP",
	JZ:    "JZ",
	LOAD:  "LOAD",
	STORE: "STORE",
	HALT:  "HALT",
	CALL:  "CALL",
	RET:   "RET",
	CMP:   "CMP",
	JNZ:   "JNZ",
	JC:    "JC",
	SHL:   "SHL",
	SHR:   "SHR",
	DIV:   "DIV",
	MOD:   "MOD",
}

// NameToOpcode maps mnemonic names to opcode byte values.
// Generated from OpcodeNames to avoid drift between the two maps.
var NameToOpcode = func() map[string]byte {
	m := make(map[string]byte, len(OpcodeNames))
	for op, name := range OpcodeNames {
		m[name] = op
	}
	return m
}()

// OpcodeWidth returns the number of bytes consumed by an instruction
// starting with the given opcode.
func OpcodeWidth(op byte) int {
	switch op {
	case PUSH:
		return 5 // 1 opcode + 4 operand bytes
	case JMP, JZ, LOAD, STORE, CALL, JNZ, JC:
		return 3 // 1 opcode + 2 address bytes
	default:
		return 1 // NOP, POP, DUP, SWAP, ADD, SUB, MUL, AND, OR, XOR, NOT, HALT, RET, CMP, SHL, SHR, DIV, MOD
	}
}

// AllOpcodes returns a slice of all defined opcode bytes in numeric order.
func AllOpcodes() []byte {
	opcodes := make([]byte, 0, OpcodeCount())
	for i := byte(0); i < byte(len(OpcodeTable)); i++ {
		if OpcodeTable[i].Name != "" {
			opcodes = append(opcodes, i)
		}
	}
	return opcodes
}

// InstructionSize returns the total byte size of a single instruction
// including its opcode and operands. Returns -1 for unknown opcodes.
// This is an alias for OpcodeWidth provided for API clarity.
func InstructionSize(opcode byte) int {
	w := OpcodeWidth(opcode)
	if w <= 0 {
		return -1
	}
	return w
}
