package vm

// BreakpointManager manages address-based breakpoints for the VM debugger.
type BreakpointManager struct {
	breakpoints map[uint16]bool
	enabled     bool
}

// NewBreakpointManager creates a new BreakpointManager.
func NewBreakpointManager() *BreakpointManager {
	return &BreakpointManager{
		breakpoints: make(map[uint16]bool),
		enabled:     true,
	}
}

// Add adds a breakpoint at the given address.
func (bm *BreakpointManager) Add(addr uint16) {
	bm.breakpoints[addr] = true
}

// Remove removes a breakpoint at the given address. Returns true if it existed.
func (bm *BreakpointManager) Remove(addr uint16) bool {
	if bm.breakpoints[addr] {
		delete(bm.breakpoints, addr)
		return true
	}
	return false
}

// Clear removes all breakpoints.
func (bm *BreakpointManager) Clear() {
	bm.breakpoints = make(map[uint16]bool)
}

// Has checks if there is a breakpoint at the given address.
func (bm *BreakpointManager) Has(addr uint16) bool {
	return bm.breakpoints[addr]
}

// Toggle toggles a breakpoint at the given address. Returns true if added, false if removed.
func (bm *BreakpointManager) Toggle(addr uint16) bool {
	if bm.breakpoints[addr] {
		delete(bm.breakpoints, addr)
		return false
	}
	bm.breakpoints[addr] = true
	return true
}

// List returns a sorted slice of all breakpoint addresses.
func (bm *BreakpointManager) List() []uint16 {
	addrs := make([]uint16, 0, len(bm.breakpoints))
	for addr := range bm.breakpoints {
		addrs = append(addrs, addr)
	}
	return addrs
}

// Count returns the number of active breakpoints.
func (bm *BreakpointManager) Count() int {
	return len(bm.breakpoints)
}

// Enable enables breakpoint checking.
func (bm *BreakpointManager) Enable() {
	bm.enabled = true
}

// Disable disables breakpoint checking (breakpoints are ignored).
func (bm *BreakpointManager) Disable() {
	bm.enabled = false
}

// Enabled returns whether breakpoint checking is enabled.
func (bm *BreakpointManager) Enabled() bool {
	return bm.enabled
}

// CheckHit checks if the current PC has a breakpoint and breakpoints are enabled.
func (bm *BreakpointManager) CheckHit(pc uint16) bool {
	return bm.enabled && bm.breakpoints[pc]
}
