unit numfmt;

{ Number formatting for ECW — the single deep module behind every "print a
  number" call site.

  Ported from the verified console formatters that used to live in ecwengine
  (FmtNumber/FmtFixed/FmtSci18/FmtHex32/FmtBin32/FmtOct32/FmtExp) and the
  GUI row formatters that used to live in viewfmt (RowDec/RowExp/RowDecFixed).

  Canonical behaviour = the byte-verified console text (diff_ref 493/493).
  One algorithm per mode, parameterised by Prec / NoTrail0 / NoLead0 /
  UnsignedHex / DecimalSep.  At the console defaults (Auto, Prec=17,
  NoTrail0=on, DecimalSep='.') the output is byte-identical to the old
  engine's FmtNumber; the GUI rows reach the same text at default config
  (spec remaining-fixes-spec 2c).  The GUI's historical divergences (Int64
  integer fast-path, 15-sig ffExponent fallback, missing -0) were bugs and
  are gone — this module is the one truth. }

{$mode objfpc}{$H+}

interface

uses SysUtils, Math;

type
  TNumMode = (
    nmAuto,       // dec/exp auto: fixed while it fits, else 18-sig scientific
    nmExp,        // always scientific, Prec+1 sig, 4-digit exponent
    nmDecFixed,   // always fixed (tiny form 'Decimal'): huge -> exponent digits
    nmHex,        // 32-bit hex (8 digits)
    nmBin,        // 32-bit binary (32 digits)
    nmOct         // 32-bit octal (11 digits)
  );

  TFormatOpt = record
    Mode: TNumMode;
    Prec: Integer;        // decimals after point (fixed) / sig-digit control
    NoTrail0: Boolean;    // trim trailing zeros (fixed region only)
    NoLead0: Boolean;     // radix: strip leading zeros
    UnsignedHex: Boolean; // radix: unsigned interpretation
    DecimalSep: Char;     // output decimal separator (default '.')
  end;

  { Format v according to Opt.  Never raises on NaN/Inf: dec/exp modes return
    'ERROR', radix modes return 'overflow' when out of Int32 range. }
  function Format(v: Extended; const Opt: TFormatOpt): string;

  { Opt constructors.  AutoOpt(17, True) reproduces the console byte-exactly. }
  function AutoOpt(Prec: Integer; NoTrail0: Boolean): TFormatOpt;
  function ExpOpt(Prec: Integer): TFormatOpt;
  function DecFixedOpt(Prec: Integer; NoTrail0: Boolean): TFormatOpt;
  function RadixOpt(aMode: TNumMode; NoLead0, UnsignedHex: Boolean): TFormatOpt;

implementation

const
  P18 = 1e18;        { 10^18 exactly representable in Extended }
  MaxSig = 18;       { highest mantissa precision we ever emit }

{ ---- separator-safe primitives ------------------------------------------- }

{ Format s with FPC under a forced DecimalSeparator; returns text whose
  decimal point is exactly Sep (callers may scan for it). }
function FmtFixedSep(v: Extended; d: Integer; Sep: Char): string;
var old: Char;
begin
  old := DefaultFormatSettings.DecimalSeparator;
  DefaultFormatSettings.DecimalSeparator := Sep;
  Result := FloatToStrF(v, ffFixed, 0, d);
  DefaultFormatSettings.DecimalSeparator := old;
end;

function FmtExpSep(v: Extended; Precision, Digits: Integer; Sep: Char): string;
var old: Char;
begin
  old := DefaultFormatSettings.DecimalSeparator;
  DefaultFormatSettings.DecimalSeparator := Sep;
  Result := FloatToStrF(v, ffExponent, Precision, Digits);
  DefaultFormatSettings.DecimalSeparator := old;
end;

{ Trim trailing zeros of the fixed (non-scientific) part; never trims an
  all-zero integer ("100" stays "100").  Sep is the decimal point char. }
function TrimTrailZeros(const s: string; Sep: Char): string;
var i, p: Integer;
begin
  p := Pos(Sep, s);
  if p = 0 then begin Result := s; Exit; end;   // integer-looking: keep digits
  i := Length(s);
  while (i > p) and (s[i] = '0') do Dec(i);
  if i = p then Dec(i);                          // drop the trailing '.'
  Result := Copy(s, 1, i);
end;

{ Trim trailing zeros of an exponent-form mantissa ("1.2300E+0002" ->
  "1.23E+0002"); never leaves the mantissa empty. }
function TrimExpMantissa(const s: string; Sep: Char): string;
var e: Integer; mant: string;
begin
  e := Pos('E', s);
  if e = 0 then Exit(s);
  mant := TrimTrailZeros(Copy(s, 1, e - 1), Sep);
  if mant = '' then mant := '0';
  Result := mant + Copy(s, e, Length(s) - e + 1);
end;

{ number of integer digits of av>=0, by scanning a generous fixed probe }
function CountIntDigits(av: Extended): Integer;
var s: string; i: Integer;
begin
  s := FloatToStrF(av, ffFixed, 0, 17);
  Result := 0;
  for i := 1 to Length(s) do
    if s[i] in ['0'..'9'] then Inc(Result) else Break;
end;

function IsNegZero(v: Extended): Boolean;
{ Leaf-safe: never depends on the host FPU mask.  For v = 0, 1/v would raise
  if exZeroDivide is unmasked, so we only probe the sign bit, then restore. }
var saved: TFPUExceptionMask;
begin
  Result := False;
  if v <> 0 then Exit;
  saved := GetExceptionMask;
  SetExceptionMask(saved + [exZeroDivide, exInvalidOp, exOverflow, exUnderflow]);
  Result := (1 / v) < 0;
  SetExceptionMask(saved);
end;

{ ---- scientific core ------------------------------------------------------ }

{ Scientific, Sig significant digits, sign + 4-digit exponent.

  Ported from the engine's FmtSci18/FmtExp bodies (byte-verified against the
  console): FPC's ffExponent caps mantissas at 17 sig digits, so the mantissa
  is built by hand — normalise av>0 to s in [1,10) with e0 tracking the power
  of ten, chunking the scale by 10^18 so it is built with ~e0/18 roundings,
  then fixed-format the mantissa and zero-pad a sign+4-digit exponent.  A
  mantissa that rounds up to 10.xxxxx carries into e0 exactly as the original
  did. }
function FmtSciSig(v: Extended; Sig: Integer; Sep: Char): string;
var
  av, s, p: Extended;
  e0, i, a, b: Integer;
  mant, es: string;
begin
  if Sig > MaxSig then Sig := MaxSig;
  Result := '';
  if v < 0 then begin Result := '-'; av := -v; end else av := v;
  if av = 0 then begin
    { no Log10 of zero: emit a Sig-digit zero mantissa with exponent +0000 }
    mant := '0' + Sep;
    while Length(mant) < Sig + 1 do mant := mant + '0';
    Result := Result + mant + 'E+0000';
    Exit;
  end;
  e0 := Trunc(Log10(av));
  p := 1;
  if e0 > 0 then begin
    { 10^18 is exactly representable in Extended: chunk the exponent so the
      power-of-ten is built with ~e0/18 (<= 275) roundings, not e0 of them. }
    a := e0 div 18;
    b := e0 mod 18;
    for i := 1 to a do p := p * P18;
    for i := 1 to b do p := p * 10;
  end else if e0 < 0 then begin
    for i := -1 downto e0 do p := p / 10;
  end;
  s := av / p;
  while s >= 10 do begin
    Inc(e0);
    p := p * 10;
    s := av / p;
  end;
  while s < 1 do begin
    Dec(e0);
    p := p / 10;
    s := av / p;
  end;
  mant := FmtFixedSep(s, Sig - 1, Sep);
  if (Length(mant) >= 2) and (mant[1] = '1') and (mant[2] = '0') then begin
    { mantissa rounded up to 10.xxxxx: carry into the exponent }
    Inc(e0);
    p := p * 10;
    s := av / p;
    mant := FmtFixedSep(s, Sig - 1, Sep);
  end;
  es := IntToStr(Abs(e0));
  while Length(es) < 4 do es := '0' + es;
  if e0 < 0 then es := '-' + es else es := '+' + es;
  Result := Result + mant + 'E' + es;
end;

{ ---- radix core ----------------------------------------------------------- }

function IsRealX(v: Extended): Boolean;
begin
  Result := not (IsNan(v) or IsInfinite(v));
end;

function Int32RangeOK(v: Extended): Boolean;
begin
  Result := False;
  if not IsRealX(v) then Exit;
  Result := (Int(v) >= -2147483648.0) and (Int(v) <= 2147483647.0);
end;

function Trunc32(v: Extended): LongWord;
var i: Int64;
begin
  if not IsRealX(v) then begin Result := 0; Exit; end;
  i := Trunc(v);
  Result := LongWord(i and $FFFFFFFF);
end;

function FmtRadix(v: Extended; m: TNumMode; UnsignedHex: Boolean): string;
var u: LongWord; i: Integer;
begin
  if not Int32RangeOK(v) then begin Result := 'overflow'; Exit; end;
  u := Trunc32(v);
  if m = nmHex then begin
    if UnsignedHex then Result := IntToHex(u, 8)
    else Result := IntToHex(LongInt(u), 8);
  end else if m = nmBin then begin
    Result := '';
    for i := 31 downto 0 do
      Result := Result + Chr(Ord('0') + ((u shr i) and 1));
  end else begin { nmOct }
    Result := '';
    for i := 10 downto 0 do
      Result := Result + Chr(Ord('0') + ((u shr (3 * i)) and 7));
  end;
end;

function StripLead(const s: string): string;
var i: Integer;
begin
  i := 1;
  while (i < Length(s)) and (s[i] = '0') do Inc(i);
  Result := Copy(s, i, Length(s) - i + 1);
end;

{ ---- constructors ---------------------------------------------------------- }

function AutoOpt(Prec: Integer; NoTrail0: Boolean): TFormatOpt;
begin
  Result.Mode := nmAuto;
  Result.Prec := Prec;
  Result.NoTrail0 := NoTrail0;
  Result.NoLead0 := False;
  Result.UnsignedHex := False;
  Result.DecimalSep := '.';
end;

function ExpOpt(Prec: Integer): TFormatOpt;
begin
  Result.Mode := nmExp;
  Result.Prec := Prec;
  Result.NoTrail0 := False;
  Result.NoLead0 := False;
  Result.UnsignedHex := False;
  Result.DecimalSep := '.';
end;

function DecFixedOpt(Prec: Integer; NoTrail0: Boolean): TFormatOpt;
begin
  Result.Mode := nmDecFixed;
  Result.Prec := Prec;
  Result.NoTrail0 := NoTrail0;
  Result.NoLead0 := False;
  Result.UnsignedHex := False;
  Result.DecimalSep := '.';
end;

function RadixOpt(aMode: TNumMode; NoLead0, UnsignedHex: Boolean): TFormatOpt;
begin
  Result.Mode := aMode;
  Result.Prec := 0;
  Result.NoTrail0 := False;
  Result.NoLead0 := NoLead0;
  Result.UnsignedHex := UnsignedHex;
  Result.DecimalSep := '.';
end;

{ ---- Auto (console FmtNumber) ---------------------------------------------- }

function FormatAuto(v: Extended; Prec: Integer; NoTrail0: Boolean; Sep: Char): string;
var
  av: Extended;
  d, intdigits: Integer;
  i64: Int64;
begin
  if IsNan(v) or IsInfinite(v) then begin Result := 'ERROR'; Exit; end;
  { exact integer within +/-1e18 -> plain integer digits }
  if (Frac(v) = 0) and (v >= -P18) and (v <= P18) then begin
    if IsNegZero(v) then begin Result := '-0'; Exit; end;
    i64 := Round(v);
    Result := IntToStr(i64);
    Exit;
  end;
  av := Abs(v);
  if av <= P18 then begin
    { fixed notation }
    if av < 1 then
      d := Prec                        // Prec decimal places
    else begin
      intdigits := CountIntDigits(av);      // Prec+1 significant digits
      d := Prec + 1 - intdigits;
      if d < 0 then d := 0;
    end;
    Result := FmtFixedSep(v, d, Sep);
    if NoTrail0 then Result := TrimTrailZeros(Result, Sep);
    if (v < 0) and (Result = '0') then Result := '-0';
  end else begin
    Result := FmtSciSig(v, Prec + 1, Sep);   // console: Prec+1 = 18 sig
  end;
end;

{ ---- Exp: always scientific ------------------------------------------------ }

{ Canonical = console FmtExp (manual 18-sig mantissa, sign+4-digit exponent).
  FPC's ffExponent caps mantissas at 17 sig, so nonzero mantissas are built by
  hand (FmtSciSig).  Zero keeps FmtExp's exact FPC form.  Prec controls sig
  digits as Prec+1 (RowExp's intent), capped at 18; at Prec=17 this is
  byte-equal to FmtExp.  Mantissa is never trimmed — the console reference and
  the per-format oracle (spec 2a) both keep trailing zeros. }
function FormatExp(v: Extended; Prec: Integer; Sep: Char): string;
var sig: Integer;
begin
  if IsNan(v) or IsInfinite(v) then begin Result := 'ERROR'; Exit; end;
  if v = 0 then begin
    Result := FmtExpSep(v, 18, 4, Sep);
    Exit;
  end;
  sig := Prec + 1;
  if sig < 1 then sig := 1
  else if sig > MaxSig then sig := MaxSig;
  Result := FmtSciSig(v, sig, Sep);
end;

{ ---- DecFixed (tiny form 'Decimal'): fixed while it fits -------------------- }

function FormatDecFixed(v: Extended; Prec: Integer; NoTrail0: Boolean; Sep: Char): string;
var
  s: string;
  d: Integer;
begin
  if IsNan(v) or IsInfinite(v) then begin Result := 'ERROR'; Exit; end;
  d := Prec;
  if Abs(v) < P18 then begin
    s := FmtFixedSep(v, d, Sep);
    if NoTrail0 then s := TrimTrailZeros(s, Sep);
    if (v < 0) and (s = '0') then s := '-0';
    Result := s;
  end else begin
    { too large for a fixed string: keep the digits via exponent notation }
    s := FmtExpSep(v, 15, 4, Sep);
    if NoTrail0 then s := TrimExpMantissa(s, Sep);
    Result := s;
  end;
end;

{ ---- dispatch --------------------------------------------------------------- }

function Format(v: Extended; const Opt: TFormatOpt): string;
var
  Sep: Char;
begin
  Result := '';
  Sep := Opt.DecimalSep;
  if Sep = #0 then Sep := '.';
  case Opt.Mode of
    nmAuto:     Result := FormatAuto(v, Opt.Prec, Opt.NoTrail0, Sep);
    nmExp:      Result := FormatExp(v, Opt.Prec, Sep);
    nmDecFixed: Result := FormatDecFixed(v, Opt.Prec, Opt.NoTrail0, Sep);
    nmHex, nmBin, nmOct:
      begin
        Result := FmtRadix(v, Opt.Mode, Opt.UnsignedHex);
        if Opt.NoLead0 and (Result <> 'overflow') then
          Result := StripLead(Result);
      end;
  end;
end;

end.
