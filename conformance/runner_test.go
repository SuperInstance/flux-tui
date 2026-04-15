package conformance

import "testing"

func TestRunAllBuiltinVectors(t *testing.T) {
        vectors := GenerateBuiltinVectors()
        if len(vectors) < 31 {
                t.Errorf("expected at least 31 builtin vectors, got %d", len(vectors))
        }
        results := RunVectors(vectors)
        passed := 0
        failed := 0
        for _, r := range results {
                if r.Pass {
                        passed++
                } else {
                        failed++
                        t.Errorf("FAIL: %s — %s (actual: %s)", r.Name, r.Reason, r.Actual)
                }
        }
        t.Logf("Builtin vectors: %d/%d passed, %d failed", passed, len(vectors), failed)
        if failed > 0 {
                t.Errorf("%d builtin vectors failed", failed)
        }
}

func TestRunVector_NOP(t *testing.T) {
        tv := TestVector{
                Name:           "nop",
                Program:        []byte{0x00, 0x10}, // NOP, HALT
                ExpectedHalted: true,
        }
        r := RunVector(tv)
        if !r.Pass {
                t.Errorf("NOP vector failed: %s", r.Reason)
        }
}

func TestRunVector_Factorial5(t *testing.T) {
        tv := TestVector{
                Name:           "factorial5",
                Program:        buildFactorial5(),
                ExpectedStack:  []uint32{120},
                ExpectedHalted: true,
        }
        r := RunVector(tv)
        if !r.Pass {
                t.Errorf("factorial5 vector failed: %s (actual: %s)", r.Reason, r.Actual)
        }
}

func TestRunVector_CallRetNested(t *testing.T) {
        tv := TestVector{
                Name:           "call_ret_nested",
                Program:        buildCallRetNested(),
                ExpectedStack:  []uint32{10, 50},
                ExpectedHalted: true,
        }
        r := RunVector(tv)
        if !r.Pass {
                t.Errorf("call_ret_nested vector failed: %s (actual: %s)", r.Reason, r.Actual)
        }
}

func TestSummary(t *testing.T) {
        results := []Result{
                {Name: "a", Pass: true},
                {Name: "b", Pass: true},
                {Name: "c", Pass: false, Reason: "stack mismatch"},
        }
        s := Summary(results)
        if s != "Total: 3  Passed: 2  Failed: 1" {
                t.Errorf("unexpected summary: %s", s)
        }
}

func TestStacksEqual(t *testing.T) {
        if !stacksEqual([]uint32{1, 2, 3}, []uint32{1, 2, 3}) {
                t.Error("expected equal")
        }
        if stacksEqual([]uint32{1, 2}, []uint32{1, 2, 3}) {
                t.Error("expected not equal for different lengths")
        }
        if stacksEqual([]uint32{1, 2}, []uint32{1, 3}) {
                t.Error("expected not equal for different values")
        }
}
