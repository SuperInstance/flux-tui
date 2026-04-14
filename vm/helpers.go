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
        CALL:  "CALL",
        RET:   "RET",
        CMP:   "CMP",
        JNZ:   "JNZ",
        JC:    "JC",
        SHL:   "SHL",
        SHR:   "SHR",
        DIV:   "DIV",
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
        "CALL":  CALL,
        "RET":   RET,
        "CMP":   CMP,
        "JNZ":   JNZ,
        "JC":    JC,
        "SHL":   SHL,
        "SHR":   SHR,
        "DIV":   DIV,
}

// OpcodeWidth returns the number of bytes consumed by an instruction
// starting with the given opcode.
func OpcodeWidth(op byte) int {
        switch op {
        case PUSH:
                return 5 // 1 opcode + 4 operand bytes
        case JMP, JZ, LOAD, STORE, CALL, JNZ, JC:
                return 3 // 1 opcode + 2 address bytes
        default:
                return 1 // NOP, POP, DUP, SWAP, ADD, SUB, MUL, AND, OR, XOR, NOT, HALT, RET, CMP, SHL, SHR, DIV
        }
}
