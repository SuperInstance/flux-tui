// Package assembler implements a lexer and assembler for FLUX assembly language.
package assembler

import (
        "strings"
        "unicode"
)

// TokenType represents the type of a lexed token.
type TokenType int

const (
        TokenOpcode   TokenType = iota
        TokenNumber             // Decimal (123), hex (0xFF), or negative (-42)
        TokenLabel              // Label definition: identifier followed by colon (loop:)
        TokenLabelRef           // Bare identifier used as label reference (in JMP/JZ operands)
        TokenColon              // ':' character
        TokenComment            // Comment (; or # to end of line)
        TokenEOF                // End of input
        TokenNewline            // Newline character
        TokenError              // Lexer error
        TokenDirective          // Data directive (.DB, .DW, .ASCII)
        TokenString             // Quoted string literal
)

// String returns a human-readable name for the token type.
func (t TokenType) String() string {
        switch t {
        case TokenOpcode:
                return "OPCODE"
        case TokenNumber:
                return "NUMBER"
        case TokenLabel:
                return "LABEL"
        case TokenLabelRef:
                return "LABEL_REF"
        case TokenColon:
                return "COLON"
        case TokenComment:
                return "COMMENT"
        case TokenEOF:
                return "EOF"
        case TokenNewline:
                return "NEWLINE"
        case TokenError:
                return "ERROR"
        case TokenDirective:
                return "DIRECTIVE"
        case TokenString:
                return "STRING"
        default:
                return "UNKNOWN"
        }
}

// Token represents a single lexed token with its type, value, and position.
type Token struct {
        Type  TokenType
        Value string
        Line  int
        Col   int
}

// knownOpcodes maps opcode mnemonic strings (uppercased) to their token status.
var knownOpcodes = map[string]bool{
        "NOP": true, "PUSH": true, "POP": true, "DUP": true, "SWAP": true,
        "ADD": true, "SUB": true, "MUL": true, "AND": true, "OR": true,
        "XOR": true, "NOT": true, "JMP": true, "JZ": true, "LOAD": true,
        "STORE": true, "HALT": true,
        "CALL": true, "RET": true, "CMP": true, "JNZ": true, "JC": true,
        "SHL": true, "SHR": true, "DIV": true,
}

// Lexer tokenizes FLUX assembly source code.
type Lexer struct {
        input string
        pos   int
        line  int
        col   int
}

// NewLexer creates a new lexer for the given input string.
func NewLexer(input string) *Lexer {
        return &Lexer{
                input: input,
                pos:   0,
                line:  1,
                col:   1,
        }
}

// peek returns the current character without advancing the position.
func (l *Lexer) peek() rune {
        if l.pos >= len(l.input) {
                return 0
        }
        return rune(l.input[l.pos])
}

// advance returns the current character and advances the position.
func (l *Lexer) advance() rune {
        if l.pos >= len(l.input) {
                return 0
        }
        ch := rune(l.input[l.pos])
        l.pos++
        if ch == '\n' {
                l.line++
                l.col = 1
        } else {
                l.col++
        }
        return ch
}

// skipWhitespace skips spaces and tabs (not newlines).
func (l *Lexer) skipWhitespace() {
        for l.pos < len(l.input) && (l.input[l.pos] == ' ' || l.input[l.pos] == '\t') {
                l.advance()
        }
}

// NextToken reads and returns the next token from the input.
func (l *Lexer) NextToken() Token {
        l.skipWhitespace()

        if l.pos >= len(l.input) {
                return Token{Type: TokenEOF, Value: "", Line: l.line, Col: l.col}
        }

        ch := l.peek()
        startLine := l.line
        startCol := l.col

        if ch == '\n' {
                l.advance()
                return Token{Type: TokenNewline, Value: "\n", Line: startLine, Col: startCol}
        }

        if ch == ';' || ch == '#' {
                l.advance()
                start := l.pos
                for l.pos < len(l.input) && l.peek() != '\n' {
                        l.advance()
                }
                val := l.input[start:l.pos]
                return Token{Type: TokenComment, Value: val, Line: startLine, Col: startCol}
        }

        if ch == ':' {
                l.advance()
                return Token{Type: TokenColon, Value: ":", Line: startLine, Col: startCol}
        }

        if ch == '\r' {
                l.advance()
                return l.NextToken()
        }

        if ch == '-' || (ch >= '0' && ch <= '9') {
                return l.readNumber()
        }

        if ch == '"' {
                return l.readString()
        }

        if ch == '.' {
                return l.readIdentifier()
        }

        if isIdentStart(ch) {
                return l.readIdentifier()
        }

        l.advance()
        return Token{Type: TokenError, Value: string(ch), Line: startLine, Col: startCol}
}

// readNumber lexes a numeric literal: decimal, hex (0x prefix), or negative.
func (l *Lexer) readNumber() Token {
        startLine := l.line
        startCol := l.col
        start := l.pos

        if l.peek() == '-' {
                l.advance()
        }

        if l.pos < len(l.input) && l.pos+1 < len(l.input) &&
                l.input[l.pos] == '0' && (l.input[l.pos+1] == 'x' || l.input[l.pos+1] == 'X') {
                l.advance()
                l.advance()
                for l.pos < len(l.input) && isHexDigit(rune(l.input[l.pos])) {
                        l.advance()
                }
                val := l.input[start:l.pos]
                if len(val) <= 2 {
                        return Token{Type: TokenError, Value: val, Line: startLine, Col: startCol}
                }
                return Token{Type: TokenNumber, Value: val, Line: startLine, Col: startCol}
        }

        for l.pos < len(l.input) && rune(l.input[l.pos]) >= '0' && rune(l.input[l.pos]) <= '9' {
                l.advance()
        }
        val := l.input[start:l.pos]
        if val == "-" {
                return Token{Type: TokenError, Value: val, Line: startLine, Col: startCol}
        }
        return Token{Type: TokenNumber, Value: val, Line: startLine, Col: startCol}
}

// readIdentifier lexes an identifier and classifies it.
func (l *Lexer) readIdentifier() Token {
        startLine := l.line
        startCol := l.col
        start := l.pos

        for l.pos < len(l.input) && isIdentPart(rune(l.input[l.pos])) {
                l.advance()
        }
        val := l.input[start:l.pos]
        upper := strings.ToUpper(val)

        if strings.HasPrefix(val, ".") {
                switch upper {
                case ".DB", ".DW", ".ASCII":
                        return Token{Type: TokenDirective, Value: upper, Line: startLine, Col: startCol}
                }
        }

        if knownOpcodes[upper] {
                return Token{Type: TokenOpcode, Value: upper, Line: startLine, Col: startCol}
        }

        if l.pos < len(l.input) && l.peek() == ':' {
                return Token{Type: TokenLabel, Value: val, Line: startLine, Col: startCol}
        }

        return Token{Type: TokenLabelRef, Value: val, Line: startLine, Col: startCol}
}

func isIdentStart(ch rune) bool {
        return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

func isIdentPart(ch rune) bool {
        return isIdentStart(ch) || (ch >= '0' && ch <= '9') || ch == '.'
}

// readString lexes a quoted string literal, handling escape sequences.
func (l *Lexer) readString() Token {
        // l.peek() is currently '"'
        l.advance() // consume opening quote
        startLine := l.line
        startCol := l.col
        var sb strings.Builder
        for l.pos < len(l.input) {
                ch := l.peek()
                if ch == '"' {
                        l.advance() // consume closing quote
                        return Token{Type: TokenString, Value: sb.String(), Line: startLine, Col: startCol}
                }
                if ch == '\\' {
                        l.advance()
                        esc := l.peek()
                        switch esc {
                        case 'n':
                                sb.WriteByte('\n')
                        case 't':
                                sb.WriteByte('\t')
                        case 'r':
                                sb.WriteByte('\r')
                        case '\\':
                                sb.WriteByte('\\')
                        case '"':
                                sb.WriteByte('"')
                        default:
                                sb.WriteByte('\\')
                                sb.WriteByte(byte(esc))
                        }
                        if esc != 0 {
                                l.advance()
                        }
                        continue
                }
                if ch == 0 || ch == '\n' {
                        return Token{Type: TokenError, Value: "unterminated string", Line: startLine, Col: startCol}
                }
                sb.WriteByte(byte(ch))
                l.advance()
        }
        return Token{Type: TokenError, Value: "unterminated string", Line: startLine, Col: startCol}
}

func isHexDigit(ch rune) bool {
        return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

// TokenizeAll tokenizes the entire input and returns all tokens.
func TokenizeAll(input string) []Token {
        lexer := NewLexer(input)
        var tokens []Token
        for {
                tok := lexer.NextToken()
                tokens = append(tokens, tok)
                if tok.Type == TokenEOF {
                        break
                }
        }
        return tokens
}

// FilterTokens filters out comments, newlines, and EOF tokens.
func FilterTokens(tokens []Token) []Token {
        var result []Token
        for _, t := range tokens {
                switch t.Type {
                case TokenComment, TokenNewline, TokenEOF:
                        continue
                }
                result = append(result, t)
        }
        return result
}

var _ = unicode.IsSpace
