package main

import (
        "fmt"
        "os"
        "path/filepath"
        "strings"

        tea "github.com/charmbracelet/bubbletea"
        "github.com/charmbracelet/lipgloss"

        "github.com/SuperInstance/flux-tui/assembler"
        "github.com/SuperInstance/flux-tui/tui/screens"
        "github.com/SuperInstance/flux-tui/vm"
)

// model is the root TUI model. It manages screen routing and global keybindings.
type model struct {
        engine        *vm.Engine
        currentScreen screens.ScreenType
        screens       map[screens.ScreenType]screens.ScreenModel
        width         int
        height        int
        quitting      bool
}

func newModel(engine *vm.Engine, sourceCode string) model {
        // If source code was provided via CLI, assemble and load it
        if sourceCode != "" {
                code, errs := assembler.Assemble(sourceCode)
                if len(errs) > 0 {
                        fmt.Fprintf(os.Stderr, "Assembly errors:\n")
                        for _, e := range errs {
                                fmt.Fprintf(os.Stderr, "  %s\n", e.Error())
                        }
                } else {
                        engine.LoadProgram(code)
                        fmt.Fprintf(os.Stderr, "Loaded %d bytes from assembly\n", len(code))
                }
        }

        return model{
                engine:        engine,
                currentScreen: screens.ScreenDebugger,
                screens: map[screens.ScreenType]screens.ScreenModel{
                        screens.ScreenDebugger:    screens.NewDebuggerModel(engine),
                        screens.ScreenConformance: screens.NewConformanceModel(engine),
                        screens.ScreenInspector:   screens.NewInspectorModel(engine),
                        screens.ScreenReference:   screens.NewReferenceModel(),
                        screens.ScreenHelp:        screens.NewHelpModel(),
                },
        }
}

func (m model) Init() tea.Cmd {
        return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
        switch msg := msg.(type) {
        case tea.WindowSizeMsg:
                m.width = msg.Width
                m.height = msg.Height
                // Propagate size to all screens
                innerHeight := m.height - 2 // minus title bar + status hint
                if innerHeight < 4 {
                        innerHeight = 4
                }
                for _, sm := range m.screens {
                        sm.SetSize(m.width, innerHeight)
                }
                return m, nil

        case tea.KeyMsg:
                key := msg.String()

                // Global quit - Ctrl+C always quits regardless of screen
                if key == "ctrl+c" {
                        m.quitting = true
                        return m, tea.Quit
                }

                // Global screen switching keys (work from any screen)
                switch key {
                case "tab":
                        m.currentScreen = screens.NextScreen(m.currentScreen)
                        return m, nil
                case "shift+tab":
                        m.currentScreen = screens.PrevScreen(m.currentScreen)
                        return m, nil
                case "1":
                        m.currentScreen = screens.ScreenDebugger
                        return m, nil
                case "2":
                        m.currentScreen = screens.ScreenConformance
                        return m, nil
                case "3":
                        m.currentScreen = screens.ScreenInspector
                        return m, nil
                case "4":
                        m.currentScreen = screens.ScreenReference
                        return m, nil
                case "?":
                        m.currentScreen = screens.ScreenHelp
                        return m, nil
                }

                // 'q' goes back to debugger from any non-debugger screen
                if key == "q" && m.currentScreen != screens.ScreenDebugger {
                        m.currentScreen = screens.ScreenDebugger
                        return m, nil
                }

                // Forward all other keys to the active screen
                activeScreen := m.screens[m.currentScreen]
                updated, cmd := activeScreen.Update(msg)

                // Capture the possibly-mutated screen model back
                if ds, ok := updated.(screens.DebuggerScreen); ok {
                        m.screens[screens.ScreenDebugger] = ds
                }
                if cs, ok := updated.(screens.ConformanceScreen); ok {
                        m.screens[screens.ScreenConformance] = cs
                }
                if is, ok := updated.(screens.InspectorScreen); ok {
                        m.screens[screens.ScreenInspector] = is
                }
                if rs, ok := updated.(screens.ReferenceScreen); ok {
                        m.screens[screens.ScreenReference] = rs
                }
                if hs, ok := updated.(screens.HelpScreen); ok {
                        m.screens[screens.ScreenHelp] = hs
                }

                return m, cmd
        }

        // Forward non-key messages (like WindowSizeMsg) to active screen
        activeScreen := m.screens[m.currentScreen]
        updated, cmd := activeScreen.Update(msg)
        if ds, ok := updated.(screens.DebuggerScreen); ok {
                m.screens[screens.ScreenDebugger] = ds
        }
        return m, cmd
}

func (m model) View() string {
        if m.quitting {
                return "Goodbye!\n"
        }

        if m.width == 0 {
                m.width = 80
        }
        if m.height == 0 {
                m.height = 24
        }

        var b strings.Builder

        // Title bar with screen name and navigation hints
        screenName := m.currentScreen.DisplayName()
        screenHint := ""
        switch m.currentScreen {
        case screens.ScreenDebugger:
                screenHint = "[s]tep [r]un [b]reak [l]oad [:]cmd"
        case screens.ScreenConformance:
                screenHint = "[enter] Run [e] External [j/k] Nav"
        case screens.ScreenInspector:
                screenHint = "[j/k] Scroll [PgUp/PgDn]"
        case screens.ScreenReference:
                screenHint = "[j/k] Scroll [/] Filter"
        case screens.ScreenHelp:
                screenHint = "[j/k] Scroll [q] Back"
        }

        titleLeft := fmt.Sprintf(" flux-tui  [%s]", screenName)
        titleRight := fmt.Sprintf("Tab: cycle | 1-4: direct | ?: help | %s ", screenHint)
        titleWidth := m.width

        // Calculate padding
        leftLen := lipgloss.Width(titleLeft)
        rightLen := lipgloss.Width(titleRight)
        if leftLen+rightLen > titleWidth {
                // Truncate right side if too wide
                available := titleWidth - leftLen - 1
                if available < 10 {
                        available = 10
                }
                titleRight = titleRight[:available] + " "
                rightLen = lipgloss.Width(titleRight)
        }
        padding := titleWidth - leftLen - rightLen
        if padding < 0 {
                padding = 0
        }

        titleBar := lipgloss.NewStyle().
                Bold(true).
                Foreground(lipgloss.Color("#FFFFFF")).
                Background(lipgloss.Color("#1a1a2e")).
                Width(titleWidth).
                Render(titleLeft + strings.Repeat(" ", padding) + titleRight)
        b.WriteString(titleBar)
        b.WriteString("\n")

        // Screen content
        activeScreen := m.screens[m.currentScreen]
        // Ensure the screen has correct dimensions
        innerHeight := m.height - 2
        if innerHeight < 4 {
                innerHeight = 4
        }
        activeScreen.SetSize(m.width, innerHeight)
        b.WriteString(activeScreen.View())

        return b.String()
}

func main() {
        engine := vm.NewEngine()

        var sourceCode string

        // Parse CLI arguments
        if len(os.Args) > 1 {
                filename := os.Args[1]
                data, err := os.ReadFile(filename)
                if err != nil {
                        fmt.Fprintf(os.Stderr, "Error reading %s: %v\n", filename, err)
                        os.Exit(1)
                }

                ext := strings.ToLower(filepath.Ext(filename))
                switch ext {
                case ".fluxasm", ".asm", ".s", ".flux":
                        // Assembly source: assemble it
                        sourceCode = string(data)
                case ".fluxbin", ".bin", ".rom":
                        // Raw bytecode: load directly
                        engine.LoadProgram(data)
                        fmt.Fprintf(os.Stderr, "Loaded %d bytes from %s\n", len(data), filename)
                default:
                        // Try to detect: if first non-whitespace byte is a valid opcode, treat as binary
                        trimmed := strings.TrimSpace(string(data))
                        if len(trimmed) > 0 {
                                firstChar := trimmed[0]
                                // If it starts with a semicolon, hash, or letter (label/comment), it's assembly
                                if firstChar == ';' || firstChar == '#' || (firstChar >= 'A' && firstChar <= 'Z') || (firstChar >= 'a' && firstChar <= 'z') {
                                        sourceCode = string(data)
                                } else {
                                        // Otherwise treat as binary
                                        engine.LoadProgram(data)
                                        fmt.Fprintf(os.Stderr, "Loaded %d bytes from %s (detected as binary)\n", len(data), filename)
                                }
                        }
                }
        }

        // Check for --conformance flag
        for _, arg := range os.Args[1:] {
                if arg == "--conformance" || arg == "-t" {
                        // Run conformance tests in batch mode and exit
                        runBatchConformance()
                        return
                }
        }

        m := newModel(engine, sourceCode)

        p := tea.NewProgram(m, tea.WithAltScreen())
        if _, err := p.Run(); err != nil {
                fmt.Fprintf(os.Stderr, "Error: %v\n", err)
                os.Exit(1)
        }
}

func runBatchConformance() {
        fmt.Println("FLUX VM Conformance Test Runner")
        fmt.Println("================================")

        engine := vm.NewEngine()
        conformanceScreen := screens.NewConformanceScreen(engine)

        // Trigger a run
        updated, _ := conformanceScreen.Update(nil)
        if cs, ok := updated.(screens.ConformanceScreen); ok {
                // The run is async in the real TUI, but we can call RunAll directly
                results := cs.RunBuiltin()
                passed, failed := 0, 0
                for _, r := range results {
                        if r.Pass {
                                passed++
                                fmt.Printf("  PASS  %s\n", r.Name)
                        } else {
                                failed++
                                fmt.Printf("  FAIL  %s: %s\n", r.Name, r.Reason)
                        }
                }
                fmt.Printf("\nResults: %d/%d passed", passed, passed+failed)
                if failed > 0 {
                        fmt.Printf(", %d failed", failed)
                }
                fmt.Println()
        }
}
