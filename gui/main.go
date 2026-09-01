// ECW Expression Calculator — Go/iup-go GUI
// Faithful port of the original's four forms (TCALCFORM, TCFGFORM, TDEFFORM,
// TTINYFORM) using IUP native controls: GTK on Linux, Win32 on Windows,
// Cocoa on macOS. The expression engine (engine.go) is shared with the CLI.
//
// The original used pixel positions; IUP lays out via boxes. The layout
// mirrors the original form structure (label/input/buttons, radio column +
// result rows, tabs, group boxes) with native widgets.

package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/gen2brain/iup-go/iup"
	"github.com/igitur/ecwcalc"
)

// ---------- global state (mirrors the FPC globals) ----------

type appConfig struct {
	autoCalc        bool
	smallDialog     bool
	stayOnTop       bool
	showErrStatus   bool
	copyToClipboard bool
	copyAsIs        bool
	prec            int
	rAlign          bool
	noLead0         bool
	noTrail0        bool
	unsignedHex     bool
	sepMode         int
}

var cfg = appConfig{
	autoCalc: true, showErrStatus: true, copyToClipboard: true,
	prec: 17, noTrail0: true,
}

var engine = ecwcalc.New()

// ---------- INI persistence (mirrors config.pas: <exe>.ini, [Main]) ----------

func cfgPath() string {
	p := os.Args[0]
	if i := strings.LastIndexByte(p, '.'); i > 0 && !strings.ContainsAny(p[i:], `/\`) {
		return p[:i] + ".ini"
	}
	return p + ".ini"
}

func loadConfig() {
	b, err := os.ReadFile(cfgPath())
	if err != nil {
		return
	}
	vals := map[string]string{}
	section := ""
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, ";") || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = strings.TrimSpace(line[1 : len(line)-1])
			continue
		}
		if eq := strings.IndexByte(line, '='); eq > 0 {
			vals[section+"."+strings.TrimSpace(line[:eq])] = strings.TrimSpace(line[eq+1:])
		}
	}
	cfg.autoCalc = vals["Main.AutoCalc"] != "0"
	cfg.smallDialog = vals["Main.SmallDialog"] == "1"
	cfg.stayOnTop = vals["Main.StayOnTop"] == "1"
	cfg.showErrStatus = vals["Main.ShowErrorStatus"] != "0"
	cfg.copyToClipboard = vals["Main.CopyToClipboard"] != "0"
	cfg.copyAsIs = vals["Main.CopyAsIs"] == "1"
	if v, ok := vals["Main.Prec"]; ok {
		fmt.Sscanf(v, "%d", &cfg.prec)
	}
	cfg.rAlign = vals["Main.RAlign"] == "1"
	cfg.noLead0 = vals["Main.NoLead0"] == "1"
	cfg.noTrail0 = vals["Main.NoTrail0"] == "1"
	cfg.unsignedHex = vals["Main.UnsignedHex"] == "1"
	if v, ok := vals["Main.SepMode"]; ok {
		fmt.Sscanf(v, "%d", &cfg.sepMode)
	}
	applyConfig()
}

func saveConfig() {
	var sb strings.Builder
	sb.WriteString("[Main]\n")
	fmt.Fprintf(&sb, "AutoCalc=%v\n", boolInt(cfg.autoCalc))
	fmt.Fprintf(&sb, "SmallDialog=%v\n", boolInt(cfg.smallDialog))
	fmt.Fprintf(&sb, "StayOnTop=%v\n", boolInt(cfg.stayOnTop))
	fmt.Fprintf(&sb, "ShowErrorStatus=%v\n", boolInt(cfg.showErrStatus))
	fmt.Fprintf(&sb, "CopyToClipboard=%v\n", boolInt(cfg.copyToClipboard))
	fmt.Fprintf(&sb, "CopyAsIs=%v\n", boolInt(cfg.copyAsIs))
	fmt.Fprintf(&sb, "Prec=%d\n", cfg.prec)
	fmt.Fprintf(&sb, "RAlign=%v\n", boolInt(cfg.rAlign))
	fmt.Fprintf(&sb, "NoLead0=%v\n", boolInt(cfg.noLead0))
	fmt.Fprintf(&sb, "NoTrail0=%v\n", boolInt(cfg.noTrail0))
	fmt.Fprintf(&sb, "UnsignedHex=%v\n", boolInt(cfg.unsignedHex))
	fmt.Fprintf(&sb, "SepMode=%d\n", cfg.sepMode)
	os.WriteFile(cfgPath(), []byte(sb.String()), 0o644)
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func applyConfig() {
	engine.SetUnsignedHex(cfg.unsignedHex)
	engine.SetSepMode(cfg.sepMode)
}

// ---------- evaluation + formatting (mirrors mainform.DoEval) ----------

type results struct {
	dec, hex, bin, oct, exp, errText string
}

func doEval(expr string) results {
	expr = strings.TrimSpace(expr)
	if expr == "" {
		return results{}
	}
	v, err := engine.EvalExpr(expr)
	if err != nil {
		return results{dec: "Error", hex: "Error", bin: "Error", oct: "Error", exp: "Error", errText: err.Error()}
	}
	return results{
		dec:     ecwcalc.FmtNumber(v),
		hex:     ecwcalc.FmtHex32(cfg.unsignedHex, v),
		bin:     ecwcalc.FmtBin32(v),
		oct:     ecwcalc.FmtOct32(v),
		exp:     ecwcalc.FmtExp(v),
		errText: "ok",
	}
}

// ---------- clipboard helper ----------

func copyToClipboard(s string) {
	cb := iup.Clipboard()
	iup.SetAttribute(cb, "TEXT", s)
	_ = cb
}

func nowMillis() int64 { return time.Now().UnixMilli() }

// iup-go's SetCallback dispatches via a strict type switch on the *named*
// callback types (ActionFunc, ListActionFunc, ValueChangedFunc...).  Bare
// closures have an unnamed func type and are silently dropped, so we wrap
// every callback with these helpers to give it the named type.
func act(fn func(iup.Ihandle) int) iup.ActionFunc                        { return fn }
func lAct(fn func(iup.Ihandle, string, int, int) int) iup.ListActionFunc { return fn }
func vcAct(fn func(iup.Ihandle) int) iup.ValueChangedFunc                { return fn }

// ---------- main form (TCALCFORM) ----------

type mainForm struct {
	dlg       iup.Ihandle
	combo     iup.Ihandle
	resDec    iup.Ihandle
	resHex    iup.Ihandle
	resBin    iup.Ihandle
	resOct    iup.Ihandle
	resExp    iup.Ihandle
	resErr    iup.Ihandle
	radioDec  iup.Ihandle
	radioHex  iup.Ihandle
	radioBin  iup.Ihandle
	radioOct  iup.Ihandle
	radioExp  iup.Ihandle
	lastClick int64
	history   []string
}

func (m *mainForm) selectedFormat() string {
	switch {
	case iup.GetAttribute(m.radioHex, "VALUE") == "ON":
		return "hex"
	case iup.GetAttribute(m.radioBin, "VALUE") == "ON":
		return "bin"
	case iup.GetAttribute(m.radioOct, "VALUE") == "ON":
		return "oct"
	case iup.GetAttribute(m.radioExp, "VALUE") == "ON":
		return "exp"
	}
	return "dec"
}

func (m *mainForm) copySelected() string {
	switch m.selectedFormat() {
	case "hex":
		return iup.GetAttribute(m.resHex, "VALUE")
	case "bin":
		return iup.GetAttribute(m.resBin, "VALUE")
	case "oct":
		return iup.GetAttribute(m.resOct, "VALUE")
	case "exp":
		return iup.GetAttribute(m.resExp, "VALUE")
	}
	return iup.GetAttribute(m.resDec, "VALUE")
}

func (m *mainForm) doCopy() {
	t := m.copySelected()
	if cfg.copyToClipboard {
		copyToClipboard(t)
	} else {
		iup.SetAttribute(m.combo, "VALUE", t)
	}
}

func (m *mainForm) updateResults(r results) {
	iup.SetAttribute(m.resDec, "VALUE", r.dec)
	iup.SetAttribute(m.resHex, "VALUE", r.hex)
	iup.SetAttribute(m.resBin, "VALUE", r.bin)
	iup.SetAttribute(m.resOct, "VALUE", r.oct)
	iup.SetAttribute(m.resExp, "VALUE", r.exp)
	if cfg.showErrStatus {
		iup.SetAttribute(m.resErr, "TITLE", r.errText)
	} else {
		iup.SetAttribute(m.resErr, "TITLE", "")
	}
}

func (m *mainForm) rememberHistory(s string) {
	for _, h := range m.history {
		if h == s {
			return
		}
	}
	m.history = append([]string{s}, m.history...)
	if len(m.history) > 11 {
		m.history = m.history[:11]
	}
	iup.SetAttribute(m.combo, "REMOVEITEM", "ALL")
	for _, h := range m.history {
		iup.SetAttribute(m.combo, "APPENDITEM", h)
	}
}

func (m *mainForm) evaluate() {
	s := iup.GetAttribute(m.combo, "VALUE")
	if strings.TrimSpace(s) == "" {
		return
	}
	m.updateResults(doEval(s))
	m.rememberHistory(strings.TrimSpace(s))
}

func buildMainForm() *mainForm {
	m := &mainForm{}

	lblExpr := iup.Label("E&xpression:")
	m.combo = iup.List()
	iup.SetAttribute(m.combo, "DROPDOWN", "YES")
	iup.SetAttribute(m.combo, "EDITABLE", "YES")
	iup.SetAttribute(m.combo, "SIZE", "340x")
	btnEval := iup.Button("E&valuate")

	m.radioDec = iup.Toggle("&Dec")
	m.radioHex = iup.Toggle("&Hex")
	m.radioBin = iup.Toggle("&Bin")
	m.radioOct = iup.Toggle("&Oct")
	m.radioExp = iup.Toggle("&Exp")
	radioCol := iup.Radio(iup.Vbox(m.radioDec, m.radioHex, m.radioBin, m.radioOct, m.radioExp))

	m.resDec = iup.Text()
	m.resHex = iup.Text()
	m.resBin = iup.Text()
	m.resOct = iup.Text()
	m.resExp = iup.Text()
	for _, t := range []iup.Ihandle{m.resDec, m.resHex, m.resBin, m.resOct, m.resExp} {
		iup.SetAttribute(t, "READONLY", "YES")
		iup.SetAttribute(t, "SIZE", "300x")
	}
	iup.SetAttribute(m.resDec, "VALUE", "0")
	iup.SetAttribute(m.resHex, "VALUE", "00000000")
	iup.SetAttribute(m.resBin, "VALUE", "00000000000000000000000000000000")
	iup.SetAttribute(m.resOct, "VALUE", "00000000000")
	iup.SetAttribute(m.resExp, "VALUE", "0.00000000000000000E+0000")

	rows := iup.Vbox(
		iup.Hbox(iup.Label("Dec:"), m.resDec),
		iup.Hbox(iup.Label("Hex:"), m.resHex),
		iup.Hbox(iup.Label("Bin:"), m.resBin),
		iup.Hbox(iup.Label("Oct:"), m.resOct),
		iup.Hbox(iup.Label("Exp:"), m.resExp),
	)

	btnCopy := iup.Button("&Copy")
	btnSetup := iup.Button("&Setup...")
	btnHelp := iup.Button("Help")
	btnClose := iup.Button("Close")

	lblErr := iup.Label("Error status:")
	m.resErr = iup.Label("ok")

	// callbacks — all wrapped in act()/lAct()/vcAct() so the named-type
	// dispatch in iup-go's SetCallback matches.
	btnEval.SetCallback("ACTION", act(func(ih iup.Ihandle) int { m.evaluate(); return iup.DEFAULT }))
	m.combo.SetCallback("ACTION", lAct(func(ih iup.Ihandle, s string, item, state int) int {
		if cfg.autoCalc {
			m.evaluate()
		}
		return iup.DEFAULT
	}))
	m.combo.SetCallback("VALUECHANGED_CB", vcAct(func(ih iup.Ihandle) int {
		if cfg.autoCalc {
			m.evaluate()
		}
		return iup.DEFAULT
	}))
	btnCopy.SetCallback("ACTION", act(func(ih iup.Ihandle) int { m.doCopy(); return iup.DEFAULT }))
	btnSetup.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		buildCfgForm().popupModal()
		return iup.DEFAULT
	}))
	btnHelp.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		iup.Message("ECW Expression Calculator",
			"Type an expression such as 2+3*4 or sin(pi/2) and press Evaluate.\n"+
				"Results are shown in Dec, Hex, Bin, Oct and Exp formats.\n"+
				"Copy as selects the format used by the Copy button.\n\n"+
				"Operators: + - * / ** // % << >> & | ^ ~ !  (see README)")
		return iup.DEFAULT
	}))
	btnClose.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		iup.SetAttribute(m.dlg, "VISIBLE", "NO")
		return iup.CLOSE
	}))

	// double-click on a radio copies that format (RadioMouseDown, 400ms)
	for _, r := range []iup.Ihandle{m.radioDec, m.radioHex, m.radioBin, m.radioOct, m.radioExp} {
		var cb iup.ButtonFunc = func(ih iup.Ihandle, but, pressed, x, y int, status string) int {
			if but == 1 && pressed == 1 {
				now := nowMillis()
				if now-m.lastClick < 400 {
					iup.SetAttribute(ih, "VALUE", "ON")
					m.doCopy()
					m.lastClick = 0
				} else {
					m.lastClick = now
				}
			}
			return iup.DEFAULT
		}
		r.SetCallback("BUTTON_CB", cb)
	}

	top := iup.Hbox(lblExpr, m.combo, btnEval)
	middle := iup.Hbox(iup.Vbox(iup.Label("Copy as:"), radioCol), iup.Fill(), rows)
	bottom := iup.Hbox(iup.Fill(), iup.Vbox(btnCopy, btnSetup, btnHelp, btnClose))
	statusRow := iup.Hbox(lblErr, iup.Label(" "), m.resErr)

	content := iup.Vbox(top, middle, statusRow, bottom)
	iup.SetAttribute(content, "GAP", "8")
	iup.SetAttribute(content, "MARGIN", "8x8")

	m.dlg = iup.Dialog(content)
	iup.SetAttribute(m.dlg, "TITLE", "Calculator")
	iup.SetAttribute(m.dlg, "SHRINK", "YES")
	return m
}

// ---------- tiny form (TTINYFORM) ----------

type tinyForm struct {
	dlg    iup.Ihandle
	out    iup.Ihandle
	in     iup.Ihandle
	format int // 0=Dec 1=Hex 2=Bin 3=Oct 4=Exp
}

var tinyF *tinyForm

func (t *tinyForm) doEval() {
	s := iup.GetAttribute(t.in, "VALUE")
	if strings.TrimSpace(s) == "" {
		return
	}
	r := doEval(s)
	switch t.format {
	case 1:
		iup.SetAttribute(t.out, "VALUE", r.hex)
	case 2:
		iup.SetAttribute(t.out, "VALUE", r.bin)
	case 3:
		iup.SetAttribute(t.out, "VALUE", r.oct)
	case 4:
		iup.SetAttribute(t.out, "VALUE", r.exp)
	default:
		iup.SetAttribute(t.out, "VALUE", r.dec)
	}
}

func buildTinyForm() *tinyForm {
	t := &tinyForm{}
	t.out = iup.Text()
	iup.SetAttribute(t.out, "READONLY", "YES")
	iup.SetAttribute(t.out, "VALUE", "0")
	t.in = iup.List()
	iup.SetAttribute(t.in, "DROPDOWN", "YES")
	iup.SetAttribute(t.in, "EDITABLE", "YES")

	btnCopy := iup.Button("¬") // copy glyph
	btnEval := iup.Button("=")
	btnSetup := iup.Button("¼") // setup glyph
	btnFmt := iup.Button("#")

	btnCopy.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		copyToClipboard(iup.GetAttribute(t.out, "VALUE"))
		return iup.DEFAULT
	}))
	btnEval.SetCallback("ACTION", act(func(ih iup.Ihandle) int { t.doEval(); return iup.DEFAULT }))
	btnSetup.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		buildCfgForm().popupModal()
		return iup.DEFAULT
	}))
	btnFmt.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		t.format = (t.format + 1) % 5
		t.doEval()
		return iup.DEFAULT
	}))
	t.in.SetCallback("ACTION", lAct(func(ih iup.Ihandle, s string, item, state int) int {
		if cfg.autoCalc {
			t.doEval()
		}
		return iup.DEFAULT
	}))

	content := iup.Vbox(
		iup.Hbox(t.out, btnCopy, btnEval),
		iup.Hbox(t.in, btnSetup, btnFmt),
	)
	t.dlg = iup.Dialog(content)
	iup.SetAttribute(t.dlg, "TITLE", "Calculator")
	iup.SetAttribute(t.dlg, "RASTERSIZE", "240x") // width hint; height natural
	return t
}

// ---------- config form (TCFGFORM) ----------

type cfgForm struct {
	dlg        iup.Ihandle
	optAuto    iup.Ihandle
	optSmall   iup.Ihandle
	optOnTop   iup.Ihandle
	optStatus  iup.Ihandle
	optMode0   iup.Ihandle
	optMode1   iup.Ihandle
	optAsIs    iup.Ihandle
	optPrec    iup.Ihandle
	optRAlign  iup.Ihandle
	optNoLead  iup.Ihandle
	optNoTrail iup.Ihandle
	defList    iup.Ihandle
}

func onOff(b bool) string {
	if b {
		return "ON"
	}
	return "OFF"
}

func (c *cfgForm) loadCfg() {
	iup.SetAttribute(c.optAuto, "VALUE", onOff(cfg.autoCalc))
	iup.SetAttribute(c.optSmall, "VALUE", onOff(cfg.smallDialog))
	iup.SetAttribute(c.optOnTop, "VALUE", onOff(cfg.stayOnTop))
	iup.SetAttribute(c.optStatus, "VALUE", onOff(cfg.showErrStatus))
	if cfg.copyToClipboard {
		iup.SetAttribute(c.optMode1, "VALUE", "ON")
	} else {
		iup.SetAttribute(c.optMode0, "VALUE", "ON")
	}
	iup.SetAttribute(c.optAsIs, "VALUE", onOff(cfg.copyAsIs))
	iup.SetAttribute(c.optPrec, "VALUE", fmt.Sprintf("%d", cfg.prec))
	iup.SetAttribute(c.optRAlign, "VALUE", onOff(cfg.rAlign))
	iup.SetAttribute(c.optNoLead, "VALUE", onOff(cfg.noLead0))
	iup.SetAttribute(c.optNoTrail, "VALUE", onOff(cfg.noTrail0))
	c.refreshDefs()
}

func (c *cfgForm) saveCfg() {
	cfg.autoCalc = iup.GetAttribute(c.optAuto, "VALUE") == "ON"
	cfg.smallDialog = iup.GetAttribute(c.optSmall, "VALUE") == "ON"
	cfg.stayOnTop = iup.GetAttribute(c.optOnTop, "VALUE") == "ON"
	cfg.showErrStatus = iup.GetAttribute(c.optStatus, "VALUE") == "ON"
	cfg.copyToClipboard = iup.GetAttribute(c.optMode1, "VALUE") == "ON"
	cfg.copyAsIs = iup.GetAttribute(c.optAsIs, "VALUE") == "ON"
	fmt.Sscanf(iup.GetAttribute(c.optPrec, "VALUE"), "%d", &cfg.prec)
	cfg.rAlign = iup.GetAttribute(c.optRAlign, "VALUE") == "ON"
	cfg.noLead0 = iup.GetAttribute(c.optNoLead, "VALUE") == "ON"
	cfg.noTrail0 = iup.GetAttribute(c.optNoTrail, "VALUE") == "ON"
}

func (c *cfgForm) refreshDefs() {
	iup.SetAttribute(c.defList, "DELNODE", "ALL")
	for i := 0; i < engine.NumDefs(); i++ {
		decl := engine.DefName(i)
		if engine.DefIsFunc(i) {
			decl += "(" + strings.Join(engineDefArgs(i), ",") + ")"
		}
		iup.SetAttribute(c.defList, "ADDNODE", fmt.Sprintf("%d;%s", i, decl))
	}
}

func engineDefArgs(i int) []string {
	decl := engine.DefDecl(i)
	open := strings.IndexByte(decl, '(')
	close := strings.IndexByte(decl, ')')
	if open < 0 || close < 0 {
		return nil
	}
	return strings.Split(decl[open+1:close], ",")
}

func (c *cfgForm) popupModal() {
	c.loadCfg()
	iup.Popup(c.dlg, iup.CENTER, iup.CENTER)
}

func buildCfgForm() *cfgForm {
	c := &cfgForm{}

	// --- Interface tab ---
	c.optAuto = iup.Toggle("&Automatic calculations (disable 'Evaluate' button)")
	c.optSmall = iup.Toggle("&Small dialog (show simplified dialog form)")
	c.optOnTop = iup.Toggle("Always stay &on top")
	c.optStatus = iup.Toggle("S&how error status")
	groupGeneral := iup.Frame(iup.Vbox(c.optAuto, c.optSmall, c.optOnTop, c.optStatus))
	iup.SetAttribute(groupGeneral, "TITLE", " General settings ")

	c.optMode0 = iup.Toggle("Copy result into &edit field")
	c.optMode1 = iup.Toggle("Copy result to &clipboard")
	c.optAsIs = iup.Toggle("Cop&y as is")
	groupCopy := iup.Frame(iup.Vbox(iup.Radio(iup.Vbox(c.optMode0, c.optMode1)), c.optAsIs))
	iup.SetAttribute(groupCopy, "TITLE", " 'Copy' button behaviour ")

	c.optPrec = iup.Text()
	iup.SetAttribute(c.optPrec, "SIZE", "40x")
	c.optRAlign = iup.Toggle("Show results &right aligned")
	c.optNoLead = iup.Toggle("hex/bin/oct without &leading zeros")
	c.optNoTrail = iup.Toggle("Show decimal result without &trailing zeros")
	groupDisplay := iup.Frame(iup.Vbox(
		iup.Hbox(iup.Label("&Digits after decimal point in dec/exp results"), c.optPrec),
		iup.Hbox(c.optRAlign, c.optNoLead),
		c.optNoTrail,
	))
	iup.SetAttribute(groupDisplay, "TITLE", " Results display ")

	// --- Definitions tab ---
	c.defList = iup.Tree()
	iup.SetAttribute(c.defList, "RASTERSIZE", "290x220")
	btnAdd := iup.Button("&Add...")
	btnEdit := iup.Button("&Edit")
	btnDelete := iup.Button("&Delete")
	tabDefs := iup.Hbox(c.defList, iup.Vbox(btnAdd, btnEdit, btnDelete))

	btnOK := iup.Button("OK")
	btnCancel := iup.Button("Cancel")

	btnAdd.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		f := buildDefForm()
		if f.popupModal() == iup.CLOSE {
			decl := strings.TrimSpace(f.declText())
			if decl != "" {
				if err := engine.AddDefDecl(decl); err != nil {
					iup.Message("Invalid definition", err.Error())
				} else {
					c.refreshDefs()
				}
			}
		}
		return iup.DEFAULT
	}))
	btnEdit.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		idx := selectedDefIndex(c.defList)
		if idx < 0 || idx >= engine.NumDefs() {
			iup.Message("Edit", "Select a definition first")
			return iup.DEFAULT
		}
		f := buildDefForm()
		f.setDeclText(engine.DefDecl(idx))
		if f.popupModal() == iup.CLOSE {
			decl := strings.TrimSpace(f.declText())
			if decl != "" {
				if err := engine.AddDefDecl(decl); err != nil {
					iup.Message("Invalid definition", err.Error())
				} else {
					engine.DeleteDef(idx)
					c.refreshDefs()
				}
			}
		}
		return iup.DEFAULT
	}))
	btnDelete.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		idx := selectedDefIndex(c.defList)
		if idx < 0 || idx >= engine.NumDefs() {
			iup.Message("Delete", "Select a definition first")
			return iup.DEFAULT
		}
		engine.DeleteDef(idx)
		c.refreshDefs()
		return iup.DEFAULT
	}))
	btnOK.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		c.saveCfg()
		saveConfig()
		applyConfig()
		if cfg.smallDialog && tinyF != nil {
			iup.Show(tinyF.dlg)
		} else if !cfg.smallDialog && tinyF != nil {
			iup.Hide(tinyF.dlg)
		}
		return iup.CLOSE
	}))
	btnCancel.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		return iup.CLOSE
	}))

	tabInt := iup.Vbox(groupGeneral, groupCopy, groupDisplay)
	tabInt.SetAttribute("TABTITLE", "Interface")
	tabDefs.SetAttribute("TABTITLE", "User variables/functions")
	content := iup.Vbox(
		iup.Tabs(tabInt, tabDefs),
		iup.Hbox(iup.Fill(), btnOK, btnCancel),
	)
	c.dlg = iup.Dialog(content)
	iup.SetAttribute(c.dlg, "TITLE", "Calculator configuration")
	iup.SetAttribute(c.dlg, "RASTERSIZE", "480x320")
	iup.SetAttribute(c.dlg, "DEFAULT", "OK")
	return c
}

func selectedDefIndex(list iup.Ihandle) int {
	v := iup.GetAttribute(list, "VALUE")
	if v == "" {
		return -1
	}
	idx := 0
	fmt.Sscanf(v, "%d", &idx)
	return idx
}

// ---------- definition form (TDEFFORM) ----------

type defForm struct {
	dlg    iup.Ihandle
	name   iup.Ihandle
	body   iup.Ihandle
	btnOK  iup.Ihandle
	result int
}

func (f *defForm) declText() string {
	n := strings.TrimSpace(iup.GetAttribute(f.name, "VALUE"))
	if n == "" {
		return ""
	}
	return n + "=" + strings.TrimSpace(iup.GetAttribute(f.body, "VALUE"))
}

func (f *defForm) setDeclText(decl string) {
	if p := strings.IndexByte(decl, '='); p > 0 {
		iup.SetAttribute(f.name, "VALUE", decl[:p])
		iup.SetAttribute(f.body, "VALUE", decl[p+1:])
	} else {
		iup.SetAttribute(f.name, "VALUE", decl)
	}
	f.updateOK()
}

func (f *defForm) updateOK() {
	ok := strings.TrimSpace(iup.GetAttribute(f.name, "VALUE")) != "" &&
		strings.TrimSpace(iup.GetAttribute(f.body, "VALUE")) != ""
	iup.SetAttribute(f.btnOK, "ACTIVE", onOff(ok))
}

func (f *defForm) popupModal() int {
	f.updateOK()
	f.result = 0
	iup.Popup(f.dlg, iup.CENTER, iup.CENTER)
	return f.result
}

func buildDefForm() *defForm {
	f := &defForm{}
	f.name = iup.Text()
	f.body = iup.Text()
	iup.SetAttribute(f.name, "SIZE", "360x")
	iup.SetAttribute(f.body, "SIZE", "360x")
	f.btnOK = iup.Button("OK")
	btnCancel := iup.Button("Cancel")
	btnHelp := iup.Button("Help")

	f.name.SetCallback("VALUECHANGED_CB", vcAct(func(ih iup.Ihandle) int { f.updateOK(); return iup.DEFAULT }))
	f.body.SetCallback("VALUECHANGED_CB", vcAct(func(ih iup.Ihandle) int { f.updateOK(); return iup.DEFAULT }))
	f.btnOK.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		f.result = iup.CLOSE
		return iup.CLOSE
	}))
	btnCancel.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		f.result = 0 // not iup.CLOSE -> callers treat as cancel
		return iup.CLOSE
	}))
	btnHelp.SetCallback("ACTION", act(func(ih iup.Ihandle) int {
		iup.Message("Definition",
			"Declaration:  name(arg1,arg2)=expression\n"+
				"or           name=value\n\n"+
				"Example:  f(x)=x*x   then use  f(5)")
		return iup.DEFAULT
	}))

	content := iup.Vbox(
		iup.Label("&Function or variable declaration:"),
		f.name,
		iup.Label("&Expression with declared arguments:"),
		f.body,
		iup.Hbox(f.btnOK, btnCancel, btnHelp),
	)
	f.dlg = iup.Dialog(content)
	iup.SetAttribute(f.dlg, "TITLE", "Definition")
	iup.SetAttribute(f.dlg, "RASTERSIZE", "400x150")
	iup.SetAttribute(f.dlg, "DEFAULT", "OK")
	return f
}

// ---------- main ----------

func main() {
	iup.Open()
	defer iup.Close()

	loadConfig()
	applyConfig()

	mainF := buildMainForm()
	_ = mainF
	tinyF = buildTinyForm()
	if cfg.smallDialog {
		iup.Show(tinyF.dlg)
	}

	iup.Show(mainF.dlg)
	iup.MainLoop()
}
