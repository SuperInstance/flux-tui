// Package screens defines the screen types, models, and routing for the FLUX TUI.
//
// Architecture: 5 screens in a fixed cycle:
//
//	Debugger -> Conformance -> Inspector -> Reference -> Help -> Debugger ...
package screens

import (
	tea "github.com/charmbracelet/bubbletea"

	"github.com/SuperInstance/flux-tui/vm"
)

// ScreenType identifies different screens in the TUI.
type ScreenType int

const (
	// ScreenDebugger is the main VM debugger with step/run, register/stack/memory views.
	ScreenDebugger ScreenType = iota
	// ScreenConformance is the conformance test dashboard.
	ScreenConformance
	// ScreenInspector is the bytecode hex dump inspector.
	ScreenInspector
	// ScreenReference is the ISA reference browser.
	ScreenReference
	// ScreenHelp is the help and keybinding reference screen.
	ScreenHelp
	ScreenCount
)

// ScreenNames maps ScreenType to human-readable names.
var ScreenNames = map[ScreenType]string{
	ScreenDebugger:    "Debugger",
	ScreenConformance: "Conformance",
	ScreenInspector:   "Inspector",
	ScreenReference:   "Reference",
	ScreenHelp:        "Help",
}

// ScreenOrder defines the tab order for cycling through screens.
var ScreenOrder = []ScreenType{
	ScreenDebugger,
	ScreenConformance,
	ScreenInspector,
	ScreenReference,
	ScreenHelp,
}

// NextScreen returns the next screen in the cycle.
func NextScreen(current ScreenType) ScreenType {
	for i, s := range ScreenOrder {
		if s == current {
			if i+1 < len(ScreenOrder) {
				return ScreenOrder[i+1]
			}
			return ScreenOrder[0]
		}
	}
	return ScreenDebugger
}

// PrevScreen returns the previous screen in the cycle.
func PrevScreen(current ScreenType) ScreenType {
	for i, s := range ScreenOrder {
		if s == current {
			if i > 0 {
				return ScreenOrder[i-1]
			}
			return ScreenOrder[len(ScreenOrder)-1]
		}
	}
	return ScreenDebugger
}

// DisplayName returns the human-readable name for a screen type.
func (s ScreenType) DisplayName() string {
	if name, ok := ScreenNames[s]; ok {
		return name
	}
	return "Unknown"
}

// --- Screen model interfaces ---

// ScreenModel is the interface that all screen models must implement.
// Each screen receives Update/View messages and controls its own state.
type ScreenModel interface {
	tea.Model
	// SetSize informs the screen of available dimensions.
	SetSize(width, height int)
}

// --- Factory functions for creating screen models ---

// NewDebuggerModel creates the main VM debugger screen.
func NewDebuggerModel(engine *vm.Engine) ScreenModel {
	return NewDebuggerScreen(engine)
}

// NewConformanceModel creates the conformance test dashboard.
func NewConformanceModel(engine *vm.Engine) ScreenModel {
	return NewConformanceScreen(engine)
}

// NewInspectorModel creates the bytecode hex inspector.
func NewInspectorModel(engine *vm.Engine) ScreenModel {
	return NewInspectorScreen(engine)
}

// NewReferenceModel creates the ISA reference browser.
func NewReferenceModel() ScreenModel {
	return NewReferenceScreen()
}

// NewHelpModel creates the help screen.
func NewHelpModel() ScreenModel {
	return NewHelpScreen()
}

// NewScreenModel creates a screen model by type.
func NewScreenModel(screenType ScreenType, engine *vm.Engine) ScreenModel {
	switch screenType {
	case ScreenDebugger:
		return NewDebuggerModel(engine)
	case ScreenConformance:
		return NewConformanceModel(engine)
	case ScreenInspector:
		return NewInspectorModel(engine)
	case ScreenReference:
		return NewReferenceModel()
	case ScreenHelp:
		return NewHelpModel()
	default:
		return NewDebuggerModel(engine)
	}
}
