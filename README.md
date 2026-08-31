# ecwcalc — ECW Expression Calculator (FreePascal port + Rust/vizia port)

A clean-room port of the **ECW Expression Calculator** (a legacy Delphi 3-era
Windows calculator by Alexey Torgashin / UVViewSoft), delivered as:

- **FreePascal CLI** (`ecw.pas`) — byte-for-byte verified against the
  original console engine under Wine (**188/188 differential tests**).
- **FreePascal GUI** (`gui/`) — faithful Lazarus LCL reproduction of the
  original's four forms, sharing the same verified engine.
- **Rust/vizia port** (`vizia/`, branch `vizia-port`) — the engine ported to
  Rust (f64) and a vizia immediate-mode GUI reproducing the main form.

## Contents

| Path | Description |
|---|---|
| `ecw.pas` | FreePascal CLI (uses `ecwengine`) |
| `gui/` | FreePascal GUI — Lazarus LCL, 4 forms, faithful to the original DFM |
| `vizia/` | Rust port — engine (`src/engine.rs`) + vizia immediate-mode GUI (`src/main.rs`) |

## Build — FreePascal CLI

```bash
fpc -O3 ecw.pas
./ecw "2+3*4"                        # 14
./ecw --unsigned "0xFFFFFFFF+1"      # 4294967296
./ecw --sep=1 "1,5+2,5"              # 4   (comma decimal / semicolon list)
./ecw                                # interactive, prompt '> '
```

## Build — FreePascal GUI

Requires Lazarus 3.x with LCL.

```bash
cd gui
lazbuild ecwcalc.lpi                 # produces gui/ecwcalc
./ecwcalc
```

## Build — Rust/vizia port

Requires Rust 1.85+ and vizia's system dependencies (winit: X11/Wayland libs,
`libxkbcommon-x11`).

```bash
cd vizia
cargo build --release
./target/release/ecw-vizia           # the calculator GUI
cargo test                           # engine unit tests + battery vs the FPC CLI
```

The vizia GUI reproduces the original main form: expression combo, five
result formats (Dec/Hex/Bin/Oct/Exp) updated live on Evaluate, error status,
and the Copy/Setup…/Help/Close button column — immediate-mode (no retained
widget tree; the view is rebuilt each frame from state signals).

## Language features (all ground-truthed against the original)

- **Operators** (loosest → tightest):
  `= == <> != < > <= >=` → `& | ^ && || ^^ << >>` → `+ -` → `* / ** // %` →
  unary `+ - ~ !`; all binary operators left-associative; unary binds tighter
  than `**` (`-2**2 = 4`).
- **Integer semantics**: 32-bit truncation with sign reinterpretation
  (`1<<31 = -2147483648`, `-8>>1 = 2147483644`), truncated `//` and `%`
  (`-8//3 = -2`).
- **Numbers**: `12`, `0xAB`, `$AB`, `12h`, `0ABh`, `101b`, `12o`, `012`,
  `1.`, `.5`, `1e2`, `12.34e-56`. `--unsigned` gives 32-bit unsigned hex
  (`0xFFFFFFFF` → 4294967295).
- **Constants**: `e`, `pi`.
- **Functions**: `sin cos tan ctan asin acos atan actan sinh cosh tanh
  asinh acosh atanh exp ln log sqr sqrt fact abs sign int frac rad deg`
  + list functions `sum prod avg geo min max poly`.
- **Variables and user functions**: `z=1,(z+1/z)/2`; `f(x)=x*x,f(5)`.
- **Separators** (`--sep=0/1/2`): `.`+`,` / `,`+`;` / `.`+`;`.
- **Exact error messages**: `overflow: /`, `unknown function: foo`,
  `invalid expression: ...`, `illegal |arg|>1: asin`, etc.

## Fidelity notes

- **FreePascal**: Extended (80-bit) arithmetic with Delphi-compatible FPU
  exception masking → byte-for-byte identical output to the original
  (188/188 differential tests pass, incl. exact error strings and the
  17/18/15-digit display rule).
- **Rust**: computes in f64 (Rust has no 80-bit float); 110/139 battery cases
  are byte-identical, and the remaining 29 are *documented* last-ULP
  differences (transcendentals, pi/e, long literals) — semantics, error
  messages, integer/bit ops and formatting rules match exactly.

## License

MIT — see `LICENSE`.
