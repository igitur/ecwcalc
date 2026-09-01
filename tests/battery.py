#!/usr/bin/env python3
"""Battery for the FPC port (CLI is its own oracle).

Regression check: every expression must produce the same outcome class as
the reference batteries (Go/Rust): 29 known-error expressions must yield
ERROR, the other 110 must yield a value. Plus exact spot-checks.

Usage: battery.py [cli-binary]   (default ./ecw)
"""
import subprocess, sys

CLI = sys.argv[1] if len(sys.argv) > 1 else "./ecw"

ERROR_EXPRS = [
 "123e",
 "1e",
 "0xABh",
 "$",
 "1/0",
 "ln(0)",
 "ln(-1)",
 "asin(2)",
 "sqrt(-1)",
 "fact(-1)",
 "fact(1.5)",
 "atanh(1)",
 "atanh(2)",
 "acosh(0)",
 "poly(1)",
 "sum(1)",
 "2+",
 "2 3",
 "sin",
 "SIN(1)",
 "unknownfunc(3)",
 "x",
 ")",
 "(1+2",
 "2**",
 "1e-",
 "0x12z",
 "2,3",
 "avg()"
]

SPOTS = [
 [
  "2+3*4",
  "14"
 ],
 [
  "2**10",
  "1024"
 ],
 [
  "10/4",
  "2.5"
 ],
 [
  "10//4",
  "2"
 ],
 [
  "10%4",
  "2"
 ],
 [
  "-8//3",
  "-2"
 ],
 [
  "-8%3",
  "-2"
 ],
 [
  "0xFFFFFFFF",
  "-1"
 ],
 [
  "sin(pi/2)",
  "1"
 ],
 [
  "tan(pi/4)",
  "1"
 ],
 [
  "sqrt(2)",
  "1.41421356237309505"
 ],
 [
  "fact(5)",
  "120"
 ],
 [
  "1<<31",
  "-2147483648"
 ],
 [
  "~0",
  "-1"
 ],
 [
  "255&15",
  "15"
 ],
 [
  "0xAB",
  "171"
 ],
 [
  "log(10,100)",
  "2"
 ],
 [
  "rad(180)",
  "3.14159265358979324"
 ],
 [
  "deg(pi)",
  "180"
 ],
 [
  "min(3,1,2)",
  "1"
 ],
 [
  "geo(2,8)",
  "4"
 ],
 [
  "max(3,1,2)",
  "3"
 ]
]

def run(e):
    r = subprocess.run([CLI, e], capture_output=True, text=True)
    return r.stdout.strip()

fail = 0
for e in ERROR_EXPRS:
    out = run(e)
    if not out.startswith("ERROR"):
        print(f"FAIL: expected ERROR for {e!r}, got {out!r}")
        fail += 1

# the full list minus the error cases = value cases
VALUE_EXPRS = [
 "2+3*4",
 "(1+2)*3",
 "2**10",
 "2**-2",
 "0**0",
 "10/4",
 "10//4",
 "10%4",
 "-8//3",
 "-8%3",
 "5-3-2",
 "100/3",
 "1/3",
 "1/7",
 "2/3",
 "1e2",
 "1e-2",
 "12.34e-56",
 "0.5e2",
 "1.5e3",
 "2.5e-3",
 "0xFFFFFFFF",
 "0xFFFFFFFF+1",
 "0x80000000",
 "1<<31",
 "-8>>1",
 "1<<4",
 "0xAB>>4",
 "~0",
 "~5",
 "255&15",
 "255|15",
 "255^15",
 "0xFF<<8",
 "0xFFFF<<16",
 "1<<32",
 "0xAB",
 "0ABh",
 "101b",
 "12h",
 "12o",
 "012",
 "0x",
 "$AB",
 "sin(pi/2)",
 "cos(0)",
 "tan(pi/4)",
 "sqrt(2)",
 "sqrt(4)",
 "exp(1)",
 "ln(e)",
 "ln(1)",
 "log(100)",
 "log(10,100)",
 "fact(5)",
 "fact(0)",
 "abs(-3)",
 "sign(-5)",
 "sign(0)",
 "int(3.7)",
 "int(-3.7)",
 "frac(3.7)",
 "rad(180)",
 "deg(pi)",
 "sqr(5)",
 "ctan(pi/4)",
 "actan(1)",
 "sinh(1)",
 "cosh(1)",
 "tanh(1)",
 "asinh(1)",
 "acosh(2)",
 "atanh(0.5)",
 "asin(1)",
 "acos(0)",
 "atan(1)",
 "sum(1,2,3)",
 "prod(2,3,4)",
 "avg(1,2,3)",
 "geo(2,8)",
 "min(3,1,2)",
 "max(3,1,2)",
 "poly(2,1,2,3)",
 "1<2",
 "2<1",
 "2<=2",
 "3>=4",
 "1=1",
 "1==1",
 "1<>2",
 "1!=2",
 "1&&2",
 "0||1",
 "1^^0",
 "1^^1",
 "pi",
 "e",
 "z=1,(z+1/z)/2",
 "f(x)=x*x,f(5)",
 "g(x)=sin(x),g(pi/2)",
 "h(x)=x+1,h(h(10))",
 "0.1+0.2",
 "2**1000",
 "123456789.123456789",
 "0.33333333333333333333",
 "999999999.999999999",
 "9.99999999999999999",
 "123456789012345.6789",
 "1e5+1e-5",
 "+2"
]
for e in VALUE_EXPRS:
    out = run(e)
    if out.startswith("ERROR"):
        print(f"FAIL: expected value for {e!r}, got {out!r}")
        fail += 1

for e, want in SPOTS:
    out = run(e)
    if out != want:
        print(f"FAIL: {e!r}: got {out!r}, want {want!r}")
        fail += 1

print(f"battery: {len(ERROR_EXPRS)} error-class + {len(VALUE_EXPRS)} value-class + {len(SPOTS)} spots, {fail} failures")
sys.exit(1 if fail else 0)
