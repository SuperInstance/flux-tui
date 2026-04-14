package styles

import "github.com/charmbracelet/lipgloss"

var (
	// Title is for major section headers.
	Title = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#00FFFF")).
		PaddingLeft(1).
		PaddingRight(1)

	// Subtitle is for minor section headers.
	Subtitle = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#FFFFFF")).
		PaddingLeft(1)

	// Dim is for muted, less important text.
	Dim = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#888888"))

	// Highlight is for emphasized text (current line, active item).
	Highlight = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#00FF00"))

	// Error is for error messages.
	Error = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#FF0000"))

	// Success is for success indicators.
	Success = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#00FF00"))

	// Warning is for warning messages.
	Warning = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#FFFF00"))

	// Border is a rounded border style with cyan color.
	Border = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("#00FFFF")).
		Padding(0, 1)

	// BorderTitle is the title placed on the border.
	BorderTitle = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#00FFFF")).
		Background(lipgloss.Color("#333333"))

	// PanelHeader is used for section headers inside panels.
	PanelHeader = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#00AAFF")).
		PaddingLeft(1)

	// HelpKey is for keyboard shortcut keys in help text.
	HelpKey = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#FFFF00")).
		Width(5).
		Inline(true)

	// HelpDesc is for keyboard shortcut descriptions.
	HelpDesc = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#CCCCCC"))

	// StatusLine is for the bottom status bar.
	StatusLine = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#AAAAAA")).
		PaddingLeft(1)

	// SelectedItem is for the currently selected list item.
	SelectedItem = lipgloss.NewStyle().
		Background(lipgloss.Color("#334455")).
		Foreground(lipgloss.Color("#FFFFFF")).
		Bold(true)

	// PassStyle is for pass indicators.
	PassStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#00FF00"))

	// FailStyle is for fail indicators.
	FailStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#FF0000")).
		Bold(true)

	// AddrStyle is for memory addresses.
	AddrStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#8888FF")).
		Bold(true)

	// HexByteStyle is for hex byte values.
	HexByteStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#AAAAAA"))

	// InstructionStyle is for disassembled instructions.
	InstructionStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#DDDDDD"))

	// CurrentLine is for the currently executing line.
	CurrentLine = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#00FF00")).
		Background(lipgloss.Color("#1a1a2e"))
)
