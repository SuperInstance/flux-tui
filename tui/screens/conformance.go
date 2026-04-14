package screens

import (
        "fmt"
        "os"
        "path/filepath"
        "strings"

        tea "github.com/charmbracelet/bubbletea"

        "github.com/SuperInstance/flux-tui/conformance"
        "github.com/SuperInstance/flux-tui/tui/styles"
        "github.com/SuperInstance/flux-tui/vm"
)

type conformanceDoneMsg struct {
        results []conformance.Result
        loaded  int
        skipped int
        source  string // "builtin" or file path
}

// ConformanceScreen is the conformance test dashboard screen.
// It runs FLUX conformance vectors against the VM and shows pass/fail results.
type ConformanceScreen struct {
        engine    *vm.Engine
        vectors   []conformance.TestVector
        results   []conformance.Result
        selected  int
        running   bool
        width     int
        height    int
        pending   bool
        loadPath  string // external vectors file path
        summary   string // last run summary
}

// NewConformanceScreen creates a new conformance screen with built-in vectors.
func NewConformanceScreen(engine *vm.Engine) ConformanceScreen {
        return ConformanceScreen{
                engine:  engine,
                vectors: conformance.GenerateBuiltinVectors(),
                pending: true,
        }
}

// SetSize sets the available dimensions for the conformance screen.
func (m ConformanceScreen) SetSize(width, height int) {
        m.width = width
        m.height = height
}

func (m ConformanceScreen) Init() tea.Cmd { return nil }

func (m ConformanceScreen) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
        switch msg := msg.(type) {
        case tea.WindowSizeMsg:
                m.width = msg.Width
                m.height = msg.Height
                return m, nil
        case conformanceLoadMsg:
                if msg.err != nil {
                        m.summary = msg.err.Error()
                        m.pending = false
                        return m, nil
                }
                m.vectors = msg.vectors
                m.loadPath = msg.path
                m.pending = true
                m.results = nil
                m.selected = 0
                if msg.skipped > 0 {
                        m.summary = fmt.Sprintf("Loaded %d vectors from %s (%d skipped - incompatible ISA)", len(msg.vectors), filepath.Base(msg.path), msg.skipped)
                } else {
                        m.summary = fmt.Sprintf("Loaded %d vectors from %s", len(msg.vectors), filepath.Base(msg.path))
                }
                return m, nil
        case tea.KeyMsg:
                return m.handleKey(msg)
        case conformanceDoneMsg:
                m.results = msg.results
                m.running = false
                m.pending = false
                passed, failed := 0, 0
                for _, r := range msg.results {
                        if r.Pass {
                                passed++
                        } else {
                                failed++
                        }
                }
                src := msg.source
                if msg.skipped > 0 {
                        m.summary = fmt.Sprintf("Ran %d from %s: %d passed, %d failed, %d skipped", msg.loaded, src, passed, failed, msg.skipped)
                } else {
                        m.summary = fmt.Sprintf("Ran %d from %s: %d passed, %d failed", msg.loaded, src, passed, failed)
                }
                return m, nil
        }
        return m, nil
}

// RunBuiltin runs the built-in vectors and returns results (for batch mode).
func (m ConformanceScreen) RunBuiltin() []conformance.Result {
        return conformance.RunAll()
}

func (m ConformanceScreen) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
        switch msg.String() {
        case "ctrl+c":
                return m, tea.Quit
        case "enter", "r":
                if !m.running {
                        m.running = true
                        m.summary = "Running..."
                        vectors := m.vectors
                        source := "builtin"
                        if m.loadPath != "" {
                                source = filepath.Base(m.loadPath)
                        }
                        return m, func() tea.Msg {
                                results := conformance.RunVectors(vectors)
                                return conformanceDoneMsg{
                                        results: results,
                                        loaded:  len(vectors),
                                        source:  source,
                                }
                        }
                }
        case "up", "k":
                if m.selected > 0 {
                        m.selected--
                }
        case "down", "j":
                if m.selected < len(m.vectors)-1 {
                        m.selected++
                }
        case "pgup":
                m.selected -= 10
                if m.selected < 0 {
                        m.selected = 0
                }
        case "pgdown":
                m.selected += 10
                if m.selected > len(m.vectors)-1 {
                        m.selected = len(m.vectors) - 1
                }
        case "home":
                m.selected = 0
        case "end":
                if len(m.vectors) > 0 {
                        m.selected = len(m.vectors) - 1
                }
        case "e":
                // Load external vectors
                m.loadPath = ""
                m.pending = true
                m.results = nil
                m.summary = ""
                return m, func() tea.Msg {
                        // Try default conformance path
                        paths := []string{
                                "conformance/vectors/manifest.json",
                                "../flux-conformance/vectors/manifest.json",
                        }
                        for _, p := range paths {
                                if _, err := os.Stat(p); err == nil {
                                        vecs, skipped, err := conformance.LoadExternalVectors(p)
                                        if err == nil && len(vecs) > 0 {
                                                return conformanceLoadMsg{path: p, vectors: vecs, skipped: skipped}
                                        }
                                }
                        }
                        return conformanceLoadMsg{err: fmt.Errorf("no conformance vectors found (tried conformance/vectors/manifest.json)")}
                }
        }
        return m, nil
}

type conformanceLoadMsg struct {
        path    string
        vectors []conformance.TestVector
        skipped int
        err     error
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
        if m.loadPath != "" {
                b.WriteString(styles.Dim.Render(fmt.Sprintf(" [%s]", filepath.Base(m.loadPath))))
        }
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
        pendingCount := total - passed - failed

        // Summary line
        if m.summary != "" {
                b.WriteString(styles.StatusLine.Render(" " + m.summary))
        } else if m.pending {
                b.WriteString(styles.StatusLine.Render(fmt.Sprintf(" Total: %d  Ready to run  [enter] to start", total)))
        } else {
                b.WriteString(styles.StatusLine.Render(
                        fmt.Sprintf(" Total: %d  Passed: %s  Failed: %s  Pending: %d",
                                total,
                                styles.PassStyle.Render(fmt.Sprintf("%d", passed)),
                                styles.FailStyle.Render(fmt.Sprintf("%d", failed)),
                                pendingCount,
                        ),
                ))
        }
        b.WriteString("\n")

        // Results list
        uh := m.height - 12
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

        b.WriteString(styles.PanelHeader.Render(fmt.Sprintf(" Results (%d vectors) ", total)))
        b.WriteString("\n")
        for i := si; i < ei; i++ {
                tv := m.vectors[i]
                var icon, status string
                if m.pending {
                        icon = "o"
                        status = styles.Dim.Render("PENDING")
                } else if i < len(m.results) {
                        res := m.results[i]
                        if res.Pass {
                                icon = "+"
                                status = styles.PassStyle.Render("PASS")
                        } else {
                                icon = "x"
                                status = styles.FailStyle.Render(cfTrunc(res.Reason, m.width-45))
                        }
                } else {
                        icon = "o"
                        status = styles.Dim.Render("PENDING")
                }
                line := fmt.Sprintf("  %s %-32s %s", icon, tv.Name, status)
                if i == m.selected {
                        b.WriteString(styles.SelectedItem.Render(line))
                } else {
                        b.WriteString(line)
                }
                b.WriteString("\n")
        }

        // Selected vector detail
        if m.selected >= 0 && m.selected < len(m.vectors) {
                tv := m.vectors[m.selected]
                b.WriteString("\n")
                b.WriteString(styles.PanelHeader.Render(" Selected Vector "))
                b.WriteString("\n")
                b.WriteString(fmt.Sprintf("  Name:     %s\n", tv.Name))
                b.WriteString(fmt.Sprintf("  Category: %s\n", tv.Category))
                b.WriteString(fmt.Sprintf("  Program:  %d bytes\n", len(tv.Program)))
                b.WriteString(fmt.Sprintf("  Expected: stack=%v, halted=%v\n", cfFmtStack(tv.ExpectedStack), tv.ExpectedHalted))
                if !m.pending && m.selected < len(m.results) {
                        res := m.results[m.selected]
                        b.WriteString("  Result:   ")
                        if res.Pass {
                                b.WriteString(styles.PassStyle.Render("PASS"))
                        } else {
                                b.WriteString(styles.FailStyle.Render("FAIL: " + res.Reason))
                        }
                        b.WriteString("\n")
                        if res.Actual != "" {
                                b.WriteString(styles.Dim.Render("  Actual:   " + res.Actual))
                                b.WriteString("\n")
                        }
                }
        }

        b.WriteString("\n")
        b.WriteString(styles.StatusLine.Render(cfTrunc("[enter/r] Run  [e] Load external  [j/k] Navigate  [Home/End] Jump  [q] Back", m.width)))
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
