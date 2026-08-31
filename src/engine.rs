// ============================================================================
// ECW Expression Calculator — Rust engine
// Ported from gui/ecwengine.pas (FreePascal), which was reverse-engineered
// from ecw.exe (v1.04-era, Delphi 3 RTL) and verified live against the
// original console engine (ec.exe v1.03b3) under Wine (188/188 differential
// tests pass byte-for-byte for the FPC port).
//
// Fidelity note: the original computes in x87 Extended (80-bit).  This Rust
// port computes in f64, so last-ULP results of transcendental / division
// operations may differ from the original by 1 unit in the last place.
// Parsing, operator semantics, error messages and formatting rules are
// ported verbatim.
// ============================================================================

pub struct UserDef {
    pub name: String,
    pub is_func: bool,
    pub num_args: usize,
    pub arg_names: Vec<String>,
    pub body: String,
    pub val: f64,
}

pub struct Engine {
    s: Vec<char>,
    p: usize,
    err: String,
    pub defs: Vec<UserDef>,
    pub unsigned_hex: bool,
    pub sep_mode: i32, // 0: '.' ',',  1: ',' ';',  2: '.' ';'
    locals: Vec<(String, f64)>,
    depth: i32,
    last_tok_start: usize,
}

const MAX_ARGS: usize = 4000;
const MAX_DEFS: usize = 256;
const MAX_DEPTH: i32 = 32;

impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
}

impl Engine {
    pub fn new() -> Self {
        Engine {
            s: Vec::new(),
            p: 0,
            err: String::new(),
            defs: Vec::new(),
            unsigned_hex: false,
            sep_mode: 0,
            locals: Vec::new(),
            depth: 0,
            last_tok_start: 0,
        }
    }

    // ---------- low-level helpers ----------

    #[inline]
    fn len(&self) -> usize {
        self.s.len()
    }

    #[inline]
    fn peek_c(&self) -> char {
        if self.p >= self.len() { '\0' } else { self.s[self.p] }
    }

    #[inline]
    fn peek_c2(&self) -> char {
        if self.p + 1 >= self.len() { '\0' } else { self.s[self.p + 1] }
    }

    #[inline]
    fn next_c(&mut self) -> char {
        let c = self.peek_c();
        if c != '\0' { self.p += 1; }
        c
    }

    #[inline]
    fn set_err(&mut self, m: &str) {
        if self.err.is_empty() {
            self.err = m.to_string();
        }
    }

    #[inline]
    fn is_sp(c: char) -> bool {
        c == ' ' || c == '\t' || c == '\n' || c == '\r'
    }

    fn skip_ws(&mut self) {
        while self.p < self.len() && Self::is_sp(self.s[self.p]) {
            self.p += 1;
        }
    }

    #[inline]
    fn hex_val(c: char) -> i32 {
        match c {
            '0'..='9' => (c as u8 - b'0') as i32,
            'a'..='f' => (c as u8 - b'a') as i32 + 10,
            'A'..='F' => (c as u8 - b'A') as i32 + 10,
            _ => -1,
        }
    }

    #[inline]
    fn frac0(v: f64) -> bool {
        v.fract() == 0.0
    }

    #[inline]
    fn decimal_sep(&self) -> char {
        if self.sep_mode == 1 { ',' } else { '.' }
    }

    #[inline]
    fn list_sep_c(&self) -> char {
        if self.sep_mode == 0 { ',' } else { ';' }
    }

    fn to_int(&mut self, v: f64, op: &str) -> Option<i64> {
        if !Self::frac0(v) {
            self.set_err(&format!("illegal real arg: {}", op));
            return None;
        }
        if v > 9.223372036854775807e18 || v < -9.223372036854775808e18 {
            self.set_err(&format!("overflow in int arg: {}", op));
            return None;
        }
        Some(v.round() as i64)
    }

    fn bit_not(&mut self, v: f64) -> f64 {
        match self.to_int(v, "~") {
            Some(i) => !(i as u32) as i32 as f64,
            None => 0.0,
        }
    }

    fn bit_op2(&mut self, op: &str, a: f64, b: f64) -> f64 {
        let ia = match self.to_int(a, op) { Some(x) => x, None => return 0.0 };
        let ib = match self.to_int(b, op) { Some(x) => x, None => return 0.0 };
        let ua = ia as u32;
        let ub = ib as u32;
        match op {
            "&" => (ua & ub) as i32 as f64,
            "|" => (ua | ub) as i32 as f64,
            "^" => (ua ^ ub) as i32 as f64,
            "<<" => {
                if ib < 0 { self.set_err("illegal arg2<0: <<"); return 0.0; }
                let c = ib as i32;
                if c >= 32 { 0.0 } else { (ua.wrapping_shl(c as u32)) as i32 as f64 }
            }
            ">>" => {
                if ib < 0 { self.set_err("illegal arg2<0: >>"); return 0.0; }
                let c = ib as i32;
                if c >= 32 { 0.0 } else { (ua.wrapping_shr(c as u32)) as i32 as f64 }
            }
            _ => 0.0,
        }
    }

    fn pow_e(&mut self, x: f64, y: f64) -> f64 {
        if y == 0.0 {
            return if x == 0.0 { 0.0 } else { 1.0 }; // 0^0 = 0 (original)
        }
        if x == 0.0 {
            if y < 0.0 { self.set_err("overflow: **"); }
            return 0.0;
        }
        // integer-exponent fast path: exponentiation by squaring
        if Self::frac0(y) && y.abs() <= 1e9 {
            let mut n = y.round() as i64;
            let neg = n < 0;
            if neg { n = -n; }
            let mut base = x;
            let mut acc = 1.0f64;
            while n > 0 {
                if (n & 1) != 0 { acc *= base; }
                n >>= 1;
                if n > 0 { base *= base; }
            }
            if neg {
                if acc == 0.0 { self.set_err("overflow: **"); return 0.0; }
                acc = 1.0 / acc;
            }
            if acc.is_infinite() || acc.is_nan() { self.set_err("overflow: **"); return 0.0; }
            return acc;
        }
        let r = if x < 0.0 {
            if !Self::frac0(y) { self.set_err("invalid usage: **"); return 0.0; }
            let sgn = if (y / 2.0).fract() == 0.0 { 1.0 } else { -1.0 };
            sgn * (y * (-x).ln()).exp()
        } else {
            (y * x.ln()).exp()
        };
        if r.is_infinite() || r.is_nan() { self.set_err("overflow: **"); }
        r
    }

    fn fact(&mut self, a: f64) -> f64 {
        if a < 0.0 { self.set_err("illegal arg<0: fact"); return 0.0; }
        if !Self::frac0(a) { self.set_err("illegal real arg: fact"); return 0.0; }
        if a > 1750.0 { self.set_err("overflow: fact"); return 0.0; }
        let mut r = 1.0;
        for i in 2..=(a.trunc() as i64) {
            r *= i as f64;
        }
        r
    }

    fn call_std(&mut self, a: f64, fname: &str) -> f64 {
        let r = match fname {
            "sin" => a.sin(),
            "cos" => a.cos(),
            "tan" => a.tan(),
            "ctan" => {
                if a == 0.0 { self.set_err("overflow: ctan"); return 0.0; }
                a.cos() / a.sin()
            }
            "asin" => {
                if a < -1.0 || a > 1.0 { self.set_err("illegal |arg|>1: asin"); return 0.0; }
                a.asin()
            }
            "acos" => {
                if a < -1.0 || a > 1.0 { self.set_err("illegal |arg|>1: acos"); return 0.0; }
                a.acos()
            }
            "atan" => a.atan(),
            "actan" => {
                if a == 0.0 { self.set_err("overflow: actan"); return 0.0; }
                std::f64::consts::FRAC_PI_2 - a.atan()
            }
            "sinh" => (a.exp() - (-a).exp()) / 2.0,
            "cosh" => (a.exp() + (-a).exp()) / 2.0,
            "tanh" => {
                let e2 = (2.0 * a).exp();
                (e2 - 1.0) / (e2 + 1.0)
            }
            "asinh" => (a + (a * a + 1.0).sqrt()).ln(),
            "acosh" => {
                if a < 1.0 { self.set_err("illegal arg<1: acosh"); return 0.0; }
                (a + (a * a - 1.0).sqrt()).ln()
            }
            "atanh" => {
                if a == 1.0 || a == -1.0 { self.set_err("overflow: atanh"); return 0.0; }
                if a > 1.0 || a < -1.0 { self.set_err("illegal |arg|>1: atanh"); return 0.0; }
                0.5 * ((1.0 + a) / (1.0 - a)).ln()
            }
            "exp" => a.exp(),
            "ln" => {
                if a < 0.0 { self.set_err("illegal arg<0: ln"); return 0.0; }
                if a == 0.0 { self.set_err("overflow: ln"); return 0.0; }
                a.ln()
            }
            "log" => {
                if a < 0.0 { self.set_err("illegal arg<0: log"); return 0.0; }
                if a == 0.0 { self.set_err("overflow: log"); return 0.0; }
                a.ln() / 10.0f64.ln()
            }
            "sqr" => a * a,
            "sqrt" => {
                if a < 0.0 { self.set_err("illegal arg<0: sqrt"); return 0.0; }
                a.sqrt()
            }
            "fact" => return self.fact(a),
            "abs" => a.abs(),
            "sign" => { if a > 0.0 { 1.0 } else if a < 0.0 { -1.0 } else { 0.0 } }
            "int" => a.trunc(),
            "frac" => a.fract(),
            "rad" => a * (std::f64::consts::PI / 180.0),
            "deg" => a * (180.0 / std::f64::consts::PI),
            _ => {
                self.set_err(&format!("unknown function: {}", fname));
                return 0.0;
            }
        };
        if (r.is_infinite() || r.is_nan()) && self.err.is_empty() {
            self.set_err(&format!("overflow: {}", fname));
        }
        r
    }

    fn call_list(&mut self, fname: &str, a: &[f64]) -> f64 {
        let n = a.len();
        let r = match fname {
            "sum" => a.iter().sum(),
            "prod" => a.iter().product(),
            "avg" => {
                let s: f64 = a.iter().sum();
                if n == 0 { 0.0 } else { s / n as f64 }
            }
            "geo" => {
                let p: f64 = a.iter().product();
                if n == 0 { 0.0 }
                else if p == 0.0 { 0.0 }
                else if p < 0.0 {
                    -self.pow_e(-p, 1.0 / n as f64)
                } else {
                    self.pow_e(p, 1.0 / n as f64)
                }
            }
            "min" => {
                let mut m = a[0];
                for i in 1..n { if a[i] < m { m = a[i]; } }
                m
            }
            "max" => {
                let mut m = a[0];
                for i in 1..n { if a[i] > m { m = a[i]; } }
                m
            }
            "poly" => {
                if n < 2 { self.set_err("missing arg2: poly"); return 0.0; }
                let mut acc = 0.0;
                for i in (1..n).rev() {
                    acc = acc * a[0] + a[i];
                }
                acc
            }
            _ => {
                self.set_err(&format!("unknown list function: {}", fname));
                return 0.0;
            }
        };
        if (r.is_infinite() || r.is_nan()) && self.err.is_empty() {
            self.set_err(&format!("overflow: {}", fname));
        }
        r
    }

    fn is_list_func(name: &str) -> bool {
        matches!(name, "sum" | "prod" | "avg" | "geo" | "min" | "max")
    }

    fn is_builtin_name(name: &str) -> bool {
        const B: [&str; 35] = [
            "sin","cos","tan","ctan","asin","acos","atan","actan",
            "sinh","cosh","tanh","asinh","acosh","atanh",
            "exp","ln","log","sqr","sqrt","fact","abs","sign","int","frac","rad","deg",
            "sum","prod","avg","geo","min","max","poly","pi","e",
        ];
        B.contains(&name)
    }

    fn lookup_var(&self, name: &str) -> Option<f64> {
        for (n, v) in self.locals.iter().rev() {
            if n == name { return Some(*v); }
        }
        for d in self.defs.iter() {
            if !d.is_func && d.name == name { return Some(d.val); }
        }
        if name == "pi" { return Some(std::f64::consts::PI); }
        if name == "e" { return Some(1.0f64.exp()); }
        None
    }

    fn find_user_func(&self, name: &str, want_args: usize) -> Option<usize> {
        for (i, d) in self.defs.iter().enumerate() {
            if d.is_func && d.name == name && d.num_args == want_args {
                return Some(i);
            }
        }
        None
    }

    fn eval_user_func(&mut self, di: usize, args: &[f64]) -> f64 {
        if self.depth >= MAX_DEPTH {
            self.set_err("too complex definition");
            return 0.0;
        }
        let saved_locals = self.locals.clone();
        self.locals.clear();
        for (i, an) in self.defs[di].arg_names.iter().enumerate() {
            self.locals.push((an.clone(), args[i]));
        }
        let old_s = self.s.clone();
        let old_p = self.p;
        self.s = self.defs[di].body.chars().collect();
        self.p = 0;
        self.depth += 1;
        let r = self.parse_expr(0);
        self.depth -= 1;
        if self.err.is_empty() {
            self.skip_ws();
            if self.p < self.len() {
                self.set_err(&format!("invalid expression: {}", self.s[self.p]));
            }
        }
        self.s = old_s;
        self.p = old_p;
        self.locals = saved_locals;
        r
    }

    fn eval_call(&mut self, name: &str) -> f64 {
        let mut args: Vec<f64> = Vec::new();
        self.skip_ws();
        if self.peek_c() == ')' {
            self.set_err("missing expression");
            return 0.0;
        }
        loop {
            if args.len() >= MAX_ARGS {
                self.set_err(&format!("too many args: {}", name));
                return 0.0;
            }
            args.push(self.parse_expr(0));
            if !self.err.is_empty() { return 0.0; }
            self.skip_ws();
            if self.peek_c() == self.list_sep_c() {
                self.next_c();
                self.skip_ws();
                if self.peek_c() == ')' {
                    self.set_err("missing expression");
                    return 0.0;
                }
                continue;
            }
            break;
        }
        if self.peek_c() != ')' {
            self.set_err(&format!("missing operator: {}", name));
            return 0.0;
        }
        self.next_c();

        if args.len() == 1 {
            if let Some(di) = self.find_user_func(name, 1) {
                return self.eval_user_func(di, &args);
            }
            let r = self.call_std(args[0], name);
            if self.err == format!("invalid expression: {}", name) {
                self.err = format!("unknown function: {}", name);
            }
            return r;
        }

        if let Some(di) = self.find_user_func(name, args.len()) {
            return self.eval_user_func(di, &args);
        }

        if name == "log" && args.len() == 2 {
            if args[1] <= 0.0 { self.set_err("overflow: log"); return 0.0; }
            if args[0] <= 0.0 || args[0] == 1.0 { self.set_err("overflow: log"); return 0.0; }
            let r = args[1].ln() / args[0].ln();
            if r.is_infinite() || r.is_nan() { self.set_err("overflow: log"); }
            return r;
        }

        self.call_list(name, &args)
    }

    fn precedence(op: &str) -> i32 {
        match op {
            "*" | "/" | "**" | "//" | "%" => 50,
            "+" | "-" => 40,
            "&" | "|" | "^" | "&&" | "||" | "^^" | "<<" | ">>" => 30,
            "=" | "==" | "<>" | "!=" | "<" | ">" | "<=" | ">=" => 20,
            _ => 0,
        }
    }

    fn peek_op(&self) -> Option<String> {
        let c1 = self.peek_c();
        let c2 = self.peek_c2();
        let op: String = match c1 {
            '*' => if c2 == '*' { "**".into() } else { "*".into() },
            '/' => if c2 == '/' { "//".into() } else { "/".into() },
            '<' => if c2 == '=' { "<=".into() }
                   else if c2 == '>' { "<>".into() }
                   else if c2 == '<' { "<<".into() } else { "<".into() },
            '>' => if c2 == '=' { ">=".into() }
                   else if c2 == '>' { ">>".into() } else { ">".into() },
            '=' => if c2 == '=' { "==".into() } else { "=".into() },
            '!' => if c2 == '=' { "!=".into() } else { "!".into() },
            '&' => if c2 == '&' { "&&".into() } else { "&".into() },
            '|' => if c2 == '|' { "||".into() } else { "|".into() },
            '^' => if c2 == '^' { "^^".into() } else { "^".into() },
            '+' | '-' | '%' | '~' | '(' | ')' | ',' | ';' => c1.to_string(),
            _ => return None,
        };
        Some(op)
    }

    fn apply_op(&mut self, op: &str, a: f64, b: f64) -> f64 {
        let r = match op {
            "+" => a + b,
            "-" => a - b,
            "*" => a * b,
            "/" => {
                if b == 0.0 { self.set_err("overflow: /"); return 0.0; }
                a / b
            }
            "**" => return self.pow_e(a, b),
            "//" => {
                let ia = match self.to_int(a, "//") { Some(x) => x, None => return 0.0 };
                let ib = match self.to_int(b, "//") { Some(x) => x, None => return 0.0 };
                if ib == 0 { self.set_err("illegal arg2=0: //"); return 0.0; }
                (ia / ib) as f64
            }
            "%" => {
                let ia = match self.to_int(a, "%") { Some(x) => x, None => return 0.0 };
                let ib = match self.to_int(b, "%") { Some(x) => x, None => return 0.0 };
                if ib == 0 { self.set_err("illegal arg2=0: %"); return 0.0; }
                (ia % ib) as f64
            }
            "&" | "|" | "^" | "<<" | ">>" => return self.bit_op2(op, a, b),
            "=" | "==" => { if a == b { 1.0 } else { 0.0 } }
            "<>" | "!=" => { if a != b { 1.0 } else { 0.0 } }
            "<" => { if a < b { 1.0 } else { 0.0 } }
            ">" => { if a > b { 1.0 } else { 0.0 } }
            "<=" => { if a <= b { 1.0 } else { 0.0 } }
            ">=" => { if a >= b { 1.0 } else { 0.0 } }
            "&&" => { if (a != 0.0) && (b != 0.0) { 1.0 } else { 0.0 } }
            "||" => { if (a != 0.0) || (b != 0.0) { 1.0 } else { 0.0 } }
            "^^" => { if (a != 0.0) ^ (b != 0.0) { 1.0 } else { 0.0 } }
            _ => { self.set_err(&format!("unknown operator: {}", op)); return 0.0; }
        };
        if (r.is_infinite() || r.is_nan()) && self.err.is_empty() {
            self.set_err(&format!("overflow: {}", op));
        }
        r
    }

    fn eval_base_const(&mut self, d: &str, base: i64, kind: &str) -> f64 {
        let mut hx: u64 = 0;
        for ch in d.chars() {
            let dv = Self::hex_val(ch);
            if dv < 0 || (dv as i64) >= base {
                self.set_err(&format!("invalid {}: {}", kind, d.to_lowercase()));
                return 0.0;
            }
            if hx > (u64::MAX - dv as u64) / (base as u64) {
                self.set_err(&format!("overflow in {}: {}", kind, d.to_lowercase()));
                return 0.0;
            }
            hx = hx * (base as u64) + dv as u64;
        }
        let neg = hx >= 0x8000_0000;
        if !self.unsigned_hex {
            if hx > 0xFFFF_FFFF {
                self.set_err(&format!("overflow in {}: {}", kind, d.to_lowercase()));
                return 0.0;
            }
            if neg {
                (hx as i64 - 0x1_0000_0000) as f64
            } else {
                hx as f64
            }
        } else {
            hx as f64
        }
    }

    // multiply/divide by an exact power of ten (10^k for |k| <= 22 is exactly
    // representable in f64, so a single multiply/divide is correctly rounded)
    fn scale_pow10(v: f64, k: i32) -> f64 {
        if k == 0 { return v; }
        let neg = k < 0;
        let k = if neg { -k } else { k };
        let mut p = 1.0f64;
        for _ in 0..k { p *= 10.0; }
        if neg { v / p } else { v * p }
    }

    fn try_parse_real(&mut self) -> Option<f64> {
        if self.p >= self.len() { return None; }
        let c = self.peek_c();
        if !(c.is_ascii_digit() || c == self.decimal_sep()) { return None; }

        let start = self.p;
        // integer part
        let mut mant: i64 = 0;
        let mut had = false;
        let mut overflowed = false;
        while self.p < self.len() && self.s[self.p].is_ascii_digit() {
            if !overflowed {
                let dv = (self.s[self.p] as u8 - b'0') as i64;
                if mant > (i64::MAX - dv) / 10 {
                    overflowed = true;
                } else {
                    mant = mant * 10 + dv;
                }
            }
            self.p += 1;
            had = true;
        }
        // fraction part
        let mut frac_digits: i32 = 0;
        if self.p < self.len() && self.s[self.p] == self.decimal_sep() {
            self.p += 1;
            while self.p < self.len() && self.s[self.p].is_ascii_digit() {
                if !overflowed {
                    let dv = (self.s[self.p] as u8 - b'0') as i64;
                    if mant > (i64::MAX - dv) / 10 {
                        overflowed = true;
                    } else {
                        mant = mant * 10 + dv;
                    }
                }
                self.p += 1;
                had = true;
                frac_digits += 1;
            }
        }
        if !had { return None; }

        // exponent suffix
        let mut e: i32 = 0;
        let mut signe: i32 = 1;
        if self.p < self.len() && (self.s[self.p] == 'e' || self.s[self.p] == 'E') {
            self.p += 1;
            if self.p < self.len() && (self.s[self.p] == '+' || self.s[self.p] == '-') {
                if self.s[self.p] == '-' { signe = -1; } else { signe = 1; }
                self.p += 1;
            }
            if self.p >= self.len() || !self.s[self.p].is_ascii_digit() {
                // "1e" with no exponent digits: value is just the mantissa;
                // back up so the caller reports the trailing garbage.
                self.p = self.p.saturating_sub(1); // back to 'e' position
                if signe == -1 { self.p = self.p.saturating_sub(1); }
                return Some(0.0);
            }
            while self.p < self.len() && self.s[self.p].is_ascii_digit() {
                e = e * 10 + (self.s[self.p] as u8 - b'0') as i32;
                if e > 5000 { break; }
                self.p += 1;
            }
            e *= signe;
        }

        // Val-style: integer mantissa * 10^(e - frac_digits)
        let scale = e - frac_digits;
        if overflowed {
            let mut v = 0.0f64;
            let mut q = start;
            while q < self.len() && self.s[q].is_ascii_digit() {
                v = v * 10.0 + (self.s[q] as u8 - b'0') as f64;
                q += 1;
            }
            if q < self.len() && self.s[q] == self.decimal_sep() {
                q += 1;
                while q < self.len() && self.s[q].is_ascii_digit() {
                    v = v * 10.0 + (self.s[q] as u8 - b'0') as f64;
                    q += 1;
                }
            }
            Some(Self::scale_pow10(v, scale))
        } else {
            let mut v = mant as f64;
            if scale != 0 {
                v = Self::scale_pow10(v, scale);
            }
            Some(v)
        }
    }

    fn try_parse_number(&mut self) -> Option<f64> {
        let save = self.p;
        let c = self.peek_c();

        if c == '$' {
            self.next_c();
            let mut h = String::new();
            while self.p < self.len() && Self::hex_val(self.s[self.p]) >= 0 {
                h.push(self.s[self.p]);
                self.p += 1;
            }
            if h.is_empty() {
                self.p = save;
                return None; // bare '$': fall to invalid char
            }
            let v = self.eval_base_const(&h, 16, "hex");
            return Some(v);
        }

        if c == '0' && (self.peek_c2() == 'x' || self.peek_c2() == 'X') {
            self.p += 2;
            let mut h = String::new();
            while self.p < self.len() && Self::hex_val(self.s[self.p]) >= 0 {
                h.push(self.s[self.p]);
                self.p += 1;
            }
            if h.is_empty() {
                return Some(0.0); // "0x" -> 0
            }
            // if a non-hex alnum char follows, report it as part of invalid hex
            if self.p < self.len() && self.s[self.p].is_ascii_alphanumeric() {
                h.push(self.s[self.p]);
                self.p += 1;
                self.set_err(&format!("invalid hex: {}", h.to_lowercase()));
                return Some(0.0);
            }
            let v = self.eval_base_const(&h, 16, "hex");
            return Some(v);
        }

        // hex-digit run: catches 12h, 0ABh, 101b, 12o, and plain numbers
        let mut h = String::new();
        while self.p < self.len() && Self::hex_val(self.s[self.p]) >= 0 {
            h.push(self.s[self.p]);
            self.p += 1;
        }

        // suffix char following the run: 12h / 0ABh / 101b / 12o
        if !h.is_empty() && self.p < self.len()
            && matches!(self.s[self.p], 'h' | 'H' | 'o' | 'O' | 'b' | 'B') {
            let sc = self.s[self.p].to_ascii_lowercase();
            self.p += 1;
            return Some(match sc {
                'h' => self.eval_base_const(&h, 16, "hex"),
                'o' => self.eval_base_const(&h, 8, "oct"),
                'b' => self.eval_base_const(&h, 2, "bin"),
                _ => unreachable!(),
            });
        }

        // trailing-suffix form: "101b" — the 'b' got absorbed into h
        let hb = h.as_bytes();
        if h.len() >= 2 && matches!(hb[h.len() - 1], b'h' | b'H' | b'o' | b'O' | b'b' | b'B') {
            let sc = (hb[h.len() - 1] as char).to_ascii_lowercase();
            h.pop();
            return Some(match sc {
                'h' => self.eval_base_const(&h, 16, "hex"),
                'o' => self.eval_base_const(&h, 8, "oct"),
                'b' => self.eval_base_const(&h, 2, "bin"),
                _ => unreachable!(),
            });
        }

        // leading-zero octal: 012 = 10
        if h.len() > 1 && h.as_bytes()[0] == b'0' && self.p >= self.len() {
            let mut bad = false;
            for ch in h.bytes() {
                if !(b'0'..=b'7').contains(&ch) { bad = true; break; }
            }
            if !bad {
                let v = self.eval_base_const(&h, 8, "oct");
                return Some(v);
            }
        }

        // decimal / real: rewind and parse with try_parse_real
        self.p = save;
        let r = self.try_parse_real();
        if r.is_none() && self.p < self.len() && Self::hex_val(self.s[self.p]) >= 0 {
            self.set_err(&format!("invalid number: {}", self.s[self.p]));
        }
        r
    }

    fn parse_primary(&mut self) -> f64 {
        self.skip_ws();
        let c = self.peek_c();

        if c == '(' {
            self.next_c();
            let v = self.parse_expr(0);
            if !self.err.is_empty() { return v; }
            self.skip_ws();
            if self.peek_c() != ')' {
                self.set_err("invalid brackets");
                return 0.0;
            }
            self.next_c();
            return v;
        }

        if c == ')' {
            self.set_err("invalid brackets");
            return 0.0;
        }

        if c == '\0' {
            self.set_err("missing expression");
            return 0.0;
        }

        if c.is_ascii_digit() || c == self.decimal_sep() || c == '$' {
            self.last_tok_start = self.p;
            if let Some(v) = self.try_parse_number() {
                return v;
            }
            return 0.0;
        }

        if c.is_ascii_alphabetic() || c == '_' {
            self.last_tok_start = self.p;
            let mut name = String::new();
            while self.p < self.len() && {
                let ch = self.s[self.p];
                ch.is_ascii_alphanumeric() || ch == '_'
            } {
                name.push(self.s[self.p]);
                self.p += 1;
            }
            self.skip_ws();
            if self.peek_c() == '(' {
                self.next_c();
                return self.eval_call(&name);
            }
            if let Some(v) = self.lookup_var(&name) {
                return v;
            }
            // unknown or builtin without parens: same message
            self.set_err(&format!("invalid expression: {}", name));
            return 0.0;
        }

        self.set_err(&format!("invalid char: {}", c));
        0.0
    }

    fn parse_unary(&mut self) -> f64 {
        self.skip_ws();
        let c = self.peek_c();
        match c {
            '+' => { self.next_c(); self.parse_unary() }
            '-' => { self.next_c(); -self.parse_unary() }
            '~' => {
                self.next_c();
                let v = self.parse_unary();
                self.bit_not(v)
            }
            '!' => {
                self.next_c();
                if self.parse_unary() == 0.0 {
                    1.0
                } else {
                    0.0
                }
            }
            _ => self.parse_primary(),
        }
    }

    fn parse_expr(&mut self, min_lev: i32) -> f64 {
        let mut a = self.parse_unary();
        if !self.err.is_empty() { return a; }
        loop {
            self.skip_ws();
            let op = match self.peek_op() {
                Some(o) => o,
                None => break,
            };
            let lev = Self::precedence(&op);
            if lev == 0 || lev < min_lev { break; }
            if op == ")" || op == "," || op == ";" { break; }
            self.p += op.len(); // consume full operator (incl. multi-char)
            self.skip_ws();
            if self.p >= self.len() {
                self.set_err(&format!("missing arg2: {}", op));
                break;
            }
            let b = self.parse_expr(lev + 1); // left-assoc: RHS binds tighter
            if !self.err.is_empty() { break; }
            a = self.apply_op(&op, a, b);
            if !self.err.is_empty() { break; }
        }
        a
    }

    fn add_def(&mut self, name: &str, is_func: bool, num_args: usize,
               arg_names: &[String], body: &str, val: f64) {
        if self.defs.len() >= MAX_DEFS {
            self.set_err("too many definitions");
            return;
        }
        // replace existing
        for d in self.defs.iter_mut() {
            if d.name == name {
                d.is_func = is_func;
                d.num_args = num_args;
                d.body = body.to_string();
                d.val = val;
                d.arg_names.clear();
                d.arg_names.extend_from_slice(arg_names);
                return;
            }
        }
        self.defs.push(UserDef {
            name: name.to_string(),
            is_func,
            num_args,
            arg_names: arg_names.to_vec(),
            body: body.to_string(),
            val,
        });
    }

    // Top-level: [var=val, ...] expr  or  [f(args)=body, ...] expr
    fn parse_toplevel(&mut self) -> f64 {
        self.locals.clear();
        loop {
            self.skip_ws();
            let save = self.p;

            // detect: identifier ['(' args ')'] '=' (peek only)
            let mut looks_like_def = false;
            let mut name = String::new();
            if self.p < self.len()
                && (self.s[self.p].is_ascii_alphabetic() || self.s[self.p] == '_') {
                looks_like_def = true;
            }

            if looks_like_def {
                let mut num_args: usize = 0;
                let mut arg_names: Vec<String> = Vec::new();
                let mut q = self.p;
                // scan name
                while q < self.len() && {
                    let ch = self.s[q];
                    ch.is_ascii_alphanumeric() || ch == '_'
                } {
                    name.push(self.s[q]);
                    q += 1;
                }
                // skip ws
                while q < self.len() && Self::is_sp(self.s[q]) { q += 1; }
                if q < self.len() && self.s[q] == '(' {
                    q += 1;
                    while q < self.len() && Self::is_sp(self.s[q]) { q += 1; }
                    if q < self.len() && self.s[q] == ')' {
                        q += 1;
                    } else {
                        loop {
                            if num_args >= 64 {
                                self.set_err(&format!("too many args: {}", name));
                                return 0.0;
                            }
                            let mut an = String::new();
                            while q < self.len() && {
                                let ch = self.s[q];
                                ch.is_ascii_alphanumeric() || ch == '_'
                            } {
                                an.push(self.s[q]);
                                q += 1;
                            }
                            arg_names.push(an);
                            num_args += 1;
                            while q < self.len() && Self::is_sp(self.s[q]) { q += 1; }
                            if q < self.len() && self.s[q] == self.list_sep_c() {
                                q += 1;
                                while q < self.len() && Self::is_sp(self.s[q]) { q += 1; }
                                continue;
                            }
                            if q < self.len() && self.s[q] == ')' {
                                q += 1;
                                break;
                            }
                            looks_like_def = false;
                            break;
                        }
                    }
                    while q < self.len() && Self::is_sp(self.s[q]) { q += 1; }
                    if looks_like_def {
                        if q >= self.len() || self.s[q] != '=' {
                            looks_like_def = false;
                        }
                    }
                } else {
                    while q < self.len() && Self::is_sp(self.s[q]) { q += 1; }
                    if q >= self.len() || self.s[q] != '=' {
                        looks_like_def = false;
                    }
                }
                if !looks_like_def {
                    self.p = save;
                } else {
                    // committed: q points at '='
                    self.p = q;
                    // consume '='
                    self.next_c();
                    self.skip_ws();
                    if self.peek_c() == self.list_sep_c() {
                        self.set_err("missing expression");
                        return 0.0;
                    }
                    if num_args > 0 {
                        // capture body text up to top-level list separator
                        let mut body = String::new();
                        let mut depth_scan: i32 = 0;
                        while self.p < self.len() {
                            let ch = self.s[self.p];
                            if ch == '(' {
                                depth_scan += 1;
                            } else if ch == ')' {
                                if depth_scan > 0 { depth_scan -= 1; } else { break; }
                            } else if ch == self.list_sep_c() && depth_scan == 0 {
                                break;
                            }
                            body.push(ch);
                            self.p += 1;
                        }
                        let body = body.trim().to_string();
                        if body.is_empty() {
                            self.set_err("missing expression");
                            return 0.0;
                        }
                        self.add_def(&name, true, num_args, &arg_names, &body, 0.0);
                    } else {
                        let v = self.parse_expr(0);
                        if !self.err.is_empty() { return v; }
                        self.add_def(&name, false, 0, &[], "", v);
                    }
                    self.skip_ws();
                    if self.peek_c() == self.list_sep_c() {
                        self.next_c();
                        continue;
                    }
                    if self.p >= self.len() {
                        self.set_err(&format!("invalid expression: {}", name));
                        return 0.0;
                    }
                    let v = self.parse_expr(0);
                    return v;
                }
            }

            // not a definition: parse the final expression
            self.p = save;
            let v = self.parse_expr(0);
            if !self.err.is_empty() { return v; }
            self.skip_ws();
            if self.p < self.len() {
                // trailing garbage
                if self.s[self.p] == self.list_sep_c() {
                    let seg: String = self.s[save..self.p].iter().collect();
                    self.set_err(&format!("invalid var definition: {}", seg));
                } else {
                    let seg: String = self.s[self.last_tok_start..].iter().collect();
                    self.set_err(&format!("invalid expression: {}", seg));
                }
            }
            return v;
        }
    }

    // ---------- public API ----------

    pub fn eval_expr(&mut self, expr: &str, out_v: &mut f64) -> Result<(), String> {
        self.s = expr.chars().collect();
        self.p = 0;
        self.err.clear();
        self.depth = 0;
        let v = self.parse_toplevel();
        self.skip_ws();
        if self.err.is_empty() && self.p < self.len() {
            self.err = format!("invalid expression: {}", self.s[self.p]);
        }
        *out_v = v;
        if self.err.is_empty() {
            Ok(())
        } else {
            Err(self.err.clone())
        }
    }

    /// Add a "name=value" / "name(args)=body" declaration (Definitions tab).
    /// Returns Ok(()) on success, Err(message) on failure.
    pub fn add_def_decl(&mut self, decl: &str) -> Result<(), String> {
        let mut v = 0.0;
        let tmp = format!("{}{}0", decl, self.list_sep_c());
        match self.eval_expr(&tmp, &mut v) {
            Ok(()) => Ok(()),
            Err(m) => Err(m),
        }
    }

    /// Remove the def at `idx` (0-based). Returns the removed def's decl text.
    pub fn delete_def(&mut self, idx: usize) -> Option<String> {
        if idx < self.defs.len() {
            let d = self.defs.remove(idx);
            Some(format!(
                "{}{}",
                d.name,
                if d.is_func {
                    format!("({})", d.arg_names.join(","))
                } else {
                    String::new()
                }
            ))
        } else {
            None
        }
    }

    /// Human-readable declaration for the defs list, e.g. `f(x)` or `z`.
    pub fn unsigned(&self) -> bool {
        self.unsigned_hex
    }
    pub fn def_decl(&self, idx: usize) -> String {
        if let Some(d) = self.defs.get(idx) {
            format!(
                "{}{}",
                d.name,
                if d.is_func {
                    format!("({})", d.arg_names.join(","))
                } else {
                    String::new()
                }
            )
        } else {
            String::new()
        }
    }

    pub fn def_body(&self, idx: usize) -> String {
        self.defs.get(idx).map(|d| d.body.clone()).unwrap_or_default()
    }

    /// Update an existing def's body by index.
    pub fn update_def_body(&mut self, idx: usize, body: &str) -> Result<(), String> {
        if idx >= self.defs.len() {
            return Err("invalid def index".to_string());
        }
        // validate by evaluating body with args bound to zero
        let d = &self.defs[idx];
        let saved_locals = std::mem::take(&mut self.locals);
        let mut args: Vec<String> = Vec::new();
        if d.is_func {
            for a in &d.arg_names {
                self.locals.push((a.clone(), 0.0));
                args.push(a.clone());
            }
        }
        let mut v = 0.0;
        let expr = if args.is_empty() {
            format!("{}0", body)
        } else {
            format!("{}({})0", body, args.join(","))
        };
        let r = self.eval_expr(&expr, &mut v);
        self.locals = saved_locals;
        r.map(|_| self.defs[idx].body = body.to_string())
    }
}

// ============================================================================
// Output formatting (matches original console / GUI)
//   |v| < 1        : 17 decimal places, trailing zeros trimmed
//   1 <= |v| < 1e18: 18 significant digits, trailing zeros trimmed
//   |v| >= 1e18    : scientific, 15 significant digits, 4-digit exponent
// ============================================================================

fn trim_trail_zeros(s: &str) -> String {
    let mut i = s.len();
    let b = s.as_bytes();
    while i > 0 && b[i - 1] == b'0' { i -= 1; }
    if i > 0 && b[i - 1] == b'.' { i -= 1; }
    s[..i].to_string()
}

fn fmt_fixed(v: f64) -> String {
    let av = v.abs();
    let dec: usize;
    if av < 1.0 {
        dec = 17;
    } else {
        // 18 significant digits: count integer digits robustly
        let s = format!("{:.17}", av);
        let mut int_digits = 0usize;
        for ch in s.chars() {
            if ch.is_ascii_digit() { int_digits += 1; } else { break; }
        }
        dec = 18usize.saturating_sub(int_digits);
    }
    let mut r = trim_trail_zeros(&format!("{:.*}", dec, v));
    if v < 0.0 && r == "0" { r = "-0".to_string(); }
    r
}

/// Format a float in scientific notation, 4-digit exponent with sign:
/// 1.07150860718627E+0301  /  1.4000000000000000E+0001
fn fmt_sci(v: f64, sig_digits: usize) -> String {
    // Rust's {:.*e} gives "1.07150860718627e301"; reformat exponent.
    let s = format!("{:.*e}", sig_digits - 1, v);
    let (mant, exp) = match s.find('e') {
        Some(i) => (&s[..i], s[i + 1..].parse::<i32>().unwrap_or(0)),
        None => (s.as_str(), 0),
    };
    let sign = if exp < 0 { '-' } else { '+' };
    format!("{}E{}{:04}", mant, sign, exp.abs())
}

pub fn fmt_number(v: f64) -> String {
    if v.is_nan() || v.is_infinite() {
        return "ERROR".to_string();
    }
    if v.fract() == 0.0 && v >= -9.223372036854775808e18 && v <= 9.223372036854775807e18 {
        return format!("{}", v.round() as i64);
    }
    if v.abs() < 1e18 {
        fmt_fixed(v)
    } else {
        fmt_sci(v, 15)
    }
}

fn trunc32(v: f64) -> u32 {
    if v.is_nan() || v.is_infinite() { return 0; }
    (v.trunc() as i64) as u32
}

pub fn fmt_hex32(unsigned_hex: bool, v: f64) -> String {
    let u = trunc32(v);
    if unsigned_hex {
        format!("{:08X}", u)
    } else {
        format!("{:08X}", u as i32 as u32)
    }
}

pub fn fmt_bin32(v: f64) -> String {
    let u = trunc32(v);
    let mut r = String::with_capacity(32);
    for i in (0..32).rev() {
        r.push(if (u >> i) & 1 == 1 { '1' } else { '0' });
    }
    r
}

pub fn fmt_oct32(v: f64) -> String {
    let u = trunc32(v);
    let mut r = String::with_capacity(11);
    for i in (0..11).rev() {
        r.push((b'0' + ((u >> (3 * i)) & 7) as u8) as char);
    }
    r
}

pub fn fmt_exp(v: f64) -> String {
    if v.is_nan() || v.is_infinite() {
        return "ERROR".to_string();
    }
    fmt_sci(v, 18)
}

// ---------- convenience: one-shot evaluation (stateless, like the CLI) ----------

pub fn eval_one(expr: &str, unsigned_hex: bool, sep_mode: i32) -> Result<String, String> {
    let mut eng = Engine::new();
    eng.unsigned_hex = unsigned_hex;
    eng.sep_mode = sep_mode;
    let mut v = 0.0;
    match eng.eval_expr(expr, &mut v) {
        Ok(()) => Ok(fmt_number(v)),
        Err(m) => Err(m),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ev(expr: &str) -> String {
        eval_one(expr, false, 0).unwrap_or_else(|e| format!("ERROR: {}", e))
    }

    #[test]
    fn basics() {
        assert_eq!(ev("2+3*4"), "14");
        assert_eq!(ev("sin(pi/2)"), "1");
        assert_eq!(ev("0xAB"), "171");
        assert_eq!(ev("2**10"), "1024");
        assert_eq!(ev("1/3"), "0.33333333333333331"); // f64: 17-decimals of 0.3333333333333333148…
        assert_eq!(ev("(1+2)*3"), "9");
        assert_eq!(ev("2<3"), "1");
        assert_eq!(ev("5%2"), "1");
        assert_eq!(ev("1<<4"), "16");
    }

    #[test]
    fn errors() {
        assert_eq!(ev("1e"), "ERROR: invalid expression: 1e");
        assert_eq!(ev("SIN(1)"), "ERROR: unknown function: SIN");
        assert_eq!(ev("unknownfunc(3)"), "ERROR: unknown function: unknownfunc");
        assert_eq!(ev("poly(1)"), "ERROR: unknown function: poly");
        assert_eq!(ev(")"), "ERROR: invalid brackets");
    }

    #[test]
    fn defs() {
        assert_eq!(ev("f(x)=x*x,f(5)"), "25");
        assert_eq!(ev("z=1,(z+1/z)/2"), "1");
        assert_eq!(ev("g(x)=sin(x),g(pi/2)"), "1");
    }
}
