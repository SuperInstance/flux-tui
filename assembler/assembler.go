package assembler

import (
	"encoding/binary"
	"fmt"
	"strconv"
	"strings"

	"github.com/SuperInstance/flux-tui/vm"
)

// AsmError represents an error encountered during assembly.
type AsmError struct {
	Line    int
	Col     int
	Message string
}

// Error implements the error interface.
func (e AsmError) Error() string {
	return fmt.Sprintf("line %d, col %d: %s", e.Line, e.Col, e.Message)
}

// Assembler implements a two-pass assembler for FLUX assembly.
type Assembler struct {
	tokens []Token
	labels map[string]uint16
	errors []AsmError
}

// NewAssembler creates a new assembler instance.
func NewAssembler() *Assembler {
	return &Assembler{
		labels: make(map[string]uint16),
	}
}

// Assemble assembles FLUX assembly source code into bytecode.
func (a *Assembler) Assemble(source string) ([]byte, []AsmError) {
	a.errors = nil
	a.labels = make(map[string]uint16)
	a.tokens = TokenizeAll(source)

	_, err := a.assemblePass(1)
	if err != nil {
		if len(a.errors) == 0 {
			a.errors = append(a.errors, AsmError{Line: 0, Col: 0, Message: err.Error()})
		}
		return nil, a.errors
	}
	if len(a.errors) > 0 {
		return nil, a.errors
	}

	result, err := a.assemblePass(2)
	if err != nil {
		if len(a.errors) == 0 {
			a.errors = append(a.errors, AsmError{Line: 0, Col: 0, Message: err.Error()})
		}
		return nil, a.errors
	}

	return result, a.errors
}

// assemblePass performs one pass of assembly.
func (a *Assembler) assemblePass(pass int) ([]byte, error) {
	var output []byte
	filtered := FilterTokens(a.tokens)
	addr := vm.ProgramStart
	i := 0

	for i < len(filtered) {
		tok := filtered[i]

		switch tok.Type {
		case TokenError:
			a.errors = append(a.errors, AsmError{
				Line: tok.Line, Col: tok.Col,
				Message: fmt.Sprintf("unexpected character: %q", tok.Value),
			})
			return nil, fmt.Errorf("assembly aborted")

		case TokenLabel:
			if pass == 1 {
				if _, exists := a.labels[tok.Value]; exists {
					a.errors = append(a.errors, AsmError{
						Line: tok.Line, Col: tok.Col,
						Message: fmt.Sprintf("duplicate label: %s", tok.Value),
					})
					return nil, fmt.Errorf("assembly aborted")
				}
				a.labels[tok.Value] = addr
			}
			i++
			if i < len(filtered) && filtered[i].Type == TokenColon {
				i++
			}
			continue

		case TokenOpcode:
			opName := tok.Value
			opcode, ok := vm.NameToOpcode[opName]
			if !ok {
				a.errors = append(a.errors, AsmError{
					Line: tok.Line, Col: tok.Col,
					Message: fmt.Sprintf("unknown opcode: %s", opName),
				})
				return nil, fmt.Errorf("assembly aborted")
			}

			output = append(output, opcode)

			switch opcode {
			case vm.PUSH:
				if i+1 >= len(filtered) {
					a.errors = append(a.errors, AsmError{Line: tok.Line, Col: tok.Col, Message: "PUSH requires an operand"})
					return nil, fmt.Errorf("assembly aborted")
				}
				ot := filtered[i+1]
				val, err := parseNumber(ot.Value, ot.Line, ot.Col, &a.errors)
				if err != nil {
					return nil, fmt.Errorf("assembly aborted")
				}
				buf := make([]byte, 4)
				binary.BigEndian.PutUint32(buf, val)
				output = append(output, buf...)
				i += 2

			case vm.JMP, vm.JZ:
				if i+1 >= len(filtered) {
					a.errors = append(a.errors, AsmError{Line: tok.Line, Col: tok.Col, Message: fmt.Sprintf("%s requires an operand", opName)})
					return nil, fmt.Errorf("assembly aborted")
				}
				ot := filtered[i+1]
				jumpAddr, err := a.resolveAddr16(ot, pass)
				if err != nil {
					return nil, fmt.Errorf("assembly aborted")
				}
				buf := make([]byte, 2)
				binary.BigEndian.PutUint16(buf, jumpAddr)
				output = append(output, buf...)
				i += 2

			case vm.LOAD, vm.STORE:
				if i+1 >= len(filtered) {
					a.errors = append(a.errors, AsmError{Line: tok.Line, Col: tok.Col, Message: fmt.Sprintf("%s requires an operand", opName)})
					return nil, fmt.Errorf("assembly aborted")
				}
				ot := filtered[i+1]
				memAddr, err := a.resolveAddr16(ot, pass)
				if err != nil {
					return nil, fmt.Errorf("assembly aborted")
				}
				buf := make([]byte, 2)
				binary.BigEndian.PutUint16(buf, memAddr)
				output = append(output, buf...)
				i += 2

			default:
				i++
			}

			addr += uint16(vm.OpcodeWidth(opcode))

		default:
			a.errors = append(a.errors, AsmError{
				Line: tok.Line, Col: tok.Col,
				Message: fmt.Sprintf("unexpected token %s: %q", tok.Type, tok.Value),
			})
			return nil, fmt.Errorf("assembly aborted")
		}
	}

	return output, nil
}

// resolveAddr16 resolves a label reference or number to a uint16 address.
func (a *Assembler) resolveAddr16(ot Token, pass int) (uint16, error) {
	switch ot.Type {
	case TokenLabelRef:
		if pass == 1 {
			return 0, nil
		}
		resolved, ok := a.labels[ot.Value]
		if !ok {
			a.errors = append(a.errors, AsmError{
				Line: ot.Line, Col: ot.Col,
				Message: fmt.Sprintf("undefined label: %s", ot.Value),
			})
			return 0, fmt.Errorf("assembly aborted")
		}
		return resolved, nil

	case TokenNumber:
		parsed, err := strconv.ParseUint(ot.Value, 0, 16)
		if err != nil {
			a.errors = append(a.errors, AsmError{
				Line: ot.Line, Col: ot.Col,
				Message: fmt.Sprintf("invalid address: %s", ot.Value),
			})
			return 0, fmt.Errorf("assembly aborted")
		}
		return uint16(parsed), nil

	default:
		a.errors = append(a.errors, AsmError{
			Line: ot.Line, Col: ot.Col,
			Message: fmt.Sprintf("expected label or number, got %s", ot.Type),
		})
		return 0, fmt.Errorf("assembly aborted")
	}
}

// parseNumber parses a numeric literal string into a uint32 value.
func parseNumber(value string, line, col int, errors *[]AsmError) (uint32, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		*errors = append(*errors, AsmError{Line: line, Col: col, Message: "expected a number"})
		return 0, fmt.Errorf("assembly aborted")
	}

	negative := false
	if value[0] == '-' {
		negative = true
		value = value[1:]
	}

	base := 10
	if strings.HasPrefix(value, "0x") || strings.HasPrefix(value, "0X") {
		base = 16
		value = value[2:]
	}

	parsed, err := strconv.ParseUint(value, base, 32)
	if err != nil {
		*errors = append(*errors, AsmError{Line: line, Col: col, Message: fmt.Sprintf("invalid number: %s", value)})
		return 0, fmt.Errorf("assembly aborted")
	}

	result := uint32(parsed)
	if negative {
		result = uint32(-int32(result))
	}

	return result, nil
}
