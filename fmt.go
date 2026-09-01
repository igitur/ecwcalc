// ============================================================================
// Output formatting (matches original console / GUI)
//   |v| < 1        : 17 decimal places, trailing zeros trimmed
//   1 <= |v| < 1e18: 18 significant digits, trailing zeros trimmed
//   |v| >= 1e18    : scientific, 15 significant digits, 4-digit exponent
// ============================================================================

package ecwcalc

import (
	"fmt"
	"math"
	"strconv"
	"strings"
)

func trimTrailZeros(s string) string {
	i := len(s)
	for i > 0 && s[i-1] == '0' {
		i--
	}
	if i > 0 && s[i-1] == '.' {
		i--
	}
	return s[:i]
}

func fmtFixed(v float64) string {
	av := math.Abs(v)
	var dec int
	if av < 1.0 {
		dec = 17
	} else {
		// 18 significant digits: count integer digits robustly
		s := strconv.FormatFloat(av, 'f', 17, 64)
		intDigits := 0
		for _, ch := range s {
			if ch >= '0' && ch <= '9' {
				intDigits++
			} else {
				break
			}
		}
		dec = 18 - intDigits
		if dec < 0 {
			dec = 0
		}
	}
	r := trimTrailZeros(strconv.FormatFloat(v, 'f', dec, 64))
	if v < 0.0 && r == "0" {
		r = "-0"
	}
	return r
}

// fmtSci formats a float in scientific notation, 4-digit exponent with sign:
// 1.07150860718627E+0301  /  1.4000000000000000E+0001
func fmtSci(v float64, sigDigits int) string {
	// Go's 'e' gives "1.07150860718627e+301"; reformat the exponent.
	s := strconv.FormatFloat(v, 'e', sigDigits-1, 64)
	ei := strings.IndexByte(s, 'e')
	if ei < 0 {
		return s + "E+0000"
	}
	mant := s[:ei]
	exp, _ := strconv.Atoi(s[ei+1:])
	sign := "+"
	if exp < 0 {
		sign = "-"
		exp = -exp
	}
	return fmt.Sprintf("%sE%s%04d", mant, sign, exp)
}

// FmtNumber formats a value like the original console: integers as-is,
// |v| < 1e18 in fixed notation, larger in scientific.
func FmtNumber(v float64) string {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return "ERROR"
	}
	if frac0(v) && v >= -9.223372036854775808e18 && v <= 9.223372036854775807e18 {
		return strconv.FormatInt(int64(math.Round(v)), 10)
	}
	if math.Abs(v) < 1e18 {
		return fmtFixed(v)
	}
	return fmtSci(v, 15)
}

func trunc32(v float64) uint32 {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return 0
	}
	return uint32(int64(math.Trunc(v)))
}

// FmtHex32 formats a value as 8 hex digits (32-bit).
func FmtHex32(unsignedHex bool, v float64) string {
	u := trunc32(v)
	if unsignedHex {
		return fmt.Sprintf("%08X", u)
	}
	return fmt.Sprintf("%08X", uint32(int32(u)))
}

// FmtBin32 formats a value as 32 bits.
func FmtBin32(v float64) string {
	u := trunc32(v)
	var sb strings.Builder
	for i := 31; i >= 0; i-- {
		if (u>>uint(i))&1 == 1 {
			sb.WriteByte('1')
		} else {
			sb.WriteByte('0')
		}
	}
	return sb.String()
}

// FmtOct32 formats a value as 11 octal digits.
func FmtOct32(v float64) string {
	u := trunc32(v)
	var sb strings.Builder
	for i := 10; i >= 0; i-- {
		sb.WriteByte(byte('0' + ((u >> uint(3*i)) & 7)))
	}
	return sb.String()
}

// FmtExp formats a value in 18-digit scientific notation.
func FmtExp(v float64) string {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return "ERROR"
	}
	return fmtSci(v, 18)
}

// ---------- convenience: one-shot evaluation (stateless, like the CLI) ----------

// EvalOne evaluates an expression with the given flags and returns the
// formatted result, or an error string.
func EvalOne(expr string, unsignedHex bool, sepMode int) (string, error) {
	eng := New()
	eng.unsignedHex = unsignedHex
	eng.sepMode = sepMode
	v, err := eng.EvalExpr(expr)
	if err != nil {
		return "", err
	}
	return FmtNumber(v), nil
}
