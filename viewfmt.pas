unit viewfmt;

{$mode objfpc}{$H+}

{ Display-row formatting for the GUI result fields.

  The engine's Fmt* functions reproduce the *console* (ec.exe) output with
  hard-wired precision and always-trimmed trailing zeros.  The GUI result
  rows instead honour the Setup dialog's display options (Prec / NoTrail0 /
  NoLead0) while defaulting (Prec=17, NoTrail0=on) to the same text as the
  engine, so existing verified results are unchanged. }

interface

uses SysUtils, Math, ecwengine;

function RowDec(v: Extended; Prec: Integer; TrimTrail0: Boolean): string;
function RowDecFixed(v: Extended; Prec: Integer; TrimTrail0: Boolean): string;
function RowExp(v: Extended; Prec: Integer; TrimTrail0: Boolean): string;
function RowHex32(v: Extended; StripLead0: Boolean): string;
function RowBin32(v: Extended; StripLead0: Boolean): string;
function RowOct32(v: Extended; StripLead0: Boolean): string;

implementation

function ClampPrec(Prec: Integer): Integer;
begin
  if Prec < 0 then Result := 0
  else if Prec > 18 then Result := 18
  else Result := Prec;
end;

function TrimTrailZeros(const s: string): string;
var i: Integer;
begin
  i := Length(s);
  while (i > 0) and (s[i] = '0') do Dec(i);
  if (i > 0) and (s[i] = '.') then Dec(i);
  Result := Copy(s, 1, i);
end;

// Trim trailing zeros of the mantissa of an exponent-form string
// ("1.2300E+0002" -> "1.23E+0002"); never leaves the mantissa empty.
function TrimExpMantissa(const s: string): string;
var
  e: Integer;
  mant: string;
begin
  e := Pos('E', s);
  if e = 0 then Exit(s);
  mant := TrimTrailZeros(Copy(s, 1, e - 1));
  if mant = '' then mant := '0';
  Result := mant + Copy(s, e, Length(s) - e + 1);
end;

function CountIntDigits(av: Extended): Integer;
var
  s: string;
  i: Integer;
begin
  s := FloatToStrF(av, ffFixed, 0, 17);
  Result := 0;
  for i := 1 to Length(s) do
    if s[i] in ['0'..'9'] then Inc(Result) else Break;
end;

function RowDec(v: Extended; Prec: Integer; TrimTrail0: Boolean): string;
var
  av: Extended;
  d: Integer;
  s: string;
begin
  if IsNan(v) or IsInfinite(v) then Exit('ERROR');
  if Frac(v) = 0 then
    if (v >= -9.223372036854775808e18) and (v <= 9.223372036854775807e18) then
      Exit(IntToStr(Round(v)));
  if Abs(v) < 1e18 then begin
    av := Abs(v);
    if av < 1 then
      d := ClampPrec(Prec)
    else begin
      d := ClampPrec(Prec) + 1 - CountIntDigits(av);   // Prec+1 significant digits
      if d < 0 then d := 0;
    end;
    s := FloatToStrF(v, ffFixed, 0, d);
    if TrimTrail0 then s := TrimTrailZeros(s);
    if (v < 0) and (s = '0') then s := '-0';
    Result := s;
  end else begin
    s := FloatToStrF(v, ffExponent, 15, 4);
    if TrimTrail0 then s := TrimExpMantissa(s);
    Result := s;
  end;
end;

function RowExp(v: Extended; Prec: Integer; TrimTrail0: Boolean): string;
var
  d: Integer;
  s: string;
begin
  if IsNan(v) or IsInfinite(v) then Exit('ERROR');
  d := ClampPrec(Prec) + 1;               // significant digits of the mantissa
  if d > 18 then d := 18;
  s := FloatToStrF(v, ffExponent, d, 4);
  if TrimTrail0 then s := TrimExpMantissa(s);
  Result := s;
end;

// Always-decimal variant of RowDec: keeps the value in fixed (non-scientific)
// notation for every magnitude that fits, so integers still carry their
// decimal places (trimmed only when NoTrail0 is on); huge magnitudes that a
// fixed string cannot hold fall back to exponent notation for their digits.
function RowDecFixed(v: Extended; Prec: Integer; TrimTrail0: Boolean): string;
var
  d: Integer;
  s: string;
begin
  if IsNan(v) or IsInfinite(v) then Exit('ERROR');
  d := ClampPrec(Prec);
  if Abs(v) < 1e18 then begin
    s := FloatToStrF(v, ffFixed, 0, d);
    if TrimTrail0 then s := TrimTrailZeros(s);
    if (v < 0) and (s = '0') then s := '-0';
    Result := s;
  end else begin
    // too large for a fixed string: keep the digits via exponent notation
    s := FloatToStrF(v, ffExponent, 15, 4);
    if TrimTrail0 then s := TrimExpMantissa(s);
    Result := s;
  end;
end;

function StripLead(const s: string): string;
var i: Integer;
begin
  i := 1;
  while (i < Length(s)) and (s[i] = '0') do Inc(i);
  Result := Copy(s, i, Length(s) - i + 1);
end;

function RowHex32(v: Extended; StripLead0: Boolean): string;
begin
  Result := FmtHex32(v);
  if StripLead0 then Result := StripLead(Result);
end;

function RowBin32(v: Extended; StripLead0: Boolean): string;
begin
  Result := FmtBin32(v);
  if StripLead0 then Result := StripLead(Result);
end;

function RowOct32(v: Extended; StripLead0: Boolean): string;
begin
  Result := FmtOct32(v);
  if StripLead0 then Result := StripLead(Result);
end;

end.
