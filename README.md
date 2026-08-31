# ecwcalc — ECW Expression Calculator (Rust/vizia port)

A clean-room port of the **ECW Expression Calculator** (a legacy Delphi 3-era
Windows calculator by Alexey Torgashin / UVViewSoft), written in Rust with a
vizia immediate-mode GUI.

This branch is the full replacement of the original codebase: a single Rust
project containing the expression engine and the GUI. The FreePascal
reference implementation (CLI + Lazarus GUI, byte-exact vs the original)
lives on `main` and serves as the differential-testing oracle.

## Build & run

Requires Rust 1.85+ and vizia's system dependencies (winit/glutin: X11 and
Wayland dev libs on Linux — `libxkbcommon-dev libwayland-dev libx11-dev
libxcb-* libgl1-mesa-dev libegl1-mesa-dev`).

```bash
cargo build --release
./target/release/ecw-vizia           # the calculator GUI
cargo test                           # engine unit tests + differential battery
```

## The GUI

All five of the original's windows, immediate-mode (no retained widget tree;
views are rebuilt each frame from state signals):

| Form | What it is |
|---|---|
| Calculator | main form — expression field, history, Copy-as radios (Dec/Hex/Bin/Oct/Exp), five result rows, error status, Evaluate/Copy/Setup…/Help/Close |
| Setup | tabbed dialog — Interface (auto-calc, small dialog, stay-on-top, show error status, copy behaviour, display options) + User variables/functions (list + Add/Edit/Delete) |
| Definition | function/variable dialog — declaration + expression fields, OK/Cancel |
| Tiny form | compact calculator (toggled by "Small dialog") — output, input, glyph buttons ¬ = ¼ # |
| Help | language reference summary |

Screenshots of every form are in `screenshots/` (captured live from the
running port).

## Language features (all ground-truthed against the original)

- **Operators** (loosest → tightest):
  `= == <> != < > <= >=` → `& | ^ && || ^^ << >>` → `+ -` → `* / ** // %` →
  unary `+ - ~ !`; all binary operators left-associative; unary binds tighter
  than `**` (`-2**2 = 4`).
- **Integer semantics**: 32-bit truncation with sign reinterpretation
  (`1<<31 = -2147483648`, `-8>>1 = 2147483644`), truncated `//` and `%`
  (`-8//3 = -2`).
- **Numbers**: `12`, `0xAB`, `$AB`, `12h`, `0ABh`, `101b`, `12o`, `012`,
  `1.`, `.5`, `1e2`, `12.34e-56`. The GUI's Hex display honours the
  unsigned flag (`0xFFFFFFFF` → 4294967295).
- **Constants**: `e`, `pi`.
- **Functions**: `sin cos tan ctan asin acos atan actan sinh cosh tanh
  asinh acosh atanh exp ln log sqr sqrt fact abs sign int frac rad deg`
  + list functions `sum prod avg geo min max poly`.
- **Variables and user functions**: `z=1,(z+1/z)/2`; `f(x)=x*x,f(5)`.
- **Exact error messages**: `overflow: /`, `unknown function: foo`,
  `invalid expression: ...`, `illegal |arg|>1: asin`, etc.

## Fidelity notes

The engine computes in f64 (Rust has no 80-bit float; the original — and the
FPC reference — use 80-bit Extended). The 139-case differential battery
against the FPC oracle shows 110/139 byte-identical results; the remaining
29 are *documented* last-ULP differences (transcendentals, pi/e, long
literals). Semantics, error messages, integer/bit ops and formatting rules
match exactly.

## CI & releases

| Workflow | Trigger | What it does |
|---|---|---|
| `.github/workflows/ci.yml` | push / PR to `main`, `vizia-port` | Ubuntu: `cargo build`, unit tests, and the 139-case differential battery vs the FPC oracle (fetched from `main`, compiled with fpc) |
| `.github/workflows/release.yml` | tag `v*` (or manual dispatch) | Builds `ecw-vizia` on Linux x64, Windows x64, macOS arm64 and creates a GitHub Release with the per-platform binaries |

Release binaries:

| Platform | Binary |
|---|---|
| linux-x64 | `ecw-vizia-linux-x64` |
| windows-x64 | `ecw-vizia-windows-x64.exe` |
| macos-arm64 | `ecw-vizia-macos-arm64` |

To ship a release: `git tag v1.0 && git push origin v1.0`.

## License

MIT — see `LICENSE`.
