// ECW Expression Calculator — vizia immediate-mode GUI
// Ported from the original's TCALCFORM layout (see gui/ in the FPC port).
// The engine (engine.rs) is shared with the CLI / battery tests.
//
// vizia 0.4 is signal-based: model fields are Signal<T>, views observe them
// via Binding, and events mutate the signals.

use ecw_vizia::engine::{self, Engine};
use vizia::prelude::*;

pub struct CalcState {
    expr: Signal<String>,
    dec: Signal<String>,
    hex: Signal<String>,
    bin: Signal<String>,
    oct: Signal<String>,
    exp: Signal<String>,
    err: Signal<String>,
}

impl CalcState {
    fn new() -> Self {
        Self {
            expr: Signal::new(String::new()),
            dec: Signal::new("0".to_string()),
            hex: Signal::new("00000000".to_string()),
            bin: Signal::new("00000000000000000000000000000000".to_string()),
            oct: Signal::new("00000000000".to_string()),
            exp: Signal::new("0.00000000000000000E+0000".to_string()),
            err: Signal::new("ok".to_string()),
        }
    }

    fn evaluate(&mut self) {
        let mut eng = Engine::new();
        let mut v = 0.0;
        let expr = self.expr.get();
        match eng.eval_expr(&expr, &mut v) {
            Ok(()) => {
                self.dec.set(engine::fmt_number(v));
                self.hex.set(engine::fmt_hex32(&eng, v));
                self.bin.set(engine::fmt_bin32(v));
                self.oct.set(engine::fmt_oct32(v));
                self.exp.set(engine::fmt_exp(v));
                self.err.set("ok".to_string());
            }
            Err(m) => {
                self.err.set(m);
            }
        }
    }
}

impl Model for CalcState {
    fn event(&mut self, cx: &mut EventContext, event: &mut Event) {
        event.map(|calc_event, _| match calc_event {
            CalcEvent::SetExpr(s) => {
                self.expr.set(s.clone());
            }
            CalcEvent::Evaluate => {
                self.evaluate();
            }
            CalcEvent::Copy => {
                // Copy the dec result (simplest faithful behaviour: copy decimal)
                let _ = cx.set_clipboard(self.dec.get());
            }
        });
    }
}

pub enum CalcEvent {
    SetExpr(String),
    Evaluate,
    Copy,
}

fn main() -> Result<(), ApplicationError> {
    Application::new(|cx| {
        let state = CalcState::new();
        let s_dec = state.dec.clone();
        let s_hex = state.hex.clone();
        let s_bin = state.bin.clone();
        let s_oct = state.oct.clone();
        let s_exp = state.exp.clone();
        let s_err = state.err.clone();
        state.build(cx);

        Element::new(cx)
            .class("window")
            .position_type(PositionType::Absolute)
            .left(Pixels(8.0))
            .top(Pixels(8.0))
            .width(Pixels(448.0))
            .height(Pixels(250.0))
            .background_color(Color::rgb(236, 233, 216));

        // Expression row: label + textbox + Evaluate
        Label::new(cx, "Expression:")
            .position_type(PositionType::Absolute)
            .left(Pixels(20.0))
            .top(Pixels(16.0))
            .font_size(12.0);

        Textbox::new(cx, String::new())
            .position_type(PositionType::Absolute)
            .left(Pixels(20.0))
            .top(Pixels(32.0))
            .width(Pixels(320.0))
            .height(Pixels(24.0))
            .on_edit(|cx, text| {
                cx.emit(CalcEvent::SetExpr(text));
            });

        Button::new(cx, |cx| Label::new(cx, "Evaluate"))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(32.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0))
            .on_press(|cx| {
                cx.emit(CalcEvent::Evaluate);
            });

        // Results: five rows (label: value)
        Label::new(cx, "Copy as:")
            .position_type(PositionType::Absolute)
            .left(Pixels(20.0))
            .top(Pixels(64.0))
            .font_size(12.0);

        row(cx, "Dec", 82.0, 24.0, 70.0);
        Binding::new(cx, s_dec, move |cx| {
            Label::new(cx, s_dec.get())
            .position_type(PositionType::Absolute)
                .left(Pixels(70.0))
                .top(Pixels(82.0))
                .font_size(12.0);
        });

        row(cx, "Hex", 102.0, 24.0, 70.0);
        Binding::new(cx, s_hex, move |cx| {
            Label::new(cx, s_hex.get())
            .position_type(PositionType::Absolute)
                .left(Pixels(70.0))
                .top(Pixels(102.0))
                .font_size(12.0);
        });

        row(cx, "Bin", 122.0, 24.0, 70.0);
        Binding::new(cx, s_bin, move |cx| {
            Label::new(cx, s_bin.get())
            .position_type(PositionType::Absolute)
                .left(Pixels(70.0))
                .top(Pixels(122.0))
                .font_size(12.0);
        });

        row(cx, "Oct", 142.0, 24.0, 70.0);
        Binding::new(cx, s_oct, move |cx| {
            Label::new(cx, s_oct.get())
            .position_type(PositionType::Absolute)
                .left(Pixels(70.0))
                .top(Pixels(142.0))
                .font_size(12.0);
        });

        row(cx, "Exp", 162.0, 24.0, 70.0);
        Binding::new(cx, s_exp, move |cx| {
            Label::new(cx, s_exp.get())
            .position_type(PositionType::Absolute)
                .left(Pixels(70.0))
                .top(Pixels(162.0))
                .font_size(12.0);
        });

        // Error status
        Label::new(cx, "Error status:")
            .position_type(PositionType::Absolute)
            .left(Pixels(20.0))
            .top(Pixels(190.0))
            .font_size(12.0);
        Binding::new(cx, s_err, move |cx| {
            Label::new(cx, s_err.get())
            .position_type(PositionType::Absolute)
                .left(Pixels(70.0))
                .top(Pixels(208.0))
                .font_size(12.0);
        });

        // Copy / Setup / Help / Close button column
        Button::new(cx, |cx| Label::new(cx, "Copy"))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(64.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0))
            .on_press(|cx| {
                cx.emit(CalcEvent::Copy);
            });

        Button::new(cx, |cx| Label::new(cx, "Setup..."))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(94.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0));

        Button::new(cx, |cx| Label::new(cx, "Help"))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(124.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0));

        Button::new(cx, |cx| Label::new(cx, "Close"))
            .position_type(PositionType::Absolute)
            .left(Pixels(352.0))
            .top(Pixels(154.0))
            .width(Pixels(80.0))
            .height(Pixels(24.0))
            .on_press(|cx| cx.emit(WindowEvent::WindowClose));
    })
    .title("Calculator")
    .run()
}

fn row(cx: &mut Context, name: &'static str, top: f32, _label_w: f32, _val_x: f32) {
    Label::new(cx, name)
            .position_type(PositionType::Absolute)
        .left(Pixels(24.0))
        .top(Pixels(top))
        .font_size(12.0);
}
