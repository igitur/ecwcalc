# ECWCalc domain glossary

Terms the codebase uses so seams have stable names. Keep this current when a
term is named or sharpened during design work.

## Engine / evaluation

- **Expression engine** — `ecwengine.pas`. Parses and evaluates an expression
  line, holds the user-definition registry. Purely an evaluator: it does no
  output formatting and has no LCL dependency.
- **Definition declaration** — a line shaped `name=value` or `name(args)=body`
  that `EvalExpr` accepts and registers into the persistent definition set as
  a side effect. Registered by `ParseTopLevel`.
- **Evaluation** — calling `EvalExpr` for its numeric result. Currently also
  the channel through which declarations are registered (see ADR-0001 for the
  intended split).
- **Console** — the CLI binary `ec` (`ec.lpr`). Its text output is the
  byte-exact fidelity oracle (493/493 vs the original under Wine).

## Formatting

- **Number formatting** — `numfmt.pas`. The single deep module that prints any
  number, used by both console and GUI. Canonical behaviour = the verified
  console text; the GUI reaches the same text at default config.
- **Format policy** — the `TFormatOpt` record passed to `Format`: a mode plus
  Prec / NoTrail0 / NoLead0 / UnsignedHex / DecimalSep. Divergences between
  callers are *data*, never separate code paths.
- **Format mode** — `Auto` (dec/exp auto), `Exp` (always scientific), `DecFixed`
  (tiny-form "Decimal"), `Hex` / `Bin` / `Oct` (32-bit radix rows).
- **Result row** — one output of the GUI: a dec/hex/bin/oct/exp field. In the
  full shell each value renders as five result rows; in the tiny shell one
  chosen row.
- **Console reference** — the old engine formatters (`FmtNumber`/`FmtFixed`/
  `FmtSci18`/`FmtHex32`/…) and GUI `Row*` functions, now absorbed into numfmt.
  GUI-internal divergences they carried (Int64 fast-path, 15-sig ffExponent,
  missing -0) were bugs and were deleted, not preserved.

## GUI

- **Shell** — a top-level calculator form. Two concrete shells exist:
  `TCalcForm` (full) and `TTinyForm` (compact). They share eval/apply-config/
  history behaviour that is not yet behind one interface (candidate #2).
- **Setup dialog** — `cfgform.pas`, the tabbed Options form; edits `cfg`.
- **User definition** — a variable or function the user declares; shown in the
  Setup dialog's Definitions tab, persisted to `ecw_defs.ini`.

## Configuration

- **Config** — `config.pas`. Holds the 16-field `TAppConfig` global record
  (`cfg`), loads/saves the `.ini`, and pushes only the two engine-relevant
  options (`UnsignedHex`, `SepMode`) through `ApplyConfig`.
- **Display options** — `Prec`, `NoLead0`, `NoTrail0` — read live by shells and
  threaded into numfmt's format policy at each call site.
