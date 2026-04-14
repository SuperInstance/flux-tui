package screens

import (
        "fmt"
        "strings"

        tea "github.com/charmbracelet/bubbletea"

        "github.com/SuperInstance/flux-tui/tui/styles"
)

// HelpScreen is the help and information screen.
type HelpScreen struct {
        scroll int
        width  int
        height int
}

// NewHelpScreen creates a new help screen.
func NewHelpScreen() HelpScreen {
        return HelpScreen{}
}

// helpContent returns the full help text as a slice of lines.
func helpContent() []string {
        return []string{
                "",
                "FLUX VM Debugger — Help",
                "═══════════════════════════════════════════════",
                "",
                "OVERVIEW",
                "───────────────────────────────────────────────",
                "  The FLUX TUI is a bytecode VM debugger for the",
                "  FLUX virtual machine. It provides real-time",
                "  inspection of registers, stack, memory, and",
                "  disassembled instructions.",
                "",
                "SCREENS",
                "───────────────────────────────────────────────",
                "  Debugger        Main VM debugger with step/run",
                "  Conformance     Run test vectors and verify VM",
                "  Inspector       Hex dump view of program memory",
                "  ISA Reference   Browse all VM opcodes and specs",
                "  Help            This screen",
                "  Switch screens with Tab / Shift+Tab.",
                "",
                "DEBUGGER KEYBINDINGS",
                "───────────────────────────────────────────────",
                "  s              Step one instruction",
                "  r              Run until halt",
                "  b              Reset (break) VM",
                "  n              Save snapshot",
                "  p              Restore last snapshot",
                "  l              Load assembly file",
                "  :              Enter command mode",
                "  q              Quit",
                "",
                "COMMANDS (in : mode)",
                "───────────────────────────────────────────────",
                "  step           Execute one instruction",
                "  run            Run until halt",
                "  reset          Reset the VM",
                "  stack          Show stack contents",
                "  mem <addr>     Read memory word at address",
                "  regs           Show register state",
                "  pc             Show program counter",
                "  help           Show available commands",
                "",
                "INSPECTOR KEYBINDINGS",
                "───────────────────────────────────────────────",
                "  ↑/↓ or j/k    Scroll one line",
                "  PgUp/PgDn      Scroll one page",
                "  Home/End       Jump to start/end",
                "  q              Back to debugger",
                "",
                "CONFORMANCE KEYBINDINGS",
                "───────────────────────────────────────────────",
                "  Enter or r     Run all test vectors",
                "  ↑/↓ or j/k    Navigate test list",
                "  q              Back to debugger",
                "",
                "REFERENCE KEYBINDINGS",
                "───────────────────────────────────────────────",
                "  ↑/↓ or j/k    Scroll opcode list",
                "  PgUp/PgDn      Scroll one page",
                "  /              Enter filter mode",
                "  Esc            Clear filter",
                "  q              Back to debugger",
                "",
                "FLUX ISA QUICK REFERENCE",
                "───────────────────────────────────────────────",
                "  0x00 NOP       0x07 MUL       0x0C XOR",
                "  0x01 PUSH imm  0x08 AND       0x0D JZ addr",
                "  0x02 POP       0x09 OR        0x0E LOAD addr",
                "  0x03 DUP       0x0A NOT       0x0F STORE addr",
                "  0x04 SWAP      0x0B JMP addr  0x10 HALT",
                "  0x05 ADD       0x06 SUB",
                "",
                "  Memory is big-endian. Program loads at",
                "  0x0100. Stack grows upward.",
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
                case "q":
                        return m, nil
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
                case strings.HasPrefix(line, "  ") && !strings.HasPrefix(line, "    "):
                        b.WriteString(styles.PanelHeader.Render(line))
                case line == "OVERVIEW" || line == "SCREENS" ||
                        strings.Contains(line, "KEYBINDINGS") ||
                        line == "COMMANDS (in : mode)" ||
                        line == "FLUX ISA QUICK REFERENCE":
                        b.WriteString(styles.Subtitle.Render(line))
                default:
                        b.WriteString(styles.HelpDesc.Render(helpTruncate(line, m.width-2)))
                }
                b.WriteString("\n")
        }

        // Scroll indicator
        totalLines := len(lines)
        if m.scroll > 0 || m.scroll+visibleLines < totalLines {
                scrollPct := 100
                if totalLines > visibleLines {
                        scrollPct = (m.scroll * 100) / (totalLines - visibleLines)
                }
                b.WriteString(styles.Dim.Render(fmt.Sprintf("  ── %d%% ──", scrollPct)))
                b.WriteString("\n")
        }

        b.WriteString(styles.StatusLine.Render("[↑↓] Scroll  [PgUp/PgDn] Page  [Home/End]  [q] Back"))

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


