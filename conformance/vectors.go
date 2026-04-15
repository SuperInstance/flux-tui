// Package conformance provides test vector loading and generation for the FLUX VM.
package conformance

import (
        "encoding/binary"
        "encoding/hex"
        "encoding/json"
        "fmt"
        "os"
        "strconv"
        "strings"

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

// jsonVector is the JSON representation of a test vector (simple format).
type jsonVector struct {
        Name           string   `json:"name"`
        Category       string   `json:"category"`
        Program        []byte   `json:"program"`
        ExpectedStack  []uint32 `json:"expected_stack"`
        ExpectedHalted bool     `json:"expected_halted"`
}

// jsonVectorV1 represents the flux-conformance v1 format with hex bytecode.
type jsonVectorV1 struct {
        Name           string      `json:"name"`
        BytecodeHex    string      `json:"bytecode_hex"`
        InitialStack   interface{} `json:"initial_stack"`
        ExpectedStack  interface{} `json:"expected_stack"`
        ExpectedFlags  interface{} `json:"expected_flags"`
        Category       string      `json:"category"`
        Description    string      `json:"description"`
}

// jsonVectorV3 represents the flux-conformance v3 format.
type jsonVectorV3 struct {
        Name               string      `json:"name"`
        Category           string      `json:"category"`
        V3Only             bool        `json:"v3_only"`
        BytecodeHex        string      `json:"bytecode_hex"`
        InitialStack       interface{} `json:"initial_stack"`
        ExpectedStack      interface{} `json:"expected_stack"`
        ExpectedFlags      interface{} `json:"expected_flags"`
        AllowFloatEpsilon  bool        `json:"allow_float_epsilon"`
        Description        string      `json:"description"`
}

// conformanceFile represents the top-level structure of a conformance vectors file.
type conformanceFile struct {
        Version      string          `json:"version"`
        TotalVectors int             `json:"total_vectors"`
        Vectors      json.RawMessage `json:"vectors"`
}

// maxSupportedOpcode is the highest opcode our VM supports (0x18 = DIV, ISA v1.1).
const maxSupportedOpcode = 0x19

// LoadVectors loads test vectors from a JSON file, falling back to built-in vectors.
// Supports three formats:
//   - Simple binary program array format
//   - flux-conformance v1 format (hex bytecode)
//   - flux-conformance v3 format (hex bytecode with categories)
func LoadVectors(path string) ([]TestVector, error) {
        vectors, err := loadVectorsFile(path)
        if err != nil {
                return nil, fmt.Errorf("failed to load vectors from %s: %w", path, err)
        }
        if len(vectors) == 0 {
                return nil, fmt.Errorf("no vectors found in %s", path)
        }
        return vectors, nil
}

// LoadExternalVectors loads vectors from an external JSON file.
// Returns loaded vectors and a count of skipped (incompatible) vectors.
func LoadExternalVectors(path string) (loaded []TestVector, skipped int, err error) {
        data, err := os.ReadFile(path)
        if err != nil {
                return nil, 0, fmt.Errorf("failed to read: %w", err)
        }

        // Try to parse as a conformance file (has version + vectors key)
        var wrapper conformanceFile
        if err := json.Unmarshal(data, &wrapper); err == nil && wrapper.Vectors != nil {
                // Detect format by checking if vectors are objects (v1/v3) or arrays (simple)
                var firstRaw json.RawMessage
                var rawArray []json.RawMessage
                if err := json.Unmarshal(wrapper.Vectors, &rawArray); err == nil && len(rawArray) > 0 {
                        firstRaw = rawArray[0]
                }

                // Check if first element has bytecode_hex field (v1/v3 format)
                var probe map[string]json.RawMessage
                if json.Unmarshal(firstRaw, &probe) == nil {
                        if _, ok := probe["bytecode_hex"]; ok {
                                return loadHexFormatVectors(wrapper.Vectors)
                        }
                }
        }

        // Try simple binary format
        var simple []jsonVector
        if err := json.Unmarshal(data, &simple); err == nil && len(simple) > 0 {
                vectors := make([]TestVector, len(simple))
                for i, rv := range simple {
                        vectors[i] = TestVector{
                                Name:          rv.Name,
                                Category:      rv.Category,
                                Program:       rv.Program,
                                ExpectedStack: rv.ExpectedStack,
                                ExpectedHalted: rv.ExpectedHalted,
                        }
                }
                return vectors, 0, nil
        }

        return nil, 0, fmt.Errorf("unrecognized vector format in %s", path)
}

// loadHexFormatVectors loads vectors from the flux-conformance hex bytecode format.
// Filters out vectors that use opcodes beyond our VM's supported range (0x00-0x18).
func loadHexFormatVectors(raw json.RawMessage) (loaded []TestVector, skipped int, err error) {
        var items []json.RawMessage
        if err := json.Unmarshal(raw, &items); err != nil {
                return nil, 0, fmt.Errorf("failed to parse vector array: %w", err)
        }

        for _, item := range items {
                // Try v3 format first (has v3_only field)
                var v3 jsonVectorV3
                if err := json.Unmarshal(item, &v3); err == nil && v3.BytecodeHex != "" {
                        program, parseErr := hexToBytes(v3.BytecodeHex)
                        if parseErr != nil {
                                skipped++
                                continue
                        }
                        if !isSupportedOpcode(program) {
                                skipped++
                                continue
                        }
                        stack, _ := toUint32Slice(v3.ExpectedStack)
                        tv := TestVector{
                                Name:          v3.Name,
                                Category:      v3.Category,
                                Program:       program,
                                ExpectedStack: stack,
                                ExpectedHalted: true,
                        }
                        loaded = append(loaded, tv)
                        continue
                }

                // Try v1 format
                var v1 jsonVectorV1
                if err := json.Unmarshal(item, &v1); err == nil && v1.BytecodeHex != "" {
                        program, parseErr := hexToBytes(v1.BytecodeHex)
                        if parseErr != nil {
                                skipped++
                                continue
                        }
                        if !isSupportedOpcode(program) {
                                skipped++
                                continue
                        }
                        stack, _ := toUint32Slice(v1.ExpectedStack)
                        tv := TestVector{
                                Name:          v1.Name,
                                Category:      v1.Category,
                                Program:       program,
                                ExpectedStack: stack,
                                ExpectedHalted: true,
                        }
                        loaded = append(loaded, tv)
                        continue
                }

                skipped++
        }

        return loaded, skipped, nil
}

// loadVectorsFile loads test vectors from a JSON file (simple format).
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

// GenerateBuiltinVectors returns a comprehensive set of built-in test vectors
// covering all 26 FLUX opcodes (17 base + 9 v1.1 extensions).
func GenerateBuiltinVectors() []TestVector {
        return []TestVector{
                {Name: "nop_noop", Category: "control",
                        Program: []byte{vm.NOP, vm.HALT}, ExpectedHalted: true},

                {Name: "push_pop_empty", Category: "stack",
                        Program: append(pushU32(42), vm.POP, vm.HALT), ExpectedHalted: true},

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
                        Program:       buildJmpForward(),
                        ExpectedStack: []uint32{77},
                        ExpectedHalted: true},

                {Name: "jz_taken", Category: "control",
                        Program:       buildJzTaken(),
                        ExpectedStack: []uint32{88},
                        ExpectedHalted: true},

                {Name: "jz_not_taken", Category: "control",
                        Program:       buildJzNotTaken(),
                        ExpectedStack: []uint32{44},
                        ExpectedHalted: true},

                {Name: "load_store_roundtrip", Category: "memory",
                        Program:       buildLoadStoreRoundtrip(),
                        ExpectedStack: []uint32{1234},
                        ExpectedHalted: true},

                {Name: "factorial_5", Category: "complex",
                        Program:       buildFactorial5(),
                        ExpectedStack: []uint32{120},
                        ExpectedHalted: true},

                {Name: "multiple_nops", Category: "control",
                        Program: []byte{vm.NOP, vm.NOP, vm.NOP, vm.HALT}, ExpectedHalted: true},

                {Name: "push_negative", Category: "stack",
                        Program: append(pushU32(0xFFFFFFD6), vm.HALT),
                        ExpectedStack: []uint32{0xFFFFFFD6},
                        ExpectedHalted: true},

                {Name: "chained_arithmetic", Category: "arithmetic",
                        Program: append(append(append(pushU32(2), pushU32(3)...), vm.ADD), append(pushU32(4), vm.MUL, vm.HALT)...),
                        ExpectedStack: []uint32{20}, ExpectedHalted: true},

                // --- v1.1 Extension Opcode Vectors ---

                {Name: "ext_call_ret_basic", Category: "extension",
                        Program:       buildCallRetBasic(),
                        ExpectedStack: []uint32{42},
                        ExpectedHalted: true},

                {Name: "ext_call_ret_nested", Category: "extension",
                        Program:       buildCallRetNested(),
                        ExpectedStack: []uint32{10, 50},
                        ExpectedHalted: true},

                {Name: "ext_cmp_equal", Category: "extension",
                        Program:       buildCmpEqual(),
                        ExpectedStack: []uint32{},
                        ExpectedHalted: true},

                {Name: "ext_cmp_not_equal", Category: "extension",
                        Program:       buildCmpNotEqual(),
                        ExpectedStack: []uint32{},
                        ExpectedHalted: true},

                {Name: "ext_cmp_less_than", Category: "extension",
                        Program:       buildCmpLessThan(),
                        ExpectedStack: []uint32{},
                        ExpectedHalted: true},

                {Name: "ext_shl_basic", Category: "extension",
                        Program: append(append(pushU32(4), pushU32(1)...), vm.SHL, vm.HALT),
                        ExpectedStack: []uint32{8}, ExpectedHalted: true},

                {Name: "ext_shl_large", Category: "extension",
                        Program: append(append(pushU32(1), pushU32(4)...), vm.SHL, vm.HALT),
                        ExpectedStack: []uint32{16}, ExpectedHalted: true},

                {Name: "ext_shr_basic", Category: "extension",
                        Program: append(append(pushU32(16), pushU32(2)...), vm.SHR, vm.HALT),
                        ExpectedStack: []uint32{4}, ExpectedHalted: true},

                {Name: "ext_shr_logical", Category: "extension",
                        Program: append(append(pushU32(0x80000000), pushU32(1)...), vm.SHR, vm.HALT),
                        ExpectedStack: []uint32{0x40000000}, ExpectedHalted: true},

                {Name: "ext_shl_overflow_carry", Category: "extension",
                        Program: append(append(pushU32(1), pushU32(0)...), vm.SHL, vm.HALT),
                        ExpectedStack: []uint32{1}, ExpectedHalted: true},

                {Name: "ext_shr_no_carry", Category: "extension",
                        Program: append(append(pushU32(8), pushU32(4)...), vm.SHR, vm.HALT),
                        ExpectedStack: []uint32{0}, ExpectedHalted: true},

                {Name: "ext_div_exact", Category: "extension",
                        Program: append(append(pushU32(15), pushU32(3)...), vm.DIV, vm.HALT),
                        ExpectedStack: []uint32{5}, ExpectedHalted: true},

                {Name: "ext_div_with_remainder", Category: "extension",
                        Program: append(append(pushU32(17), pushU32(5)...), vm.DIV, vm.HALT),
                        ExpectedStack: []uint32{3}, ExpectedHalted: true},

                {Name: "ext_mod_basic", Category: "extension",
                        Program: append(append(pushU32(17), pushU32(5)...), vm.MOD, vm.HALT),
                        ExpectedStack: []uint32{2}, ExpectedHalted: true},

                {Name: "ext_mod_by_one", Category: "extension",
                        Program: append(append(pushU32(42), pushU32(1)...), vm.MOD, vm.HALT),
                        ExpectedStack: []uint32{0}, ExpectedHalted: true},

                {Name: "ext_mod_max", Category: "extension",
                        Program: append(append(pushU32(0xFFFFFFFF), pushU32(10)...), vm.MOD, vm.HALT),
                        ExpectedStack: []uint32{5}, ExpectedHalted: true},

                {Name: "ext_jnz_taken", Category: "extension",
                        Program:       buildJnzTaken(),
                        ExpectedStack: []uint32{77},
                        ExpectedHalted: true},

                {Name: "ext_jnz_not_taken", Category: "extension",
                        Program:       buildJnzNotTaken(),
                        ExpectedStack: []uint32{55},
                        ExpectedHalted: true},

                {Name: "ext_sub_then_jc", Category: "extension",
                        Program:       buildSubThenJc(),
                        ExpectedStack: []uint32{2},
                        ExpectedHalted: true},

                {Name: "ext_carry_jc_taken", Category: "extension",
                        Program:       buildCarryJcTaken(),
                        ExpectedStack: []uint32{0xFFFFFFFE, 99},
                        ExpectedHalted: true},

                {Name: "ext_cmp_greater", Category: "extension",
                        Program: append(append(pushU32(7), pushU32(3)...), vm.CMP, vm.HALT),
                        ExpectedStack: []uint32{},
                        ExpectedHalted: true},

                {Name: "ext_div_zero_halt", Category: "edge",
                        Program: append(append(pushU32(42), pushU32(0)...), vm.DIV, vm.HALT),
                        ExpectedStack: []uint32{},
                        ExpectedHalted: true},

                {Name: "ext_mod_zero_halt", Category: "edge",
                        Program: append(append(pushU32(42), pushU32(0)...), vm.MOD, vm.HALT),
                        ExpectedStack: []uint32{},
                        ExpectedHalted: true},

                {Name: "ext_mul_overflow", Category: "edge",
                        Program: append(append(pushU32(0xFFFFFFFF), pushU32(2)...), vm.MUL, vm.HALT),
                        ExpectedStack: []uint32{0xFFFFFFFE},
                        ExpectedHalted: true},

                {Name: "ext_shl_31bits", Category: "edge",
                        Program: append(append(pushU32(1), pushU32(31)...), vm.SHL, vm.HALT),
                        ExpectedStack: []uint32{0x80000000},
                        ExpectedHalted: true},

                {Name: "ext_call_ret_depth_10", Category: "edge",
                        Program:       buildCallRetDepthN(10),
                        ExpectedStack: []uint32{1},
                        ExpectedHalted: true},
        }
}

// --- Helper functions ---

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

func buildJmpForward() []byte {
        base := vm.ProgramStart
        target := base + 4
        return append(append(jmpU16(target), vm.NOP), append(pushU32(77), vm.HALT)...)
}

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

func buildLoadStoreRoundtrip() []byte {
        var p []byte
        p = append(p, pushU32(1234)...)
        p = append(p, storeU16(0x0200)...)
        p = append(p, loadU16(0x0200)...)
        p = append(p, vm.HALT)
        return p
}

// buildFactorial5 computes 5! = 120 using memory at 0x0300 (acc) and 0x0304 (counter).
// Counter is offset by 4 bytes (word-aligned) to prevent StoreWord overlap.
func buildFactorial5() []byte {
        base := vm.ProgramStart
        loopAddr := base + 16
        doneAddr := base + 47

        var p []byte
        p = append(p, pushU32(1)...)
        p = append(p, storeU16(0x0300)...)
        p = append(p, pushU32(5)...)
        p = append(p, storeU16(0x0304)...)
        p = append(p, loadU16(0x0304)...)
        p = append(p, jzU16(doneAddr)...)
        p = append(p, loadU16(0x0300)...)
        p = append(p, loadU16(0x0304)...)
        p = append(p, vm.MUL)
        p = append(p, storeU16(0x0300)...)
        p = append(p, loadU16(0x0304)...)
        p = append(p, pushU32(1)...)
        p = append(p, vm.SUB)
        p = append(p, storeU16(0x0304)...)
        p = append(p, jmpU16(loopAddr)...)
        p = append(p, loadU16(0x0300)...)
        p = append(p, vm.HALT)
        return p
}

// --- v1.1 Extension helpers ---

func buildCmpEqual() []byte {
        return append(append(pushU32(7), pushU32(7)...), vm.CMP, vm.HALT)
}

func buildCmpNotEqual() []byte {
        return append(append(pushU32(5), pushU32(3)...), vm.CMP, vm.HALT)
}

func buildCmpLessThan() []byte {
        return append(append(pushU32(3), pushU32(5)...), vm.CMP, vm.HALT)
}

func buildSubThenJc() []byte {
        // PUSH 5, PUSH 3, SUB -> result=2, carry=false (no underflow)
        // JC to dead HALT -> not taken, falls through to real HALT
        base := vm.ProgramStart
        var p []byte
        p = append(p, pushU32(5)...)
        p = append(p, pushU32(3)...)
        p = append(p, vm.SUB)
        // JC to a dead HALT (never taken since no carry)
        deadTarget := base + uint16(len(p)) + 3 + 1 // JC(3) + HALT(1)
        p = append(p, vm.JC, byte(deadTarget>>8), byte(deadTarget))
        p = append(p, vm.HALT) // this executes (result=2 on stack)
        return p
}

func buildCallRetBasic() []byte {
        // CALL subroutine -> PUSH 42 -> RET -> HALT
        base := vm.ProgramStart
        var p []byte

        // Main: CALL sub
        p = append(p, vm.CALL, 0x00, 0x00) // placeholder, patch below
        callIdx := len(p) - 2
        p = append(p, vm.HALT)

        // Subroutine: PUSH 42, RET
        subAddr := base + uint16(len(p))
        p[callIdx] = byte(subAddr >> 8)
        p[callIdx+1] = byte(subAddr)
        p = append(p, pushU32(42)...)
        p = append(p, vm.RET)
        return p
}

func buildCallRetNested() []byte {
        // PUSH 10, CALL subA, HALT
        // subA: PUSH 20, CALL subB, ADD, RET
        // subB: PUSH 30, RET
        // Result: stack = [10, 50] (10 + (20+30))
        base := vm.ProgramStart
        var p []byte

        p = append(p, pushU32(10)...)
        p = append(p, vm.CALL, 0x00, 0x00) // CALL subA
        mainCallIdx := len(p) - 2
        p = append(p, vm.HALT)

        subAAddr := base + uint16(len(p))
        p[mainCallIdx] = byte(subAAddr >> 8)
        p[mainCallIdx+1] = byte(subAAddr)

        p = append(p, pushU32(20)...)
        p = append(p, vm.CALL, 0x00, 0x00) // CALL subB
        subACallIdx := len(p) - 2
        p = append(p, vm.ADD)
        p = append(p, vm.RET)

        subBAddr := base + uint16(len(p))
        p[subACallIdx] = byte(subBAddr >> 8)
        p[subACallIdx+1] = byte(subBAddr)
        p = append(p, pushU32(30)...)
        p = append(p, vm.RET)
        return p
}
func buildJnzTaken() []byte {
        // PUSH 77, PUSH 1, JNZ past_dead_halt -> HALT (77 stays on stack)
        base := vm.ProgramStart
        var p []byte
        p = append(p, pushU32(77)...)
        p = append(p, pushU32(1)...)
        p = append(p, vm.JNZ, 0x00, 0x00) // placeholder
        jnzIdx := len(p) - 2
        p = append(p, vm.HALT) // dead: JNZ taken skips this
        skipTarget := base + uint16(len(p))
        p[jnzIdx] = byte(skipTarget >> 8)
        p[jnzIdx+1] = byte(skipTarget)
        p = append(p, vm.HALT)
        return p
}

func buildJnzNotTaken() []byte {
        // PUSH 55, PUSH 0, JNZ somewhere -> not taken (0), falls through to HALT
        base := vm.ProgramStart
        var p []byte
        p = append(p, pushU32(55)...)
        p = append(p, pushU32(0)...)
        // JNZ to a dead HALT (never taken since value is 0)
        deadTarget := base + uint16(len(p)) + 3 + 1 // JNZ(3) + HALT(1)
        p = append(p, vm.JNZ, byte(deadTarget>>8), byte(deadTarget))
        p = append(p, vm.HALT) // this executes
        return p
}

func buildCarryJcTaken() []byte {
        // PUSH 3, PUSH 5, SUB -> result=0xFFFFFFFE, carry=true (underflow)
        // JC taken -> skip dead HALT -> PUSH 99 -> HALT
        base := vm.ProgramStart
        var p []byte
        p = append(p, pushU32(3)...)
        p = append(p, pushU32(5)...)
        p = append(p, vm.SUB)
        // JC target = current offset + JC(3) + dead HALT(1) = PUSH 99 location
        push99Offset := base + uint16(len(p)) + 3 + 1
        p = append(p, vm.JC, byte(push99Offset>>8), byte(push99Offset))
        p = append(p, vm.HALT) // dead: JC taken skips this
        p = append(p, pushU32(99)...)
        p = append(p, vm.HALT)
        return p
}

func buildCallRetDepthN(depth int) []byte {
        // Test deep call stack using recursion: a subroutine that counts down
        // and calls itself, then PUSH 1 after unwinding.
        // Uses memory at 0x0400 as counter.
        //
        // Main:
        //   PUSH depth, STORE 0x0400
        //   CALL subroutine
        //   HALT  (should never reach here — subroutine does the final push)
        //
        // Subroutine:
        //   LOAD 0x0400
        //   JZ done        <- if counter is 0, jump to done
        //   LOAD 0x0400
        //   PUSH 1, SUB
        //   STORE 0x0400
        //   CALL subroutine  <- recursive call
        //   RET
        //
        // Done:
        //   PUSH 1
        //   RET  <- return to caller

        base := vm.ProgramStart
        var p []byte

        // Main: PUSH depth, STORE 0x0400, CALL sub, HALT
        p = append(p, pushU32(uint32(depth))...)
        p = append(p, storeU16(0x0400)...)

        // CALL subroutine (placeholder, patch below)
        p = append(p, vm.CALL, 0x00, 0x00)
        callIdx := uint16(len(p)) - 2

        p = append(p, vm.HALT) // should never execute

        // Subroutine starts here
        subAddr := base + uint16(len(p))
        p[callIdx] = byte(subAddr >> 8)
        p[callIdx+1] = byte(subAddr)

        // Sub body: LOAD counter, JZ done, decrement, recursive CALL, RET
        p = append(p, loadU16(0x0400)...)
        p = append(p, vm.JZ, 0x00, 0x00) // placeholder for done target
        jzIdx := uint16(len(p)) - 2

        p = append(p, loadU16(0x0400)...)
        p = append(p, pushU32(1)...)
        p = append(p, vm.SUB)
        p = append(p, storeU16(0x0400)...)

        // Recursive CALL (points to self = subAddr)
        p = append(p, vm.CALL, byte(subAddr>>8), byte(subAddr))

        p = append(p, vm.RET) // return to caller after recursion unwinds

        // Done: PUSH 1, RET
        doneAddr := base + uint16(len(p))
        p[jzIdx] = byte(doneAddr >> 8)
        p[jzIdx+1] = byte(doneAddr)

        p = append(p, pushU32(1)...)
        p = append(p, vm.RET)

        return p
}


// hexToBytes converts a hex string (with optional spaces) to a byte slice.
func hexToBytes(hexStr string) ([]byte, error) {
        hexStr = strings.ReplaceAll(hexStr, " ", "")
        hexStr = strings.ReplaceAll(hexStr, "\n", "")
        return hex.DecodeString(hexStr)
}

// toUint32Slice converts an interface{} (JSON number array) to []uint32.
func toUint32Slice(v interface{}) ([]uint32, bool) {
        if v == nil {
                return nil, true
        }
        switch arr := v.(type) {
        case []interface{}:
                result := make([]uint32, len(arr))
                for i, item := range arr {
                        n, ok := toFloat64(item)
                        if !ok {
                                return nil, false
                        }
                        result[i] = uint32(n)
                }
                return result, true
        case []float64:
                result := make([]uint32, len(arr))
                for i, n := range arr {
                        result[i] = uint32(n)
                }
                return result, true
        default:
                return nil, false
        }
}

func toFloat64(v interface{}) (float64, bool) {
        switch n := v.(type) {
        case float64:
                return n, true
        case json.Number:
                f, err := n.Float64()
                return f, err == nil
        case string:
                f, err := strconv.ParseFloat(n, 64)
                return f, err == nil
        default:
                return 0, false
        }
}

// isSupportedOpcode checks if a program only uses opcodes our VM supports (0x00-0x18).
// Walks instruction boundaries using vm.OpcodeWidth rather than checking every byte,
// to avoid false rejections from large operand values in PUSH/addr instructions.
func isSupportedOpcode(program []byte) bool {
        for i := 0; i < len(program); {
                op := program[i]
                if op > maxSupportedOpcode {
                        return false
                }
                w := vm.OpcodeWidth(op)
                if w <= 0 {
                        return false
                }
                i += w
        }
        return true
}
