// Package conformance provides test vector loading and generation for the FLUX VM.
package conformance

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"

	"github.com/SuperInstance/flux-tui/vm"
)

// TestVector represents a single conformance test case for the VM.
type TestVector struct {
	Name           string
	Category       string
	Program        []byte
	ExpectedStack  []uint32
	ExpectedMemory map[uint16]uint32
	ExpectedHalted bool
}

// jsonVector is the JSON representation of a test vector.
type jsonVector struct {
	Name           string   `json:"name"`
	Category       string   `json:"category"`
	Program        []byte   `json:"program"`
	ExpectedStack  []uint32 `json:"expected_stack"`
	ExpectedHalted bool     `json:"expected_halted"`
}

// loadVectorsFile loads test vectors from a JSON file.
func loadVectorsFile(path string) ([]TestVector, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read vectors file: %w", err)
	}
	var raw []jsonVector
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("failed to parse vectors JSON: %w", err)
	}
	var vectors []TestVector
	for _, rv := range raw {
		vectors = append(vectors, TestVector{
			Name:           rv.Name,
			Category:       rv.Category,
			Program:        rv.Program,
			ExpectedStack:  rv.ExpectedStack,
			ExpectedMemory: nil,
			ExpectedHalted: rv.ExpectedHalted,
		})
	}
	return vectors, nil
}

// LoadVectors loads test vectors from a JSON file, falling back to built-in vectors.
func LoadVectors(path string) ([]TestVector, error) {
	vectors, err := loadVectorsFile(path)
	if err != nil {
		return GenerateBuiltinVectors(), nil
	}
	if len(vectors) == 0 {
		return GenerateBuiltinVectors(), nil
	}
	return vectors, nil
}

// GenerateBuiltinVectors returns a comprehensive set of built-in test vectors.
func GenerateBuiltinVectors() []TestVector {
	return []TestVector{
		{Name: "nop_noop", Category: "control",
			Program: []byte{vm.NOP, vm.HALT}},

		{Name: "push_pop_empty", Category: "stack",
			Program: append(pushU32(42), vm.POP, vm.HALT)},

		{Name: "push_single", Category: "stack",
			Program: append(pushU32(42), vm.HALT),
			ExpectedStack: []uint32{42}, ExpectedHalted: true},

		{Name: "add_basic", Category: "arithmetic",
			Program: append(append(pushU32(3), pushU32(4)...), vm.ADD, vm.HALT),
			ExpectedStack: []uint32{7}, ExpectedHalted: true},

		{Name: "sub_basic", Category: "arithmetic",
			Program: append(append(pushU32(10), pushU32(3)...), vm.SUB, vm.HALT),
			ExpectedStack: []uint32{7}, ExpectedHalted: true},

		{Name: "mul_basic", Category: "arithmetic",
			Program: append(append(pushU32(6), pushU32(7)...), vm.MUL, vm.HALT),
			ExpectedStack: []uint32{42}, ExpectedHalted: true},

		{Name: "and_basic", Category: "bitwise",
			Program: append(append(pushU32(0xFF), pushU32(0x0F)...), vm.AND, vm.HALT),
			ExpectedStack: []uint32{0x0F}, ExpectedHalted: true},

		{Name: "or_basic", Category: "bitwise",
			Program: append(append(pushU32(0xF0), pushU32(0x0F)...), vm.OR, vm.HALT),
			ExpectedStack: []uint32{0xFF}, ExpectedHalted: true},

		{Name: "xor_basic", Category: "bitwise",
			Program: append(append(pushU32(0xFF), pushU32(0x0F)...), vm.XOR, vm.HALT),
			ExpectedStack: []uint32{0xF0}, ExpectedHalted: true},

		{Name: "not_basic", Category: "bitwise",
			Program: []byte{vm.PUSH, 0, 0, 0, 0, vm.NOT, vm.HALT},
			ExpectedStack: []uint32{0xFFFFFFFF}, ExpectedHalted: true},

		{Name: "dup_basic", Category: "stack",
			Program: append(pushU32(99), vm.DUP, vm.HALT),
			ExpectedStack: []uint32{99, 99}, ExpectedHalted: true},

		{Name: "swap_basic", Category: "stack",
			Program: append(append(pushU32(1), pushU32(2)...), vm.SWAP, vm.HALT),
			ExpectedStack: []uint32{2, 1}, ExpectedHalted: true},

		{Name: "jmp_forward", Category: "control",
			Program:        buildJmpForward(),
			ExpectedStack:  []uint32{77},
			ExpectedHalted: true},

		{Name: "jz_taken", Category: "control",
			Program:        buildJzTaken(),
			ExpectedStack:  []uint32{88},
			ExpectedHalted: true},

		{Name: "jz_not_taken", Category: "control",
			Program:        buildJzNotTaken(),
			ExpectedStack:  []uint32{44},
			ExpectedHalted: true},

		{Name: "load_store_roundtrip", Category: "memory",
			Program:        buildLoadStoreRoundtrip(),
			ExpectedStack:  []uint32{1234},
			ExpectedHalted: true},

		{Name: "factorial_5", Category: "complex",
			Program:        buildFactorial5(),
			ExpectedStack:  []uint32{120},
			ExpectedHalted: true},

		{Name: "multiple_nops", Category: "control",
			Program: []byte{vm.NOP, vm.NOP, vm.NOP, vm.HALT}},

		{Name: "push_negative", Category: "stack",
			Program:        pushU32(0xFFFFFFD6),
			ExpectedStack:  []uint32{0xFFFFFFD6},
			ExpectedHalted: true},

		{Name: "chained_arithmetic", Category: "arithmetic",
			Program: append(append(append(pushU32(2), pushU32(3)...), vm.ADD), append(pushU32(4), vm.MUL, vm.HALT)...),
			ExpectedStack: []uint32{20}, ExpectedHalted: true},
	}
}

func pushU32(val uint32) []byte {
	buf := make([]byte, 5)
	buf[0] = vm.PUSH
	binary.BigEndian.PutUint32(buf[1:], val)
	return buf
}

func jmpU16(addr uint16) []byte {
	buf := make([]byte, 3)
	buf[0] = vm.JMP
	binary.BigEndian.PutUint16(buf[1:], addr)
	return buf
}

func jzU16(addr uint16) []byte {
	buf := make([]byte, 3)
	buf[0] = vm.JZ
	binary.BigEndian.PutUint16(buf[1:], addr)
	return buf
}

func loadU16(addr uint16) []byte {
	buf := make([]byte, 3)
	buf[0] = vm.LOAD
	binary.BigEndian.PutUint16(buf[1:], addr)
	return buf
}

func storeU16(addr uint16) []byte {
	buf := make([]byte, 3)
	buf[0] = vm.STORE
	binary.BigEndian.PutUint16(buf[1:], addr)
	return buf
}

// buildJmpForward: JMP over NOP, PUSH 77, HALT
func buildJmpForward() []byte {
	base := vm.ProgramStart
	target := base + 4
	return append(append(jmpU16(target), vm.NOP), append(pushU32(77), vm.HALT)...)
}

// buildJzTaken: PUSH 0, JZ past PUSH 55, PUSH 88, HALT
func buildJzTaken() []byte {
	base := vm.ProgramStart
	target := base + 13
	var p []byte
	p = append(p, pushU32(0)...)
	p = append(p, jzU16(target)...)
	p = append(p, pushU32(55)...)
	p = append(p, pushU32(88)...)
	p = append(p, vm.HALT)
	return p
}

// buildJzNotTaken: PUSH 1, JZ past PUSH 44, HALT
func buildJzNotTaken() []byte {
	base := vm.ProgramStart
	target := base + 13
	var p []byte
	p = append(p, pushU32(1)...)
	p = append(p, jzU16(target)...)
	p = append(p, pushU32(44)...)
	p = append(p, vm.HALT)
	return p
}

// buildLoadStoreRoundtrip: PUSH 1234, STORE 0x0200, LOAD 0x0200, HALT
func buildLoadStoreRoundtrip() []byte {
	var p []byte
	p = append(p, pushU32(1234)...)
	p = append(p, storeU16(0x0200)...)
	p = append(p, loadU16(0x0200)...)
	p = append(p, vm.HALT)
	return p
}

// buildFactorial5 computes 5! = 120 using memory at 0x0300 (acc) and 0x0301 (counter).
func buildFactorial5() []byte {
	base := vm.ProgramStart
	loopAddr := base + 16
	doneAddr := base + 47

	var p []byte
	p = append(p, pushU32(1)...)
	p = append(p, storeU16(0x0300)...)
	p = append(p, pushU32(5)...)
	p = append(p, storeU16(0x0301)...)
	p = append(p, loadU16(0x0301)...)
	p = append(p, jzU16(doneAddr)...)
	p = append(p, loadU16(0x0300)...)
	p = append(p, loadU16(0x0301)...)
	p = append(p, vm.MUL)
	p = append(p, storeU16(0x0300)...)
	p = append(p, loadU16(0x0301)...)
	p = append(p, pushU32(1)...)
	p = append(p, vm.SUB)
	p = append(p, storeU16(0x0301)...)
	p = append(p, jmpU16(loopAddr)...)
	p = append(p, loadU16(0x0300)...)
	p = append(p, vm.HALT)
	return p
}
