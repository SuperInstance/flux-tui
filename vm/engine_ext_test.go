package vm

import (
        "testing"
)

// --- Breakpoint tests ---

func TestBreakpointManager_AddRemove(t *testing.T) {
        bm := NewBreakpointManager()
        if bm.Has(0x0100) {
                t.Error("expected no breakpoint at 0x0100 initially")
        }
        bm.Add(0x0100)
        if !bm.Has(0x0100) {
                t.Error("expected breakpoint at 0x0100 after Add")
        }
        bm.Remove(0x0100)
        if bm.Has(0x0100) {
                t.Error("expected no breakpoint after Remove")
        }
        if bm.Remove(0x0100) {
                t.Error("expected Remove to return false for non-existent breakpoint")
        }
}

func TestBreakpointManager_Toggle(t *testing.T) {
        bm := NewBreakpointManager()
        added := bm.Toggle(0x0200)
        if !added {
                t.Error("expected Toggle to add breakpoint")
        }
        added = bm.Toggle(0x0200)
        if added {
                t.Error("expected Toggle to remove existing breakpoint")
        }
}

func TestBreakpointManager_Clear(t *testing.T) {
        bm := NewBreakpointManager()
        bm.Add(0x0100)
        bm.Add(0x0200)
        bm.Add(0x0300)
        if bm.Count() != 3 {
                t.Errorf("expected 3 breakpoints, got %d", bm.Count())
        }
        bm.Clear()
        if bm.Count() != 0 {
                t.Errorf("expected 0 breakpoints after Clear, got %d", bm.Count())
        }
}

func TestBreakpointManager_List(t *testing.T) {
        bm := NewBreakpointManager()
        bm.Add(0x0300)
        bm.Add(0x0100)
        bm.Add(0x0200)
        list := bm.List()
        if len(list) != 3 {
                t.Errorf("expected 3 breakpoints in list, got %d", len(list))
        }
}

func TestBreakpointManager_EnableDisable(t *testing.T) {
        bm := NewBreakpointManager()
        bm.Add(0x0100)
        if !bm.Enabled() {
                t.Error("expected breakpoints enabled by default")
        }
        bm.Disable()
        if bm.Enabled() {
                t.Error("expected breakpoints disabled after Disable()")
        }
        if bm.CheckHit(0x0100) {
                t.Error("expected CheckHit to return false when disabled")
        }
        bm.Enable()
        if !bm.CheckHit(0x0100) {
                t.Error("expected CheckHit to return true when enabled and bp set")
        }
}

func TestEngine_Breakpoints(t *testing.T) {
        e := NewEngine()
        bm := e.Breakpoints()
        if bm == nil {
                t.Fatal("expected non-nil BreakpointManager")
        }
        bm.Add(0x0200)
        if !e.Breakpoints().Has(0x0200) {
                t.Error("expected breakpoint to persist via accessor")
        }
}

func TestEngine_RunStopsOnBreakpoint(t *testing.T) {
        e := NewEngine()
        // Build: PUSH 1, PUSH 1, ADD, HALT
        // Set breakpoint at HALT address - Run should stop there before executing HALT
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 1)...) // 0x0100 (5 bytes)
        prog = append(prog, FormatA(PUSH, 1)...) // 0x0105 (5 bytes)
        prog = append(prog, ADD)                 // 0x010A (1 byte)
        haltAddr := ProgramStart + uint16(len(prog))
        prog = append(prog, HALT)                // 0x010B

        e.LoadProgram(prog)
        // Set breakpoint at the HALT instruction address
        e.Breakpoints().Add(haltAddr)

        e.Run()

        if e.Halted {
                t.Error("expected engine NOT halted (should stop at breakpoint before HALT)")
        }
        if e.StepCount() != 3 {
                t.Errorf("expected 3 steps (PUSH+PUSH+ADD), got %d", e.StepCount())
        }
        // PC should be at the HALT instruction (breakpoint hit before executing it)
        if e.PC != haltAddr {
                t.Errorf("expected PC 0x%04X at breakpoint, got 0x%04X", haltAddr, e.PC)
        }
}

func TestEngine_RunPassesBreakpointWhenDisabled(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 1), FormatA(PUSH, 1)...), ADD, HALT)
        e.LoadProgram(prog)
        e.Breakpoints().Add(ProgramStart + 10) // somewhere in the program
        e.Breakpoints().Disable()
        e.Run()
        if !e.Halted {
                t.Error("expected engine to halt when breakpoints disabled")
        }
}

// --- New opcode tests ---

func TestCallRet(t *testing.T) {
        e := NewEngine()
        // Build a call/return sequence using computed addresses
        prog := make([]byte, 0)

        // 0x0100: CALL subroutine
        prog = append(prog, FormatB(CALL, 0)...) // placeholder
        callOffset := uint16(len(prog) + int(ProgramStart) - 3) // offset of the addr field
        retAddr := ProgramStart + uint16(len(prog))               // 0x0103
        prog = append(prog, HALT) // 0x0103: HALT (target of RET)

        // Subroutine starts here
        subAddr := ProgramStart + uint16(len(prog))
        // Fix CALL target
        prog[callOffset-ProgramStart+1] = byte(subAddr >> 8)
        prog[callOffset-ProgramStart+2] = byte(subAddr)

        prog = append(prog, FormatA(PUSH, 42)...) // sub: PUSH 42
        prog = append(prog, RET)                  // sub+5: RET

        _, err := e.LoadProgram(prog)
        if err != nil {
                t.Fatalf("LoadProgram: %v", err)
        }

        // Step CALL
        e.Step()
        if e.PC != subAddr {
                t.Errorf("expected PC 0x%04X after CALL, got 0x%04X", subAddr, e.PC)
        }
        // Return address should be on the RETURN stack (not data stack)
        val, _ := e.returnStack.Peek()
        if val != uint32(retAddr) {
                t.Errorf("expected return addr 0x%04X on return stack, got 0x%08X", retAddr, val)
        }

        // Step PUSH 42
        e.Step()

        // Step RET
        e.Step()
        if e.PC != retAddr {
                t.Errorf("expected PC 0x%04X after RET, got 0x%04X", retAddr, e.PC)
        }
        val, _ = e.stack.Peek()
        if val != 42 {
                t.Errorf("expected 42 on stack after RET, got %d", val)
        }

        // Step HALT
        e.Step()
        if !e.Halted {
                t.Error("expected halted after HALT at return address")
        }
}

func TestCallRetNested(t *testing.T) {
        e := NewEngine()
        // Build nested calls with forward-reference patching
        prog := make([]byte, 0)

        // Main: PUSH 10, CALL subA, HALT
        prog = append(prog, FormatA(PUSH, 10)...)
        _ = ProgramStart + uint16(len(prog)) // mainCallPC used implicitly
        prog = append(prog, FormatB(CALL, 0)...) // placeholder
        mainCallAddrIdx := len(prog) - 2         // index of addr field in prog
        prog = append(prog, HALT)

        // SubA: PUSH 20, CALL subB, ADD, RET
        subAAddr := ProgramStart + uint16(len(prog))
        // Patch main CALL
        prog[mainCallAddrIdx] = byte(subAAddr >> 8)
        prog[mainCallAddrIdx+1] = byte(subAAddr)

        prog = append(prog, FormatA(PUSH, 20)...)
        _ = ProgramStart + uint16(len(prog)) // subACallPC used implicitly
        prog = append(prog, FormatB(CALL, 0)...) // placeholder
        subACallAddrIdx := len(prog) - 2
        prog = append(prog, ADD)
        prog = append(prog, RET)

        // SubB: PUSH 30, RET
        subBAddr := ProgramStart + uint16(len(prog))
        // Patch subA CALL
        prog[subACallAddrIdx] = byte(subBAddr >> 8)
        prog[subACallAddrIdx+1] = byte(subBAddr)

        prog = append(prog, FormatA(PUSH, 30)...)
        prog = append(prog, RET)

        e.LoadProgram(prog)
        e.Run()

        if !e.Halted {
                t.Error("expected halted after nested calls")
        }
        items := e.StackValues()
        if len(items) != 2 {
                t.Fatalf("expected 2 items on stack, got %d: %v", len(items), items)
        }
        if items[0] != 10 {
                t.Errorf("expected items[0]=10, got %d", items[0])
        }
        if items[1] != 50 {
                t.Errorf("expected items[1]=50 (20+30), got %d", items[1])
        }
}

func TestCMP(t *testing.T) {
        e := NewEngine()
        // CMP: pops a (top), pops b, computes b-a, sets flags, NO push
        // PUSH 5, PUSH 3, CMP => b-a = 5-3 = 2, flags: Z=false
        prog := append(append(FormatA(PUSH, 5), FormatA(PUSH, 3)...), CMP, HALT)
        e.LoadProgram(prog)
        e.Run()

        if e.regs.Zero() {
                t.Error("expected zero flag NOT set for 5-3=2")
        }
        if e.stack.Depth() != 0 {
                t.Errorf("expected empty stack after CMP, got %d items", e.stack.Depth())
        }
}

func TestCMP_Equal(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 7), FormatA(PUSH, 7)...), CMP, HALT)
        e.LoadProgram(prog)
        e.Run()

        if !e.regs.Zero() {
                t.Error("expected zero flag set for 7-7=0")
        }
        if e.stack.Depth() != 0 {
                t.Errorf("expected empty stack after CMP, got %d items", e.stack.Depth())
        }
}

func TestCMP_LessThan(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 3), FormatA(PUSH, 5)...), CMP, HALT)
        e.LoadProgram(prog)
        e.Run()

        if !e.regs.Carry() {
                t.Error("expected carry flag set for 3-5 (unsigned underflow)")
        }
}

func TestJNZ_Taken(t *testing.T) {
        e := NewEngine()
        // PUSH 42 (keep), PUSH 1 (test), JNZ target
        target := ProgramStart + 13
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 42)...)
        prog = append(prog, FormatA(PUSH, 1)...)
        prog = append(prog, FormatB(JNZ, target)...)
        prog = append(prog, HALT)
        for uint16(len(prog))+ProgramStart < target {
                prog = append(prog, NOP)
        }
        prog = append(prog, HALT)

        e.LoadProgram(prog)
        e.Step() // PUSH 42
        e.Step() // PUSH 1
        e.Step() // JNZ -> taken
        if e.PC != target {
                t.Errorf("expected PC 0x%04X after JNZ (taken), got 0x%04X", target, e.PC)
        }
        if e.stack.Depth() != 1 {
                t.Errorf("expected depth 1 after JNZ, got %d", e.stack.Depth())
        }
}

func TestJNZ_NotTaken(t *testing.T) {
        e := NewEngine()
        target := ProgramStart + 20
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 99)...)
        prog = append(prog, FormatA(PUSH, 0)...)
        prog = append(prog, FormatB(JNZ, target)...)
        prog = append(prog, HALT)

        e.LoadProgram(prog)
        e.Run()
        if !e.Halted {
                t.Error("expected halted (JNZ not taken, HALT executed)")
        }
}

func TestJC_Taken(t *testing.T) {
        e := NewEngine()
        // Set carry: PUSH 1, PUSH 2, SUB => 1-2 carry
        jcTarget := ProgramStart + 16
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 1)...)
        prog = append(prog, FormatA(PUSH, 2)...)
        prog = append(prog, SUB)
        prog = append(prog, FormatB(JC, jcTarget)...)
        prog = append(prog, HALT)
        for uint16(len(prog))+ProgramStart < jcTarget {
                prog = append(prog, NOP)
        }
        prog = append(prog, HALT)

        e.LoadProgram(prog)
        e.Run()
        if !e.Halted {
                t.Error("expected halted after JC taken + HALT at target")
        }
}

func TestJC_NotTaken(t *testing.T) {
        e := NewEngine()
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 5)...)
        prog = append(prog, FormatA(PUSH, 3)...)
        prog = append(prog, SUB)
        prog = append(prog, FormatB(JC, 0x0200)...)
        prog = append(prog, HALT)

        e.LoadProgram(prog)
        e.Run()
        if !e.Halted {
                t.Error("expected halted (JC not taken, HALT executed)")
        }
}

func TestSHL(t *testing.T) {
        e := NewEngine()
        // PUSH 4 (value=b), PUSH 1 (shift=a), SHL => b << a = 4 << 1 = 8
        prog := append(append(FormatA(PUSH, 4), FormatA(PUSH, 1)...), SHL, HALT)
        e.LoadProgram(prog)
        e.Run()
        val, _ := e.stack.Peek()
        if val != 8 {
                t.Errorf("expected 8 (4<<1), got %d", val)
        }
}

func TestSHL_LargeShift(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 42), FormatA(PUSH, 0)...), SHL, HALT)
        e.LoadProgram(prog)
        e.Run()
        val, _ := e.stack.Peek()
        if val != 42 {
                t.Errorf("expected 42 (42<<0), got %d", val)
        }
}

func TestSHR(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 16), FormatA(PUSH, 2)...), SHR, HALT)
        e.LoadProgram(prog)
        e.Run()
        val, _ := e.stack.Peek()
        if val != 4 {
                t.Errorf("expected 4 (16>>2), got %d", val)
        }
}

func TestSHR_Logical(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 0x80000000), FormatA(PUSH, 1)...), SHR, HALT)
        e.LoadProgram(prog)
        e.Run()
        val, _ := e.stack.Peek()
        if val != 0x40000000 {
                t.Errorf("expected 0x40000000 (0x80000000>>1), got 0x%08X", val)
        }
}

func TestDIV(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 15), FormatA(PUSH, 3)...), DIV, HALT)
        e.LoadProgram(prog)
        e.Run()
        val, _ := e.stack.Peek()
        if val != 5 {
                t.Errorf("expected 5 (15/3), got %d", val)
        }
}

func TestDIV_ByOne(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 42), FormatA(PUSH, 1)...), DIV, HALT)
        e.LoadProgram(prog)
        e.Run()
        val, _ := e.stack.Peek()
        if val != 42 {
                t.Errorf("expected 42 (42/1), got %d", val)
        }
}

func TestDIV_ByZero(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 42), FormatA(PUSH, 0)...), DIV, HALT)
        e.LoadProgram(prog)
        e.Run()
        if !e.Halted {
                t.Error("expected engine halted on division by zero")
        }
}

func TestSHR_ZeroFlag(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 1), FormatA(PUSH, 4)...), SHR, HALT)
        e.LoadProgram(prog)
        e.Run()
        if !e.regs.Zero() {
                t.Error("expected zero flag set after shifting 1 >> 4 = 0")
        }
}

func TestSHL_ZeroFlag(t *testing.T) {
        e := NewEngine()
        prog := append(append(FormatA(PUSH, 0), FormatA(PUSH, 1)...), SHL, HALT)
        e.LoadProgram(prog)
        e.Run()
        if !e.regs.Zero() {
                t.Error("expected zero flag set after shifting 0 << 1 = 0")
        }
}

func TestCMP_SubsequentJZ(t *testing.T) {
        e := NewEngine()
        jzTarget := ProgramStart + 5 + 5 + 1 + 5 + 3
        prog := make([]byte, 0)
        prog = append(prog, FormatA(PUSH, 5)...)
        prog = append(prog, FormatA(PUSH, 5)...)
        prog = append(prog, CMP)
        prog = append(prog, FormatA(PUSH, 0)...)
        prog = append(prog, FormatB(JZ, jzTarget)...)
        prog = append(prog, HALT)
        for uint16(len(prog))+ProgramStart < jzTarget {
                prog = append(prog, NOP)
        }
        prog = append(prog, HALT)

        e.LoadProgram(prog)
        e.Run()
        if !e.Halted {
                t.Error("expected halted after JZ taken to target HALT")
        }
}

// --- OpcodeWidth tests ---

func TestOpcodeWidth_NewOpcodes(t *testing.T) {
        if OpcodeWidth(CALL) != 3 {
                t.Errorf("expected CALL width 3, got %d", OpcodeWidth(CALL))
        }
        if OpcodeWidth(RET) != 1 {
                t.Errorf("expected RET width 1, got %d", OpcodeWidth(RET))
        }
        if OpcodeWidth(CMP) != 1 {
                t.Errorf("expected CMP width 1, got %d", OpcodeWidth(CMP))
        }
        if OpcodeWidth(JNZ) != 3 {
                t.Errorf("expected JNZ width 3, got %d", OpcodeWidth(JNZ))
        }
        if OpcodeWidth(JC) != 3 {
                t.Errorf("expected JC width 3, got %d", OpcodeWidth(JC))
        }
        if OpcodeWidth(SHL) != 1 {
                t.Errorf("expected SHL width 1, got %d", OpcodeWidth(SHL))
        }
        if OpcodeWidth(SHR) != 1 {
                t.Errorf("expected SHR width 1, got %d", OpcodeWidth(SHR))
        }
        if OpcodeWidth(DIV) != 1 {
                t.Errorf("expected DIV width 1, got %d", OpcodeWidth(DIV))
        }
}

// --- OpcodeTable completeness ---

func TestOpcodeTable_AllOpcodes(t *testing.T) {
        expected := []struct {
                code byte
                name string
        }{
                {NOP, "NOP"}, {PUSH, "PUSH"}, {POP, "POP"}, {DUP, "DUP"}, {SWAP, "SWAP"},
                {ADD, "ADD"}, {SUB, "SUB"}, {MUL, "MUL"}, {AND, "AND"}, {OR, "OR"},
                {XOR, "XOR"}, {NOT, "NOT"}, {JMP, "JMP"}, {JZ, "JZ"}, {LOAD, "LOAD"},
                {STORE, "STORE"}, {HALT, "HALT"},
                {CALL, "CALL"}, {RET, "RET"}, {CMP, "CMP"}, {JNZ, "JNZ"}, {JC, "JC"},
                {SHL, "SHL"}, {SHR, "SHR"}, {DIV, "DIV"},
        }
        if len(OpcodeTable) != 25 {
                t.Errorf("expected 25 opcodes in table, got %d", len(OpcodeTable))
        }
        for _, tc := range expected {
                if int(tc.code) >= len(OpcodeTable) {
                        t.Errorf("opcode 0x%02X (%s) out of table range", tc.code, tc.name)
                        continue
                }
                if OpcodeTable[tc.code].Name != tc.name {
                        t.Errorf("opcode 0x%02X: expected name %s, got %s", tc.code, tc.name, OpcodeTable[tc.code].Name)
                }
        }
}
