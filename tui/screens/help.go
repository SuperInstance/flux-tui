package screens

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/SuperInstance/flux-tui/tui/styles"
)

// HelpScreen is the help and information screen.
// It documents all keybindings, screen descriptions, and the FLUX ISA.
type HelpScreen struct {
	scroll int
	width  int
	height int
}

// NewHelpScreen creates a new help screen.
func NewHelpScreen() HelpScreen {
	return HelpScreen{}
}

// SetSize sets the available dimensions for the help screen.
func (m HelpScreen) SetSize(width, height int) {
	m.width = width
	m.height = height
}

// helpContent returns the full help text as a slice of lines.
func helpContent() []string {
	return []string{
		"",
		"  FLUX VM Debugger - Help",
		"  =============================",
		"",
		"OVERVIEW",
		"  ----------------------------------------",
		"  The FLUX TUI is a terminal-based debugger",
		"  for the FLUX bytecode virtual machine.",
		"  It provides real-time inspection of the",
		"  operand stack, memory, and disassembled",
		"  instructions as you step through code.",
		"",
		"SCREENS (Tab / Shift+Tab to cycle)",
		"  ----------------------------------------",
		"  Debugger        Main VM step/run debugger",
		"                  with register, stack, memory",
		"                  and disassembly views",
		"  Conformance     Run test vectors against VM",
		"                  and verify pass/fail results",
		"  Inspector       Hex dump view of program",
		"                  memory with ASCII preview",
		"  Reference       Browse all 17 VM opcodes,",
		"                  encoding formats, semantics",
		"  Help            This screen",
		"",
		"DEBUGGER KEY BINDINGS",
		"  ----------------------------------------",
		"  s / Right       Step one instruction",
		"  r               Run until HALT",
		"  b               Reset (break) VM to start",
		"  n               Save snapshot of VM state",
		"  p               Restore last snapshot",
		"  l               Load .fluxasm assembly file",
		"  :               Enter command mode",
		"  q / Ctrl+C      Quit",
		"",
		"COMMANDS (in : mode)",
		"  ----------------------------------------",
		"  step            Execute one instruction",
		"  run             Run until HALT",
		"  reset           Reset the VM",
		"  stack           Show stack contents",
		"  mem <addr>      Read memory word at addr",
		"  regs            Show register state",
		"  pc              Show program counter",
		"  help            Show available commands",
		"",
		"INSPECTOR KEY BINDINGS",
		"  ----------------------------------------",
		"  Up/Down or j/k  Scroll one line",
		"  PgUp/PgDn       Scroll one page",
		"  Home/End        Jump to start/end",
		"  q               Back to debugger",
		"",
		"CONFORMANCE KEY BINDINGS",
		"  ----------------------------------------",
		"  Enter or r      Run all test vectors",
		"  Up/Down or j/k  Navigate test list",
		"  PgUp/PgDn       Jump in list",
		"  Home/End        Jump to first/last",
		"  e               Load external vectors",
		"  q               Back to debugger",
		"",
		"REFERENCE KEY BINDINGS",
		"  ----------------------------------------",
		"  Up/Down or j/k  Scroll opcode list",
		"  PgUp/PgDn       Scroll one page",
		"  Home/End        Jump to start/end",
		"  /               Enter filter mode",
		"  Esc             Clear filter",
		"  q               Back to debugger",
		"",
		"FLUX ISA v1 - OPCODE MAP",
		"  ----------------------------------------",
		"  0x00 NOP          No operation",
		"  0x01 PUSH imm32   Push 4-byte immediate",
		"  0x02 POP           Pop top of stack",
		"  0x03 DUP           Duplicate top of stack",
		"  0x04 SWAP          Swap top two values",
		"  0x05 ADD           Pop two, push sum",
		"  0x06 SUB           Pop two, push b-a",
		"  0x07 MUL           Pop two, push product",
		"  0x08 AND           Pop two, push bitwise AND",
		"  0x09 OR            Pop two, push bitwise OR",
		"  0x0A XOR           Pop two, push bitwise XOR",
		"  0x0B NOT           Pop one, push bitwise NOT",
		"  0x0C JMP addr16    Unconditional jump",
		"  0x0D JZ addr16     Jump if top of stack = 0",
		"  0x0E LOAD addr16   Load word from memory",
		"  0x0F STORE addr16  Store word to memory",
		"  0x10 HALT          Stop execution",
		"",
		"INSTRUCTION ENCODING",
		"  ----------------------------------------",
		"  Format A (PUSH):    [opcode][b3][b2][b1][b0]",
		"                       1 + 4 = 5 bytes",
		"  Format B (JMP/JZ/  [opcode][hi][lo]",
		"    LOAD/STORE):      1 + 2 = 3 bytes",
		"  No-operand:         [opcode]           1 byte",
		"",
		"  All values are big-endian.",
		"  Program loads at 0x0100.",
		"  Stack: 256 entries, LIFO, upward growth.",
		"  Memory: 64KB byte-addressable.",
		"  Flags: Z(ero), C(arry), O(verflow).",
		"",
		"ASSEMBLY SYNTAX",
		"  ----------------------------------------",
		"  PUSH <value>    ; push immediate (dec/hex)",
		"  POP             ; pop and discard",
		"  DUP             ; duplicate top",
		"  SWAP            ; swap top two",
		"  ADD             ; a + b -> stack",
		"  SUB             ; b - a -> stack",
		"  MUL             ; a * b -> stack",
		"  AND/OR/XOR/NOT  ; bitwise ops",
		"  JMP <label|addr>",
		"  JZ <label|addr> ; jump if top = 0",
		"  LOAD <addr>     ; load word from memory",
		"  STORE <addr>    ; store word to memory",
		"  HALT            ; stop execution",
		"",
		"  Labels:   name:        (at start of line)",
		"  Comments: ; or #        (to end of line)",
		"  Numbers:  42, 0xFF, -1  (decimal, hex, neg)",
		"",
	}
}

// Init initializes the help screen.
func (m HelpScreen) Init() tea.Cmd {
	return nil
}

// Update handles messages for the help screen.
func (m HelpScreen) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		lines := helpContent()
		maxScroll := helpMax(0, len(lines)-m.height+4)

		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "up", "k":
			if m.scroll > 0 {
				m.scroll--
			}
		case "down", "j":
			if m.scroll < maxScroll {
				m.scroll++
			}
		case "pgup":
			m.scroll -= m.height - 4
			if m.scroll < 0 {
				m.scroll = 0
			}
		case "pgdown":
			m.scroll += m.height - 4
			if m.scroll > maxScroll {
				m.scroll = maxScroll
			}
		case "home":
			m.scroll = 0
		case "end":
			m.scroll = maxScroll
		}
	}
	return m, nil
}

// View renders the help screen.
func (m HelpScreen) View() string {
	if m.width == 0 {
		m.width = 80
	}
	if m.height == 0 {
		m.height = 24
	}

	var b strings.Builder

	b.WriteString(styles.Title.Render(" Help "))
	b.WriteString("\n")

	lines := helpContent()
	visibleLines := m.height - 4
	if visibleLines < 4 {
		visibleLines = 4
	}

	if m.scroll+visibleLines > len(lines) {
		m.scroll = helpMax(0, len(lines)-visibleLines)
	}

	for i := m.scroll; i < m.scroll+visibleLines && i < len(lines); i++ {
		line := lines[i]
		switch {
		case line == "":
			b.WriteString(line)
		case strings.HasPrefix(line, "  FLUX VM") || strings.HasPrefix(line, "  ="):
			b.WriteString(styles.Subtitle.Render(line))
		case strings.HasPrefix(line, "OVERVIEW") || strings.HasPrefix(line, "SCREENS") ||
			strings.Contains(line, "KEY BINDINGS") ||
			strings.HasPrefix(line, "COMMANDS") ||
			strings.HasPrefix(line, "FLUX ISA") ||
			strings.HasPrefix(line, "INSTRUCTION") ||
			strings.HasPrefix(line, "ASSEMBLY"):
			b.WriteString(styles.Subtitle.Render("  " + line))
		case strings.HasPrefix(line, "  ---"):
			b.WriteString(styles.Dim.Render(line))
		default:
			b.WriteString(styles.HelpDesc.Render(helpTruncate(line, m.width-2)))
		}
		b.WriteString("\n")
	}

	// Scroll indicator
	totalLines := len(lines)
	if totalLines > visibleLines {
		scrollPct := 100
		if totalLines > visibleLines {
			scrollPct = (m.scroll * 100) / (totalLines - visibleLines)
		}
		b.WriteString(styles.Dim.Render(fmt.Sprintf("  -- %d%% --", scrollPct)))
		b.WriteString("\n")
	}

	b.WriteString(styles.StatusLine.Render("[j/k or Up/Down] Scroll  [PgUp/PgDn] Page  [Home/End]  [q] Back"))

	return b.String()
}

func helpTruncate(s string, maxLen int) string {
	if maxLen <= 0 {
		return ""
	}
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen]
}

func helpMax(a, b int) int {
	if a > b {
		return a
	}
	return b
}
