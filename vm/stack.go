package vm

import (
        "fmt"
)

// StackSize defines the maximum number of entries on the stack.
const StackSize = 256

// Stack is a LIFO stack of uint32 values used by the VM.
type Stack struct {
        items [StackSize]uint32
        sp    int // stack pointer: index of next free slot; 0 = empty
}

// NewStack creates and returns a new empty Stack.
func NewStack() *Stack {
        return &Stack{}
}

// Push pushes a value onto the stack.
// Returns an error if the stack is full (overflow).
func (s *Stack) Push(val uint32) error {
        if s.sp >= StackSize {
                return fmt.Errorf("stack overflow: cannot push, stack has %d items", StackSize)
        }
        s.items[s.sp] = val
        s.sp++
        return nil
}

// Pop removes and returns the top value from the stack.
// Returns an error if the stack is empty (underflow).
func (s *Stack) Pop() (uint32, error) {
        if s.sp <= 0 {
                return 0, fmt.Errorf("stack underflow: cannot pop from empty stack")
        }
        s.sp--
        val := s.items[s.sp]
        s.items[s.sp] = 0 // zero out for cleanliness
        return val, nil
}

// Peek returns the top value from the stack without removing it.
// Returns an error if the stack is empty.
func (s *Stack) Peek() (uint32, error) {
        if s.sp <= 0 {
                return 0, fmt.Errorf("stack underflow: cannot peek empty stack")
        }
        return s.items[s.sp-1], nil
}

// Depth returns the current number of items on the stack.
func (s *Stack) Depth() int {
        return s.sp
}

// Dup duplicates the top value on the stack.
// Returns an error if the stack is empty or full.
func (s *Stack) Dup() error {
        if s.sp <= 0 {
                return fmt.Errorf("stack underflow: cannot dup from empty stack")
        }
        if s.sp >= StackSize {
                return fmt.Errorf("stack overflow: cannot dup, stack has %d items", StackSize)
        }
        val := s.items[s.sp-1]
        s.items[s.sp] = val
        s.sp++
        return nil
}

// Swap exchanges the top two values on the stack.
// Returns an error if fewer than two items are on the stack.
func (s *Stack) Swap() error {
        if s.sp < 2 {
                return fmt.Errorf("stack underflow: cannot swap, need at least 2 items, have %d", s.sp)
        }
        s.items[s.sp-1], s.items[s.sp-2] = s.items[s.sp-2], s.items[s.sp-1]
        return nil
}

// Clear removes all items from the stack.
func (s *Stack) Clear() {
        for i := range s.items {
                s.items[i] = 0
        }
        s.sp = 0
}

// Items returns a copy of the current stack items from bottom to top.
func (s *Stack) Items() []uint32 {
        result := make([]uint32, s.sp)
        copy(result, s.items[:s.sp])
        return result
}
