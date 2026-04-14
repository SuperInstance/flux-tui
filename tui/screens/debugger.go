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
	dbgModeBreakpoint // entering breakpoint address
	dbgModeMemAddr    // entering memory address
)

// DebuggerScreen is the full-featured VM debugger screen.
// It provides step/run debugging, register/stack/memory inspection,
// disassembly view, snapshot/restore, file loading, and command mode.
type DebuggerScreen struct {
	engine        *vm.Engine
	sourceCode    string
	sourceLines   []string
	width         int
	height        int
	errMsg        string
	inputMode     dbgMode
	inputBuf      string
	snapshot      *vm.EngineSnapshot
	snapshots     []*vm.EngineSnapshot // multi-snapshot list
	memAddr       uint16               // memory view base address
	memScrollMode bool                 // whether memory view can be navigated
}

// NewDebuggerScreen creates a new debugger screen.
func NewDebuggerScreen(engine *vm.Engine) DebuggerScreen {
	return DebuggerScreen{engine: engine}
}

// SetSize sets the available dimensions for the debugger screen.
func (m DebuggerScreen) SetSize(width, height int) {
	m.width = width
	m.height = height
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
	case dbgModeBreakpoint:
		return m.handleBreakpointInput(msg)
	case dbgModeMemAddr:
		return m.handleMemAddrInput(msg)
	}
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "s", "right":
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
	case "f": // Toggle breakpoint at current PC
		addr := m.engine.PC
		bm := m.engine.Breakpoints()
		added := bm.Toggle(addr)
		if added {
			m.errMsg = fmt.Sprintf("Breakpoint set at 0x%04X", addr)
		} else {
			m.errMsg = fmt.Sprintf("Breakpoint cleared at 0x%04X", addr)
		}
	case "F": // Clear all breakpoints
		m.engine.Breakpoints().Clear()
		m.errMsg = "All breakpoints cleared."
	case "c": // Continue (run, stop at breakpoint or halt)
		if m.engine.Halted {
			m.errMsg = "VM is halted. Press 'b' to reset."
		} else {
			m.engine.Run()
			if m.engine.Halted {
				m.errMsg = ""
			} else {
				m.errMsg = fmt.Sprintf("Breakpoint hit at 0x%04X", m.engine.PC)
			}
		}
	case "g": // Go to memory address
		m.inputMode = dbgModeMemAddr
		m.inputBuf = ""
		m.errMsg = ""
	case "N": // Save numbered snapshot
		snap := m.engine.Snapshot()
		m.snapshots = append(m.snapshots, snap)
		m.errMsg = fmt.Sprintf("Snapshot #%d saved.", len(m.snapshots))
	case "P": // List snapshots
		if len(m.snapshots) == 0 {
			m.errMsg = "No numbered snapshots. Press 'N' to save."
		} else {
			lines := []string{fmt.Sprintf("Snapshots: %d", len(m.snapshots))}
			for i := len(m.snapshots) - 1; i >= 0 && i >= len(m.snapshots)-5; i-- {
				lines = append(lines, fmt.Sprintf("  #%d: PC=0x%04X Steps=%d", i+1, m.snapshots[i].PC, m.snapshots[i].StepCount))
			}
			m.errMsg = strings.Join(lines, " | ")
		}
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

func (m DebuggerScreen) handleBreakpointInput(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.inputMode = dbgModeNormal
		m.inputBuf = ""
		m.errMsg = ""
	case "enter":
		addrStr := strings.TrimSpace(m.inputBuf)
		m.inputBuf = ""
		m.inputMode = dbgModeNormal
		if addrStr == "" {
			return m, nil
		}
		var addr uint16
		_, err := fmt.Sscanf(addrStr, "%x", &addr)
		if err != nil {
			m.errMsg = fmt.Sprintf("Invalid address: %s", addrStr)
			return m, nil
		}
		bm := m.engine.Breakpoints()
		added := bm.Toggle(addr)
		if added {
			m.errMsg = fmt.Sprintf("Breakpoint set at 0x%04X", addr)
		} else {
			m.errMsg = fmt.Sprintf("Breakpoint cleared at 0x%04X", addr)
		}
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

func (m DebuggerScreen) handleMemAddrInput(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.inputMode = dbgModeNormal
		m.inputBuf = ""
		m.errMsg = ""
	case "enter":
		addrStr := strings.TrimSpace(m.inputBuf)
		m.inputBuf = ""
		m.inputMode = dbgModeNormal
		if addrStr == "" {
			return m, nil
		}
		var addr uint16
		_, err := fmt.Sscanf(addrStr, "%x", &addr)
		if err != nil {
			m.errMsg = fmt.Sprintf("Invalid address: %s", addrStr)
			return m, nil
		}
		m.memAddr = addr
		m.memScrollMode = true
		m.errMsg = fmt.Sprintf("Memory view at 0x%04X", addr)
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

func executeDbgCommand(e *vm.Engine, cmd string) string {
	parts := strings.Fields(cmd)
	if len(parts) == 0 {
		return ""
	}
	switch parts[0] {
	case "help":
		return "Commands: step, run, continue, reset, stack, mem <addr>, regs, pc, bp <addr>, bplist, bpclear, snapshot, restore"
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
	case "continue":
		if e.Halted {
			return "VM is halted."
		}
		e.Run()
		if e.Halted {
			return ""
		}
		return fmt.Sprintf("Breakpoint hit at 0x%04X", e.PC)
	case "reset":
		e.Reset()
		return "Reset."
	case "snapshot":
		return "Use 'n' key to save snapshot."
	case "restore":
		return "Use 'p' key to restore snapshot."
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
	case "bp":
		if len(parts) < 2 {
			return "Usage: bp <addr>"
		}
		var addr uint16
		_, err := fmt.Sscanf(parts[1], "%x", &addr)
		if err != nil {
			return fmt.Sprintf("Invalid address: %s", parts[1])
		}
		bm := e.Breakpoints()
		added := bm.Toggle(addr)
		if added {
			return fmt.Sprintf("Breakpoint set at 0x%04X", addr)
		}
		return fmt.Sprintf("Breakpoint cleared at 0x%04X", addr)
	case "bplist":
		bpAddrs := e.Breakpoints().List()
		if len(bpAddrs) == 0 {
			return "No breakpoints."
		}
		lines := make([]string, len(bpAddrs))
		for i, addr := range bpAddrs {
			lines[i] = fmt.Sprintf("  0x%04X", addr)
		}
		return strings.Join(lines, "\n")
	case "bpclear":
		e.Breakpoints().Clear()
		return "All breakpoints cleared."
	case "goto":
		return "Use 'g' key to navigate memory view."
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

	status := "HALTED"
	statusStyle := styles.FailStyle
	if !m.engine.Halted {
		status = "RUNNING"
		statusStyle = styles.PassStyle
	}
	r := m.engine.Registers()
	flags := fmtDbgFlags(r)
	b.WriteString(styles.StatusLine.Render(
		fmt.Sprintf(" PC: 0x%04X  Step: %d  Flags: %s  %s", m.engine.PC, m.engine.Cycles, flags, statusStyle.Render(status)),
	))
	b.WriteString("\n")

	switch m.inputMode {
	case dbgModeLoad:
		b.WriteString(styles.Warning.Render(fmt.Sprintf(" Load file: %s_", m.inputBuf)))
		b.WriteString("\n")
	case dbgModeCommand:
		b.WriteString(styles.Warning.Render(fmt.Sprintf(":%s_", m.inputBuf)))
		b.WriteString("\n")
	case dbgModeBreakpoint:
		b.WriteString(styles.Warning.Render(fmt.Sprintf(" Breakpoint addr: 0x%s_", m.inputBuf)))
		b.WriteString("\n")
	case dbgModeMemAddr:
		b.WriteString(styles.Warning.Render(fmt.Sprintf(" Goto memory addr: 0x%s_", m.inputBuf)))
		b.WriteString("\n")
	}

	if m.errMsg != "" {
		if strings.Contains(m.errMsg, "saved") || strings.Contains(m.errMsg, "restored") || strings.Contains(m.errMsg, "Reset") || strings.Contains(m.errMsg, "cleared") {
			b.WriteString(styles.Success.Render(" " + m.errMsg))
		} else {
			b.WriteString(styles.Error.Render(" " + m.errMsg))
		}
		b.WriteString("\n")
	}

	if m.engine.ProgramLength() == 0 && m.sourceCode == "" {
		b.WriteString(styles.Dim.Render(" No program loaded. Press 'l' to load .fluxasm or use CLI: flux-tui program.fluxasm"))
		b.WriteString("\n")
	} else {
		availHeight := m.height - 7 // title + status + input + err + bottom bar + borders
		if m.inputMode != dbgModeNormal {
			availHeight--
		}
		if m.errMsg != "" {
			availHeight--
		}

		// Layout: registers(4 lines) + stack(6 lines) + memory(6 lines) + disassembly(rest)
		regH := 4
		stkH := 6
		memH := 6
		dasmH := availHeight - regH - stkH - memH - 4 // 4 for panel borders/padding
		if dasmH < 4 {
			dasmH = 4
			stkH = 4
			memH = 4
		}

		b.WriteString(renderDbgRegisters(m.engine, m.width))
		b.WriteString("\n")
		b.WriteString(renderDbgStack(m.engine, m.width, stkH))
		b.WriteString("\n")
		memBase := vm.ProgramStart
		if m.memScrollMode {
			memBase = m.memAddr
		}
		b.WriteString(renderDbgMemory(m.engine, m.width, memH, memBase))
		b.WriteString("\n")
		b.WriteString(renderDbgDisasm(m.engine, m.width, dasmH))
		b.WriteString("\n")
	}

	b.WriteString(styles.StatusLine.Render(dbgTrunc("[s]tep [r]un [c]ontinue [b]reak/reset [f]bp-toggle [g]oto-mem [n]snap [N]snap# [l]oad [:]cmd [q]uit", m.width)))
	return b.String()
}

func fmtDbgFlags(r *vm.Registers) string {
	f := [3]byte{'-', '-', '-'}
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
	b.WriteString(styles.PanelHeader.Render(" Registers "))
	b.WriteString("\n")
	b.WriteString(dbgTrunc(fmt.Sprintf("  PC:    0x%04X", r.PC), w-4))
	b.WriteString("\n")
	b.WriteString(dbgTrunc(fmt.Sprintf("  Flags: %s (0x%02X)  Z=%v  C=%v  O=%v", fmtDbgFlags(r), r.Flags, r.Zero(), r.Carry(), r.Overflow()), w-4))
	b.WriteString("\n")
	return styles.Border.Width(w).Height(3).Render(b.String())
}

func renderDbgStack(e *vm.Engine, w int, maxL int) string {
	items := e.StackValues()
	var b strings.Builder
	b.WriteString(styles.PanelHeader.Render(fmt.Sprintf(" Stack (%d items) ", len(items))))
	b.WriteString("\n")
	if len(items) == 0 {
		b.WriteString(styles.Dim.Render("  (empty)"))
		b.WriteString("\n")
	} else {
		start := len(items) - maxL
		if start < 0 {
			start = 0
		}
		if start > 0 {
			b.WriteString(styles.Dim.Render(fmt.Sprintf("  ... %d more above ...", start)))
			b.WriteString("\n")
		}
		for i := start; i < len(items); i++ {
			marker := "  "
			if i == len(items)-1 {
				marker = "> "
			}
			b.WriteString(dbgTrunc(fmt.Sprintf("%s[%d] 0x%08X (%d)", marker, i, items[i], items[i]), w-6))
			b.WriteString("\n")
		}
	}
	h := maxL + 2
	if len(items) == 0 {
		h = 3
	}
	if start := len(items) - maxL; start > 0 {
		h++
	}
	return styles.Border.Width(w).Height(h).Render(b.String())
}

func renderDbgMemory(e *vm.Engine, w int, maxL int, baseAddr uint16) string {
	mem := e.Mem()
	bpl := 8
	var b strings.Builder
	b.WriteString(styles.PanelHeader.Render(fmt.Sprintf(" Memory @ 0x%04X ", baseAddr)))
	b.WriteString("\n")
	for row := 0; row < maxL; row++ {
		addr := baseAddr + uint16(row*bpl)
		if int(addr) >= vm.MemorySize {
			break
		}
		b.WriteString(styles.AddrStyle.Render(fmt.Sprintf("%04X:", addr)))
		b.WriteString(" ")
		parts := make([]string, bpl)
		for col := 0; col < bpl; col++ {
			a := addr + uint16(col)
			if int(a) < vm.MemorySize {
				bt, _ := mem.Load(a)
				parts[col] = fmt.Sprintf("%02X", bt)
			} else {
				parts[col] = "  "
			}
		}
		b.WriteString(styles.HexByteStyle.Render(strings.Join(parts, " ")))
		if addr >= vm.ProgramStart && addr < vm.ProgramStart+uint16(e.ProgramLength()) {
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
			// Strip address prefix
			if len(dasm) > 12 && dasm[2] == 'x' {
				dasm = dasm[12:]
			}
			b.WriteString("  ")
			if addr == e.PC {
				b.WriteString(styles.CurrentLine.Render("> " + dasm))
			} else {
				b.WriteString(styles.InstructionStyle.Render(dasm))
			}
		}
		b.WriteString("\n")
	}
	return styles.Border.Width(w).Height(maxL+2).Render(b.String())
}

func extractAddrFromDasmLine(line string) uint16 {
	parts := strings.SplitN(line, ":", 2)
	if len(parts) < 2 {
		return 0
	}
	addrStr := strings.TrimSpace(parts[0])
	var addr uint16
	_, err := fmt.Sscanf(addrStr, "0x%x", &addr)
	if err != nil {
		return 0
	}
	return addr
}

func renderDbgDisasm(e *vm.Engine, w int, maxL int) string {
	var b strings.Builder
	b.WriteString(styles.PanelHeader.Render(" Disassembly "))
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
			lineAddr := extractAddrFromDasmLine(line)
			hasBP := e.Breakpoints().Has(lineAddr)
			isPC := (i == pcLine)
			if isPC && hasBP {
				pfx = ">>"
				b.WriteString(styles.CurrentLine.Render(pfx + line))
			} else if isPC {
				pfx = ">>"
				b.WriteString(styles.CurrentLine.Render(pfx + line))
			} else if hasBP {
				pfx = " *"
				b.WriteString(styles.Warning.Render(pfx + line))
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
