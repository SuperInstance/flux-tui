package screens

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/SuperInstance/flux-tui/assembler"
	"github.com/SuperInstance/flux-tui/tui/styles"
	"github.com/SuperInstance/flux-tui/vm"
)

const inspBytesPerRow = 16

// InspectorScreen is the bytecode inspector screen.
// It shows a hex dump view of program memory with inline disassembly.
type InspectorScreen struct {
	engine *vm.Engine
	offset int // scroll offset in bytes
	width  int
	height int
}

// NewInspectorScreen creates a new inspector screen.
func NewInspectorScreen(engine *vm.Engine) InspectorScreen {
	return InspectorScreen{engine: engine}
}

// SetSize sets the available dimensions for the inspector screen.
func (m InspectorScreen) SetSize(width, height int) {
	m.width = width
	m.height = height
}

func (m InspectorScreen) Init() tea.Cmd { return nil }

func (m InspectorScreen) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "up", "k":
			if m.offset > 0 {
				m.offset--
			}
		case "down", "j":
			mx := inspMax(0, m.engine.ProgramLength()-inspBytesPerRow)
			if m.offset < mx {
				m.offset++
			}
		case "pgup":
			m.offset -= inspBytesPerRow * 4
			if m.offset < 0 {
				m.offset = 0
			}
		case "pgdown":
			mx := inspMax(0, m.engine.ProgramLength()-inspBytesPerRow)
			m.offset += inspBytesPerRow * 4
			if m.offset > mx {
				m.offset = mx
			}
		case "home":
			m.offset = 0
		case "end":
			m.offset = inspMax(0, m.engine.ProgramLength()-inspBytesPerRow)
		}
	}
	return m, nil
}

func (m InspectorScreen) View() string {
	if m.width == 0 {
		m.width = 80
	}
	if m.height == 0 {
		m.height = 24
	}
	var b strings.Builder

	b.WriteString(styles.Title.Render(" Bytecode Inspector "))
	b.WriteString("\n")

	pl := m.engine.ProgramLength()
	mem := m.engine.Mem()
	pc := m.engine.PC

	if pl == 0 {
		b.WriteString(styles.Dim.Render("\n  No program loaded.\n\n  Load a program in the Debugger screen with 'l',\n  then switch here with Tab.\n"))
		b.WriteString("\n")
		b.WriteString(styles.StatusLine.Render(inspTrunc("[q] Back to Debugger", m.width)))
		return b.String()
	}

	// Top half: hex dump
	hh := m.height/2 - 4
	if hh < 4 {
		hh = 4
	}
	b.WriteString(styles.PanelHeader.Render(fmt.Sprintf(" Hex Dump (%d bytes @ 0x%04X) ", pl, vm.ProgramStart)))
	b.WriteString("\n")
	b.WriteString(styles.Dim.Render(" ADDR  "))
	b.WriteString(" +0 +1 +2 +3 +4 +5 +6 +7 +8 +9 +A +B +C +D +E +F  ASCII")
	b.WriteString("\n")
	b.WriteString(styles.Dim.Render(strings.Repeat("-", inspMin(m.width-2, 72))))
	b.WriteString("\n")

	rowStart := uint16(m.offset) / inspBytesPerRow * inspBytesPerRow
	for row := 0; row < hh; row++ {
		addr := vm.ProgramStart + rowStart + uint16(row*inspBytesPerRow)
		if int(addr-vm.ProgramStart) >= pl {
			break
		}
		b.WriteString(styles.AddrStyle.Render(fmt.Sprintf(" %04X: ", addr)))
		var ascii strings.Builder
		for col := 0; col < inspBytesPerRow; col++ {
			ba := addr + uint16(col)
			if int(ba-vm.ProgramStart) < pl {
				bt, _ := mem.Load(ba)
				if ba == pc {
					b.WriteString(styles.Highlight.Render(fmt.Sprintf("%02X", bt)))
				} else {
					b.WriteString(styles.HexByteStyle.Render(fmt.Sprintf("%02X", bt)))
				}
				// ASCII representation
				if bt >= 32 && bt <= 126 {
					ascii.WriteByte(bt)
				} else {
					ascii.WriteByte('.')
				}
			} else {
				b.WriteString("  ")
				ascii.WriteByte(' ')
			}
			if col < inspBytesPerRow-1 {
				b.WriteString(" ")
			}
		}
		b.WriteString("  ")
		b.WriteString(styles.Dim.Render(ascii.String()))
		b.WriteString("\n")
	}

	// Bottom half: disassembly
	b.WriteString("\n")
	dh := m.height/2 - 6
	if dh < 4 {
		dh = 4
	}
	b.WriteString(styles.PanelHeader.Render(" Disassembly "))
	b.WriteString("\n")

	data := mem.LoadRange(vm.ProgramStart, pl)
	dasm := assembler.Disassemble(data, vm.ProgramStart)
	dasmLines := strings.Split(strings.TrimSpace(dasm), "\n")
	pcLineIdx := -1
	for i, line := range dasmLines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, fmt.Sprintf("  0x%04X:", pc)) {
			pcLineIdx = i
			break
		}
	}
	do := 0
	if pcLineIdx >= 0 && pcLineIdx > dh-2 {
		do = pcLineIdx - dh + 2
	}
	endL := do + dh
	if endL > len(dasmLines) {
		endL = len(dasmLines)
	}
	for i := do; i < endL; i++ {
		line := strings.TrimSpace(dasmLines[i])
		pfx := "  "
		if i == pcLineIdx {
			pfx = ">>"
			b.WriteString(styles.CurrentLine.Render(pfx + line))
		} else {
			b.WriteString(styles.InstructionStyle.Render(pfx + line))
		}
		b.WriteString("\n")
	}

	b.WriteString("\n")
	scrollPct := 0
	maxOff := inspMax(0, pl-inspBytesPerRow)
	if maxOff > 0 {
		scrollPct = (m.offset * 100) / maxOff
	}
	b.WriteString(styles.Dim.Render(fmt.Sprintf(" Scroll: %d/%d (%d%%)", m.offset, maxOff, scrollPct)))
	b.WriteString("\n")
	b.WriteString(styles.StatusLine.Render(inspTrunc("[j/k or Up/Down] Scroll  [PgUp/PgDn] Page  [Home/End]  [q] Back", m.width)))
	return b.String()
}

func inspTrunc(s string, n int) string {
	if n <= 0 {
		return ""
	}
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func inspMax(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func inspMin(a, b int) int {
	if a < b {
		return a
	}
	return b
}
