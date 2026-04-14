package conformance

import (
	"fmt"
	"strings"

	"github.com/SuperInstance/flux-tui/vm"
)

// Result represents the outcome of running a single test vector.
type Result struct {
	Name   string
	Pass   bool
	Reason string
	Actual string
}

// RunVector executes a single test vector and returns the result.
func RunVector(tv TestVector) Result {
	e := vm.NewEngine()
	_, err := e.LoadProgram(tv.Program)
	if err != nil {
		return Result{
			Name:   tv.Name,
			Pass:   false,
			Reason: fmt.Sprintf("load failed: %v", err),
		}
	}

	e.Run()

	actualStack := e.StackValues()
	halted := e.Halted

	if halted != tv.ExpectedHalted {
		return Result{
			Name:   tv.Name,
			Pass:   false,
			Reason: fmt.Sprintf("halted: expected %v, got %v", tv.ExpectedHalted, halted),
			Actual: fmt.Sprintf("stack=%s, halted=%v", fmtStack(actualStack), halted),
		}
	}

	if !stacksEqual(actualStack, tv.ExpectedStack) {
		return Result{
			Name:   tv.Name,
			Pass:   false,
			Reason: fmt.Sprintf("stack mismatch: expected %s, got %s", fmtStack(tv.ExpectedStack), fmtStack(actualStack)),
			Actual: fmt.Sprintf("stack=%s, halted=%v", fmtStack(actualStack), halted),
		}
	}

	if tv.ExpectedMemory != nil {
		for addr, expectedVal := range tv.ExpectedMemory {
			actualVal, err := e.Mem().LoadWord(addr)
			if err != nil || actualVal != expectedVal {
				return Result{
					Name:   tv.Name,
					Pass:   false,
					Reason: fmt.Sprintf("memory[0x%04X]: expected 0x%08X, got 0x%08X", addr, expectedVal, actualVal),
					Actual: fmt.Sprintf("stack=%s, halted=%v", fmtStack(actualStack), halted),
				}
			}
		}
	}

	return Result{
		Name:   tv.Name,
		Pass:   true,
		Actual: fmt.Sprintf("stack=%s, halted=%v", fmtStack(actualStack), halted),
	}
}

// RunAll executes all built-in test vectors and returns results.
func RunAll() []Result {
	vectors := GenerateBuiltinVectors()
	results := make([]Result, len(vectors))
	for i, tv := range vectors {
		results[i] = RunVector(tv)
	}
	return results
}

func stacksEqual(a, b []uint32) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func fmtStack(items []uint32) string {
	if len(items) == 0 {
		return "[]"
	}
	parts := make([]string, len(items))
	for i, v := range items {
		parts[i] = fmt.Sprintf("%d", v)
	}
	return "[" + strings.Join(parts, ", ") + "]"
}
