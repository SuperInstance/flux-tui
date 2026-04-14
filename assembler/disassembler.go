package assembler

import (
	"encoding/binary"
	"fmt"

	"github.com/SuperInstance/flux-tui/vm"
)

// Disassemble converts bytecode to a human-readable assembly listing.
func Disassemble(data []byte, baseAddr uint16) string {
	var lines []string
	offset := 0
	for offset < len(data) {
		addr := baseAddr + uint16(offset)
		text, consumed := DisassembleInstruction(data, offset)
		lines = append(lines, fmt.Sprintf("  0x%04X:  %s", addr, text))
		offset += consumed
	}
	result := ""
	for _, line := range lines {
		result += line + "\n"
	}
	return result
}

// DisassembleInstruction disassembles a single instruction at the given offset.
func DisassembleInstruction(data []byte, offset int) (string, int) {
	if offset >= len(data) {
		return "??? (end of data)", 1
	}

	opcode := data[offset]
	name, ok := vm.OpcodeNames[opcode]
	if !ok {
		return fmt.Sprintf("DB 0x%02X", opcode), 1
	}

	width := vm.OpcodeWidth(opcode)
	if offset+width > len(data) {
		remaining := len(data) - offset
		hexBytes := ""
		for i := 0; i < remaining; i++ {
			if i > 0 {
				hexBytes += " "
			}
			hexBytes += fmt.Sprintf("0x%02X", data[offset+i])
		}
		return fmt.Sprintf("DB %s ; incomplete %s", hexBytes, name), remaining
	}

	switch opcode {
	case vm.PUSH:
		val := binary.BigEndian.Uint32(data[offset+1 : offset+5])
		return fmt.Sprintf("PUSH 0x%08X  ; %d", val, int32(val)), 5

	case vm.JMP:
		addr := binary.BigEndian.Uint16(data[offset+1 : offset+3])
		return fmt.Sprintf("JMP 0x%04X", addr), 3

	case vm.JZ:
		addr := binary.BigEndian.Uint16(data[offset+1 : offset+3])
		return fmt.Sprintf("JZ 0x%04X", addr), 3

	case vm.LOAD:
		addr := binary.BigEndian.Uint16(data[offset+1 : offset+3])
		return fmt.Sprintf("LOAD 0x%04X", addr), 3

	case vm.STORE:
		addr := binary.BigEndian.Uint16(data[offset+1 : offset+3])
		return fmt.Sprintf("STORE 0x%04X", addr), 3

	default:
		return name, 1
	}
}
