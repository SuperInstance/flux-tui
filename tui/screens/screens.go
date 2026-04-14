package screens

// Extended screen type constants for the new screens.
// These extend the existing ScreenType iota from types.go.
// types.go defines: ScreenDebugger=0, ScreenMemory=1, ScreenStack=2,
// ScreenSource=3, ScreenOutput=4, ScreenHelp=5, ScreenCount=6.
const (
	// ScreenConformance is the conformance test dashboard.
	ScreenConformance ScreenType = ScreenCount
	// ScreenInspector is the bytecode inspector.
	ScreenInspector ScreenType = ScreenCount + 1
	// ScreenReference is the ISA reference browser.
	ScreenReference ScreenType = ScreenCount + 2
	// ScreenExtendedCount is the total number of screens including extended ones.
	ScreenExtendedCount ScreenType = ScreenCount + 3
)
