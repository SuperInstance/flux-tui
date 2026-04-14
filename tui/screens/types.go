// Package screens defines the screen types and models for the FLUX TUI.
package screens

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/SuperInstance/flux-tui/vm"
)

// ScreenType identifies different screens in the TUI.
type ScreenType int

const (
	ScreenDebugger ScreenType = iota
	ScreenMemory
	ScreenStack
	ScreenSource
	ScreenOutput
	ScreenHelp
	ScreenCount
)

// ScreenNames maps ScreenType to human-readable names.
var ScreenNames = map[ScreenType]string{
	ScreenDebugger: "Debugger",
	ScreenMemory:   "Memory",
	ScreenStack:    "Stack",
	ScreenSource:   "Source",
	ScreenOutput:   "Output",
	ScreenHelp:     "Help",
}

// ScreenOrder defines the tab order for cycling through screens.
var ScreenOrder = []ScreenType{
	ScreenDebugger,
	ScreenMemory,
	ScreenStack,
	ScreenSource,
	ScreenOutput,
	ScreenHelp,
}

// NextScreen returns the next screen in the cycle.
func NextScreen(current ScreenType) ScreenType {
	for i, s := range ScreenOrder {
		if s == current {
			if i+1 < len(ScreenOrder) {
				return ScreenOrder[i+1]
			}
			return ScreenOrder[0]
		}
	}
	return ScreenDebugger
}

// PrevScreen returns the previous screen in the cycle.
func PrevScreen(current ScreenType) ScreenType {
	for i, s := range ScreenOrder {
		if s == current {
			if i > 0 {
				return ScreenOrder[i-1]
			}
			return ScreenOrder[len(ScreenOrder)-1]
		}
	}
	return ScreenDebugger
}

// DisplayName returns the human-readable name for a screen type.
func (s ScreenType) DisplayName() string {
	if name, ok := ScreenNames[s]; ok {
		return name
	}
	return "Unknown"
}

// --- Screen models ---

// NewDebuggerModel creates a new debugger screen model.
func NewDebuggerModel(engine *vm.Engine) tea.Model {
	return &debuggerModel{engine: engine}
}

type debuggerModel struct {
	engine *vm.Engine
	width  int
	height int
}

func (m *debuggerModel) Init() tea.Cmd { return nil }

func (m *debuggerModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if msg, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = msg.Width
		m.height = msg.Height
	}
	return m, nil
}

func (m *debuggerModel) View() string {
	stack := m.engine.StackValues()
	stackStr := "(empty)"
	if len(stack) > 0 {
		stackStr = fmt.Sprintf("%v", stack)
	}
	return fmt.Sprintf(
		" Debugger\n\n"+
			"  PC:     0x%04X\n"+
			"  Halted: %v\n"+
			"  Cycles: %d\n"+
			"  Stack:  %s\n\n"+
			"  Tab: switch screens | q: quit",
		m.engine.PC,
		m.engine.Halted,
		m.engine.Cycles,
		stackStr,
	)
}

// NewMemoryModel creates a new memory view screen model.
func NewMemoryModel(engine *vm.Engine) tea.Model {
	return &memoryModel{engine: engine}
}

type memoryModel struct {
	engine *vm.Engine
	width  int
	height int
}

func (m *memoryModel) Init() tea.Cmd { return nil }

func (m *memoryModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if msg, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = msg.Width
		m.height = msg.Height
	}
	return m, nil
}

func (m *memoryModel) View() string {
	lines := " Memory View\n\n"
	mem := m.engine.Mem()
	start := vm.ProgramStart
	end := start + uint16(m.engine.ProgramLength())
	for addr := start; addr < end && addr < start+256; addr++ {
		b, _ := mem.Load(addr)
		if b != 0 {
			lines += fmt.Sprintf("  0x%04X: 0x%02X\n", addr, b)
		}
	}
	lines += "\n  Tab: switch screens | q: quit"
	return lines
}

// NewStackModel creates a new stack view screen model.
func NewStackModel(engine *vm.Engine) tea.Model {
	return &stackModel{engine: engine}
}

type stackModel struct {
	engine *vm.Engine
	width  int
	height int
}

func (m *stackModel) Init() tea.Cmd { return nil }

func (m *stackModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if msg, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = msg.Width
		m.height = msg.Height
	}
	return m, nil
}

func (m *stackModel) View() string {
	lines := " Stack View\n\n"
	stack := m.engine.StackValues()
	if len(stack) == 0 {
		lines += "  (empty)"
	} else {
		for i, val := range stack {
			lines += fmt.Sprintf("  [%d] 0x%08X (%d)\n", i, val, val)
		}
	}
	lines += "\n  Tab: switch screens | q: quit"
	return lines
}

// NewSourceModel creates a new source view screen model.
func NewSourceModel(engine *vm.Engine) tea.Model {
	return &sourceModel{engine: engine}
}

type sourceModel struct {
	engine *vm.Engine
	width  int
	height int
}

func (m *sourceModel) Init() tea.Cmd { return nil }

func (m *sourceModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if msg, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = msg.Width
		m.height = msg.Height
	}
	return m, nil
}

func (m *sourceModel) View() string {
	return " Source View\n\n  (No source loaded)\n\n  Tab: switch screens | q: quit"
}

// NewOutputModel creates a new output screen model.
func NewOutputModel(engine *vm.Engine) tea.Model {
	return &outputModel{engine: engine}
}

type outputModel struct {
	engine *vm.Engine
	width  int
	height int
}

func (m *outputModel) Init() tea.Cmd { return nil }

func (m *outputModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if msg, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = msg.Width
		m.height = msg.Height
	}
	return m, nil
}

func (m *outputModel) View() string {
	return " Output\n\n  (No output)\n\n  Tab: switch screens | q: quit"
}

// NewHelpModel creates a new help screen model.
func NewHelpModel(engine *vm.Engine) tea.Model {
	return &helpModel{engine: engine}
}

type helpModel struct {
	engine *vm.Engine
	width  int
	height int
}

func (m *helpModel) Init() tea.Cmd { return nil }

func (m *helpModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if msg, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = msg.Width
		m.height = msg.Height
	}
	return m, nil
}

func (m *helpModel) View() string {
	return ` Help

 Key Bindings:
   Tab/Shift+Tab  Cycle through screens
   q/Ctrl+C       Quit

 Assembly Syntax:
   PUSH <value>    Push value onto stack
   POP             Pop top of stack
   DUP             Duplicate top of stack
   SWAP            Swap top two stack items
   ADD/SUB/MUL     Arithmetic operations
   AND/OR/XOR/NOT  Bitwise operations
   JMP <label>     Unconditional jump
   JZ <label>      Jump if top of stack is zero
   LOAD <addr>     Load from memory
   STORE <addr>    Store to memory
   HALT            Stop execution

   Labels:  name:
   Comments: ; or #

 Tab: switch screens | q: quit
`
}
