package screens

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/SuperInstance/flux-tui/tui/styles"
	"github.com/SuperInstance/flux-tui/vm"
)

type refInputMode int

const (
	refBrowse refInputMode = iota
	refFilter
)

// ReferenceScreen is the ISA reference browser screen.
// It displays all FLUX opcodes with their encoding formats and descriptions,
// and supports filtering by name or category.
type ReferenceScreen struct {
	scroll    int
	filter    string
	width     int
	height    int
	inputMode refInputMode
	filterBuf string
}

// NewReferenceScreen creates a new reference screen.
func NewReferenceScreen() ReferenceScreen {
	return ReferenceScreen{}
}

// SetSize sets the available dimensions for the reference screen.
func (m ReferenceScreen) SetSize(width, height int) {
	m.width = width
	m.height = height
}

func (m ReferenceScreen) filteredOpcodes() []vm.OpcodeMeta {
	table := vm.OpcodeTable[:]
	if m.filter == "" {
		return table
	}
	var result []vm.OpcodeMeta
	f := strings.ToUpper(m.filter)
	for _, op := range table {
		if strings.Contains(strings.ToUpper(op.Name), f) ||
			strings.Contains(strings.ToUpper(op.Description), f) {
			result = append(result, op)
		}
	}
	return result
}

func (m ReferenceScreen) Init() tea.Cmd { return nil }

func (m ReferenceScreen) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
	case tea.KeyMsg:
		switch m.inputMode {
		case refFilter:
			return m.handleRefFilter(msg)
		case refBrowse:
			return m.handleRefBrowse(msg)
		}
	}
	return m, nil
}

func (m ReferenceScreen) handleRefBrowse(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	filtered := m.filteredOpcodes()
	mx := refMax(0, len(filtered)-1)
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "up", "k":
		if m.scroll > 0 {
			m.scroll--
		}
	case "down", "j":
		if m.scroll < mx {
			m.scroll++
		}
	case "pgup":
		m.scroll -= 10
		if m.scroll < 0 {
			m.scroll = 0
		}
	case "pgdown":
		m.scroll += 10
		if m.scroll > mx {
			m.scroll = mx
		}
	case "home":
		m.scroll = 0
	case "end":
		m.scroll = mx
	case "/":
		m.inputMode = refFilter
		m.filterBuf = ""
	case "escape":
		m.filter = ""
		m.scroll = 0
	}
	return m, nil
}

func (m ReferenceScreen) handleRefFilter(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		m.filter = strings.TrimSpace(m.filterBuf)
		m.inputMode = refBrowse
		m.scroll = 0
	case "escape":
		m.inputMode = refBrowse
		m.filterBuf = ""
		m.filter = ""
	case "backspace":
		if len(m.filterBuf) > 0 {
			m.filterBuf = m.filterBuf[:len(m.filterBuf)-1]
		}
	default:
		if len(msg.String()) == 1 {
			m.filterBuf += msg.String()
		}
	}
	return m, nil
}

func (m ReferenceScreen) View() string {
	if m.width == 0 {
		m.width = 80
	}
	if m.height == 0 {
		m.height = 24
	}
	var b strings.Builder

	b.WriteString(styles.Title.Render(" ISA Reference "))
	if m.filter != "" {
		b.WriteString(styles.Dim.Render(fmt.Sprintf(" (filter: %s)", m.filter)))
	}
	b.WriteString("\n")

	if m.inputMode == refFilter {
		b.WriteString(styles.Warning.Render(fmt.Sprintf(" Filter: /%s_", m.filterBuf)))
		b.WriteString("\n")
	}

	// Column headers
	header := fmt.Sprintf("  %-8s %-6s %-6s %-8s %s", "HEX", "NAME", "FMT", "STACK", "DESCRIPTION")
	b.WriteString(styles.Subtitle.Render(header))
	b.WriteString("\n")
	b.WriteString(styles.Dim.Render(strings.Repeat("-", refMin(m.width, 80))))
	b.WriteString("\n")

	// Opcode rows
	filtered := m.filteredOpcodes()
	lh := m.height - 8
	if lh < 4 {
		lh = 4
	}
	si := m.scroll
	if si+lh > len(filtered) {
		si = refMax(0, len(filtered)-lh)
	}
	ei := refMin(si+lh, len(filtered))

	for i := si; i < ei; i++ {
		op := filtered[i]
		// Find the actual opcode byte index in the original table
		opcodeByte := byte(i)
		for idx, tableOp := range vm.OpcodeTable {
			if tableOp.Name == op.Name {
				opcodeByte = byte(idx)
				break
			}
		}
		line := fmt.Sprintf("  0x%02X     %-6s %-6s %-8s %s",
			opcodeByte, op.Name, op.Format, op.StackEffect, op.Description)
		b.WriteString(refTrunc(line, m.width-2))
		b.WriteString("\n")
	}

	// Footer
	b.WriteString("\n")
	b.WriteString(styles.Dim.Render(fmt.Sprintf(" Showing %d/%d opcodes  |  Memory: big-endian  |  Program loads at 0x%04X",
		len(filtered), len(vm.OpcodeTable), vm.ProgramStart)))
	b.WriteString("\n")

	// Encoding format reference
	encRef := "  Format A: [opcode(1)][value(4 BE)] = 5 bytes (PUSH)  |  Format B: [opcode(1)][addr(2 BE)] = 3 bytes (JMP/JZ/LOAD/STORE)  |  No-operand: 1 byte"
	b.WriteString(styles.Dim.Render(refTrunc(encRef, m.width)))
	b.WriteString("\n")

	b.WriteString(styles.StatusLine.Render(refTrunc("[j/k or Up/Down] Scroll  [/] Filter  [Esc] Clear  [Home/End]  [q] Back", m.width)))
	return b.String()
}

func refTrunc(s string, n int) string {
	if n <= 0 {
		return ""
	}
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func refMax(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func refMin(a, b int) int {
	if a < b {
		return a
	}
	return b
}
