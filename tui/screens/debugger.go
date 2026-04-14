package screens

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/SuperInstance/flux-tui/assembler"
	"github.com/SuperInstance/flux-tui/tui/styles"
	"github.com/SuperInstance/flux-tui/vm"
)

// LoadDoneMsg is sent when an async file load completes.
type LoadDoneMsg struct {
	Source string
	Err    error
}

type dbgMode int

const (
	dbgModeNormal dbgMode = iota
	dbgModeLoad
	dbgModeCommand
)

// DebuggerScreen is the full-featured VM debugger screen.
type DebuggerScreen struct {
	engine      *vm.Engine
	sourceCode  string
	sourceLines []string
	width       int
	height      int
	errMsg      string
	inputMode   dbgMode
	inputBuf    string
	snapshot    *vm.EngineSnapshot
}

// NewDebuggerScreen creates a new debugger screen.
func NewDebuggerScreen(engine *vm.Engine) DebuggerScreen {
	return DebuggerScreen{engine: engine}
}

func (m DebuggerScreen) Init() tea.Cmd { return nil }

func (m DebuggerScreen) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
	case tea.KeyMsg:
		return m.handleKey(msg)
	case LoadDoneMsg:
		if msg.Err != nil {
			m.errMsg = fmt.Sprintf("load error: %v", msg.Err)
			m.inputMode = dbgModeNormal
			m.inputBuf = ""
			return m, nil
		}
		m.sourceCode = msg.Source
		m.sourceLines = strings.Split(msg.Source, "\n")
		code, errs := assembler.Assemble(msg.Source)
		if len(errs) > 0 {
			m.errMsg = errs[0].Error()
			m.inputMode = dbgModeNormal
			m.inputBuf = ""
			return m, nil
		}
		m.engine.Reset()
		m.engine.LoadProgram(code)
		m.errMsg = ""
		m.inputMode = dbgModeNormal
		m.inputBuf = ""
		return m, nil
	}
	return m, nil
}

func (m DebuggerScreen) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch m.inputMode {
	case dbgModeLoad:
		return m.handleLoadInput(msg)
	case dbgModeCommand:
		return m.handleCommandInput(msg)
	}
	switch msg.String() {
	case "ctrl+c", "q":
		return m, tea.Quit
	case "s":
		if m.engine.Halted {
			m.errMsg = "VM is halted. Press 'b' to reset."
		} else {
			m.engine.Step()
			m.errMsg = ""
		}
	case "r":
		if m.engine.Halted {
			m.errMsg = "VM is halted. Press 'b' to reset."
		} else {
			m.engine.Run()
			m.errMsg = ""
		}
	case "b":
		m.engine.Reset()
		m.errMsg = ""
	case "n":
		m.snapshot = m.engine.Snapshot()
		m.errMsg = "Snapshot saved."
	case "p":
		if m.snapshot == nil {
			m.errMsg = "No snapshot. Press 'n' to save one."
		} else {
			m.engine.Restore(m.snapshot)
			m.errMsg = "Snapshot restored."
		}
	case "l":
		m.inputMode = dbgModeLoad
		m.inputBuf = ""
		m.errMsg = ""
	case ":":
		m.inputMode = dbgModeCommand
		m.inputBuf = ""
		m.errMsg = ""
	}
	return m, nil
}

func (m DebuggerScreen) handleLoadInput(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.inputMode = dbgModeNormal
		m.inputBuf = ""
		m.errMsg = ""
	case "enter":
		path := strings.TrimSpace(m.inputBuf)
		if path == "" {
			m.inputMode = dbgModeNormal
			return m, nil
		}
		m.inputBuf = ""
		return m, loadFileCmd(path)
	case "backspace":
		if len(m.inputBuf) > 0 {
			m.inputBuf = m.inputBuf[:len(m.inputBuf)-1]
		}
	default:
		if len(msg.String()) == 1 {
			m.inputBuf += msg.String()
		}
	}
	return m, nil
}

func (m DebuggerScreen) handleCommandInput(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.inputMode = dbgModeNormal
		m.inputBuf = ""
		m.errMsg = ""
	case "enter":
		cmd := strings.TrimSpace(m.inputBuf)
		m.inputBuf = ""
		m.inputMode = dbgModeNormal
		m.errMsg = executeDbgCommand(m.engine, cmd)
	default:
		if len(msg.String()) == 1 {
			m.inputBuf += msg.String()
		}
	}
	return m, nil
}

func executeDbgCommand(e *vm.Engine, cmd string) string {
	parts := strings.Fields(cmd)
	if len(parts) == 0 {
		return ""
	}
	switch parts[0] {
	case "help":
		return "Commands: step, run, reset, stack, mem <addr>, regs, pc"
	case "step":
		if e.Halted {
			return "VM is halted."
		}
		e.Step()
		return ""
	case "run":
		if e.Halted {
			return "VM is halted."
		}
		e.Run()
		return ""
	case "reset":
		e.Reset()
		return "Reset."
	case "stack":
		items := e.StackValues()
		if len(items) == 0 {
			return "Stack is empty."
		}
		lines := make([]string, len(items))
		for i, v := range items {
			lines[i] = fmt.Sprintf("  [%d] 0x%08X (%d)", i, v, v)
		}
		return strings.Join(lines, "\n")
	case "mem":
		if len(parts) < 2 {
			return "Usage: mem <addr>"
		}
		var addr uint16
		fmt.Sscanf(parts[1], "%x", &addr)
		val, err := e.Mem().LoadWord(addr)
		if err != nil {
			return fmt.Sprintf("Error: %v", err)
		}
		return fmt.Sprintf("Memory[0x%04X] = 0x%08X (%d)", addr, val, val)
	case "regs":
		r := e.Registers()
		return fmt.Sprintf("PC=0x%04X Flags=0x%02X Z=%v C=%v O=%v", r.PC, r.Flags, r.Zero(), r.Carry(), r.Overflow())
	case "pc":
		return fmt.Sprintf("PC = 0x%04X", e.PC)
	default:
		return fmt.Sprintf("Unknown command: %s", parts[0])
	}
}

func loadFileCmd(path string) tea.Cmd {
	return func() tea.Msg {
		data, err := os.ReadFile(path)
		if err != nil {
			return LoadDoneMsg{Err: err}
		}
		return LoadDoneMsg{Source: string(data)}
	}
}

func (m DebuggerScreen) View() string {
	if m.width == 0 {
		m.width = 80
	}
	if m.height == 0 {
		m.height = 24
	}
	var b strings.Builder

	b.WriteString(styles.Title.Render(" FLUX VM Debugger "))
	b.WriteString("\n")

	status := "Halted"
	if !m.engine.Halted {
		status = "Running"
	}
	r := m.engine.Registers()
	flags := fmtDbgFlags(r)
	b.WriteString(styles.StatusLine.Render(fmt.Sprintf("PC: 0x%04X  Step: %d  Flags: %s  Status: %s", m.engine.PC, m.engine.Cycles, flags, status)))
	b.WriteString("\n")

	switch m.inputMode {
	case dbgModeLoad:
		b.WriteString(styles.Warning.Render(fmt.Sprintf("Load file: %s_", m.inputBuf)))
		b.WriteString("\n")
	case dbgModeCommand:
		b.WriteString(styles.Warning.Render(fmt.Sprintf(":%s_", m.inputBuf)))
		b.WriteString("\n")
	}

	if m.errMsg != "" {
		if strings.Contains(m.errMsg, "saved") || strings.Contains(m.errMsg, "restored") || strings.Contains(m.errMsg, "Reset") {
			b.WriteString(styles.Success.Render(m.errMsg))
		} else {
			b.WriteString(styles.Error.Render(m.errMsg))
		}
		b.WriteString("\n")
	}

	if m.engine.ProgramLength() == 0 && m.sourceCode == "" {
		b.WriteString(styles.Dim.Render("No program loaded. Press 'l' to load assembly or binary."))
		b.WriteString("\n")
	} else {
		uh := m.height - 8
		if uh < 10 {
			uh = 10
		}
		b.WriteString(renderDbgRegisters(m.engine, m.width))
		b.WriteString("\n")
		sh := 6
		if uh < 20 {
			sh = 4
		}
		b.WriteString(renderDbgStack(m.engine, m.width, sh))
		b.WriteString("\n")
		mh := 4
		if uh > 24 {
			mh = 8
		}
		b.WriteString(renderDbgMemory(m.engine, m.width, mh))
		b.WriteString("\n")
		dh := uh - 22
		if dh < 4 {
			dh = 4
		}
		b.WriteString(renderDbgDisasm(m.engine, m.width, dh))
		b.WriteString("\n")
	}

	b.WriteString(styles.StatusLine.Render(dbgTrunc("[s]tep [r]un [b]reak/reset [n]snapshot [p]restore [l]oad [:]cmd [q]uit", m.width)))
	return b.String()
}

func fmtDbgFlags(r *vm.Registers) string {
	f := [4]byte{'-', '-', '-', '-'}
	if r.Zero() {
		f[0] = 'Z'
	}
	if r.Carry() {
		f[1] = 'C'
	}
	if r.Overflow() {
		f[2] = 'O'
	}
	return string(f[:])
}

func renderDbgRegisters(e *vm.Engine, w int) string {
	r := e.Registers()
	var b strings.Builder
	b.WriteString(styles.PanelHeader.Render("─ Registers "))
	b.WriteString("\n")
	b.WriteString(dbgTrunc(fmt.Sprintf("  PC: 0x%04X", r.PC), w-4))
	b.WriteString("\n")
	b.WriteString(dbgTrunc(fmt.Sprintf("  Flags: %s (0x%02X)", fmtDbgFlags(r), r.Flags), w-4))
	b.WriteString("\n")
	b.WriteString(dbgTrunc(fmt.Sprintf("  Zero: %v  Carry: %v  Overflow: %v", r.Zero(), r.Carry(), r.Overflow()), w-4))
	b.WriteString("\n")
	return styles.Border.Width(w).Height(4).Render(b.String())
}

func renderDbgStack(e *vm.Engine, w int, maxL int) string {
	items := e.StackValues()
	var b strings.Builder
	b.WriteString(styles.PanelHeader.Render("─ Stack "))
	b.WriteString("\n")
	if len(items) == 0 {
		b.WriteString(styles.Dim.Render("  (empty)"))
		b.WriteString("\n")
	} else {
		start := len(items) - maxL
		if start < 0 {
			start = 0
		}
		for i := start; i < len(items); i++ {
			b.WriteString(dbgTrunc(fmt.Sprintf("  [%d] 0x%08X (%d)", i, items[i], items[i]), w-6))
			b.WriteString("\n")
		}
	}
	h := maxL + 2
	if len(items) == 0 {
		h = 3
	}
	return styles.Border.Width(w).Height(h).Render(b.String())
}

func renderDbgMemory(e *vm.Engine, w int, maxL int) string {
	mem := e.Mem()
	bpl := 8
	var b strings.Builder
	b.WriteString(styles.PanelHeader.Render(fmt.Sprintf("─ Memory (0x%04X) ", vm.ProgramStart)))
	b.WriteString("\n")
	for row := 0; row < maxL; row++ {
		addr := vm.ProgramStart + uint16(row*bpl)
		b.WriteString(styles.AddrStyle.Render(fmt.Sprintf("%04X:", addr)))
		b.WriteString(" ")
		parts := make([]string, bpl)
		for col := 0; col < bpl; col++ {
			a := addr + uint16(col)
			if a < vm.ProgramStart+uint16(e.ProgramLength()) {
				bt, _ := mem.Load(a)
				parts[col] = fmt.Sprintf("%02X", bt)
			} else {
				parts[col] = "  "
			}
		}
		b.WriteString(styles.HexByteStyle.Render(strings.Join(parts, " ")))
		if addr < vm.ProgramStart+uint16(e.ProgramLength()) {
			data := mem.LoadRange(addr, bpl)
			el := bpl
			rem := e.ProgramLength() - int(addr-vm.ProgramStart)
			if rem < el {
				el = rem
			}
			dasm := assembler.Disassemble(data[:el], addr)
			if idx := strings.Index(dasm, "\n"); idx >= 0 {
				dasm = dasm[:idx]
			}
			dasm = strings.TrimSpace(dasm)
			if len(dasm) > 12 {
				dasm = dasm[12:]
			}
			b.WriteString("  ")
			if addr == e.PC {
				b.WriteString(styles.CurrentLine.Render("▸ " + dasm))
			} else {
				b.WriteString(styles.InstructionStyle.Render(dasm))
			}
		}
		b.WriteString("\n")
	}
	return styles.Border.Width(w).Height(maxL+2).Render(b.String())
}

func renderDbgDisasm(e *vm.Engine, w int, maxL int) string {
	var b strings.Builder
	b.WriteString(styles.PanelHeader.Render("─ Disassembly "))
	b.WriteString("\n")
	if e.ProgramLength() == 0 {
		b.WriteString(styles.Dim.Render("  (no program)"))
		b.WriteString("\n")
	} else {
		mem := e.Mem()
		data := mem.LoadRange(vm.ProgramStart, e.ProgramLength())
		dasm := assembler.Disassemble(data, vm.ProgramStart)
		lines := strings.Split(strings.TrimSpace(dasm), "\n")
		pcLine := -1
		for i, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, fmt.Sprintf("  0x%04X:", e.PC)) {
				pcLine = i
				break
			}
		}
		sl := 0
		if pcLine >= 0 && pcLine > maxL-2 {
			sl = pcLine - maxL + 2
		}
		el := sl + maxL
		if el > len(lines) {
			el = len(lines)
		}
		for i := sl; i < el; i++ {
			line := strings.TrimSpace(lines[i])
			pfx := "  "
			if i == pcLine {
				pfx = "▶ "
				b.WriteString(styles.CurrentLine.Render(pfx + line))
			} else {
				b.WriteString(styles.InstructionStyle.Render(pfx + line))
			}
			b.WriteString("\n")
		}
	}
	return styles.Border.Width(w).Height(maxL+2).Render(b.String())
}

func dbgTrunc(s string, n int) string {
	if n <= 0 {
		return ""
	}
	if len(s) <= n {
		return s
	}
	return s[:n]
}
