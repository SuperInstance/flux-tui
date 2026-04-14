package vm

// Opcode constants for the FLUX bytecode VM.
const (
	NOP   byte = 0x00
	PUSH  byte = 0x01
	POP   byte = 0x02
	DUP   byte = 0x03
	SWAP  byte = 0x04
	ADD   byte = 0x05
	SUB   byte = 0x06
	MUL   byte = 0x07
	AND   byte = 0x08
	OR    byte = 0x09
	XOR   byte = 0x0A
	NOT   byte = 0x0B
	JMP   byte = 0x0C
	JZ    byte = 0x0D
	LOAD  byte = 0x0E
	STORE byte = 0x0F
	HALT  byte = 0x10
)

// OpcodeMeta describes metadata for a single opcode.
type OpcodeMeta struct {
	Name        string
	Description string
	Format      string // "A" (opcode+4-byte operand) or "B" (opcode+2-byte operand) or "-" (no operand)
	StackEffect string // e.g. "+1", "-1", "+2-2", etc.
}

// OpcodeTable maps each opcode index to its metadata.
var OpcodeTable [17]OpcodeMeta

func init() {
	OpcodeTable = [17]OpcodeMeta{
		NOP:   {Name: "NOP", Description: "No operation", Format: "-", StackEffect: ""},
		PUSH:  {Name: "PUSH", Description: "Push 4-byte immediate value onto stack", Format: "A", StackEffect: "+1"},
		POP:   {Name: "POP", Description: "Pop top value from stack", Format: "-", StackEffect: "-1"},
		DUP:   {Name: "DUP", Description: "Duplicate top of stack", Format: "-", StackEffect: "+1"},
		SWAP:  {Name: "SWAP", Description: "Swap top two stack values", Format: "-", StackEffect: ""},
		ADD:   {Name: "ADD", Description: "Pop two, push sum", Format: "-", StackEffect: "-1"},
		SUB:   {Name: "SUB", Description: "Pop two, push difference (b-a)", Format: "-", StackEffect: "-1"},
		MUL:   {Name: "MUL", Description: "Pop two, push product", Format: "-", StackEffect: "-1"},
		AND:   {Name: "AND", Description: "Pop two, push bitwise AND", Format: "-", StackEffect: "-1"},
		OR:    {Name: "OR", Description: "Pop two, push bitwise OR", Format: "-", StackEffect: "-1"},
		XOR:   {Name: "XOR", Description: "Pop two, push bitwise XOR", Format: "-", StackEffect: "-1"},
		NOT:   {Name: "NOT", Description: "Pop one, push bitwise NOT", Format: "-", StackEffect: ""},
		JMP:   {Name: "JMP", Description: "Unconditional jump to address", Format: "B", StackEffect: ""},
		JZ:    {Name: "JZ", Description: "Jump to address if top of stack is zero", Format: "B", StackEffect: "-1"},
		LOAD:  {Name: "LOAD", Description: "Load 4-byte word from memory, push onto stack", Format: "B", StackEffect: "+1"},
		STORE: {Name: "STORE", Description: "Pop value, store 4-byte word to memory", Format: "B", StackEffect: "-1"},
		HALT:  {Name: "HALT", Description: "Halt execution", Format: "-", StackEffect: ""},
	}
}

// FormatA encodes a Format A instruction: [opcode(1 byte)][value(4 bytes big-endian)].
// Total length: 5 bytes.
func FormatA(opcode byte, value uint32) []byte {
	buf := make([]byte, 5)
	buf[0] = opcode
	buf[1] = byte(value >> 24)
	buf[2] = byte(value >> 16)
	buf[3] = byte(value >> 8)
	buf[4] = byte(value)
	return buf
}

// FormatB encodes a Format B instruction: [opcode(1 byte)][addr(2 bytes big-endian)].
// Total length: 3 bytes.
func FormatB(opcode byte, addr uint16) []byte {
	buf := make([]byte, 3)
	buf[0] = opcode
	buf[1] = byte(addr >> 8)
	buf[2] = byte(addr)
	return buf
}

// OpcodeName returns the human-readable name for an opcode, or "UNKNOWN" if invalid.
func OpcodeName(op byte) string {
	if int(op) < len(OpcodeTable) {
		return OpcodeTable[op].Name
	}
	return "UNKNOWN"
}

// ValidOpcode returns true if the byte is a recognized opcode.
func ValidOpcode(op byte) bool {
	return int(op) < len(OpcodeTable) && OpcodeTable[op].Name != ""
}
