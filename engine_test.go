package ecwcalc

import "testing"

func ev(expr string) string {
	r, err := EvalOne(expr, false, 0)
	if err != nil {
		return "ERROR: " + err.Error()
	}
	return r
}

func TestBasics(t *testing.T) {
	cases := []struct{ expr, want string }{
		{"2+3*4", "14"},
		{"sin(pi/2)", "1"},
		{"0xAB", "171"},
		{"2**10", "1024"},
		{"1/3", "0.33333333333333331"}, // f64: 17-decimals of 0.3333333333333333148…
		{"(1+2)*3", "9"},
		{"2<3", "1"},
		{"5%2", "1"},
		{"1<<4", "16"},
	}
	for _, c := range cases {
		if got := ev(c.expr); got != c.want {
			t.Errorf("%s: got %q want %q", c.expr, got, c.want)
		}
	}
}

func TestErrors(t *testing.T) {
	cases := []struct{ expr, want string }{
		{"1e", "ERROR: invalid expression: 1e"},
		{"SIN(1)", "ERROR: unknown function: SIN"},
		{"unknownfunc(3)", "ERROR: unknown function: unknownfunc"},
		{"poly(1)", "ERROR: unknown function: poly"},
		{")", "ERROR: invalid brackets"},
	}
	for _, c := range cases {
		if got := ev(c.expr); got != c.want {
			t.Errorf("%s: got %q want %q", c.expr, got, c.want)
		}
	}
}

func TestDefs(t *testing.T) {
	cases := []struct{ expr, want string }{
		{"f(x)=x*x,f(5)", "25"},
		{"z=1,(z+1/z)/2", "1"},
		{"g(x)=sin(x),g(pi/2)", "1"},
	}
	for _, c := range cases {
		if got := ev(c.expr); got != c.want {
			t.Errorf("%s: got %q want %q", c.expr, got, c.want)
		}
	}
}

func TestFormatting(t *testing.T) {
	cases := []struct {
		expr string
		dec, hex, bin, oct, exp string
	}{
		{"2**1000", "1.07150860718627E+0301", "00000000", "00000000000000000000000000000000", "00000000000", "1.07150860718626732E+0301"},
		{"0xFFFFFFFF", "-1", "FFFFFFFF", "11111111111111111111111111111111", "37777777777", "-1.00000000000000000E+0000"},
	}
	for _, c := range cases {
		eng := New()
		v, err := eng.EvalExpr(c.expr)
		if err != nil {
			t.Errorf("%s: eval err %v", c.expr, err)
			continue
		}
		if got := FmtNumber(v); got != c.dec {
			t.Errorf("%s dec: got %q want %q", c.expr, got, c.dec)
		}
		if got := FmtHex32(false, v); got != c.hex {
			t.Errorf("%s hex: got %q want %q", c.expr, got, c.hex)
		}
		if got := FmtBin32(v); got != c.bin {
			t.Errorf("%s bin: got %q want %q", c.expr, got, c.bin)
		}
		if got := FmtOct32(v); got != c.oct {
			t.Errorf("%s oct: got %q want %q", c.expr, got, c.oct)
		}
		if got := FmtExp(v); got != c.exp {
			t.Errorf("%s exp: got %q want %q", c.expr, got, c.exp)
		}
	}
}
