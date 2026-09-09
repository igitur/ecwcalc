# ADR-0001: Number formatting is one deep module (numfmt.pas)

Status: accepted
Date: 2026-09-10
Area: formatting

## Context

Printing a number was implemented twice, side by side: the expression
engine's console reference printers (`FmtNumber`/`FmtFixed`/`FmtSci18`/
`FmtExp`/`FmtHex32`/`FmtBin32`/`FmtOct32`, ecwengine.pas) and the GUI row
formatters (`RowDec`/`RowExp`/`RowDecFixed`/`RowHex32`/…, viewfmt.pas). The
GUI rows partially delegated to the engine (radix) and partially re-derived
the same fixed/sci algorithm (dec/exp), duplicating `TrimTrailZeros`, integer
digit counting and the 18-sig scientific builder with subtly different edge
semantics. Fidelity work (the spec'd custom tie-rounding formatter) would have
had to land in both copies and stay in lockstep.

Two real callers (console and GUI rows) cross the same seam, so the seam is
real, not hypothetical.

## Decision

Move all number printing into one pure leaf unit, `numfmt.pas`, shared by both
binaries:

- One entry point: `Format(v: Extended; const Opt: TFormatOpt): string`.
- A **format policy** record carrying `Mode` (`Auto` / `Exp` / `DecFixed` /
  `Hex` / `Bin` / `Oct`), `Prec`, `NoTrail0`, `NoLead0`, `UnsignedHex`,
  `DecimalSep`. Divergences between callers are data inside `Opt`, never
  separate code paths.
- The console's `Fmt*` and the GUI's `Row*` exports are deleted. The CLI calls
  `Format(v, AutoOpt(17, True))`; the GUI shells build an `Opt` from `cfg`.
- The engine keeps only parsing/evaluation/definitions; it no longer prints.
- Dead surface is removed with the move: engine `FmtExp`, `DecimalSepChar`,
  `ListSepChar`, `DefIsFunc`, `ClearDefs`, write-only `SavedMask`, dead
  `IsListFunc` all had zero callers and are gone.

### Fidelity rule

Canonical behaviour is the byte-verified console text (diff_ref 493/493). The
GUI's historical divergences — Int64 integer fast-path (2e18 rendered as
digits), 15-sig `ffExponent` fallback for |v| ≥ 1e18, missing `-0` — were
bugs against the engine reference and are deleted. At default config the GUI
rows reach the same text as the console (spec 2c acceptance).

`FmtFixed`/`FmtSci18`/`FmtExp` semantics live on as the Auto and Exp modes,
including the manual 18-sig mantissa builder (FPC `ffExponent` caps mantissas
at 17 sig digits) and the exact `FmtExp` zero special case.

## Consequences

- Locality: rounding-tie and printer bugs concentrate in one module.
- Leverage: one interface serves console, all five result rows, and the future
  per-format corpus harness.
- Console output is byte-identical (verified: diff_ref 484 match + 7 accepted,
  battery green — same as before the change).
- numfmt is a leaf (SysUtils/Math only); the engine has no formatting
  dependency and formatting no longer reads engine parse-state globals
  (`UnsignedHex` now travels in `Opt`).
- Not yet done (future ADRs): declaring definitions through their own seam
  rather than `EvalExpr`'s side effect, and pushing config through seams to
  the two consumers.
