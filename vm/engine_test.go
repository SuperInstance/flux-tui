package vm

import (
        "testing"
)

func TestNOP(t *testing.T) {
        e := NewEngine()
        prog := []byte{NOP, HALT}
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        err = e.Step()
        if err != nil {
                t.Fatalf("Step NOP: %v", err)
        }
        if e.StepCount() != 1 {
                t.Errorf("expected step count 1, got %d", e.StepCount())
        }
        if e.PC != ProgramStart+1 {
                t.Errorf("expected PC 0x%04X, got 0x%04X", ProgramStart+1, e.PC)
        }
}

func TestPushPop(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 42), FormatA(PUSH, 99)...)
        prog = append(prog, POP, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }

        // Step through PUSH 42
        e.Step()
        if e.stack.Depth() != 1 {
                t.Errorf("expected depth 1 after PUSH, got %d", e.stack.Depth())
        }
        val, _ := e.stack.Peek()
        if val != 42 {
                t.Errorf("expected 42 on stack, got %d", val)
        }

        // Step through PUSH 99
        e.Step()
        if e.stack.Depth() != 2 {
                t.Errorf("expected depth 2 after second PUSH, got %d", e.stack.Depth())
        }

        // Step through POP
        e.Step()
        if e.stack.Depth() != 1 {
                t.Errorf("expected depth 1 after POP, got %d", e.stack.Depth())
        }
        val, _ = e.stack.Peek()
        if val != 42 {
                t.Errorf("expected 42 remaining after POP, got %d", val)
        }
}

func TestDup(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 77), DUP, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step() // PUSH 77
        e.Step() // DUP
        if e.stack.Depth() != 2 {
                t.Errorf("expected depth 2 after DUP, got %d", e.stack.Depth())
        }
        items := e.stack.Items()
        if items[0] != 77 || items[1] != 77 {
                t.Errorf("expected [77, 77], got %v", items)
        }
}

func TestSwap(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 10), FormatA(PUSH, 20)...)
        prog = append(prog, SWAP, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step() // PUSH 10
        e.Step() // PUSH 20
        e.Step() // SWAP
        items := e.stack.Items()
        if items[0] != 20 || items[1] != 10 {
                t.Errorf("expected [20, 10] after SWAP, got %v", items)
        }
}

func TestAdd(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 3), FormatA(PUSH, 4)...)
        prog = append(prog, ADD, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step() // PUSH 3
        e.Step() // PUSH 4
        e.Step() // ADD
        val, _ := e.stack.Peek()
        if val != 7 {
                t.Errorf("expected 7, got %d", val)
        }
        if e.stack.Depth() != 1 {
                t.Errorf("expected depth 1, got %d", e.stack.Depth())
        }
}

func TestSub(t *testing.T) {
        e := NewEngine()
        // Engine SUB: pops a (top), pops b, pushes b-a
        // PUSH 10 (bottom), PUSH 3 (top), SUB => 10 - 3 = 7
        prog := append(FormatA(PUSH, 10), FormatA(PUSH, 3)...)
        prog = append(prog, SUB, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step() // PUSH 10
        e.Step() // PUSH 3
        e.Step() // SUB (10 - 3 = 7)
        val, _ := e.stack.Peek()
        if val != 7 {
                t.Errorf("expected 7 (10-3), got %d", val)
        }
}

func TestMul(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 6), FormatA(PUSH, 7)...)
        prog = append(prog, MUL, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step() // PUSH 6
        e.Step() // PUSH 7
        e.Step() // MUL
        val, _ := e.stack.Peek()
        if val != 42 {
                t.Errorf("expected 42 (6*7), got %d", val)
        }
}

func TestAnd(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 0x0F), FormatA(PUSH, 0xFF)...)
        prog = append(prog, AND, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step(); e.Step(); e.Step() // PUSH, PUSH, AND
        val, _ := e.stack.Peek()
        if val != 0x0F {
                t.Errorf("expected 0x0F, got 0x%08X", val)
        }
}

func TestOr(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 0xF0), FormatA(PUSH, 0x0F)...)
        prog = append(prog, OR, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step(); e.Step(); e.Step()
        val, _ := e.stack.Peek()
        if val != 0xFF {
                t.Errorf("expected 0xFF, got 0x%08X", val)
        }
}

func TestXor(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 0xFF), FormatA(PUSH, 0xFF)...)
        prog = append(prog, XOR, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step(); e.Step(); e.Step()
        val, _ := e.stack.Peek()
        if val != 0 {
                t.Errorf("expected 0 (XOR self), got 0x%08X", val)
        }
        // Check zero flag
        if !e.regs.Zero() {
                t.Errorf("expected zero flag set after XOR self")
        }
}

func TestNot(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 0x0F), NOT, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step() // PUSH 0x0F
        e.Step() // NOT
        val, _ := e.stack.Peek()
        if val != ^uint32(0x0F) {
                t.Errorf("expected 0xFFFFFFF0, got 0x%08X", val)
        }
}

func TestJmp(t *testing.T) {
        e := NewEngine()
        // Build program carefully:
        // [0x0100] JMP 0x0103  (3 bytes: opcode + 2-byte addr)
        // [0x0103] PUSH 99     (5 bytes)
        // [0x0108] HALT        (1 byte)
        target := ProgramStart + 3
        prog := make([]byte, 0)
        prog = append(prog, FormatB(JMP, target)...)   // JMP to PUSH 99
        prog = append(prog, FormatA(PUSH, 99)...)       // target: PUSH 99
        prog = append(prog, HALT)

        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }

        e.Step() // JMP -> PC should be 0x0103
        if e.PC != 0x0103 {
                t.Errorf("expected PC 0x0103 after JMP, got 0x%04X", e.PC)
        }
}

func TestJZ_Taken(t *testing.T) {
        e := NewEngine()
        // PUSH 999 (keep on stack), PUSH 0 (test value), JZ target
        // Stack: [999, 0]. JZ pops 0, zero=true, jumps to target
        // At target: PUSH 88, HALT
        // Layout:
        // [0x0100] PUSH 999     (5 bytes)
        // [0x0105] PUSH 0       (5 bytes)
        // [0x010A] JZ 0x010F    (3 bytes)
        // [0x010D] HALT          (1 byte - skipped)
        // [0x010E] <padding>     (1 byte)
        // [0x010F] PUSH 88      (5 bytes)
        // [0x0114] HALT          (1 byte)
        target := ProgramStart + 15 // 0x010F
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 999)...)    // 0x0100
        prog = append(prog, FormatA(PUSH, 0)...)      // 0x0105
        prog = append(prog, FormatB(JZ, target)...)   // 0x010A
        prog = append(prog, HALT)                      // 0x010D (skipped)
        // Padding to reach target
        current := ProgramStart + uint16(len(prog))
        for current < target {
                prog = append(prog, NOP)
                current++
        }
        prog = append(prog, FormatA(PUSH, 88)...)    // target
        prog = append(prog, HALT)

        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }

        e.Step() // PUSH 999
        e.Step() // PUSH 0
        e.Step() // JZ -> pops 0, zero=true, jumps
        if e.PC != target {
                t.Errorf("expected PC 0x%04X after JZ (taken), got 0x%04X", target, e.PC)
        }
        // Stack should have only 999
        if e.stack.Depth() != 1 {
                t.Errorf("expected depth 1 after JZ, got %d", e.stack.Depth())
        }
        val, _ := e.stack.Peek()
        if val != 999 {
                t.Errorf("expected 999 on stack, got %d", val)
        }
}

func TestJZ_NotTaken(t *testing.T) {
        e := NewEngine()
        target := ProgramStart + 10 // far away
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 0)...)       // bottom of stack
        prog = append(prog, FormatA(PUSH, 42)...)      // top of stack (non-zero)
        prog = append(prog, FormatB(JZ, target)...)    // JZ pops 42, non-zero, no jump
        prog = append(prog, HALT)                       // executed

        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }

        e.Step() // PUSH 0
        e.Step() // PUSH 42
        e.Step() // JZ -> not taken (42 != 0)
        // PC should be right after the JZ instruction (3 bytes: opcode + 2 addr)
        expectedPC := ProgramStart + 5 + 5 + 3 // PUSH(5) + PUSH(5) + JZ(3)
        if e.PC != expectedPC {
                t.Errorf("expected PC 0x%04X after JZ not taken, got 0x%04X", expectedPC, e.PC)
        }
}

func TestLoadStore(t *testing.T) {
        e := NewEngine()
        memAddr := uint16(0x0200)
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 0xDEADBEEF)...)  // value to store
        prog = append(prog, FormatB(STORE, memAddr)...)     // store at 0x0200
        prog = append(prog, FormatB(LOAD, memAddr)...)       // load from 0x0200
        prog = append(prog, HALT)

        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }

        e.Run()
        val, err := e.stack.Peek()
        if err != nil {
                t.Fatalf("stack peek: %v", err)
        }
        if val != 0xDEADBEEF {
                t.Errorf("expected 0xDEADBEEF after LOAD, got 0x%08X", val)
        }
        // Also verify directly from memory
        memVal, _ := e.mem.LoadWord(memAddr)
        if memVal != 0xDEADBEEF {
                t.Errorf("memory at 0x%04X: expected 0xDEADBEEF, got 0x%08X", memAddr, memVal)
        }
}

func TestHalt(t *testing.T) {
        e := NewEngine()
        prog := []byte{HALT}
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Step() // HALT
        if !e.IsHalted() {
                t.Error("expected engine to be halted")
        }
        // Step on halted engine should return error
        err = e.Step()
        if err == nil {
                t.Error("expected error when stepping halted engine")
        }
}

func TestSnapshotRestore(t *testing.T) {
        e := NewEngine()
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 42)...)
        prog = append(prog, HALT)

        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }

        // Run to completion
        e.Run()
        if !e.IsHalted() {
                t.Error("expected halted after Run")
        }
        if e.stack.Depth() != 1 {
                t.Errorf("expected depth 1, got %d", e.stack.Depth())
        }

        // Now take snapshot and restore to verify state capture
        e2 := NewEngine()
        e2.LoadProgram(prog)
        e2.Step() // PUSH 42
        snap := e2.Snapshot()

        // Modify state
        e2.Step() // HALT
        if e2.IsHalted() {
                // Good, it halted
        }

        // Restore
        e2.Restore(snap)
        if e2.IsHalted() {
                t.Error("expected not halted after restore")
        }
        if e2.StepCount() != 1 {
                t.Errorf("expected step count 1 after restore, got %d", e2.StepCount())
        }
        val, _ := e2.stack.Peek()
        if val != 42 {
                t.Errorf("expected 42 on stack after restore, got %d", val)
        }
}

func TestStackOverflow(t *testing.T) {
        e := NewEngine()
        // Push 257 values to trigger overflow (stack size is 256)
        prog := make([]byte, 0)
        for i := 0; i < 257; i++ {
                prog = append(prog, FormatA(PUSH, uint32(i))...)
        }
        prog = append(prog, HALT)
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }

        // Run - should halt due to stack overflow
        e.Run(300)
        if !e.IsHalted() {
                t.Error("expected engine to halt on stack overflow")
        }
        // Stack depth should be at most 256
        if e.stack.Depth() > 256 {
                t.Errorf("expected depth <= 256, got %d", e.stack.Depth())
        }
}

func TestRunToHalt(t *testing.T) {
        e := NewEngine()
        // Compute 2 + 3 * 4 = 14 using stack
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 2)...)   // [2]
        prog = append(prog, FormatA(PUSH, 3)...)   // [2, 3]
        prog = append(prog, FormatA(PUSH, 4)...)   // [2, 3, 4]
        prog = append(prog, MUL)                   // [2, 12]
        prog = append(prog, ADD)                   // [14]
        prog = append(prog, HALT)

        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Run()

        if !e.IsHalted() {
                t.Error("expected halted")
        }
        val, _ := e.stack.Peek()
        if val != 14 {
                t.Errorf("expected 14 (2 + 3*4), got %d", val)
        }
}

func TestFlagZero(t *testing.T) {
        e := NewEngine()
        prog := append(FormatA(PUSH, 5), FormatA(PUSH, 5)...)
        prog = append(prog, SUB, HALT) // 5 - 5 = 0
        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }
        e.Run()
        if !e.regs.Zero() {
                t.Error("expected zero flag set after 5-5=0")
        }
}

func TestMemoryBounds(t *testing.T) {
        m := NewMemory()
        // Test out-of-bounds read
        _, err := m.Load(0xFFFF)
        if err != nil {
                t.Errorf("read at 0xFFFF should succeed (last valid byte): %v", err)
        }
        // Note: uint16 max is 0xFFFF (65535), and MemorySize is 65536,
        // so single-byte reads can never actually go out of bounds with uint16.
        // The bounds check is still correct for safety with future changes.

        // Test out-of-bounds word read
        // Max valid word address: 0xFFFC (reads bytes 0xFFFC..0xFFFF)
        _, err = m.LoadWord(0xFFFC)
        if err != nil {
                t.Errorf("word read at 0xFFFC should succeed: %v", err)
        }
        _, err = m.LoadWord(0xFFFD)
        if err == nil {
                t.Error("word read at 0xFFFD should fail (4 bytes from 0xFFFD exceeds 0xFFFF)")
        }
}
