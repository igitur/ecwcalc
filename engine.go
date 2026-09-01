// ============================================================================
// ECW Expression Calculator — Go engine
// Ported from the Rust engine (src/engine.rs in the vizia-port branch), which
// was ported from gui/ecwengine.pas (FreePascal), which was reverse-engineered
// from ecw.exe (v1.04-era, Delphi 3 RTL) and verified live against the
// original console engine (ec.exe v1.03b3) under Wine (188/188 differential
// tests pass byte-for-byte for the FPC port).
//
// Fidelity note: the original computes in x87 Extended (80-bit).  This Go
// port computes in float64, so last-ULP results of transcendental / division
// operations may differ from the original by 1 unit in the last place
// (identical to the Rust port — same IEEE-754 double arithmetic).  Parsing,
// operator semantics, error messages and formatting rules are ported verbatim.
// ============================================================================

package ecwcalc

import (
	"math"
	"strconv"
	"strings"
)

const (
	maxArgs  = 4000
	maxDefs  = 256
	maxDepth = 32
)

// UserDef is a user variable or function declaration.
type UserDef struct {
	Name     string
	IsFunc   bool
	NumArgs  int
	ArgNames []string
	Body     string
	Val      float64
}

type varBind struct {
	name string
	val  float64
}

// Engine evaluates ECW expressions and keeps user definitions across calls.
type Engine struct {
	s            []rune
	p            int
	err          string
	defs         []UserDef
	unsignedHex  bool
	sepMode      int // 0: '.' ',',  1: ',' ';',  2: '.' ';'
	locals       []varBind
	depth        int
	lastTokStart int
}

// New creates an engine with default settings.
func New() *Engine {
	return &Engine{}
}

// ---------- low-level helpers ----------

func (e *Engine) len() int { return len(e.s) }

func (e *Engine) peekC() rune {
	if e.p >= len(e.s) {
		return 0
	}
	return e.s[e.p]
}

func (e *Engine) peekC2() rune {
	if e.p+1 >= len(e.s) {
		return 0
	}
	return e.s[e.p+1]
}

func (e *Engine) nextC() rune {
	c := e.peekC()
	if c != 0 {
		e.p++
	}
	return c
}

func (e *Engine) setErr(m string) {
	if e.err == "" {
		e.err = m
	}
}

func isSp(c rune) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

func (e *Engine) skipWS() {
	for e.p < len(e.s) && isSp(e.s[e.p]) {
		e.p++
	}
}

func hexVal(c rune) int {
	switch {
	case c >= '0' && c <= '9':
		return int(c - '0')
	case c >= 'a' && c <= 'f':
		return int(c-'a') + 10
	case c >= 'A' && c <= 'F':
		return int(c-'A') + 10
	}
	return -1
}

func frac0(v float64) bool { return v-math.Trunc(v) == 0.0 }

func (e *Engine) decimalSep() rune {
	if e.sepMode == 1 {
		return ','
	}
	return '.'
}

func (e *Engine) listSepC() rune {
	if e.sepMode == 0 {
		return ','
	}
	return ';'
}

func (e *Engine) toInt(v float64, op string) (int64, bool) {
	if !frac0(v) {
		e.setErr("illegal real arg: " + op)
		return 0, false
	}
	if v > 9.223372036854775807e18 || v < -9.223372036854775808e18 {
		e.setErr("overflow in int arg: " + op)
		return 0, false
	}
	return int64(math.Round(v)), true
}

func (e *Engine) bitNot(v float64) float64 {
	if i, ok := e.toInt(v, "~"); ok {
		return float64(int32(^uint32(i)))
	}
	return 0.0
}

func (e *Engine) bitOp2(op string, a, b float64) float64 {
	ia, ok := e.toInt(a, op)
	if !ok {
		return 0.0
	}
	ib, ok := e.toInt(b, op)
	if !ok {
		return 0.0
	}
	ua, ub := uint32(ia), uint32(ib)
	switch op {
	case "&":
		return float64(int32(ua & ub))
	case "|":
		return float64(int32(ua | ub))
	case "^":
		return float64(int32(ua ^ ub))
	case "<<":
		if ib < 0 {
			e.setErr("illegal arg2<0: <<")
			return 0.0
		}
		c := int32(ib)
		if c >= 32 {
			return 0.0
		}
		return float64(int32(ua << uint(c)))
	case ">>":
		if ib < 0 {
			e.setErr("illegal arg2<0: >>")
			return 0.0
		}
		c := int32(ib)
		if c >= 32 {
			return 0.0
		}
		return float64(int32(ua >> uint(c)))
	}
	return 0.0
}

func (e *Engine) powE(x, y float64) float64 {
	if y == 0.0 {
		if x == 0.0 {
			return 0.0 // 0^0 = 0 (original)
		}
		return 1.0
	}
	if x == 0.0 {
		if y < 0.0 {
			e.setErr("overflow: **")
		}
		return 0.0
	}
	// integer-exponent fast path: exponentiation by squaring
	if frac0(y) && math.Abs(y) <= 1e9 {
		n := int64(math.Round(y))
		neg := n < 0
		if neg {
			n = -n
		}
		base := x
		acc := 1.0
		for n > 0 {
			if n&1 != 0 {
				acc *= base
			}
			n >>= 1
			if n > 0 {
				base *= base
			}
		}
		if neg {
			if acc == 0.0 {
				e.setErr("overflow: **")
				return 0.0
			}
			acc = 1.0 / acc
		}
		if math.IsInf(acc, 0) || math.IsNaN(acc) {
			e.setErr("overflow: **")
			return 0.0
		}
		return acc
	}
	var r float64
	if x < 0.0 {
		if !frac0(y) {
			e.setErr("invalid usage: **")
			return 0.0
		}
		sgn := 1.0
		if math.Mod(math.Abs(y), 2.0) == 1.0 {
			sgn = -1.0
		}
		r = sgn * math.Exp(y*math.Log(-x))
	} else {
		r = math.Exp(y * math.Log(x))
	}
	if math.IsInf(r, 0) || math.IsNaN(r) {
		e.setErr("overflow: **")
	}
	return r
}

func (e *Engine) fact(a float64) float64 {
	if a < 0.0 {
		e.setErr("illegal arg<0: fact")
		return 0.0
	}
	if !frac0(a) {
		e.setErr("illegal real arg: fact")
		return 0.0
	}
	if a > 1750.0 {
		e.setErr("overflow: fact")
		return 0.0
	}
	r := 1.0
	for i := int64(2); i <= int64(math.Trunc(a)); i++ {
		r *= float64(i)
	}
	return r
}

func (e *Engine) callStd(a float64, fname string) float64 {
	var r float64
	switch fname {
	case "sin":
		r = math.Sin(a)
	case "cos":
		r = math.Cos(a)
	case "tan":
		r = math.Tan(a)
	case "ctan":
		if a == 0.0 {
			e.setErr("overflow: ctan")
			return 0.0
		}
		r = math.Cos(a) / math.Sin(a)
	case "asin":
		if a < -1.0 || a > 1.0 {
			e.setErr("illegal |arg|>1: asin")
			return 0.0
		}
		r = math.Asin(a)
	case "acos":
		if a < -1.0 || a > 1.0 {
			e.setErr("illegal |arg|>1: acos")
			return 0.0
		}
		r = math.Acos(a)
	case "atan":
		r = math.Atan(a)
	case "actan":
		if a == 0.0 {
			e.setErr("overflow: actan")
			return 0.0
		}
		r = math.Pi/2.0 - math.Atan(a)
	case "sinh":
		r = (math.Exp(a) - math.Exp(-a)) / 2.0
	case "cosh":
		r = (math.Exp(a) + math.Exp(-a)) / 2.0
	case "tanh":
		e2 := math.Exp(2.0 * a)
		r = (e2 - 1.0) / (e2 + 1.0)
	case "asinh":
		r = math.Log(a + math.Sqrt(a*a+1.0))
	case "acosh":
		if a < 1.0 {
			e.setErr("illegal arg<1: acosh")
			return 0.0
		}
		r = math.Log(a + math.Sqrt(a*a-1.0))
	case "atanh":
		if a == 1.0 || a == -1.0 {
			e.setErr("overflow: atanh")
			return 0.0
		}
		if a > 1.0 || a < -1.0 {
			e.setErr("illegal |arg|>1: atanh")
			return 0.0
		}
		r = 0.5 * math.Log((1.0+a)/(1.0-a))
	case "exp":
		r = math.Exp(a)
	case "ln":
		if a < 0.0 {
			e.setErr("illegal arg<0: ln")
			return 0.0
		}
		if a == 0.0 {
			e.setErr("overflow: ln")
			return 0.0
		}
		r = math.Log(a)
	case "log":
		if a < 0.0 {
			e.setErr("illegal arg<0: log")
			return 0.0
		}
		if a == 0.0 {
			e.setErr("overflow: log")
			return 0.0
		}
		r = math.Log(a) / math.Log(10.0)
	case "sqr":
		r = a * a
	case "sqrt":
		if a < 0.0 {
			e.setErr("illegal arg<0: sqrt")
			return 0.0
		}
		r = math.Sqrt(a)
	case "fact":
		return e.fact(a)
	case "abs":
		r = math.Abs(a)
	case "sign":
		if a > 0.0 {
			r = 1.0
		} else if a < 0.0 {
			r = -1.0
		} else {
			r = 0.0
		}
	case "int":
		r = math.Trunc(a)
	case "frac":
		r = a - math.Trunc(a)
	case "rad":
		r = a * (math.Pi / 180.0)
	case "deg":
		r = a * (180.0 / math.Pi)
	default:
		e.setErr("unknown function: " + fname)
		return 0.0
	}
	if (math.IsInf(r, 0) || math.IsNaN(r)) && e.err == "" {
		e.setErr("overflow: " + fname)
	}
	return r
}

func (e *Engine) callList(fname string, a []float64) float64 {
	n := len(a)
	var r float64
	switch fname {
	case "sum":
		for _, x := range a {
			r += x
		}
	case "prod":
		r = 1.0
		for _, x := range a {
			r *= x
		}
	case "avg":
		s := 0.0
		for _, x := range a {
			s += x
		}
		if n == 0 {
			r = 0.0
		} else {
			r = s / float64(n)
		}
	case "geo":
		p := 1.0
		for _, x := range a {
			p *= x
		}
		if n == 0 {
			r = 0.0
		} else if p == 0.0 {
			r = 0.0
		} else if p < 0.0 {
			r = -e.powE(-p, 1.0/float64(n))
		} else {
			r = e.powE(p, 1.0/float64(n))
		}
	case "min":
		r = a[0]
		for i := 1; i < n; i++ {
			if a[i] < r {
				r = a[i]
			}
		}
	case "max":
		r = a[0]
		for i := 1; i < n; i++ {
			if a[i] > r {
				r = a[i]
			}
		}
	case "poly":
		if n < 2 {
			e.setErr("missing arg2: poly")
			return 0.0
		}
		acc := 0.0
		for i := n - 1; i >= 1; i-- {
			acc = acc*a[0] + a[i]
		}
		r = acc
	default:
		e.setErr("unknown list function: " + fname)
		return 0.0
	}
	if (math.IsInf(r, 0) || math.IsNaN(r)) && e.err == "" {
		e.setErr("overflow: " + fname)
	}
	return r
}

func isListFunc(name string) bool {
	switch name {
	case "sum", "prod", "avg", "geo", "min", "max":
		return true
	}
	return false
}

func isBuiltinName(name string) bool {
	switch name {
	case "sin", "cos", "tan", "ctan", "asin", "acos", "atan", "actan",
		"sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
		"exp", "ln", "log", "sqr", "sqrt", "fact", "abs", "sign", "int", "frac", "rad", "deg",
		"sum", "prod", "avg", "geo", "min", "max", "poly", "pi", "e":
		return true
	}
	return false
}

func (e *Engine) lookupVar(name string) (float64, bool) {
	for i := len(e.locals) - 1; i >= 0; i-- {
		if e.locals[i].name == name {
			return e.locals[i].val, true
		}
	}
	for _, d := range e.defs {
		if !d.IsFunc && d.Name == name {
			return d.Val, true
		}
	}
	if name == "pi" {
		return math.Pi, true
	}
	if name == "e" {
		return math.Exp(1.0), true
	}
	return 0, false
}

func (e *Engine) findUserFunc(name string, wantArgs int) (int, bool) {
	for i, d := range e.defs {
		if d.IsFunc && d.Name == name && d.NumArgs == wantArgs {
			return i, true
		}
	}
	return 0, false
}

func (e *Engine) evalUserFunc(di int, args []float64) float64 {
	if e.depth >= maxDepth {
		e.setErr("too complex definition")
		return 0.0
	}
	savedLocals := e.locals
	e.locals = nil
	for i, an := range e.defs[di].ArgNames {
		e.locals = append(e.locals, varBind{an, args[i]})
	}
	oldS := e.s
	oldP := e.p
	e.s = []rune(e.defs[di].Body)
	e.p = 0
	e.depth++
	r := e.parseExpr(0)
	e.depth--
	if e.err == "" {
		e.skipWS()
		if e.p < len(e.s) {
			e.setErr("invalid expression: " + string(e.s[e.p]))
		}
	}
	e.s = oldS
	e.p = oldP
	e.locals = savedLocals
	return r
}

func (e *Engine) evalCall(name string) float64 {
	var args []float64
	e.skipWS()
	if e.peekC() == ')' {
		e.setErr("missing expression")
		return 0.0
	}
	for {
		if len(args) >= maxArgs {
			e.setErr("too many args: " + name)
			return 0.0
		}
		args = append(args, e.parseExpr(0))
		if e.err != "" {
			return 0.0
		}
		e.skipWS()
		if e.peekC() == e.listSepC() {
			e.nextC()
			e.skipWS()
			if e.peekC() == ')' {
				e.setErr("missing expression")
				return 0.0
			}
			continue
		}
		break
	}
	if e.peekC() != ')' {
		e.setErr("missing operator: " + name)
		return 0.0
	}
	e.nextC()

	if len(args) == 1 {
		if di, ok := e.findUserFunc(name, 1); ok {
			return e.evalUserFunc(di, args)
		}
		r := e.callStd(args[0], name)
		if e.err == "invalid expression: "+name {
			e.err = "unknown function: " + name
		}
		return r
	}

	if di, ok := e.findUserFunc(name, len(args)); ok {
		return e.evalUserFunc(di, args)
	}

	if name == "log" && len(args) == 2 {
		if args[1] <= 0.0 {
			e.setErr("overflow: log")
			return 0.0
		}
		if args[0] <= 0.0 || args[0] == 1.0 {
			e.setErr("overflow: log")
			return 0.0
		}
		r := math.Log(args[1]) / math.Log(args[0])
		if math.IsInf(r, 0) || math.IsNaN(r) {
			e.setErr("overflow: log")
		}
		return r
	}

	return e.callList(name, args)
}

func precedence(op string) int {
	switch op {
	case "*", "/", "**", "//", "%":
		return 50
	case "+", "-":
		return 40
	case "&", "|", "^", "&&", "||", "^^", "<<", ">>":
		return 30
	case "=", "==", "<>", "!=", "<", ">", "<=", ">=":
		return 20
	}
	return 0
}

func (e *Engine) peekOp() string {
	c1 := e.peekC()
	c2 := e.peekC2()
	var op string
	switch c1 {
	case '*':
		if c2 == '*' {
			op = "**"
		} else {
			op = "*"
		}
	case '/':
		if c2 == '/' {
			op = "//"
		} else {
			op = "/"
		}
	case '<':
		if c2 == '=' {
			op = "<="
		} else if c2 == '>' {
			op = "<>"
		} else if c2 == '<' {
			op = "<<"
		} else {
			op = "<"
		}
	case '>':
		if c2 == '=' {
			op = ">="
		} else if c2 == '>' {
			op = ">>"
		} else {
			op = ">"
		}
	case '=':
		if c2 == '=' {
			op = "=="
		} else {
			op = "="
		}
	case '!':
		if c2 == '=' {
			op = "!="
		} else {
			op = "!"
		}
	case '&':
		if c2 == '&' {
			op = "&&"
		} else {
			op = "&"
		}
	case '|':
		if c2 == '|' {
			op = "||"
		} else {
			op = "|"
		}
	case '^':
		if c2 == '^' {
			op = "^^"
		} else {
			op = "^"
		}
	case '+', '-', '%', '~', '(', ')', ',', ';':
		op = string(c1)
	default:
		return ""
	}
	return op
}

func (e *Engine) applyOp(op string, a, b float64) float64 {
	var r float64
	switch op {
	case "+":
		r = a + b
	case "-":
		r = a - b
	case "*":
		r = a * b
	case "/":
		if b == 0.0 {
			e.setErr("overflow: /")
			return 0.0
		}
		r = a / b
	case "**":
		return e.powE(a, b)
	case "//":
		ia, ok := e.toInt(a, "//")
		if !ok {
			return 0.0
		}
		ib, ok := e.toInt(b, "//")
		if !ok {
			return 0.0
		}
		if ib == 0 {
			e.setErr("illegal arg2=0: //")
			return 0.0
		}
		r = float64(ia / ib)
	case "%":
		ia, ok := e.toInt(a, "%")
		if !ok {
			return 0.0
		}
		ib, ok := e.toInt(b, "%")
		if !ok {
			return 0.0
		}
		if ib == 0 {
			e.setErr("illegal arg2=0: %")
			return 0.0
		}
		r = float64(ia % ib)
	case "&", "|", "^", "<<", ">>":
		return e.bitOp2(op, a, b)
	case "=", "==":
		if a == b {
			r = 1.0
		} else {
			r = 0.0
		}
	case "<>", "!=":
		if a != b {
			r = 1.0
		} else {
			r = 0.0
		}
	case "<":
		if a < b {
			r = 1.0
		} else {
			r = 0.0
		}
	case ">":
		if a > b {
			r = 1.0
		} else {
			r = 0.0
		}
	case "<=":
		if a <= b {
			r = 1.0
		} else {
			r = 0.0
		}
	case ">=":
		if a >= b {
			r = 1.0
		} else {
			r = 0.0
		}
	case "&&":
		if a != 0.0 && b != 0.0 {
			r = 1.0
		} else {
			r = 0.0
		}
	case "||":
		if a != 0.0 || b != 0.0 {
			r = 1.0
		} else {
			r = 0.0
		}
	case "^^":
		if (a != 0.0) != (b != 0.0) {
			r = 1.0
		} else {
			r = 0.0
		}
	default:
		e.setErr("unknown operator: " + op)
		return 0.0
	}
	if (math.IsInf(r, 0) || math.IsNaN(r)) && e.err == "" {
		e.setErr("overflow: " + op)
	}
	return r
}

func (e *Engine) evalBaseConst(d string, base int64, kind string) float64 {
	var hx uint64
	for _, ch := range d {
		dv := int64(hexVal(ch))
		if dv < 0 || dv >= base {
			e.setErr("invalid " + kind + ": " + strings.ToLower(d))
			return 0.0
		}
		if hx > (^uint64(0)-uint64(dv))/uint64(base) {
			e.setErr("overflow in " + kind + ": " + strings.ToLower(d))
			return 0.0
		}
		hx = hx*uint64(base) + uint64(dv)
	}
	neg := hx >= 0x80000000
	if !e.unsignedHex {
		if hx > 0xFFFFFFFF {
			e.setErr("overflow in " + kind + ": " + strings.ToLower(d))
			return 0.0
		}
		if neg {
			return float64(int64(hx) - 0x100000000)
		}
		return float64(hx)
	}
	return float64(hx)
}

// scalePow10 multiplies/divides by an exact power of ten (10^k for |k| <= 22
// is exactly representable in float64, so a single multiply/divide is
// correctly rounded).
func scalePow10(v float64, k int32) float64 {
	if k == 0 {
		return v
	}
	neg := k < 0
	if neg {
		k = -k
	}
	p := 1.0
	for i := int32(0); i < k; i++ {
		p *= 10.0
	}
	if neg {
		return v / p
	}
	return v * p
}

func (e *Engine) tryParseReal() (float64, bool) {
	if e.p >= len(e.s) {
		return 0, false
	}
	c := e.peekC()
	if !(isDigit(c) || c == e.decimalSep()) {
		return 0, false
	}

	start := e.p
	// integer part
	var mant int64
	had := false
	overflowed := false
	for e.p < len(e.s) && isDigit(e.s[e.p]) {
		if !overflowed {
			dv := int64(e.s[e.p] - '0')
			if mant > (1<<63-1-dv)/10 {
				overflowed = true
			} else {
				mant = mant*10 + dv
			}
		}
		e.p++
		had = true
	}
	// fraction part
	var fracDigits int32
	if e.p < len(e.s) && e.s[e.p] == e.decimalSep() {
		e.p++
		for e.p < len(e.s) && isDigit(e.s[e.p]) {
			if !overflowed {
				dv := int64(e.s[e.p] - '0')
				if mant > (1<<63-1-dv)/10 {
					overflowed = true
				} else {
					mant = mant*10 + dv
				}
			}
			e.p++
			had = true
			fracDigits++
		}
	}
	if !had {
		return 0, false
	}

	// exponent suffix
	var ex int32
	signe := int32(1)
	if e.p < len(e.s) && (e.s[e.p] == 'e' || e.s[e.p] == 'E') {
		e.p++
		if e.p < len(e.s) && (e.s[e.p] == '+' || e.s[e.p] == '-') {
			if e.s[e.p] == '-' {
				signe = -1
			} else {
				signe = 1
			}
			e.p++
		}
		if e.p >= len(e.s) || !isDigit(e.s[e.p]) {
			// "1e" with no exponent digits: value is just the mantissa;
			// back up so the caller reports the trailing garbage.
			if e.p > 0 {
				e.p--
			}
			if signe == -1 && e.p > 0 {
				e.p--
			}
			return 0.0, true
		}
		for e.p < len(e.s) && isDigit(e.s[e.p]) {
			ex = ex*10 + int32(e.s[e.p]-'0')
			if ex > 5000 {
				break
			}
			e.p++
		}
		ex *= signe
	}

	// Val-style: integer mantissa * 10^(ex - fracDigits)
	scale := ex - fracDigits
	if overflowed {
		v := 0.0
		q := start
		for q < len(e.s) && isDigit(e.s[q]) {
			v = v*10.0 + float64(e.s[q]-'0')
			q++
		}
		if q < len(e.s) && e.s[q] == e.decimalSep() {
			q++
			for q < len(e.s) && isDigit(e.s[q]) {
				v = v*10.0 + float64(e.s[q]-'0')
				q++
			}
		}
		return scalePow10(v, scale), true
	}
	v := float64(mant)
	if scale != 0 {
		v = scalePow10(v, scale)
	}
	return v, true
}

func isDigit(c rune) bool { return c >= '0' && c <= '9' }
func isAlpha(c rune) bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}
func isAlnum(c rune) bool { return isDigit(c) || isAlpha(c) }

func (e *Engine) tryParseNumber() (float64, bool) {
	save := e.p
	c := e.peekC()

	if c == '$' {
		e.nextC()
		var h strings.Builder
		for e.p < len(e.s) && hexVal(e.s[e.p]) >= 0 {
			h.WriteRune(e.s[e.p])
			e.p++
		}
		if h.Len() == 0 {
			e.p = save
			return 0, false // bare '$': fall to invalid char
		}
		return e.evalBaseConst(h.String(), 16, "hex"), true
	}

	if c == '0' && (e.peekC2() == 'x' || e.peekC2() == 'X') {
		e.p += 2
		var h strings.Builder
		for e.p < len(e.s) && hexVal(e.s[e.p]) >= 0 {
			h.WriteRune(e.s[e.p])
			e.p++
		}
		if h.Len() == 0 {
			return 0.0, true // "0x" -> 0
		}
		// if a non-hex alnum char follows, report it as part of invalid hex
		if e.p < len(e.s) && isAlnum(e.s[e.p]) {
			h.WriteRune(e.s[e.p])
			e.p++
			e.setErr("invalid hex: " + strings.ToLower(h.String()))
			return 0.0, true
		}
		return e.evalBaseConst(h.String(), 16, "hex"), true
	}

	// hex-digit run: catches 12h, 0ABh, 101b, 12o, and plain numbers
	var h strings.Builder
	for e.p < len(e.s) && hexVal(e.s[e.p]) >= 0 {
		h.WriteRune(e.s[e.p])
		e.p++
	}

	// suffix char following the run: 12h / 0ABh / 101b / 12o
	if h.Len() > 0 && e.p < len(e.s) && isSuffix(e.s[e.p]) {
		sc := lowerASCII(e.s[e.p])
		e.p++
		switch sc {
		case 'h':
			return e.evalBaseConst(h.String(), 16, "hex"), true
		case 'o':
			return e.evalBaseConst(h.String(), 8, "oct"), true
		case 'b':
			return e.evalBaseConst(h.String(), 2, "bin"), true
		}
	}

	// trailing-suffix form: "101b" — the 'b' got absorbed into h
	hs := h.String()
	if len(hs) >= 2 && isSuffix(rune(hs[len(hs)-1])) {
		sc := lowerASCII(rune(hs[len(hs)-1]))
		hs = hs[:len(hs)-1]
		switch sc {
		case 'h':
			return e.evalBaseConst(hs, 16, "hex"), true
		case 'o':
			return e.evalBaseConst(hs, 8, "oct"), true
		case 'b':
			return e.evalBaseConst(hs, 2, "bin"), true
		}
	}

	// leading-zero octal: 012 = 10
	if len(hs) > 1 && hs[0] == '0' && e.p >= len(e.s) {
		bad := false
		for i := 0; i < len(hs); i++ {
			if !(hs[i] >= '0' && hs[i] <= '7') {
				bad = true
				break
			}
		}
		if !bad {
			return e.evalBaseConst(hs, 8, "oct"), true
		}
	}

	// decimal / real: rewind and parse with tryParseReal
	e.p = save
	r, ok := e.tryParseReal()
	if !ok && e.p < len(e.s) && hexVal(e.s[e.p]) >= 0 {
		e.setErr("invalid number: " + string(e.s[e.p]))
	}
	return r, ok
}

func isSuffix(c rune) bool {
	switch c {
	case 'h', 'H', 'o', 'O', 'b', 'B':
		return true
	}
	return false
}

func lowerASCII(c rune) rune {
	if c >= 'A' && c <= 'Z' {
		return c + 32
	}
	return c
}

func (e *Engine) parsePrimary() float64 {
	e.skipWS()
	c := e.peekC()

	if c == '(' {
		e.nextC()
		v := e.parseExpr(0)
		if e.err != "" {
			return v
		}
		e.skipWS()
		if e.peekC() != ')' {
			e.setErr("invalid brackets")
			return 0.0
		}
		e.nextC()
		return v
	}

	if c == ')' {
		e.setErr("invalid brackets")
		return 0.0
	}

	if c == 0 {
		e.setErr("missing expression")
		return 0.0
	}

	if isDigit(c) || c == e.decimalSep() || c == '$' {
		e.lastTokStart = e.p
		if v, ok := e.tryParseNumber(); ok {
			return v
		}
		return 0.0
	}

	if isAlpha(c) || c == '_' {
		e.lastTokStart = e.p
		var name strings.Builder
		for e.p < len(e.s) && (isAlnum(e.s[e.p]) || e.s[e.p] == '_') {
			name.WriteRune(e.s[e.p])
			e.p++
		}
		e.skipWS()
		if e.peekC() == '(' {
			e.nextC()
			return e.evalCall(name.String())
		}
		if v, ok := e.lookupVar(name.String()); ok {
			return v
		}
		// unknown or builtin without parens: same message
		e.setErr("invalid expression: " + name.String())
		return 0.0
	}

	e.setErr("invalid char: " + string(c))
	return 0.0
}

func (e *Engine) parseUnary() float64 {
	e.skipWS()
	c := e.peekC()
	switch c {
	case '+':
		e.nextC()
		return e.parseUnary()
	case '-':
		e.nextC()
		return -e.parseUnary()
	case '~':
		e.nextC()
		v := e.parseUnary()
		return e.bitNot(v)
	case '!':
		e.nextC()
		if e.parseUnary() == 0.0 {
			return 1.0
		}
		return 0.0
	}
	return e.parsePrimary()
}

func (e *Engine) parseExpr(minLev int) float64 {
	a := e.parseUnary()
	if e.err != "" {
		return a
	}
	for {
		e.skipWS()
		op := e.peekOp()
		if op == "" {
			break
		}
		lev := precedence(op)
		if lev == 0 || lev < minLev {
			break
		}
		if op == ")" || op == "," || op == ";" {
			break
		}
		e.p += len(op) // consume full operator (incl. multi-char)
		e.skipWS()
		if e.p >= len(e.s) {
			e.setErr("missing arg2: " + op)
			break
		}
		b := e.parseExpr(lev + 1) // left-assoc: RHS binds tighter
		if e.err != "" {
			break
		}
		a = e.applyOp(op, a, b)
		if e.err != "" {
			break
		}
	}
	return a
}

func (e *Engine) addDef(name string, isFunc bool, numArgs int, argNames []string, body string, val float64) {
	if len(e.defs) >= maxDefs {
		e.setErr("too many definitions")
		return
	}
	// replace existing
	for i := range e.defs {
		if e.defs[i].Name == name {
			e.defs[i].IsFunc = isFunc
			e.defs[i].NumArgs = numArgs
			e.defs[i].Body = body
			e.defs[i].Val = val
			e.defs[i].ArgNames = append([]string(nil), argNames...)
			return
		}
	}
	e.defs = append(e.defs, UserDef{
		Name: name, IsFunc: isFunc, NumArgs: numArgs,
		ArgNames: append([]string(nil), argNames...),
		Body: body, Val: val,
	})
}

// parseToplevel: [var=val, ...] expr  or  [f(args)=body, ...] expr
func (e *Engine) parseToplevel() float64 {
	e.locals = nil
	for {
		e.skipWS()
		save := e.p

		// detect: identifier ['(' args ')'] '=' (peek only)
		looksLikeDef := false
		var name strings.Builder
		if e.p < len(e.s) && (isAlpha(e.s[e.p]) || e.s[e.p] == '_') {
			looksLikeDef = true
		}

		if looksLikeDef {
			numArgs := 0
			var argNames []string
			q := e.p
			// scan name
			for q < len(e.s) && (isAlnum(e.s[q]) || e.s[q] == '_') {
				name.WriteRune(e.s[q])
				q++
			}
			// skip ws
			for q < len(e.s) && isSp(e.s[q]) {
				q++
			}
			if q < len(e.s) && e.s[q] == '(' {
				q++
				for q < len(e.s) && isSp(e.s[q]) {
					q++
				}
				if q < len(e.s) && e.s[q] == ')' {
					q++
				} else {
					for {
						if numArgs >= 64 {
							e.setErr("too many args: " + name.String())
							return 0.0
						}
						var an strings.Builder
						for q < len(e.s) && (isAlnum(e.s[q]) || e.s[q] == '_') {
							an.WriteRune(e.s[q])
							q++
						}
						argNames = append(argNames, an.String())
						numArgs++
						for q < len(e.s) && isSp(e.s[q]) {
							q++
						}
						if q < len(e.s) && e.s[q] == e.listSepC() {
							q++
							for q < len(e.s) && isSp(e.s[q]) {
								q++
							}
							continue
						}
						if q < len(e.s) && e.s[q] == ')' {
							q++
							break
						}
						looksLikeDef = false
						break
					}
				}
				for q < len(e.s) && isSp(e.s[q]) {
					q++
				}
				if looksLikeDef {
					if q >= len(e.s) || e.s[q] != '=' {
						looksLikeDef = false
					}
				}
			} else {
				for q < len(e.s) && isSp(e.s[q]) {
					q++
				}
				if q >= len(e.s) || e.s[q] != '=' {
					looksLikeDef = false
				}
			}
			if !looksLikeDef {
				e.p = save
			} else {
				// committed: q points at '='
				e.p = q
				// consume '='
				e.nextC()
				e.skipWS()
				if e.peekC() == e.listSepC() {
					e.setErr("missing expression")
					return 0.0
				}
				if numArgs > 0 {
					// capture body text up to top-level list separator
					var body strings.Builder
					depthScan := 0
					for e.p < len(e.s) {
						ch := e.s[e.p]
						if ch == '(' {
							depthScan++
						} else if ch == ')' {
							if depthScan > 0 {
								depthScan--
							} else {
								break
							}
						} else if ch == e.listSepC() && depthScan == 0 {
							break
						}
						body.WriteRune(ch)
						e.p++
					}
					bodyStr := strings.TrimSpace(body.String())
					if bodyStr == "" {
						e.setErr("missing expression")
						return 0.0
					}
					e.addDef(name.String(), true, numArgs, argNames, bodyStr, 0.0)
				} else {
					v := e.parseExpr(0)
					if e.err != "" {
						return v
					}
					e.addDef(name.String(), false, 0, nil, "", v)
				}
				e.skipWS()
				if e.peekC() == e.listSepC() {
					e.nextC()
					continue
				}
				if e.p >= len(e.s) {
					e.setErr("invalid expression: " + name.String())
					return 0.0
				}
				v := e.parseExpr(0)
				return v
			}
		}

		// not a definition: parse the final expression
		e.p = save
		v := e.parseExpr(0)
		if e.err != "" {
			return v
		}
		e.skipWS()
		if e.p < len(e.s) {
			// trailing garbage
			if e.s[e.p] == e.listSepC() {
				seg := string(e.s[save:e.p])
				e.setErr("invalid var definition: " + seg)
			} else {
				seg := string(e.s[e.lastTokStart:])
				e.setErr("invalid expression: " + seg)
			}
		}
		return v
	}
}

// ---------- public API ----------

// EvalExpr evaluates a full expression line. On success the returned error is
// nil and the float64 is the result; on error the float64 is unspecified.
func (e *Engine) EvalExpr(expr string) (float64, error) {
	e.s = []rune(expr)
	e.p = 0
	e.err = ""
	e.depth = 0
	v := e.parseToplevel()
	e.skipWS()
	if e.err == "" && e.p < len(e.s) {
		e.err = "invalid expression: " + string(e.s[e.p])
	}
	if e.err == "" {
		return v, nil
	}
	return v, errEngine{e.err}
}

type errEngine struct{ m string }

func (e errEngine) Error() string { return e.m }

// SetUnsignedHex controls how 32-bit hex constants are interpreted.
func (e *Engine) SetUnsignedHex(b bool) { e.unsignedHex = b }

// SetSepMode sets the decimal/list separator mode (0: '.' ',', 1: ',' ';',
// 2: '.' ';').
func (e *Engine) SetSepMode(m int) { e.sepMode = m }

// DecimalSep returns the active decimal separator.
func (e *Engine) DecimalSep() rune { return e.decimalSep() }

// ListSep returns the active list separator.
func (e *Engine) ListSep() rune { return e.listSepC() }

// AddDefDecl adds a "name=value" / "name(args)=body" declaration.
// Returns nil on success, an error message on failure.
func (e *Engine) AddDefDecl(decl string) error {
	tmp := decl + string(e.listSepC()) + "0"
	if _, err := e.EvalExpr(tmp); err != nil {
		return err
	}
	return nil
}

// NumDefs returns the number of stored definitions.
func (e *Engine) NumDefs() int { return len(e.defs) }

// DefName returns the name of definition i.
func (e *Engine) DefName(i int) string {
	if i >= 0 && i < len(e.defs) {
		return e.defs[i].Name
	}
	return ""
}

// DefIsFunc reports whether definition i is a function.
func (e *Engine) DefIsFunc(i int) bool {
	if i >= 0 && i < len(e.defs) {
		return e.defs[i].IsFunc
	}
	return false
}

// DefDecl returns the declaration text "name(args)=body" / "name=value".
func (e *Engine) DefDecl(i int) string {
	if i < 0 || i >= len(e.defs) {
		return ""
	}
	d := e.defs[i]
	if d.IsFunc {
		var sb strings.Builder
		sb.WriteString(d.Name)
		sb.WriteRune('(')
		for j, an := range d.ArgNames {
			if j > 0 {
				sb.WriteRune(e.listSepC())
			}
			sb.WriteString(an)
		}
		sb.WriteString(")=" + d.Body)
		return sb.String()
	}
	return d.Name + "=" + strconv.FormatFloat(d.Val, 'g', -1, 64)
}

// DefBody returns the body of definition i.
func (e *Engine) DefBody(i int) string {
	if i >= 0 && i < len(e.defs) {
		return e.defs[i].Body
	}
	return ""
}

// DeleteDef removes definition i.
func (e *Engine) DeleteDef(i int) {
	if i < 0 || i >= len(e.defs) {
		return
	}
	e.defs = append(e.defs[:i], e.defs[i+1:]...)
}

// ClearDefs removes all definitions.
func (e *Engine) ClearDefs() { e.defs = nil }

// UpdateDefBody replaces the body of definition i after validating it.
func (e *Engine) UpdateDefBody(idx int, body string) error {
	if idx < 0 || idx >= len(e.defs) {
		return errEngine{"invalid def index"}
	}
	d := &e.defs[idx]
	savedLocals := e.locals
	e.locals = nil
	var args []string
	if d.IsFunc {
		for _, a := range d.ArgNames {
			e.locals = append(e.locals, varBind{a, 0.0})
			args = append(args, a)
		}
	}
	var expr string
	if len(args) == 0 {
		expr = body + "0"
	} else {
		expr = body + "(" + strings.Join(args, string(e.listSepC())) + ")0"
	}
	_, err := e.EvalExpr(expr)
	e.locals = savedLocals
	if err != nil {
		return err
	}
	d.Body = body
	return nil
}
