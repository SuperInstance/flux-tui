package vm

// OpcodeNames maps opcode byte values to their mnemonic names.
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
}

// NameToOpcode maps mnemonic names to opcode byte values.
var NameToOpcode = map[string]byte{
	"NOP":   NOP,
	"PUSH":  PUSH,
	"POP":   POP,
	"DUP":   DUP,
	"SWAP":  SWAP,
	"ADD":   ADD,
	"SUB":   SUB,
	"MUL":   MUL,
	"AND":   AND,
	"OR":    OR,
	"XOR":   XOR,
	"NOT":   NOT,
	"JMP":   JMP,
	"JZ":    JZ,
	"LOAD":  LOAD,
	"STORE": STORE,
	"HALT":  HALT,
}

// OpcodeWidth returns the number of bytes consumed by an instruction
// starting with the given opcode.
func OpcodeWidth(op byte) int {
	switch op {
	case PUSH:
		return 5 // 1 opcode + 4 operand bytes
	case JMP, JZ, LOAD, STORE:
		return 3 // 1 opcode + 2 address bytes
	default:
		return 1 // NOP, POP, DUP, SWAP, ADD, SUB, MUL, AND, OR, XOR, NOT, HALT
	}
}

// MemoryBase is an alias for ProgramStart (0x0100) for compatibility.
const MemoryBase = ProgramStart
