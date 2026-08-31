# ecwcalc — ECW Expression Calculator (FreePascal port)

A clean-room FreePascal port of the **ECW Expression Calculator** (a legacy
Delphi 3-era Windows calculator by Alexey Torgashin / UVViewSoft, engine
"StdMath v1.04"), produced by reverse-engineering the original binary.
Byte-for-byte verified against the original engine (188/188 differential
tests).

## Build

Requires FreePascal (tested with FPC 3.2.2):

```bash
fpc -O3 ecw.pas
```

## Usage

```bash
./ecw "2+3*4"                # 14
./ecw "sin(pi/2)"            # 1
./ecw "0xAB>>4"              # 10
./ecw "avg(1,2,3)"           # 2
./ecw "2**1000"              # 1.07150860718627E+0301

# unsigned 32-bit hex semantics (matches original's UnsignedHex=1)
./ecw --unsigned "0xFFFFFFFF+1"     # 4294967296

# comma decimal separator + semicolon list separator
./ecw --sep=1 "1,5+2,5"             # 4

# interactive mode
./ecw
```

## Language

- **Operators** (loosest → tightest), all left-associative:
  `= == <> != < > <= >=` → `& | ^ && || ^^ << >>` → `+ -` → `* / ** // %`
  → unary `+ - ~ !` (unary binds tighter than `**`: `-2**2 = 4`)
- **Integer semantics**: 32-bit UInt32/Int32 with sign reinterpret
  (`1<<31 = -2147483648`, `-8>>1 = 2147483644`), truncated `//`/`%`
- **Numbers**: `12`, `0xAB`/`$AB`/`12h`/`0ABh`, `101b`, `12o`/`012`,
  reals `1.`, `.5`, `1e2`, `12.34e-56`; constants `e`, `pi`
- **Functions**: sin cos tan ctan asin acos atan actan sinh cosh tanh
  asinh acosh atanh exp ln log sqr sqrt fact abs sign int frac rad deg
  (plus `log(a,x)` two-arg form)
- **List functions**: sum prod avg geo min max poly(x, a0, a1, ...)
- **Variables**: `z=1, (z+1/z)/2`
- **User definitions**: `f(x)=x*x, f(5)` (nested and recursive calls work)
- **Separators**: default `.` decimal / `,` list; `--sep=1` → `,` decimal
  / `;` list

## Fidelity notes

- Matches the original console output format: 17 decimals for |v|<1,
  18 significant digits for 1≤|v|<1e18, 15-digit scientific ≥1e18
  (`2**1000 → 1.07150860718627E+0301`).
- FPU exception masking replicates Delphi's behavior for edge cases
  (`ln(0)` → `overflow: ln`, `fact(200)` succeeds, etc.).
- Two 19-significant-digit literal inputs display one digit shorter than
  the original's console (a sub-ULP formatting quirk of the reference).

## License

MIT
