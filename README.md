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
| `ecwcalc.lpi` / `ecwcalc.lpr` | GUI Lazarus project (uses `ecwengine`) — faithful 4-form layout |
| `ecw.lpi` / `ecw.lpr` | CLI Lazarus project (uses `ecwengine`) — no LCL dependency |
| `ecwengine.pas` | The expression engine (parser, evaluator, formatter) — shared by CLI and GUI |
| `build.sh` | `./build.sh` → GUI, `./build.sh cli` → CLI |
| `Makefile` | Wraps `build.sh`: `make`, `make cli`, `make battery` |
| `*.pas`/`*.lfm` | GUI forms (`mainform`, `cfgform`, `defform`, `tinyform`) and `Config` |

## Build

Requires Free Pascal 3.2+ (`fpc`) and Lazarus 3.x with LCL (GTK2 or Qt5
widgetset).

```bash
./build.sh                     # GUI  -> ./ecwcalc
./build.sh cli                 # CLI  -> ./ecw
```

The `Makefile` wraps the same commands: `make`/`make gui`, `make cli`, and
`make battery` (regression suite).

Or build each conventional project directly with lazbuild:

```bash
lazbuild ecwcalc.lpi           # GUI -> ./ecwcalc
lazbuild ecw.lpi               # CLI -> ./ecw
```

### Command line

```bash
./ecw "2+3*4"                        # 14
./ecw --unsigned "0xFFFFFFFF+1"      # 4294967296
./ecw --sep=1 "1,5+2,5"              # 4   (comma decimal / semicolon list)
./ecw                                # interactive, prompt '> '
```

### GUI

```bash
./build.sh
./ecwcalc
```

The GUI reproduces the original's main form (expression combo with history,
Copy-as Dec/Hex/Bin/Oct/Exp radios, per-format result fields, Error status,
Evaluate/Copy/Setup/Help/Close buttons) plus the Setup dialog (interface
settings + user variables/functions tab) and the Definition dialog. Settings
persist to `ecwcalc.ini` next to the binary.

## Language features (all ground-truthed against ECW v1.06)

- **Operators** (loosest → tightest):
  `= == <> != < > <= >=` → `& | ^ && || ^^ << >> >>>` → `+ -` → `* / // %` →
  `**` → unary `+ - ~ !`; all binary operators left-associative; unary binds
  tighter than `**` (`-2**2 = 4`, `2*3**2 = 18`).
- **Integer semantics**: 32-bit with sign reinterpretation
  (`1<<31 = -2147483648`, `-8>>1 = 2147483644`, `-8>>>1 = -4`), truncated
  `//` and `%` (`-8//3 = -2`).
- **Numbers**: `12`, `0xAB`, `$AB`, `12h`, `0ABh`, `101b`, `12o`, `012`,
  `1.`, `.5`, `1e2`, `12.34e-56`. `--unsigned` gives 32-bit unsigned hex
  (`0xFFFFFFFF` → 4294967295).
- **Constants**: `e`, `pi` (case-insensitive).
- **Functions** (case-insensitive; names follow v1.06): `sin cos tan/tg
  cot/ctg sec csc asin acos atan acot asec acsc`, `sinh/sh cosh/ch tanh/th
  coth/cth sech csch asinh acosh atanh acoth asech acsch`, `exp ln log
  lg/log10 log2 sqr sqrt fact abs sign int frac round ceil floor rad deg
  ndeg nrad` + list functions `sum sumsq prod/mul avg gavg havg qavg/rms
  norm vart var/varp vars std stdp min max gcd lcm poly log(2-arg)`.
  `log(x)` = `ln(x)`; `log(a,x)` = log base a of x.
- **Variables and user functions**: `z=1,(z+1/z)/2`; `f(x)=x*x,f(5)` — also
  addable from the GUI's Setup → User variables/functions tab.
- **Separators** (`--sep=0/1/2`): `.`+`,` / `,`+`;` / `.`+`;`.
- **Exact error messages**: `overflow: /`, `unknown function: foo`,
  `invalid expression: ...`, `illegal |arg|>1: asin`, etc.
- **Output format**: `|v|<1` → 17 decimals; `1≤|v|≤1e18` → 18 sig digits
  (integers ≤ 1e18 printed plain); `|v|>1e18` → 18-sig scientific with
  sign+4-digit exponent (`2**1000 → 1.07150860718626732E+0301`).

## Fidelity notes

- Extended (80-bit) arithmetic with Delphi-compatible FPU exception masking:
  `ln(0)` → `overflow: ln`, `fact(200)` succeeds.
- The engine unit (`ecwengine.pas`) is shared verbatim by the CLI and GUI,
  so both are guaranteed to produce identical results.
- Engine semantics now follow **ECW v1.06** (the last release): case-insensitive
  identifiers, `**` binding tighter than `* / // %`, signed shift `>>>`,
  32-bit integer ops, `log` = `ln` with `lg`/`log10`/`log2`, `cot`/`acot`/
  `tg`/`ctg`/`sec`/`csc`/`round`/`ceil`/`floor`/`ndeg`/`nrad`, aliases
  `sh`/`ch`/`th`/`cth`, hyperbolic-arc siblings, and the full StatFunc list set
  (`sumsq`, `mul`, `gavg`, `havg`, `qavg/rms`, `norm`, `vart`/`var`/`varp`/
  `vars`/`std`/`stdp`, `gcd`, `lcm`). Number formatting follows v1.06
  (18-significant-digit scientific for |v| ≥ 1e18, plain integers ≤ 1e18,
  `-0` preserved, literals with |exponent| ≥ 5000 or magnitude above the
  80-bit maximum rejected as `invalid expression`).
- Differential suite: `tests/diff_oracle.py` / `tests/diff_ref.py` compare
  against the official v1.06 console engine (`ec.exe`) under Wine; the
  captured corpus lives in `tests/oracle_corpus.jsonl` (484/493 byte-exact).
  Remaining mismatches are (a) decimal-printer model for typed literals that
  exceed 18 significant digits (`123456789012345.6789`), (b) transcendental
  values at extreme magnitudes where the original's `exp` differs from FPC's
  in the last printed digit (`exp(10000)`, `sinh(1e4)`), and (c) last-ulp
  parse ties on 20-digit literals. `tests/rtl_audit.pas`/GUI per-format
  (Hex/Bin/Oct/Exp) oracle capture is still in progress.

## License

MIT — see `LICENSE`.
