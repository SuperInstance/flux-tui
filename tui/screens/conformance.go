package screens

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/SuperInstance/flux-tui/conformance"
	"github.com/SuperInstance/flux-tui/tui/styles"
	"github.com/SuperInstance/flux-tui/vm"
)

type conformanceDoneMsg struct {
	results []conformance.Result
}

// ConformanceScreen is the conformance dashboard screen.
type ConformanceScreen struct {
	engine   *vm.Engine
	vectors  []conformance.TestVector
	results  []conformance.Result
	selected int
	running  bool
	width    int
	height   int
	pending  bool
}

// NewConformanceScreen creates a new conformance screen.
func NewConformanceScreen(engine *vm.Engine) ConformanceScreen {
	return ConformanceScreen{
		engine:  engine,
		vectors: conformance.GenerateBuiltinVectors(),
		pending: true,
	}
}

func (m ConformanceScreen) Init() tea.Cmd { return nil }

func (m ConformanceScreen) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "q":
			return m, nil
		case "up", "k":
			if m.selected > 0 {
				m.selected--
			}
		case "down", "j":
			if m.selected < len(m.vectors)-1 {
				m.selected++
			}
		case "enter", "r":
			if !m.running {
				m.running = true
				return m, func() tea.Msg {
					return conformanceDoneMsg{results: conformance.RunAll()}
				}
			}
		}
	case conformanceDoneMsg:
		m.results = msg.results
		m.running = false
		m.pending = false
		return m, nil
	}
	return m, nil
}

func (m ConformanceScreen) View() string {
	if m.width == 0 {
		m.width = 80
	}
	if m.height == 0 {
		m.height = 24
	}
	var b strings.Builder

	b.WriteString(styles.Title.Render(" Conformance Dashboard "))
	b.WriteString("\n")

	passed, failed := 0, 0
	for _, r := range m.results {
		if r.Pass {
			passed++
		} else {
			failed++
		}
	}
	total := len(m.vectors)
	pending := total - passed - failed
	summary := fmt.Sprintf("Total: %d  Passed: %d  Failed: %d  Pending: %d", total, passed, failed, pending)
	if m.running {
		summary += "  ⏳ running..."
	}
	b.WriteString(styles.StatusLine.Render(summary))
	b.WriteString("\n")

	uh := m.height - 14
	if uh < 4 {
		uh = 4
	}
	si := 0
	if m.selected >= uh {
		si = m.selected - uh + 1
	}
	ei := si + uh
	if ei > total {
		ei = total
	}
	if ei-si < uh {
		si = ei - uh
		if si < 0 {
			si = 0
		}
	}

	b.WriteString(styles.PanelHeader.Render("─ Results "))
	b.WriteString("\n")
	for i := si; i < ei; i++ {
		tv := m.vectors[i]
		var icon, status string
		if m.pending {
			icon = "○"
			status = styles.Dim.Render("PENDING")
		} else if i < len(m.results) {
			res := m.results[i]
			if res.Pass {
				icon = "✓"
				status = styles.PassStyle.Render("PASS")
			} else {
				icon = "✗"
				status = styles.FailStyle.Render(cfTrunc(res.Reason, m.width-40))
			}
		} else {
			icon = "○"
			status = styles.Dim.Render("PENDING")
		}
		line := fmt.Sprintf("  %s %-30s %s", icon, tv.Name, status)
		if i == m.selected {
			b.WriteString(styles.SelectedItem.Render(line))
		} else {
			b.WriteString(line)
		}
		b.WriteString("\n")
	}

	if m.selected >= 0 && m.selected < len(m.vectors) {
		tv := m.vectors[m.selected]
		b.WriteString("\n")
		b.WriteString(styles.PanelHeader.Render("─ Selected Vector "))
		b.WriteString("\n")
		b.WriteString(fmt.Sprintf("  Name:     %s\n", tv.Name))
		b.WriteString(fmt.Sprintf("  Category: %s\n", tv.Category))
		b.WriteString(fmt.Sprintf("  Program:  %d bytes\n", len(tv.Program)))
		b.WriteString(fmt.Sprintf("  Expected: stack=%v, halted=%v\n", cfFmtStack(tv.ExpectedStack), tv.ExpectedHalted))
		if !m.pending && m.selected < len(m.results) {
			res := m.results[m.selected]
			if res.Pass {
				b.WriteString("  Result:   ")
				b.WriteString(styles.PassStyle.Render("PASS"))
			} else {
				b.WriteString("  Result:   ")
				b.WriteString(styles.FailStyle.Render("FAIL: " + res.Reason))
			}
			b.WriteString("\n")
		}
	}

	b.WriteString("\n")
	b.WriteString(styles.StatusLine.Render(cfTrunc("[enter] Run all  [↑↓] Navigate  [q] Back", m.width)))
	return b.String()
}

func cfFmtStack(items []uint32) string {
	if len(items) == 0 {
		return "[]"
	}
	parts := make([]string, len(items))
	for i, v := range items {
		parts[i] = fmt.Sprintf("%d", v)
	}
	return "[" + strings.Join(parts, ", ") + "]"
}

func cfTrunc(s string, n int) string {
	if n <= 0 {
		return ""
	}
	if len(s) <= n {
		return s
	}
	return s[:n]
}
