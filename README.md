# ecwcalc — ECW Expression Calculator (FreePascal port)

A clean-room FreePascal port of the **ECW Expression Calculator** (a legacy
Delphi 3-era Windows calculator by Alexey Torgashin / UVViewSoft), delivered
as both a **command-line tool** and a **faithful GUI** (Lazarus LCL).

The expression engine was reverse-engineered from the original binary
(parser, evaluator, operators, error messages, number formatting) and
verified **byte-for-byte against the original console engine running under
Wine** — 188/188 differential tests pass.

## Contents

| Path | Description |
|---|---|
| `ecw.pas` | Command-line front end (uses `ecwengine`) |
| `ecwengine.pas` | The expression engine (parser, evaluator, formatter) — shared by CLI and GUI |
| `gui/` | Lazarus LCL GUI — faithful reproduction of the original 4-form layout |

## Build — command line

Requires Free Pascal 3.2+ (`fpc`).

```bash
fpc -O3 ecw.pas
./ecw "2+3*4"                        # 14
./ecw --unsigned "0xFFFFFFFF+1"      # 4294967296
./ecw --sep=1 "1,5+2,5"              # 4   (comma decimal / semicolon list)
./ecw                                # interactive, prompt '> '
```

## Build — GUI

Requires Lazarus 3.x with LCL (GTK2 or Qt5 widgetset).

```bash
cd gui
lazbuild ecwcalc.lpi                 # produces gui/ecwcalc
./ecwcalc
```

The GUI reproduces the original's main form (expression combo with history,
Copy-as Dec/Hex/Bin/Oct/Exp radios, per-format result fields, Error status,
Evaluate/Copy/Setup/Help/Close buttons) plus the Setup dialog (interface
settings + user variables/functions tab) and the Definition dialog. Settings
persist to `ecwcalc.ini` next to the binary.

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
- **Functions**: `sin cos tan asin acos atan sec csc cot sinh cosh tanh
  asinh acosh atanh exp ln log10 log2 sqrt cbrt abs sgn ceil floor round
  trunc frac fact int2str float2str` + list functions `sum prod avg geo
  min max poly` (≥2 args; `log` has a 1-arg form).
- **Variables and user functions**: `z=1,(z+1/z)/2`; `f(x)=x*x,f(5)` — also
  addable from the GUI's Setup → User variables/functions tab.
- **Separators** (`--sep=0/1/2`): `.`+`,` / `,`+`;` / `.`+`;`.
- **Exact error messages**: `overflow: /`, `unknown function: foo`,
  `invalid expression: ...`, `illegal |arg|>1: asin`, etc.
- **Output format**: `|v|<1` → 17 decimals; `1≤|v|<1e18` → 18 sig digits;
  `|v|≥1e18` → 15-sig scientific with 4-digit exponent
  (`2**1000 → 1.07150860718627E+0301`).

## Fidelity notes

- Extended (80-bit) arithmetic with Delphi-compatible FPU exception masking:
  `ln(0)` → `overflow: ln`, `fact(200)` succeeds.
- The engine unit (`ecwengine.pas`) is shared verbatim by the CLI and GUI,
  so both are guaranteed to produce identical results.
- 188/188 differential tests pass byte-for-byte against the original engine
  (see `tests/` history in git log).

## License

MIT — see `LICENSE`.
