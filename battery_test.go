package ecwcalc

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

// Differential battery: Go engine vs FPC port (which is byte-exact vs
// the original under Wine). Run: go test -run Battery
func fpc(expr string) string {
	// The FPC CLI outputs the result on stdout after '> expr'.
	// Path overridable via ECW_FPC_BIN (CI builds the CLI per-platform).
	bin := os.Getenv("ECW_FPC_BIN")
	if bin == "" {
		bin = "/tmp/ecw_fpc/ecw"
	}
	out, err := exec.Command(bin, expr).Output()
	if err != nil {
		return "ERROR: <fpc>"
	}
	s := strings.TrimSpace(string(out))
	if idx := strings.IndexByte(s, '\n'); idx >= 0 {
		return strings.TrimSpace(s[idx+1:])
	}
	return s
}

func TestBatteryVsFPC(t *testing.T) {
	// Skip unless the FPC oracle is actually available: `go test .` runs
	// this too, but only the dedicated battery step builds the oracle.
	bin := os.Getenv("ECW_FPC_BIN")
	if bin == "" {
		bin = "/tmp/ecw_fpc/ecw"
	}
	if _, err := os.Stat(bin); err != nil {
		t.Skipf("FPC oracle not found at %s (set ECW_FPC_BIN); skipping battery", bin)
	}
	exprs := []string{
		// arithmetic
		"2+3*4", "(1+2)*3", "2**10", "2**-2", "0**0", "10/4", "10//4", "10%4",
		"-8//3", "-8%3", "5-3-2", "100/3", "1/3", "1/7", "2/3", "1e2", "1e-2",
		"12.34e-56", "0.5e2", "1.5e3", "123e", "1e", "2.5e-3",
		// int semantics
		"0xFFFFFFFF", "0xFFFFFFFF+1", "0x80000000", "1<<31", "-8>>1", "1<<4",
		"0xAB>>4", "~0", "~5", "255&15", "255|15", "255^15", "0xFF<<8",
		"0xFFFF<<16", "1<<32", "0xAB", "0xABh", "0ABh", "101b", "12h", "12o",
		"012", "0x", "$AB", "$",
		// functions
		"sin(pi/2)", "cos(0)", "tan(pi/4)", "sqrt(2)", "sqrt(4)", "exp(1)",
		"ln(e)", "ln(1)", "log(100)", "log(10,100)", "fact(5)", "fact(0)",
		"abs(-3)", "sign(-5)", "sign(0)", "int(3.7)", "int(-3.7)", "frac(3.7)",
		"rad(180)", "deg(pi)", "sqr(5)", "ctan(pi/4)", "actan(1)",
		"sinh(1)", "cosh(1)", "tanh(1)", "asinh(1)", "acosh(2)", "atanh(0.5)",
		"asin(1)", "acos(0)", "atan(1)",
		// list fns
		"sum(1,2,3)", "prod(2,3,4)", "avg(1,2,3)", "geo(2,8)", "min(3,1,2)",
		"max(3,1,2)", "poly(2,1,2,3)",
		// comparisons / logic
		"1<2", "2<1", "2<=2", "3>=4", "1=1", "1==1", "1<>2", "1!=2",
		"1&&2", "0||1", "1^^0", "1^^1",
		// constants / vars
		"pi", "e", "z=1,(z+1/z)/2", "f(x)=x*x,f(5)", "g(x)=sin(x),g(pi/2)",
		"h(x)=x+1,h(h(10))",
		// format edges
		"0.1+0.2", "2**1000", "123456789.123456789", "0.33333333333333333333",
		"999999999.999999999", "9.99999999999999999", "123456789012345.6789",
		// errors
		"1/0", "ln(0)", "ln(-1)", "asin(2)", "sqrt(-1)", "fact(-1)", "fact(1.5)",
		"atanh(1)", "atanh(2)", "acosh(0)", "poly(1)", "sum(1)", "1e5+1e-5",
		"2+", "+2", "2 3", "sin", "SIN(1)", "unknownfunc(3)", "x", ")", "(1+2",
		"2**", "1e-", "0x12z", "2,3", "avg()",
	}
	// Documented f64-vs-Extended (80-bit) last-ULP differences: the FPC port
	// computes in x87 Extended like the original; Go has no 80-bit floats,
	// so transcendentals, pi/e and long literals can differ in the last ULP.
	// Semantics, error messages, integer/bit ops and formatting rules match.
	knownDiffs := map[string]bool{
		"100/3": true, "1/3": true, "1/7": true, "2/3": true, "tan(pi/4)": true,
		"sqrt(2)": true, "exp(1)": true, "frac(3.7)": true, "rad(180)": true,
		"ctan(pi/4)": true, "actan(1)": true, "sinh(1)": true, "cosh(1)": true,
		"tanh(1)": true, "asinh(1)": true, "acosh(2)": true, "atanh(0.5)": true,
		"asin(1)": true, "acos(0)": true, "atan(1)": true, "pi": true, "e": true,
		"0.1+0.2": true, "123456789.123456789": true, "0.33333333333333333333": true,
		"999999999.999999999": true, "9.99999999999999999": true,
		"123456789012345.6789": true, "1e5+1e-5": true,
	}
	pass, known, fail := 0, 0, 0
	var fails, knownFails []string
	for _, e := range exprs {
		r, err := EvalOne(e, false, 0)
		rs := r
		if err != nil {
			rs = "ERROR: " + err.Error()
		}
		f := fpc(e)
		if rs == f {
			pass++
		} else if knownDiffs[e] {
			known++
			knownFails = append(knownFails, e)
		} else {
			fail++
			fails = append(fails, e)
		}
	}
	t.Logf("battery: %d/%d exact, %d documented f64 last-ULP diffs, %d unexpected",
		pass, pass+known+fail, known, fail)
	for _, e := range knownFails {
		r, _ := EvalOne(e, false, 0)
		t.Logf("  [known] [%s] go=%s  fpc=%s", e, r, fpc(e))
	}
	for _, e := range fails {
		r, _ := EvalOne(e, false, 0)
		t.Logf("  [UNEXPECTED] [%s] go=%s  fpc=%s", e, r, fpc(e))
	}
	if fail != 0 {
		t.Fatalf("%d unexpected failures", fail)
	}
}
