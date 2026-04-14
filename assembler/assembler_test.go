package assembler

import (
        "testing"

        "github.com/SuperInstance/flux-tui/vm"
)

// --- New opcode assembly tests ---

func TestAssemble_CALL(t *testing.T) {
        code, errs := Assemble("JMP target\nCALL target\ntarget:\nHALT")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        // CALL should encode as Format B: [0x11][addr_hi][addr_lo]
        // First instruction JMP at 0x0100 (3 bytes), CALL at 0x0103 (3 bytes), HALT at 0x0106
        if code[3] != vm.CALL {
                t.Errorf("expected opcode CALL (0x11) at offset 3, got 0x%02X", code[3])
        }
        // Target address should be 0x0106 (HALT)
        addr := uint16(code[4])<<8 | uint16(code[5])
        if addr != 0x0106 {
                t.Errorf("expected CALL target 0x0106, got 0x%04X", addr)
        }
}

func TestAssemble_RET(t *testing.T) {
        code, errs := Assemble("RET")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        if len(code) != 1 {
                t.Fatalf("expected 1 byte, got %d", len(code))
        }
        if code[0] != vm.RET {
                t.Errorf("expected opcode RET (0x12), got 0x%02X", code[0])
        }
}

func TestAssemble_CMP(t *testing.T) {
        code, errs := Assemble("PUSH 5\nPUSH 3\nCMP")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        // PUSH(5) + PUSH(5) + CMP(1) = 11 bytes
        lastOp := code[10]
        if lastOp != vm.CMP {
                t.Errorf("expected opcode CMP (0x13), got 0x%02X", lastOp)
        }
}

func TestAssemble_JNZ(t *testing.T) {
        code, errs := Assemble("PUSH 1\nJNZ target\ntarget:\nHALT")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        // PUSH(5) at 0x0100, JNZ(3) at 0x0105, HALT(1) at 0x0108
        if code[5] != vm.JNZ {
                t.Errorf("expected opcode JNZ (0x14) at offset 5, got 0x%02X", code[5])
        }
        addr := uint16(code[6])<<8 | uint16(code[7])
        if addr != 0x0108 {
                t.Errorf("expected JNZ target 0x0108, got 0x%04X", addr)
        }
}

func TestAssemble_JC(t *testing.T) {
        code, errs := Assemble("JC target\ntarget:\nHALT")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        if code[0] != vm.JC {
                t.Errorf("expected opcode JC (0x15), got 0x%02X", code[0])
        }
        addr := uint16(code[1])<<8 | uint16(code[2])
        if addr != 0x0103 {
                t.Errorf("expected JC target 0x0103, got 0x%04X", addr)
        }
}

func TestAssemble_SHL_SHR_DIV(t *testing.T) {
        code, errs := Assemble("SHL")
        if len(errs) > 0 {
                t.Fatalf("SHL assembly errors: %v", errs)
        }
        if code[0] != vm.SHL {
                t.Errorf("expected SHL (0x16), got 0x%02X", code[0])
        }

        code, errs = Assemble("SHR")
        if len(errs) > 0 {
                t.Fatalf("SHR assembly errors: %v", errs)
        }
        if code[0] != vm.SHR {
                t.Errorf("expected SHR (0x17), got 0x%02X", code[0])
        }

        code, errs = Assemble("DIV")
        if len(errs) > 0 {
                t.Fatalf("DIV assembly errors: %v", errs)
        }
        if code[0] != vm.DIV {
                t.Errorf("expected DIV (0x18), got 0x%02X", code[0])
        }
}

// --- Data directive tests ---

func TestAssemble_DB(t *testing.T) {
        code, errs := Assemble(".db 0x41 0x42 0x43")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        if len(code) != 3 {
                t.Fatalf("expected 3 bytes, got %d", len(code))
        }
        if code[0] != 0x41 || code[1] != 0x42 || code[2] != 0x43 {
                t.Errorf("expected [0x41, 0x42, 0x43], got %v", code)
        }
}

func TestAssemble_DB_Single(t *testing.T) {
        code, errs := Assemble(".db 255")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        if len(code) != 1 || code[0] != 255 {
                t.Errorf("expected [255], got %v", code)
        }
}

func TestAssemble_DB_Mixed(t *testing.T) {
        // Mix directives with instructions
        code, errs := Assemble(".db 0x01\nPUSH 42\n.db 0x02")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        if len(code) != 7 { // 1 + 5 + 1
                t.Fatalf("expected 7 bytes, got %d", len(code))
        }
        if code[0] != 0x01 {
                t.Errorf("expected .db byte 0x01, got 0x%02X", code[0])
        }
        if code[1] != vm.PUSH {
                t.Errorf("expected PUSH at offset 1, got 0x%02X", code[1])
        }
        if code[6] != 0x02 {
                t.Errorf("expected .db byte 0x02 at offset 6, got 0x%02X", code[6])
        }
}

func TestAssemble_DW(t *testing.T) {
        code, errs := Assemble(".dw 0x1234")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        if len(code) != 2 {
                t.Fatalf("expected 2 bytes, got %d", len(code))
        }
        // Big-endian: 0x12, 0x34
        if code[0] != 0x12 || code[1] != 0x34 {
                t.Errorf("expected [0x12, 0x34], got [0x%02X, 0x%02X]", code[0], code[1])
        }
}

func TestAssemble_DW_Multiple(t *testing.T) {
        code, errs := Assemble(".dw 0x0001 0x0002")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        if len(code) != 4 {
                t.Fatalf("expected 4 bytes, got %d", len(code))
        }
}

func TestAssemble_ASCII(t *testing.T) {
        code, errs := Assemble(".ascii \"hello\"")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        if len(code) != 5 {
                t.Fatalf("expected 5 bytes, got %d: %v", len(code), code)
        }
        expected := []byte{'h', 'e', 'l', 'l', 'o'}
        for i, b := range expected {
                if code[i] != b {
                        t.Errorf("byte %d: expected '%c', got '%c'", i, b, code[i])
                }
        }
}

func TestAssemble_ASCII_Escapes(t *testing.T) {
        code, errs := Assemble(".ascii \"a\\nb\"")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        // Should emit: 'a', '\n', 'b' = 3 bytes
        if len(code) != 3 {
                t.Fatalf("expected 3 bytes, got %d", len(code))
        }
        if code[0] != 'a' || code[1] != '\n' || code[2] != 'b' {
                t.Errorf("expected ['a', 0x0A, 'b'], got %v", code)
        }
}

func TestAssemble_ASCII_WithInstructions(t *testing.T) {
        code, errs := Assemble(".ascii \"AB\"\nPUSH 42\n.ascii \"CD\"")
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        // "AB"(2) + PUSH(5) + "CD"(2) = 9 bytes
        if len(code) != 9 {
                t.Fatalf("expected 9 bytes, got %d", len(code))
        }
}

// --- Disassembly tests for new opcodes ---

func TestDisassemble_CALL(t *testing.T) {
        data := []byte{vm.CALL, 0x02, 0x00}
        text, consumed := DisassembleInstruction(data, 0)
        if consumed != 3 {
                t.Errorf("expected consumed 3, got %d", consumed)
        }
        if text != "CALL 0x0200" {
                t.Errorf("expected 'CALL 0x0200', got '%s'", text)
        }
}

func TestDisassemble_RET(t *testing.T) {
        data := []byte{vm.RET}
        text, consumed := DisassembleInstruction(data, 0)
        if consumed != 1 {
                t.Errorf("expected consumed 1, got %d", consumed)
        }
        if text != "RET" {
                t.Errorf("expected 'RET', got '%s'", text)
        }
}

func TestDisassemble_JNZ(t *testing.T) {
        data := []byte{vm.JNZ, 0x01, 0x00}
        text, consumed := DisassembleInstruction(data, 0)
        if consumed != 3 {
                t.Errorf("expected consumed 3, got %d", consumed)
        }
        if text != "JNZ 0x0100" {
                t.Errorf("expected 'JNZ 0x0100', got '%s'", text)
        }
}

func TestDisassemble_JC(t *testing.T) {
        data := []byte{vm.JC, 0x00, 0xFF}
        text, consumed := DisassembleInstruction(data, 0)
        if consumed != 3 {
                t.Errorf("expected consumed 3, got %d", consumed)
        }
        if text != "JC 0x00FF" {
                t.Errorf("expected 'JC 0x00FF', got '%s'", text)
        }
}

// --- Lexer tests for directives ---

func TestLexer_Directives(t *testing.T) {
        tests := []struct {
                input    string
                expected string // directive token value
        }{
                {".db 0x41", ".DB"},
                {".DB 0x41", ".DB"},
                {".dw 0x1234", ".DW"},
                {".DW 0x1234", ".DW"},
                {".ascii \"hello\"", ".ASCII"},
                {".ASCII \"hello\"", ".ASCII"},
        }
        for _, tc := range tests {
                tokens := TokenizeAll(tc.input)
                found := false
                for _, tok := range tokens {
                        if tok.Type == TokenDirective && tok.Value == tc.expected {
                                found = true
                                break
                        }
                }
                if !found {
                        t.Errorf("expected directive token %s in %q", tc.expected, tc.input)
                }
        }
}

func TestLexer_StringToken(t *testing.T) {
        tokens := TokenizeAll("\"hello\"")
        found := false
        for _, tok := range tokens {
                if tok.Type == TokenString && tok.Value == "hello" {
                        found = true
                        break
                }
        }
        if !found {
                t.Error("expected string token with value 'hello'")
        }
}

func TestLexer_StringEscape(t *testing.T) {
        tokens := TokenizeAll("\"a\\nb\"")
        found := false
        for _, tok := range tokens {
                if tok.Type == TokenString && tok.Value == "a\nb" {
                        found = true
                        break
                }
        }
        if !found {
                t.Error("expected string token with value 'a\\nb' (with newline)")
        }
}

// --- Integration: Assemble and run with new opcodes ---

func TestAssembleAndRun_SHLDIV(t *testing.T) {
        src := `
; Compute (8 << 2) / 4 = 8
PUSH 8      ; value (b)
PUSH 2      ; shift amount (a)
SHL         ; 8 << 2 = 32
PUSH 4      ; divisor (a)
DIV         ; 32 / 4 = 8
HALT
`
        code, errs := Assemble(src)
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }

        e := vm.NewEngine()
        e.LoadProgram(code)
        e.Run()

        if !e.Halted {
                t.Error("expected halted")
        }
        val, err := e.Stack().Peek()
        if err != nil {
                t.Fatalf("stack peek: %v", err)
        }
        if val != 8 {
                t.Errorf("expected 8 ((8<<2)/4), got %d", val)
        }
}

func TestAssembleAndRun_CallRet(t *testing.T) {
        src := `
PUSH 10
CALL double
HALT

double:
PUSH 20
ADD
RET
`
        code, errs := Assemble(src)
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }

        e := vm.NewEngine()
        e.LoadProgram(code)
        e.Run()

        if !e.Halted {
                t.Error("expected halted")
        }
        items := e.StackValues()
        // Stack should have [10+20] = [30]
        if len(items) != 1 {
                t.Fatalf("expected 1 item, got %d: %v", len(items), items)
        }
        if items[0] != 30 {
                t.Errorf("expected 30 (10+20), got %d", items[0])
        }
}

func TestAssembleAndRun_CMPLoop(t *testing.T) {
        src := `
; Count down from 5 to 0 using CMP and JNZ
; Result: 0 on stack
PUSH 5

loop:
DUP
PUSH 0
CMP
JNZ skip
JMP done

skip:
PUSH 1
SUB
JMP loop

done:
HALT
`
        code, errs := Assemble(src)
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }

        e := vm.NewEngine()
        e.LoadProgram(code)
        e.Run()

        if !e.Halted {
                t.Error("expected halted")
        }
        val, _ := e.Stack().Peek()
        if val != 0 {
                t.Errorf("expected 0 on stack after countdown, got %d", val)
        }
}

func TestAssemble_WithDBAndDW(t *testing.T) {
        src := `
.dw 0xDEAD
.db 0x01 0x02
PUSH 42
HALT
`
        code, errs := Assemble(src)
        if len(errs) > 0 {
                t.Fatalf("assembly errors: %v", errs)
        }
        // .dw(2) + .db(2) + PUSH(5) + HALT(1) = 10 bytes
        if len(code) != 10 {
                t.Fatalf("expected 10 bytes, got %d", len(code))
        }
        if code[0] != 0xDE || code[1] != 0xAD {
                t.Errorf("expected .dw 0xDEAD, got [0x%02X, 0x%02X]", code[0], code[1])
        }
        if code[2] != 0x01 || code[3] != 0x02 {
                t.Errorf("expected .db 0x01 0x02, got [0x%02X, 0x%02X]", code[2], code[3])
        }
}
