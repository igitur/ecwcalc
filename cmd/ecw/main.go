// ECW Expression Calculator — Go CLI (mirrors the FPC CLI interface)
//
// Usage:  ./ecw "2+3*4"
//         ./ecw --unsigned "--sep=1" "1,5+2,5"
//         ./ecw                       (interactive, prompt '> ')
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/igitur/ecwcalc"
)

func runOne(expr string) {
	if strings.TrimSpace(expr) == "" {
		return
	}
	eng := ecwcalc.New()
	v, err := eng.EvalExpr(expr)
	if err != nil {
		fmt.Println("ERROR: " + err.Error())
	} else {
		fmt.Println(ecwcalc.FmtNumber(v))
	}
}

func main() {
	unsignedHex := false
	sepMode := 0
	interactive := false
	args := os.Args[1:]
	i := 0
	for i < len(args) {
		arg := args[i]
		switch {
		case arg == "--unsigned":
			unsignedHex = true
		case strings.HasPrefix(arg, "--sep="):
			n, err := strconv.Atoi(arg[len("--sep="):])
			if err != nil || n < 0 || n > 2 {
				n = 0
			}
			sepMode = n
		case arg == "-i":
			interactive = true
		default:
			// first non-flag arg: run it and exit (FPC behaviour)
			eng := ecwcalc.New()
			eng.SetUnsignedHex(unsignedHex)
			eng.SetSepMode(sepMode)
			v, err := eng.EvalExpr(arg)
			if err != nil {
				fmt.Println("ERROR: " + err.Error())
			} else {
				fmt.Println(ecwcalc.FmtNumber(v))
			}
			return
		}
		i++
	}

	if interactive || len(args) == 0 {
		sc := bufio.NewScanner(os.Stdin)
		for {
			fmt.Print("> ")
			if !sc.Scan() {
				break
			}
			line := strings.TrimSpace(sc.Text())
			if line == "" {
				continue
			}
			eng := ecwcalc.New()
			eng.SetUnsignedHex(unsignedHex)
			eng.SetSepMode(sepMode)
			v, err := eng.EvalExpr(line)
			if err != nil {
				fmt.Println("ERROR: " + err.Error())
			} else {
				fmt.Println(ecwcalc.FmtNumber(v))
			}
		}
	}
}
