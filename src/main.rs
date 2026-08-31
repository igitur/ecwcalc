// ECW Expression Calculator — vizia immediate-mode GUI (Rust port)
// Ported from the original's four DFM forms (TCALCFORM, TCFGFORM, TDEFFORM,
// TTINYFORM) — see the FPC gui/ port for the pixel-exact LCL layout.
// The expression engine (engine.rs) is shared with the CLI + battery tests.
//
// vizia 0.4 is signal-based: model fields are Signal<T>, views observe them
// via Binding, events mutate signals.  Sub-windows (Setup / Definition /
// Help / Tiny) are real OS windows created hidden and toggled with
// WindowEvent::SetVisible.

use ecw_vizia::engine::{self, Engine};
use vizia::prelude::*;
use std::cell::RefCell;

// The engine keeps user defs across evaluations; it is not Clone so it
// lives in a thread-local and is synced from the model before each eval.
thread_local! {
    static ENGINE: RefCell<Engine> = RefCell::new(Engine::new());
}

#[derive(Clone, PartialEq)]
pub struct DefRow {
    pub decl: String, // e.g. "f(x)" or "z"
    pub body: String, // e.g. "x*x" or "1"
}

pub struct CalcState {
    // main form
    expr: Signal<String>,
    history: Signal<Vec<String>>,
    copy_as: Signal<usize>, // 0=Dec 1=Hex 2=Bin 3=Oct 4=Exp
    dec: Signal<String>,
    hex: Signal<String>,
    bin: Signal<String>,
    oct: Signal<String>,
    exp: Signal<String>,
    err: Signal<String>,
    // config
    auto_calc: Signal<bool>,
    small_dialog: Signal<bool>,
    stay_on_top: Signal<bool>,
    show_err: Signal<bool>,
    copy_mode: Signal<usize>, // 0=edit field, 1=clipboard
    copy_as_is: Signal<bool>,
    precision: Signal<usize>,
    align: Signal<usize>,
    lead_zeros: Signal<bool>,
    trail_zeros: Signal<bool>,
    // defs
    defs: Signal<Vec<DefRow>>,
    cfg_tab: Signal<usize>, // 0=Interface, 1=User variables/functions
    def_editing: Signal<Option<usize>>,
    def_name: Signal<String>,
    def_body: Signal<String>,
    // tiny form
    tiny_expr: Signal<String>,
    tiny_out: Signal<String>,
    // window visibility
    cfg_visible: Signal<bool>,
    def_visible: Signal<bool>,
    help_visible: Signal<bool>,
    tiny_visible: Signal<bool>,
    // window entities (for SetVisible targeting)
    cfg_ent: Signal<Entity>,
    def_ent: Signal<Entity>,
    help_ent: Signal<Entity>,
    tiny_ent: Signal<Entity>,
}

impl CalcState {
    fn new() -> Self {
        Self {
            expr: Signal::new(String::new()),
            history: Signal::new(Vec::new()),
            copy_as: Signal::new(0),
            dec: Signal::new("0".to_string()),
            hex: Signal::new("00000000".to_string()),
            bin: Signal::new("00000000000000000000000000000000".to_string()),
            oct: Signal::new("00000000000".to_string()),
            exp: Signal::new("0.00000000000000000E+0000".to_string()),
            err: Signal::new("ok".to_string()),
            auto_calc: Signal::new(true),
            small_dialog: Signal::new(false),
            stay_on_top: Signal::new(false),
            show_err: Signal::new(true),
            copy_mode: Signal::new(0),
            copy_as_is: Signal::new(false),
            precision: Signal::new(18),
            align: Signal::new(0),
            lead_zeros: Signal::new(false),
            trail_zeros: Signal::new(true),
            defs: Signal::new(Vec::new()),
            def_editing: Signal::new(None),
            def_name: Signal::new(String::new()),
            def_body: Signal::new(String::new()),
            tiny_expr: Signal::new(String::new()),
            tiny_out: Signal::new("0".to_string()),
            cfg_visible: Signal::new(false),
            def_visible: Signal::new(false),
            help_visible: Signal::new(false),
            tiny_visible: Signal::new(false),
            cfg_tab: Signal::new(0),
            cfg_ent: Signal::new(Entity::root()),
            def_ent: Signal::new(Entity::root()),
            help_ent: Signal::new(Entity::root()),
            tiny_ent: Signal::new(Entity::root()),
        }
    }

    fn sync_engine(&self) {
        ENGINE.with(|e| {
            let mut eng = e.borrow_mut();
            eng.defs.clear();
            for d in self.defs.get() {
                let _ = eng.add_def_decl(&format!("{}={}", d.decl, d.body));
            }
        });
    }

    fn evaluate(&mut self) {
        self.sync_engine();
        let expr = self.expr.get();
        let mut v = 0.0;
        let res = ENGINE.with(|e| e.borrow_mut().eval_expr(&expr, &mut v));
        match res {
            Ok(()) => {
                self.dec.set(engine::fmt_number(v));
                let u = ENGINE.with(|e| e.borrow().unsigned());
                self.hex.set(engine::fmt_hex32(u, v));
                self.bin.set(engine::fmt_bin32(v));
                self.oct.set(engine::fmt_oct32(v));
                self.exp.set(engine::fmt_exp(v));
                self.err.set("ok".to_string());
                // push history (dedupe, most recent first, max 11)
                let mut h = self.history.get();
                if !expr.trim().is_empty() && !h.contains(&expr) {
                    h.insert(0, expr.clone());
                    h.truncate(11);
                    self.history.set(h);
                }
            }
            Err(m) => {
                self.err.set(m);
            }
        }
    }

    fn copy_selected(&self) -> String {
        match self.copy_as.get() {
            0 => self.dec.get(),
            1 => self.hex.get(),
            2 => self.bin.get(),
            3 => self.oct.get(),
            _ => self.exp.get(),
        }
    }
}

pub enum CalcEvent {
    SetExpr(String),
    Evaluate,
    Copy,
    SetCopyAs(usize),
    RecallHistory(usize),
    // config toggles
    CfgAutoCalc(bool),
    CfgSmallDialog(bool),
    CfgStayOnTop(bool),
    CfgShowErr(bool),
    CfgCopyMode(usize),
    CfgCopyAsIs(bool),
    CfgPrecision(usize),
    CfgAlign(usize),
    CfgLeadZeros(bool),
    CfgTrailZeros(bool),
    CfgTab(usize),
    // windows
    OpenCfg,
    CloseCfg,
    OpenHelp,
    CloseHelp,
    CloseApp,
    // defs
    DefsAdd,
    DefsEdit(usize),
    DefsDelete(usize),
    DefName(String),
    DefBody(String),
    DefOk,
    DefCancel,
    // tiny form
    TinySetExpr(String),
    TinyEval,
    TinyCopy,
    TinySetup,
    TinyFormat,
    OpenTiny,
    CloseTiny,
}

impl Model for CalcState {
    fn event(&mut self, cx: &mut EventContext, event: &mut Event) {
        event.map(|calc_event, _| match calc_event {
            CalcEvent::SetExpr(s) => {
                self.expr.set(s.clone());
            }
            CalcEvent::Evaluate => {
                self.evaluate();
                if self.small_dialog.get() {
                    self.tiny_out.set(self.copy_selected());
                }
            }
            CalcEvent::Copy => {
                let _ = cx.set_clipboard(self.copy_selected());
            }
            CalcEvent::SetCopyAs(i) => {
                self.copy_as.set(*i);
            }
            CalcEvent::RecallHistory(i) => {
                let h = self.history.get();
                if let Some(s) = h.get(*i) {
                    self.expr.set(s.clone());
                    self.evaluate();
                    if self.small_dialog.get() {
                        self.tiny_out.set(self.copy_selected());
                    }
                }
            }
            CalcEvent::CfgAutoCalc(b) => self.auto_calc.set(*b),
            CalcEvent::CfgSmallDialog(b) => {
                self.small_dialog.set(*b);
                self.tiny_visible.set(*b);
                let e = self.tiny_ent.get();
                cx.emit_to(e, WindowEvent::SetVisible(*b));
                if *b {
                    self.tiny_out.set(self.copy_selected());
                }
            }
            CalcEvent::CfgStayOnTop(b) => self.stay_on_top.set(*b),
            CalcEvent::CfgShowErr(b) => self.show_err.set(*b),
            CalcEvent::CfgCopyMode(m) => self.copy_mode.set(*m),
            CalcEvent::CfgCopyAsIs(b) => self.copy_as_is.set(*b),
            CalcEvent::CfgPrecision(p) => self.precision.set(*p),
            CalcEvent::CfgAlign(a) => self.align.set(*a),
            CalcEvent::CfgLeadZeros(b) => self.lead_zeros.set(*b),
            CalcEvent::CfgTrailZeros(b) => self.trail_zeros.set(*b),
            CalcEvent::CfgTab(t) => self.cfg_tab.set(*t),
            CalcEvent::CfgCopyMode(m) => self.copy_mode.set(*m),
            CalcEvent::CfgCopyAsIs(b) => self.copy_as_is.set(*b),
            CalcEvent::OpenCfg => {
                self.cfg_visible.set(true);
                let e = self.cfg_ent.get();
                cx.emit_to(e, WindowEvent::SetVisible(true));
            }
            CalcEvent::CloseCfg => {
                self.cfg_visible.set(false);
                let e = self.cfg_ent.get();
                cx.emit_to(e, WindowEvent::SetVisible(false));
            }
            CalcEvent::OpenHelp => {
                self.help_visible.set(true);
                let e = self.help_ent.get();
                cx.emit_to(e, WindowEvent::SetVisible(true));
            }
            CalcEvent::CloseHelp => {
                self.help_visible.set(false);
                let e = self.help_ent.get();
                cx.emit_to(e, WindowEvent::SetVisible(false));
            }
            CalcEvent::CloseApp => cx.emit(WindowEvent::WindowClose),
            CalcEvent::DefsAdd => {
                self.def_editing.set(None);
                self.def_name.set(String::new());
                self.def_body.set(String::new());
                self.def_visible.set(true);
                let e = self.def_ent.get();
                cx.emit_to(e, WindowEvent::SetVisible(true));
            }
            CalcEvent::DefsEdit(i) => {
                let defs = self.defs.get();
                if let Some(d) = defs.get(*i) {
                    self.def_editing.set(Some(*i));
                    self.def_name.set(d.decl.clone());
                    self.def_body.set(d.body.clone());
                    self.def_visible.set(true);
                    let e = self.def_ent.get();
                    cx.emit_to(e, WindowEvent::SetVisible(true));
                }
            }
            CalcEvent::DefsDelete(i) => {
                let mut defs = self.defs.get();
                if *i < defs.len() {
                    defs.remove(*i);
                    self.defs.set(defs);
                }
            }
            CalcEvent::DefName(s) => self.def_name.set(s.clone()),
            CalcEvent::DefBody(s) => self.def_body.set(s.clone()),
            CalcEvent::DefOk => {
                let name = self.def_name.get();
                let body = self.def_body.get();
                let decl = format!("{}={}", name.trim(), body.trim());
                let mut defs = self.defs.get();
                match self.def_editing.get() {
                    Some(i) => {
                        if let Some(d) = defs.get_mut(i) {
                            *d = DefRow { decl: name.trim().to_string(), body: body.trim().to_string() };
                        }
                    }
                    None => {
                        defs.push(DefRow { decl: name.trim().to_string(), body: body.trim().to_string() });
                    }
                }
                // validate via the engine; revert on error
                let valid = ENGINE.with(|e| e.borrow_mut().add_def_decl(&decl)).is_ok();
                if valid {
                    self.defs.set(defs);
                    self.def_visible.set(false);
                    let e = self.def_ent.get();
                    cx.emit_to(e, WindowEvent::SetVisible(false));
                    self.err.set("ok".to_string());
                } else {
                    self.err.set("invalid definition".to_string());
                }
            }
            CalcEvent::DefCancel => {
                self.def_visible.set(false);
                let e = self.def_ent.get();
                cx.emit_to(e, WindowEvent::SetVisible(false));
            }
            CalcEvent::TinySetExpr(s) => self.tiny_expr.set(s.clone()),
            CalcEvent::TinyEval => {
                let e = self.tiny_expr.get();
                self.expr.set(e.clone());
                self.evaluate();
                self.tiny_out.set(self.copy_selected());
            }
            CalcEvent::TinyCopy => {
                let _ = cx.set_clipboard(self.tiny_out.get());
            }
            CalcEvent::TinySetup => self.cfg_visible.set(true),
            CalcEvent::TinyFormat => {
                let next = (self.copy_as.get() + 1) % 5;
                self.copy_as.set(next);
                self.tiny_out.set(self.copy_selected());
            }
            CalcEvent::OpenTiny => {
                self.tiny_visible.set(true);
                let e = self.tiny_ent.get();
                cx.emit_to(e, WindowEvent::SetVisible(true));
            }
            CalcEvent::CloseTiny => {
                self.tiny_visible.set(false);
                let e = self.tiny_ent.get();
                cx.emit_to(e, WindowEvent::SetVisible(false));
            }
        });
    }
}

fn main() -> Result<(), ApplicationError> {
    Application::new(|cx| {
        let state = CalcState::new();

        // capture signal clones for closures BEFORE state.build(cx) consumes it
        let s_expr = state.expr.clone();
        let s_copy_as = state.copy_as.clone();
        let s_dec = state.dec.clone();
        let s_hex = state.hex.clone();
        let s_bin = state.bin.clone();
        let s_oct = state.oct.clone();
        let s_exp = state.exp.clone();
        let s_err = state.err.clone();
        let s_auto = state.auto_calc.clone();
        let s_small = state.small_dialog.clone();
        let s_stay = state.stay_on_top.clone();
        let s_showerr = state.show_err.clone();
        let s_copymode = state.copy_mode.clone();
        let s_copyasis0 = state.copy_as_is.clone();
        let s_asis = state.copy_as_is.clone();
        let s_prec = state.precision.clone();
        let s_align = state.align.clone();
        let s_lead = state.lead_zeros.clone();
        let s_trail = state.trail_zeros.clone();
        let s_defs = state.defs.clone();
        let s_defvis = state.def_visible.clone();
        let s_defname = state.def_name.clone();
        let s_defbody = state.def_body.clone();
        let s_help = state.help_visible.clone();
        let s_tiny_expr = state.tiny_expr.clone();
        let s_tiny_out = state.tiny_out.clone();
        let s_tiny_vis = state.tiny_visible.clone();
        let s_cfg = state.cfg_visible.clone();
        let s_cfg_tab = state.cfg_tab.clone();
        let s_copymode = state.copy_mode.clone();
        let s_copyasis0 = state.copy_as_is.clone();
        let s_cfg_ent = state.cfg_ent.clone();
        let s_def_ent = state.def_ent.clone();
        let s_help_ent = state.help_ent.clone();
        let s_tiny_ent = state.tiny_ent.clone();

        state.build(cx);

        // ---------------- main window (root) ----------------
        Element::new(cx)
            .class("window")
            .position_type(PositionType::Absolute)
            .left(Pixels(0.0))
            .top(Pixels(0.0))
            .width(Pixels(448.0))
            .height(Pixels(250.0))
            .background_color(Color::rgb(236, 233, 216));

        Label::new(cx, "Expression:")
            .position_type(PositionType::Absolute)
            .left(Pixels(20.0))
            .top(Pixels(16.0))
            .font_size(12.0);

        Textbox::new(cx, s_expr.clone())
            .position_type(PositionType::Absolute)
            .left(Pixels(20.0))
            .top(Pixels(32.0))
            .width(Pixels(320.0))
            .height(Pixels(24.0))
            .on_edit(|cx, text| cx.emit(CalcEvent::SetExpr(text)))
            .on_submit(|cx, text, _| {
                cx.emit(CalcEvent::SetExpr(text));
                cx.emit(CalcEvent::Evaluate);
            });

        Button::new(cx, |cx| Label::new(cx, "Evaluate"))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(32.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0))
            .on_press(|cx| cx.emit(CalcEvent::Evaluate));

        Label::new(cx, "Copy as:")
            .position_type(PositionType::Absolute)
            .left(Pixels(20.0))
            .top(Pixels(64.0))
            .font_size(12.0);

        // copy-as radio group (radio + sibling label)
        let radio_names = ["Dec", "Hex", "Bin", "Oct", "Exp"];
        for (i, name) in radio_names.iter().enumerate() {
            let checked = s_copy_as.map(move |v| *v == i);
            RadioButton::new(cx, checked)
                .position_type(PositionType::Absolute)
                .left(Pixels(24.0 + i as f32 * 56.0))
                .top(Pixels(80.0))
                .on_select(move |cx| cx.emit(CalcEvent::SetCopyAs(i)));
            Label::new(cx, *name)
                .position_type(PositionType::Absolute)
                .left(Pixels(42.0 + i as f32 * 56.0))
                .top(Pixels(78.0))
                .font_size(11.0);
        }

        // result rows
        let rows: [(&str, Signal<String>, f32); 5] = [
            ("Dec", s_dec.clone(), 102.0),
            ("Hex", s_hex.clone(), 122.0),
            ("Bin", s_bin.clone(), 142.0),
            ("Oct", s_oct.clone(), 162.0),
            ("Exp", s_exp.clone(), 182.0),
        ];
        for (name, sig, top) in rows {
            Label::new(cx, name)
                .position_type(PositionType::Absolute)
                .left(Pixels(24.0))
                .top(Pixels(top))
                .font_size(12.0);
            let s = sig.clone();
            Binding::new(cx, sig, move |cx| {
                Label::new(cx, s.get())
                    .position_type(PositionType::Absolute)
                    .left(Pixels(80.0))
                    .top(Pixels(top))
                    .font_size(12.0);
            });
        }

        // error status
        Label::new(cx, "Error status:")
            .position_type(PositionType::Absolute)
            .left(Pixels(20.0))
            .top(Pixels(210.0))
            .font_size(12.0);
        Binding::new(cx, s_err.clone(), move |cx| {
            Label::new(cx, s_err.get())
                .position_type(PositionType::Absolute)
                .left(Pixels(110.0))
                .top(Pixels(210.0))
                .font_size(12.0);
        });

        // button column
        Button::new(cx, |cx| Label::new(cx, "Copy"))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(64.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0))
            .on_press(|cx| cx.emit(CalcEvent::Copy));

        Button::new(cx, |cx| Label::new(cx, "Setup..."))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(94.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0))
            .on_press(|cx| cx.emit(CalcEvent::OpenCfg));

        Button::new(cx, |cx| Label::new(cx, "Help"))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(124.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0))
            .on_press(|cx| cx.emit(CalcEvent::OpenHelp));

        Button::new(cx, |cx| Label::new(cx, "Close"))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(154.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0))
            .on_press(|cx| cx.emit(CalcEvent::CloseApp));

        // ---------------- Setup window (TCFGFORM) ----------------

        let w_cfg = Window::new(cx, move |cx| {
            Element::new(cx)
                .class("window")
                .position_type(PositionType::Absolute)
                .left(Pixels(0.0))
                .top(Pixels(0.0))
                .width(Pixels(420.0))
                .height(Pixels(320.0))
                .background_color(Color::rgb(236, 233, 216));

            // ---- tab bar (Interface / User variables/functions) ----
            Button::new(cx, |cx| Label::new(cx, "Interface"))
                .position_type(PositionType::Absolute)
                .left(Pixels(10.0))
                .top(Pixels(8.0))
                .width(Pixels(120.0))
                .height(Pixels(22.0))
                .on_press(|cx| cx.emit(CalcEvent::CfgTab(0)));
            Button::new(cx, |cx| Label::new(cx, "User variables/functions"))
                .position_type(PositionType::Absolute)
                .left(Pixels(134.0))
                .top(Pixels(8.0))
                .width(Pixels(180.0))
                .height(Pixels(22.0))
                .on_press(|cx| cx.emit(CalcEvent::CfgTab(1)));

            // ---- content switches on cfg_tab ----
            let tab_sig = s_cfg_tab.clone();
            Binding::new(cx, tab_sig.clone(), move |cx| {
                if tab_sig.get() == 0 {
                    // ================= Interface tab =================
                    // General settings group
                    Element::new(cx)
                        .position_type(PositionType::Absolute)
                        .left(Pixels(8.0))
                        .top(Pixels(36.0))
                        .width(Pixels(396.0))
                        .height(Pixels(112.0))
                        .border_color(Color::rgb(120, 120, 120))
                        .border_width(Pixels(1.0));
                    Label::new(cx, " General settings ")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(16.0))
                        .top(Pixels(30.0))
                        .font_size(12.0);

                    {
                        let sig = s_auto.clone();
                        Checkbox::new(cx, sig.clone())
                            .position_type(PositionType::Absolute)
                            .left(Pixels(18.0))
                            .top(Pixels(48.0))
                            .on_toggle(move |ev| ev.emit(CalcEvent::CfgAutoCalc(!sig.get())));
                    }
                    Label::new(cx, "Automatic calculations (disable 'Evaluate' button)")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(40.0))
                        .top(Pixels(48.0))
                        .font_size(12.0);

                    {
                        let sig = s_small.clone();
                        Checkbox::new(cx, sig.clone())
                            .position_type(PositionType::Absolute)
                            .left(Pixels(18.0))
                            .top(Pixels(72.0))
                            .on_toggle(move |ev| ev.emit(CalcEvent::CfgSmallDialog(!sig.get())));
                    }
                    Label::new(cx, "Small dialog (show simplified dialog form)")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(40.0))
                        .top(Pixels(72.0))
                        .font_size(12.0);

                    {
                        let sig = s_stay.clone();
                        Checkbox::new(cx, sig.clone())
                            .position_type(PositionType::Absolute)
                            .left(Pixels(18.0))
                            .top(Pixels(96.0))
                            .on_toggle(move |ev| ev.emit(CalcEvent::CfgStayOnTop(!sig.get())));
                    }
                    Label::new(cx, "Always stay on top")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(40.0))
                        .top(Pixels(96.0))
                        .font_size(12.0);

                    {
                        let sig = s_showerr.clone();
                        Checkbox::new(cx, sig.clone())
                            .position_type(PositionType::Absolute)
                            .left(Pixels(18.0))
                            .top(Pixels(120.0))
                            .on_toggle(move |ev| ev.emit(CalcEvent::CfgShowErr(!sig.get())));
                    }
                    Label::new(cx, "Show error status")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(40.0))
                        .top(Pixels(120.0))
                        .font_size(12.0);

                    // Copy button behaviour group
                    Element::new(cx)
                        .position_type(PositionType::Absolute)
                        .left(Pixels(8.0))
                        .top(Pixels(152.0))
                        .width(Pixels(396.0))
                        .height(Pixels(88.0))
                        .border_color(Color::rgb(120, 120, 120))
                        .border_width(Pixels(1.0));
                    Label::new(cx, " 'Copy' button behaviour ")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(16.0))
                        .top(Pixels(146.0))
                        .font_size(12.0);

                    RadioButton::new(cx, s_copymode.map(|v| *v == 0))
                        .position_type(PositionType::Absolute)
                        .left(Pixels(18.0))
                        .top(Pixels(164.0))
                        .on_select(|cx| cx.emit(CalcEvent::CfgCopyMode(0)));
                    Label::new(cx, "Copy result into edit field")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(40.0))
                        .top(Pixels(164.0))
                        .font_size(12.0);

                    RadioButton::new(cx, s_copymode.map(|v| *v == 1))
                        .position_type(PositionType::Absolute)
                        .left(Pixels(18.0))
                        .top(Pixels(188.0))
                        .on_select(|cx| cx.emit(CalcEvent::CfgCopyMode(1)));
                    Label::new(cx, "Copy result to clipboard")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(40.0))
                        .top(Pixels(188.0))
                        .font_size(12.0);

                    {
                        let sig = s_copyasis0.clone();
                        Checkbox::new(cx, sig.clone())
                            .position_type(PositionType::Absolute)
                            .left(Pixels(18.0))
                            .top(Pixels(212.0))
                            .on_toggle(move |ev| ev.emit(CalcEvent::CfgCopyAsIs(!sig.get())));
                    }
                    Label::new(cx, "Copy as is")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(40.0))
                        .top(Pixels(212.0))
                        .font_size(12.0);
                } else {
                    // ============= User variables/functions tab =============
                    Label::new(cx, "User variables and functions:")
                        .position_type(PositionType::Absolute)
                        .left(Pixels(12.0))
                        .top(Pixels(40.0))
                        .font_size(12.0);

                    // defs list (decl | body)
                    List::new(cx, s_defs.clone(), |cx, _index, item| {
                        let decl = item.map(|d| d.decl.clone());
                        let body = item.map(|d| d.body.clone());
                        HStack::new(cx, |cx| {
                            Label::new(cx, decl)
                                .width(Pixels(130.0))
                                .font_size(12.0);
                            Label::new(cx, body)
                                .width(Pixels(170.0))
                                .font_size(12.0);
                        });
                    })
                    .position_type(PositionType::Absolute)
                    .left(Pixels(12.0))
                    .top(Pixels(60.0))
                    .width(Pixels(300.0))
                    .height(Pixels(220.0))
                    .border_color(Color::rgb(120, 120, 120))
                    .border_width(Pixels(1.0))
                    .background_color(Color::rgb(255, 255, 255));

                    Button::new(cx, |cx| Label::new(cx, "Add..."))
                        .position_type(PositionType::Absolute)
                        .left(Pixels(322.0))
                        .top(Pixels(60.0))
                        .width(Pixels(84.0))
                        .height(Pixels(24.0))
                        .on_press(|cx| cx.emit(CalcEvent::DefsAdd));
                    Button::new(cx, |cx| Label::new(cx, "Edit"))
                        .position_type(PositionType::Absolute)
                        .left(Pixels(322.0))
                        .top(Pixels(92.0))
                        .width(Pixels(84.0))
                        .height(Pixels(24.0))
                        .on_press(|cx| cx.emit(CalcEvent::DefsEdit(0)));
                    Button::new(cx, |cx| Label::new(cx, "Delete"))
                        .position_type(PositionType::Absolute)
                        .left(Pixels(322.0))
                        .top(Pixels(124.0))
                        .width(Pixels(84.0))
                        .height(Pixels(24.0))
                        .on_press(|cx| cx.emit(CalcEvent::DefsDelete(0)));
                }
            });

            // OK / Cancel
            Button::new(cx, |cx| Label::new(cx, "OK"))
                .position_type(PositionType::Absolute)
                .left(Pixels(240.0))
                .top(Pixels(288.0))
                .width(Pixels(80.0))
                .height(Pixels(24.0))
                .on_press(|cx| cx.emit(CalcEvent::CloseCfg));
            Button::new(cx, |cx| Label::new(cx, "Cancel"))
                .position_type(PositionType::Absolute)
                .left(Pixels(330.0))
                .top(Pixels(288.0))
                .width(Pixels(80.0))
                .height(Pixels(24.0))
                .on_press(|cx| cx.emit(CalcEvent::CloseCfg));
        })
        .title("Setup")
        .inner_size((420, 320))
        .visible(s_cfg.clone());
        s_cfg_ent.set(w_cfg.entity());

        // ---------------- Definition window (TDEFFORM) ----------------
        let w_def = Window::new(cx, move |cx| {
            Element::new(cx)
                .class("window")
                .position_type(PositionType::Absolute)
                .left(Pixels(0.0))
                .top(Pixels(0.0))
                .width(Pixels(320.0))
                .height(Pixels(140.0))
                .background_color(Color::rgb(236, 233, 216));

            Label::new(cx, "Function or variable declaration:")
                .position_type(PositionType::Absolute)
                .left(Pixels(12.0))
                .top(Pixels(12.0))
                .font_size(12.0);
            Textbox::new(cx, s_defname.clone())
                .position_type(PositionType::Absolute)
                .left(Pixels(12.0))
                .top(Pixels(30.0))
                .width(Pixels(296.0))
                .height(Pixels(22.0))
                .on_edit(|cx, text| cx.emit(CalcEvent::DefName(text)));

            Label::new(cx, "Expression with declared arguments:")
                .position_type(PositionType::Absolute)
                .left(Pixels(12.0))
                .top(Pixels(56.0))
                .font_size(12.0);
            Textbox::new(cx, s_defbody.clone())
                .position_type(PositionType::Absolute)
                .left(Pixels(12.0))
                .top(Pixels(74.0))
                .width(Pixels(296.0))
                .height(Pixels(22.0))
                .on_edit(|cx, text| cx.emit(CalcEvent::DefBody(text)));

            Button::new(cx, |cx| Label::new(cx, "OK"))
                .position_type(PositionType::Absolute)
                .left(Pixels(180.0))
                .top(Pixels(106.0))
                .width(Pixels(60.0))
                .height(Pixels(22.0))
                .on_press(|cx| cx.emit(CalcEvent::DefOk));
            Button::new(cx, |cx| Label::new(cx, "Cancel"))
                .position_type(PositionType::Absolute)
                .left(Pixels(248.0))
                .top(Pixels(106.0))
                .width(Pixels(60.0))
                .height(Pixels(22.0))
                .on_press(|cx| cx.emit(CalcEvent::DefCancel));
        })
        .title("Definition")
        .inner_size((320, 160))
        .visible(s_defvis.clone());
        s_def_ent.set(w_def.entity());

        // ---------------- Help window ----------------
        let w_help = Window::new(cx, move |cx| {
            Element::new(cx)
                .class("window")
                .position_type(PositionType::Absolute)
                .left(Pixels(0.0))
                .top(Pixels(0.0))
                .width(Pixels(380.0))
                .height(Pixels(260.0))
                .background_color(Color::rgb(236, 233, 216));
            Label::new(cx, "ECW Expression Calculator — language")
                .position_type(PositionType::Absolute)
                .left(Pixels(12.0))
                .top(Pixels(10.0))
                .font_size(12.0);
            let help_text = "Operators: = == <> != < > <= >=  & | ^ && || ^^ << >>\n+ -  * / ** // %  unary + - ~ !\nConstants: e pi\nFunctions: sin cos tan ctan asin acos atan actan\nsinh cosh tanh asinh acosh atanh exp ln log\nsqr sqrt fact abs sign int frac rad deg\nLists: sum prod avg geo min max poly\nUser: z=1,(z+1/z)/2   f(x)=x*x,f(5)\nNumbers: 12 0xAB $AB 12h 101b 12o 012 1. .5 1e2";
            Label::new(cx, help_text)
                .position_type(PositionType::Absolute)
                .left(Pixels(12.0))
                .top(Pixels(30.0))
                .font_size(11.0);
            Button::new(cx, |cx| Label::new(cx, "OK"))
                .position_type(PositionType::Absolute)
                .left(Pixels(300.0))
                .top(Pixels(230.0))
                .width(Pixels(60.0))
                .height(Pixels(22.0))
                .on_press(|cx| cx.emit(CalcEvent::CloseHelp));
        })
        .title("Help")
        .inner_size((380, 260))
        .visible(s_help.clone());
        s_help_ent.set(w_help.entity());

        // ---------------- Tiny form (TTINYFORM) ----------------
        let w_tiny = Window::new(cx, move |cx| {
            Element::new(cx)
                .class("window")
                .position_type(PositionType::Absolute)
                .left(Pixels(0.0))
                .top(Pixels(0.0))
                .width(Pixels(240.0))
                .height(Pixels(70.0))
                .background_color(Color::rgb(236, 233, 216));
            let so = s_tiny_out.clone();
            Binding::new(cx, s_tiny_out.clone(), move |cx| {
                Label::new(cx, so.get())
                    .position_type(PositionType::Absolute)
                    .left(Pixels(6.0))
                    .top(Pixels(4.0))
                    .font_size(12.0);
            });
            Textbox::new(cx, s_tiny_expr.clone())
                .position_type(PositionType::Absolute)
                .left(Pixels(6.0))
                .top(Pixels(26.0))
                .width(Pixels(160.0))
                .height(Pixels(20.0))
                .on_edit(|cx, text| cx.emit(CalcEvent::TinySetExpr(text)))
                .on_submit(|cx, text, _| {
                    cx.emit(CalcEvent::TinySetExpr(text));
                    cx.emit(CalcEvent::TinyEval);
                });
            Button::new(cx, |cx| Label::new(cx, "\u{ac}"))
                .position_type(PositionType::Absolute)
                .left(Pixels(170.0))
                .top(Pixels(26.0))
                .width(Pixels(20.0))
                .height(Pixels(20.0))
                .on_press(|cx| cx.emit(CalcEvent::TinyCopy));
            Button::new(cx, |cx| Label::new(cx, "="))
                .position_type(PositionType::Absolute)
                .left(Pixels(192.0))
                .top(Pixels(26.0))
                .width(Pixels(20.0))
                .height(Pixels(20.0))
                .on_press(|cx| cx.emit(CalcEvent::TinyEval));
            Button::new(cx, |cx| Label::new(cx, "\u{bc}"))
                .position_type(PositionType::Absolute)
                .left(Pixels(214.0))
                .top(Pixels(26.0))
                .width(Pixels(20.0))
                .height(Pixels(20.0))
                .on_press(|cx| cx.emit(CalcEvent::TinySetup));
            Button::new(cx, |cx| Label::new(cx, "#"))
                .position_type(PositionType::Absolute)
                .left(Pixels(170.0))
                .top(Pixels(48.0))
                .width(Pixels(64.0))
                .height(Pixels(18.0))
                .on_press(|cx| cx.emit(CalcEvent::TinyFormat));
        })
        .title("ECW")
        .inner_size((240, 90))
        .visible(s_tiny_vis.clone());
        s_tiny_ent.set(w_tiny.entity());
    })
    .title("Calculator")
    .inner_size((448, 250))
    .run()
}
