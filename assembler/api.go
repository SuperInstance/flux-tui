package assembler

// Assemble is a convenience function that creates a new Assembler and assembles
// the given source code into bytecode. Returns the bytecode and any errors.
func Assemble(source string) ([]byte, []AsmError) {
	a := NewAssembler()
	return a.Assemble(source)
}
