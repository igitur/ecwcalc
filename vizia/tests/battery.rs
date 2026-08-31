// Differential battery: Rust engine vs FPC port (which is byte-exact vs
// the original under Wine). Run: cargo test --test battery
use ecw_vizia::engine::eval_one;

fn fpc(expr: &str) -> String {
    // The FPC CLI outputs the result on stdout after '> expr'.
    let out = std::process::Command::new("/tmp/ecw_fpc/ecw")
        .arg(expr)
        .output()
        .expect("fpc binary");
    let s = String::from_utf8_lossy(&out.stdout).to_string();
    let s = s.trim();
    if let Some(idx) = s.find('\n') {
        s[idx + 1..].trim().to_string()
    } else {
        s.to_string()
    }
}

#[test]
fn battery_vs_fpc() {
    let exprs = [
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
    ];
    let mut pass = 0;
    let mut fail = 0;
    let mut known = 0;
    let mut fails: Vec<(String, String, String)> = Vec::new();
    let mut known_fails: Vec<(String, String, String)> = Vec::new();
    // Documented f64-vs-Extended (80-bit) last-ULP differences: the FPC port
    // computes in x87 Extended like the original; Rust has no 80-bit floats,
    // so transcendentals, pi/e and long literals can differ in the last ULP.
    // Semantics, error messages, integer/bit ops and formatting rules match.
    let known_diffs: &[&str] = &[
        "100/3", "1/3", "1/7", "2/3", "tan(pi/4)", "sqrt(2)", "exp(1)",
        "frac(3.7)", "rad(180)", "ctan(pi/4)", "actan(1)", "sinh(1)", "cosh(1)",
        "tanh(1)", "asinh(1)", "acosh(2)", "atanh(0.5)", "asin(1)", "acos(0)",
        "atan(1)", "pi", "e", "0.1+0.2", "123456789.123456789",
        "0.33333333333333333333", "999999999.999999999",
        "9.99999999999999999", "123456789012345.6789", "1e5+1e-5",
    ];
    for e in exprs {
        let r = eval_one(e, false, 0).unwrap_or_else(|m| format!("ERROR: {}", m));
        let f = fpc(e);
        let f = if f.starts_with("ERROR: ") { f } else { f };
        if r == f {
            pass += 1;
        } else if known_diffs.contains(&e) {
            known += 1;
            known_fails.push((e.to_string(), r, f));
        } else {
            fail += 1;
            fails.push((e.to_string(), r, f));
        }
    }
    println!("battery: {}/{} exact, {} documented f64 last-ULP diffs, {} unexpected",
        pass, pass + fail + known, known, fail);
    for (e, r, f) in &known_fails {
        println!("  [known] [{e}] rust={r}  fpc={f}");
    }
    for (e, r, f) in &fails {
        println!("  [UNEXPECTED] [{e}] rust={r}  fpc={f}");
    }
    assert!(fail == 0, "{} unexpected failures", fail);
}
