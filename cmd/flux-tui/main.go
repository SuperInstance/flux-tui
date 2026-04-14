package main

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/SuperInstance/flux-tui/tui/screens"
	"github.com/SuperInstance/flux-tui/vm"
)

type model struct {
	engine        *vm.Engine
	currentScreen screens.ScreenType
	dbgScreen     screens.DebuggerScreen
	width         int
	height        int
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		key := msg.String()

		// Global keys
		switch key {
		case "ctrl+c":
			return m, tea.Quit
		case "q":
			if m.currentScreen == screens.ScreenDebugger {
				return m, tea.Quit
			}
			m.currentScreen = screens.ScreenDebugger
			return m, nil
		case "tab":
			m.currentScreen = screens.NextScreen(m.currentScreen)
			return m, nil
		case "shift+tab":
			m.currentScreen = screens.PrevScreen(m.currentScreen)
			return m, nil
		}

		// Forward to active screen
		if m.currentScreen == screens.ScreenDebugger {
			updated, cmd := m.dbgScreen.Update(msg)
			if ds, ok := updated.(screens.DebuggerScreen); ok {
				m.dbgScreen = ds
			}
			return m, cmd
		}
	}

	return m, nil
}

func (m model) View() string {
	var b strings.Builder

	if m.width == 0 {
		m.width = 80
	}
	if m.height == 0 {
		m.height = 24
	}

	// Title bar
	title := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#00FFFF")).
		Background(lipgloss.Color("#1a1a2e")).
		Padding(0, 1).
		Width(m.width).
		Render(fmt.Sprintf(" flux-tui — FLUX VM Debugger    [%s] ", m.currentScreen.DisplayName()))
	b.WriteString(title)
	b.WriteString("\n")

	// Screen content
	switch m.currentScreen {
	case screens.ScreenDebugger:
		b.WriteString(m.dbgScreen.View())
	default:
		var screenModel tea.Model
		switch m.currentScreen {
		case screens.ScreenMemory:
			screenModel = screens.NewMemoryModel(m.engine)
		case screens.ScreenStack:
			screenModel = screens.NewStackModel(m.engine)
		case screens.ScreenSource:
			screenModel = screens.NewSourceModel(m.engine)
		case screens.ScreenOutput:
			screenModel = screens.NewOutputModel(m.engine)
		case screens.ScreenHelp:
			screenModel = screens.NewHelpModel(m.engine)
		default:
			screenModel = screens.NewHelpModel(m.engine)
		}
		screenModel, _ = screenModel.Update(tea.WindowSizeMsg{Width: m.width, Height: m.height - 2})
		b.WriteString(screenModel.View())
	}

	return b.String()
}

func main() {
	engine := vm.NewEngine()

	// If a filename was provided, try to load it as raw bytecode
	if len(os.Args) > 1 {
		filename := os.Args[1]
		data, err := os.ReadFile(filename)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading %s: %v\n", filename, err)
			os.Exit(1)
		}
		engine.LoadProgram(data)
		fmt.Fprintf(os.Stderr, "Loaded %d bytes from %s\n", len(data), filename)
	}

	m := model{
		engine:    engine,
		dbgScreen: screens.NewDebuggerScreen(engine),
	}

	p := tea.NewProgram(m, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
