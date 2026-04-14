package vm

// Registers represents the VM register file.
type Registers struct {
	PC       uint16 // Program Counter
	SP       uint16 // Stack Pointer (shadow of Stack.sp, kept for display/snapshot)
	Flags    uint8  // Raw flags byte
	zero     bool   // Zero flag: set when result is 0
	carry    bool   // Carry flag: set on unsigned overflow/wrap
	overflow bool   // Overflow flag: set on signed overflow
}

// NewRegisters creates and returns a new Registers instance initialized to defaults.
func NewRegisters() *Registers {
	return &Registers{
		PC: ProgramStart,
		SP: 0,
	}
}

// Zero returns the zero flag.
func (r *Registers) Zero() bool {
	return r.zero
}

// Carry returns the carry flag.
func (r *Registers) Carry() bool {
	return r.carry
}

// Overflow returns the overflow flag.
func (r *Registers) Overflow() bool {
	return r.overflow
}

// SetFlags updates the zero, carry, and overflow flags based on an arithmetic result.
func (r *Registers) SetFlags(result uint32, carry bool, overflow bool) {
	r.zero = (result == 0)
	r.carry = carry
	r.overflow = overflow
	r.Flags = 0
	if r.zero {
		r.Flags |= 0x01
	}
	if r.carry {
		r.Flags |= 0x02
	}
	if r.overflow {
		r.Flags |= 0x04
	}
}

// SetZeroFlag is a convenience method to set only the zero flag based on a value.
func (r *Registers) SetZeroFlag(val uint32) {
	r.zero = (val == 0)
	r.Flags &^= 0x01
	if r.zero {
		r.Flags |= 0x01
	}
}

// UpdateSP sets the SP register to the given value.
func (r *Registers) UpdateSP(newSP uint16) {
	r.SP = newSP
}

// Copy returns a deep copy of the registers.
func (r *Registers) Copy() Registers {
	return Registers{
		PC:       r.PC,
		SP:       r.SP,
		Flags:    r.Flags,
		zero:     r.zero,
		carry:    r.carry,
		overflow: r.overflow,
	}
}
