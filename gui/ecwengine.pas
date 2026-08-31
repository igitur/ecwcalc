{ ============================================================================
  ECW Expression Calculator — FreePascal engine unit
  Reverse-engineered from ecw.exe (v1.04-era, Delphi 3 RTL) and verified
  live against the original console engine (ec.exe v1.03b3) under Wine.

  Build:  fpc ecwengine.pas   (unit)
  ============================================================================ }

unit ecwengine;

{$mode objfpc}{$H+}

interface

uses SysUtils, Math;

procedure InitEngine;                       // call once at program start
procedure SetUnsignedHex(b: Boolean);
procedure SetSepMode(m: Integer);
function  DecimalSepChar: Char;
function  ListSepChar: Char;

// Evaluate a full expression line; returns True on success, False on error.
// On success, V holds the result.  On error, ErrMsg holds the message.
function  EvalExpr(const Expr: string; out V: Extended; out ErrMsg: string): Boolean;

// Output formatting matching the original console.
function  FmtNumber(v: Extended): string;   // dec/exp auto
function  FmtHex32(v: Extended): string;    // 8 hex digits (32-bit)
function  FmtBin32(v: Extended): string;    // 32 bits
function  FmtOct32(v: Extended): string;    // 11 octal digits
function  FmtExp(v: Extended): string;      // 0.00000000000000000E+0000

// User variables/functions (the Definitions tab)
function  AddDefDecl(const Decl: string): string;  // '' = ok, else error msg
function  NumDefs: Integer;
function  DefName(i: Integer): string;
function  DefIsFunc(i: Integer): Boolean;
function  DefDecl(i: Integer): string;             // "name(args)=body" / "name=value"
procedure DeleteDef(i: Integer);
procedure ClearDefs;

implementation

{ ============================================================================
  ECW Expression Calculator — FreePascal reimplementation
  Reverse-engineered from ecw.exe (v1.04-era, Delphi 3 RTL) and verified
  live against the original console engine (ec.exe v1.03b3) under Wine.

  Build:  fpc -O3 ecw.pas
  Usage:  ./ecw "2+3*4"
          ./ecw --unsigned "--sep=1" "1,5+2,5"
          ./ecw                       (interactive, prompt '> ')
  ============================================================================ }

const
  SavedMask: TFPUExceptionMask = [];

const
  MaxArgs = 4000;
  MaxDefs = 256;
  MaxVars = 100;
  MaxDepth = 32;

type
  TUserDef = record
    Name: string;
    IsFunc: Boolean;
    NumArgs: Integer;
    ArgNames: array[0..63] of string;
    Body: string;
    Val: Extended;
  end;
  TVarBind = record Name: string; Val: Extended; end;

var
  S: string;
  P: Integer;
  Err: string;
  Defs: array of TUserDef;
  DefCount: Integer = 0;
  UnsignedHex: Boolean = False;
  SepMode: Integer = 0;      // 0: '.' ',',  1: ',' ';',  2: '.' ';'
  LocalVars: array of TVarBind;
  Depth: Integer = 0;
  LastTokStart: Integer = 0;

function ParseExpr(MinLev: Integer): Extended; forward;

function DecimalSep: Char; inline;
begin
  case SepMode of
    1: Result := ',';
    else Result := '.';
  end;
end;

function ListSepC: Char; inline;
begin
  case SepMode of
    0: Result := ',';
    else Result := ';';
  end;
end;

procedure SetErr(const M: string); inline;
begin
  if Err = '' then Err := M;
end;

function IsSp(C: Char): Boolean; inline;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

procedure SkipWS; inline;
begin
  while (P <= Length(S)) and IsSp(S[P]) do Inc(P);
end;

function PeekC: Char; inline;
begin
  if P > Length(S) then Result := #0 else Result := S[P];
end;

function PeekC2: Char; inline;
begin
  if P + 1 > Length(S) then Result := #0 else Result := S[P + 1];
end;

function NextC: Char; inline;
begin
  Result := PeekC;
  if Result <> #0 then Inc(P);
end;

function HexVal(C: Char): Integer; inline;
begin
  case C of
    '0'..'9': Result := Ord(C) - 48;
    'a'..'f': Result := Ord(C) - 87;
    'A'..'F': Result := Ord(C) - 55;
    else Result := -1;
  end;
end;

function Frac0(v: Extended): Boolean; inline;
begin
  Result := Frac(v) = 0;
end;

function ToInt(v: Extended; const Op: string; out I: Int64): Boolean;
begin
  Result := False;
  if not Frac0(v) then begin SetErr('illegal real arg: ' + Op); Exit; end;
  if (v > 9.223372036854775807e18) or (v < -9.223372036854775808e18) then
  begin SetErr('overflow in int arg: ' + Op); Exit; end;
  I := Round(v);
  Result := True;
end;

function BitNot(v: Extended): Extended;
var i: Int64;
begin
  if not ToInt(v, '~', i) then Exit(0);
  Result := Extended(LongInt(not UInt32(i)));
end;

function BitOp2(const Op: string; a, b: Extended): Extended;
var ia, ib: Int64; c: Integer;
begin
  Result := 0;
  if not ToInt(a, Op, ia) then Exit;
  if not ToInt(b, Op, ib) then Exit;
  case Op of
    '&' : Result := Extended(LongInt(UInt32(ia) and UInt32(ib)));
    '|' : Result := Extended(LongInt(UInt32(ia) or  UInt32(ib)));
    '^' : Result := Extended(LongInt(UInt32(ia) xor UInt32(ib)));
    '<<': begin
            if ib < 0 then begin SetErr('illegal arg2<0: <<'); Exit; end;
            c := ib;
            if c >= 32 then Result := 0
            else Result := Extended(LongInt(UInt32(ia) shl c));
          end;
    '>>': begin
            if ib < 0 then begin SetErr('illegal arg2<0: >>'); Exit; end;
            c := ib;
            if c >= 32 then Result := 0
            else Result := Extended(LongInt(UInt32(ia) shr c));
          end;
  end;
end;

function PowE(x, y: Extended): Extended;
var
  t: Extended;
  sgn: Extended;
  n: Int64;
  base, acc: Extended;
  neg: Boolean;
begin
  if y = 0 then begin
    if x = 0 then Result := 0 else Result := 1;   // 0^0 = 0 (original)
    Exit;
  end;
  if x = 0 then begin
    if y < 0 then SetErr('overflow: **');
    Result := 0;
    Exit;
  end;

  // integer-exponent fast path: exact via exponentiation by squaring
  if Frac0(y) and (Abs(y) <= 1e9) then begin
    n := Round(y);
    neg := n < 0;
    if neg then n := -n;
    base := x;
    acc := 1;
    while n > 0 do begin
      if (n and 1) <> 0 then acc := acc * base;
      n := n shr 1;
      if n > 0 then base := base * base;
    end;
    if neg then begin
      if acc = 0 then begin SetErr('overflow: **'); Exit(0); end;
      acc := 1 / acc;
    end;
    if IsInfinite(acc) or IsNan(acc) then begin SetErr('overflow: **'); Exit(0); end;
    Result := acc;
    Exit;
  end;

  if x < 0 then begin
    if not Frac0(y) then begin SetErr('invalid usage: **'); Exit(0); end;
    sgn := -1;
    if Frac(y / 2) = 0 then sgn := 1;
    t := Exp(y * Ln(-x));
    Result := sgn * t;
  end else
    Result := Exp(y * Ln(x));
  if IsInfinite(Result) or IsNan(Result) then SetErr('overflow: **');
end;

function Fact(a: Extended): Extended;
var i: Integer; r: Extended;
begin
  if a < 0 then begin SetErr('illegal arg<0: fact'); Exit(0); end;
  if not Frac0(a) then begin SetErr('illegal real arg: fact'); Exit(0); end;
  if a > 1750 then begin SetErr('overflow: fact'); Exit(0); end;
  r := 1;
  for i := 2 to Trunc(a) do r := r * i;
  Result := r;
end;

function CallStd(a: Extended; const Fn: string): Extended;
begin
  case Fn of
    'sin'  : Result := Sin(a);
    'cos'  : Result := Cos(a);
    'tan'  : Result := Tan(a);
    'ctan' : begin
             if a = 0 then begin SetErr('overflow: ctan'); Exit(0); end
             else Result := Cos(a) / Sin(a);
             end;
    'asin' : begin
             if (a < -1) or (a > 1) then begin SetErr('illegal |arg|>1: asin'); Exit(0); end;
             Result := arcsin(a);
             end;
    'acos' : begin
             if (a < -1) or (a > 1) then begin SetErr('illegal |arg|>1: acos'); Exit(0); end;
             Result := arccos(a);
             end;
    'atan' : Result := ArcTan(a);
    'actan': begin
             if a = 0 then begin SetErr('overflow: actan'); Exit(0); end;
             Result := Pi / 2 - ArcTan(a);
             end;
    'sinh' : Result := (Exp(a) - Exp(-a)) / 2;
    'cosh' : Result := (Exp(a) + Exp(-a)) / 2;
    'tanh' : Result := (Exp(2 * a) - 1) / (Exp(2 * a) + 1);
    'asinh': Result := Ln(a + Sqrt(a * a + 1));
    'acosh': begin
             if a < 1 then begin SetErr('illegal arg<1: acosh'); Exit(0); end;
             Result := Ln(a + Sqrt(a * a - 1));
             end;
    'atanh': begin
             if (a = 1) or (a = -1) then begin SetErr('overflow: atanh'); Exit(0); end;
             if (a > 1) or (a < -1) then begin SetErr('illegal |arg|>1: atanh'); Exit(0); end;
             Result := 0.5 * Ln((1 + a) / (1 - a));
             end;
    'exp'  : Result := Exp(a);
    'ln'   : begin
             if a < 0 then begin SetErr('illegal arg<0: ln'); Exit(0); end;
             if a = 0 then begin SetErr('overflow: ln'); Exit(0); end;
             Result := Ln(a);
             end;
    'log'  : begin
             if a < 0 then begin SetErr('illegal arg<0: log'); Exit(0); end;
             if a = 0 then begin SetErr('overflow: log'); Exit(0); end;
             Result := Ln(a) / Ln(10);
             end;
    'sqr'  : Result := a * a;
    'sqrt' : begin
             if a < 0 then begin SetErr('illegal arg<0: sqrt'); Exit(0); end;
             Result := Sqrt(a);
             end;
    'fact' : Result := Fact(a);
    'abs'  : Result := Abs(a);
    'sign' : if a > 0 then Result := 1 else if a < 0 then Result := -1 else Result := 0;
    'int'  : Result := Int(a);
    'frac' : Result := Frac(a);
    'rad'  : Result := a * (Pi / 180);
    'deg'  : Result := a * (180 / Pi);
    else Result := 0; SetErr('unknown function: ' + Fn);
  end;
  if (IsInfinite(Result) or IsNan(Result)) and (Err = '') then SetErr('overflow: ' + Fn);
end;

function CallList(const Fn: string; const A: array of Extended): Extended;
var i, n: Integer; r: Extended;
begin
  n := Length(A);
  case Fn of
    'sum' : begin r := 0; for i := 0 to n - 1 do r := r + A[i]; Result := r; end;
    'prod': begin r := 1; for i := 0 to n - 1 do r := r * A[i]; Result := r; end;
    'avg' : begin r := 0; for i := 0 to n - 1 do r := r + A[i];
                  if n = 0 then Result := 0 else Result := r / n; end;
    'geo' : begin r := 1; for i := 0 to n - 1 do r := r * A[i];
                  if n = 0 then Result := 0
                  else if r = 0 then Result := 0
                  else if r < 0 then begin
                    r := -r;
                    Result := -PowE(r, 1 / n);
                  end else
                    Result := PowE(r, 1 / n);
            end;
    'min' : begin Result := A[0]; for i := 1 to n - 1 do if A[i] < Result then Result := A[i]; end;
    'max' : begin Result := A[0]; for i := 1 to n - 1 do if A[i] > Result then Result := A[i]; end;
    'poly': begin
              if n < 2 then begin SetErr('missing arg2: poly'); Exit(0); end;
              // poly(x, a0, a1, ..., ak) = a0 + a1*x + ... + ak*x^k
              Result := 0;
              for i := n - 1 downto 1 do
                Result := Result * A[0] + A[i];
            end;
    else Result := 0; SetErr('unknown list function: ' + Fn);
  end;
  if (IsInfinite(Result) or IsNan(Result)) and (Err = '') then SetErr('overflow: ' + Fn);
end;

function IsListFunc(const N: string): Boolean;
begin
  Result := (N = 'sum') or (N = 'prod') or (N = 'avg') or (N = 'geo') or
            (N = 'min') or (N = 'max');
end;

function IsBuiltinName(const N: string): Boolean;
const B: array[0..35] of string =
  ('sin','cos','tan','ctan','asin','acos','atan','actan',
   'sinh','cosh','tanh','asinh','acosh','atanh',
   'exp','ln','log','sqr','sqrt','fact','abs','sign','int','frac','rad','deg',
   'sum','prod','avg','geo','min','max','poly','pi','e','');
var i: Integer;
begin
  Result := False;
  for i := 0 to 34 do
    if B[i] = N then begin Result := True; Exit; end;
end;

function LookupVar(const N: string; out V: Extended): Boolean;
var i: Integer;
begin
  for i := High(LocalVars) downto 0 do
    if LocalVars[i].Name = N then begin V := LocalVars[i].Val; Exit(True); end;
  for i := 0 to DefCount - 1 do
    if (not Defs[i].IsFunc) and (Defs[i].Name = N) then begin V := Defs[i].Val; Exit(True); end;
  if N = 'pi' then begin V := Pi; Exit(True); end;
  if N = 'e'  then begin V := Exp(1); Exit(True); end;
  Result := False;
end;

function FindUserFunc(const N: string; WantArgs: Integer; out Idx: Integer): Boolean;
var i: Integer;
begin
  for i := 0 to DefCount - 1 do
    if Defs[i].IsFunc and (Defs[i].Name = N) and (Defs[i].NumArgs = WantArgs) then
    begin Idx := i; Exit(True); end;
  Result := False;
end;

function EvalUserFunc(di: Integer; const Args: array of Extended): Extended;
var
  savedL: array of TVarBind;
  oldS: string; oldP: Integer;
  i: Integer;
begin
  if Depth >= MaxDepth then begin SetErr('too complex definition'); Exit(0); end;
  savedL := Copy(LocalVars, 0, Length(LocalVars));
  SetLength(LocalVars, Defs[di].NumArgs);
  for i := 0 to Defs[di].NumArgs - 1 do
  begin
    LocalVars[i].Name := Defs[di].ArgNames[i];
    LocalVars[i].Val := Args[i];
  end;
  oldS := S; oldP := P;
  S := Defs[di].Body; P := 1;
  Inc(Depth);
  Result := ParseExpr(0);
  Dec(Depth);
  if Err = '' then begin
    SkipWS;
    if P <= Length(S) then SetErr('invalid expression: ' + S[P]);
  end;
  S := oldS; P := oldP;
  LocalVars := savedL;
end;

function EvalCall(const Name: string): Extended;
var
  Args: array of Extended;
  n: Integer;
  di: Integer;
begin
  SetLength(Args, MaxArgs);
  n := 0;
  SkipWS;
  if PeekC = ')' then begin SetErr('missing expression'); Exit(0); end;
  while True do begin
    if n >= MaxArgs then begin SetErr('too many args: ' + Name); Exit(0); end;
    Args[n] := ParseExpr(0);
    if Err <> '' then Exit(0);
    Inc(n);
    SkipWS;
    if PeekC = ListSepC then begin
      NextC; SkipWS;
      if PeekC = ')' then begin SetErr('missing expression'); Exit(0); end;
      Continue;
    end;
    Break;
  end;
  if PeekC <> ')' then begin SetErr('missing operator: ' + Name); Exit(0); end;
  NextC;

  if n = 1 then begin
    if FindUserFunc(Name, 1, di) then Exit(EvalUserFunc(di, Copy(Args, 0, n)));
    Result := CallStd(Args[0], Name);
    if (Err = 'invalid expression: ' + Name) then
      Err := 'unknown function: ' + Name;
    Exit;
  end;

  if FindUserFunc(Name, n, di) then Exit(EvalUserFunc(di, Copy(Args, 0, n)));

  if (Name = 'log') and (n = 2) then begin
    if Args[1] <= 0 then begin SetErr('overflow: log'); Exit(0); end;
    if (Args[0] <= 0) or (Args[0] = 1) then begin SetErr('overflow: log'); Exit(0); end;
    Result := Ln(Args[1]) / Ln(Args[0]);
    if IsInfinite(Result) or IsNan(Result) then SetErr('overflow: log');
    Exit;
  end;

  Result := CallList(Name, Copy(Args, 0, n));
end;

function Precedence(const Op: string): Integer;
begin
  case Op of
    '*','/','**','//','%' : Result := 50;
    '+','-'               : Result := 40;
    '&','|','^','&&','||','^^','<<','>>' : Result := 30;
    '=','==','<>','!=','<','>','<=','>=' : Result := 20;
    else Result := 0;
  end;
end;

function PeekOp(out Op: string): Boolean;
var c1, c2: Char;
begin
  c1 := PeekC;
  case c1 of
    '*': if PeekC2 = '*' then Op := '**' else Op := '*';
    '/': if PeekC2 = '/' then Op := '//' else Op := '/';
    '<': if PeekC2 = '=' then Op := '<='
         else if PeekC2 = '>' then Op := '<>'
         else if PeekC2 = '<' then Op := '<<' else Op := '<';
    '>': if PeekC2 = '=' then Op := '>='
         else if PeekC2 = '>' then Op := '>>' else Op := '>';
    '=': if PeekC2 = '=' then Op := '==' else Op := '=';
    '!': if PeekC2 = '=' then Op := '!=' else Op := '!';
    '&': if PeekC2 = '&' then Op := '&&' else Op := '&';
    '|': if PeekC2 = '|' then Op := '||' else Op := '|';
    '^': if PeekC2 = '^' then Op := '^^' else Op := '^';
    '+','-','%','~','(',')',',',';' : Op := c1;
    else begin Result := False; Exit; end;
  end;
  Result := True;
end;

function ApplyOp(const Op: string; a, b: Extended): Extended;
var ia, ib: Int64;
begin
  case Op of
    '+'  : Result := a + b;
    '-'  : Result := a - b;
    '*'  : Result := a * b;
    '/'  : begin
           if b = 0 then begin SetErr('overflow: /'); Exit(0); end;
           Result := a / b;
           end;
    '**' : Result := PowE(a, b);
    '//' : begin
            if not ToInt(a, '//', ia) then Exit(0);
            if not ToInt(b, '//', ib) then Exit(0);
            if ib = 0 then begin SetErr('illegal arg2=0: //'); Exit(0); end;
            Result := Extended(ia div ib);
           end;
    '%'  : begin
            if not ToInt(a, '%', ia) then Exit(0);
            if not ToInt(b, '%', ib) then Exit(0);
            if ib = 0 then begin SetErr('illegal arg2=0: %'); Exit(0); end;
            Result := Extended(ia mod ib);
           end;
    '&','|','^','<<','>>' : Result := BitOp2(Op, a, b);
    '=','==' : Result := Ord(a = b);
    '<>','!=': Result := Ord(a <> b);
    '<'      : Result := Ord(a < b);
    '>'      : Result := Ord(a > b);
    '<='     : Result := Ord(a <= b);
    '>='     : Result := Ord(a >= b);
    '&&'     : Result := Ord((a <> 0) and (b <> 0));
    '||'     : Result := Ord((a <> 0) or (b <> 0));
    '^^'     : Result := Ord(((a <> 0) xor (b <> 0)));
    else Result := 0; SetErr('unknown operator: ' + Op);
  end;
  if (IsInfinite(Result) or IsNan(Result)) and (Err = '') then
    SetErr('overflow: ' + Op);
end;

procedure EvalBaseConst(const D: string; base: Integer; const Kind: string; out V: Extended);
var i, dv: Integer; hx: UInt64; neg: Boolean;
begin
  V := 0;
  hx := 0;
  for i := 1 to Length(D) do begin
    dv := HexVal(D[i]);
    if (dv < 0) or (dv >= base) then
    begin SetErr('invalid ' + Kind + ': ' + LowerCase(D)); Exit; end;
    if hx > (High(UInt64) - UInt64(dv)) div UInt64(base) then
    begin SetErr('overflow in ' + Kind + ': ' + LowerCase(D)); Exit; end;
    hx := hx * UInt64(base) + UInt64(dv);
  end;
  neg := hx >= $80000000;
  if not UnsignedHex then begin
    if hx > $FFFFFFFF then begin SetErr('overflow in ' + Kind + ': ' + LowerCase(D)); Exit; end;
    if neg then V := Extended(Int64(hx) - $100000000)
    else V := Extended(hx);
  end else
    V := Extended(hx);
end;

function ScalePow10(v: Extended; k: Integer): Extended; forward;

function TryParseReal(out V: Extended): Boolean;
var
  Start: Integer;
  mant: Int64;
  m64: Int64;
  fracDigits: Integer;
  E: Integer; i, signe: Integer;
  had: Boolean;
  C: Char;
  Overflowed: Boolean;
begin
  Result := False;
  V := 0;
  if P > Length(S) then Exit;
  C := PeekC;
  if not ((C in ['0'..'9']) or (C = DecimalSep)) then Exit;

  Start := P;
  // integer part
  mant := 0; had := False; Overflowed := False;
  while (P <= Length(S)) and (S[P] in ['0'..'9']) do begin
    if not Overflowed then begin
      if mant > (High(Int64) - (Ord(S[P]) - 48)) div 10 then Overflowed := True
      else mant := mant * 10 + (Ord(S[P]) - 48);
    end;
    Inc(P); had := True;
  end;
  // fraction part
  fracDigits := 0;
  if (P <= Length(S)) and (S[P] = DecimalSep) then begin
    Inc(P);
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do begin
      if not Overflowed then begin
        if mant > (High(Int64) - (Ord(S[P]) - 48)) div 10 then Overflowed := True
        else mant := mant * 10 + (Ord(S[P]) - 48);
      end;
      Inc(P); had := True; Inc(fracDigits);
    end;
  end;
  if not had then begin Result := False; Exit; end;

  // exponent suffix
  E := 0; signe := 1;
  if (P <= Length(S)) and ((S[P] = 'e') or (S[P] = 'E')) then begin
    Inc(P);
    if (P <= Length(S)) and ((S[P] = '+') or (S[P] = '-')) then begin
      if S[P] = '-' then signe := -1 else signe := 1;
      Inc(P);
    end;
    if (P > Length(S)) or not (S[P] in ['0'..'9']) then begin
      // "1e" with no exponent digits: value is just the mantissa
      P := P - 1; { back to 'e' position; caller treats rest as error }
      if signe = -1 then P := P - 1; { back over the sign too }
      V := 0;
      // re-read integer mantissa without exponent
      Result := True;
      Exit;
    end;
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do begin
      E := E * 10 + (Ord(S[P]) - 48);
      if E > 5000 then break;
      Inc(P);
    end;
    E := E * signe;
  end;

  // Val-style: integer mantissa * 10^(E - fracDigits)
  // Delphi 3 Val/Str2Ext computes mantissa as Int64 then scales by power of 10.
  if Overflowed then begin
    // mantissa too big for Int64: accumulate in Extended instead
    V := 0;
    P := Start;
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do begin
      V := V * 10 + (Ord(S[P]) - 48); Inc(P);
    end;
    if (P <= Length(S)) and (S[P] = DecimalSep) then begin
      Inc(P);
      while (P <= Length(S)) and (S[P] in ['0'..'9']) do begin
        V := V * 10 + (Ord(S[P]) - 48); Inc(P);
      end;
    end;
    V := ScalePow10(V, E - fracDigits);
  end else begin
    V := Extended(mant);
    if (E - fracDigits) <> 0 then
      V := ScalePow10(V, E - fracDigits);
  end;
  Result := True;
end;

{ multiply/divide by an exact power of ten: 10^k for |k| <= 18 is
  exactly representable in Extended, so a single multiply/divide gives a
  correctly-rounded result (matches Delphi Val's Power10 table). }
function ScalePow10(v: Extended; k: Integer): Extended;
var
  p: Extended;
  i: Integer;
  neg: Boolean;
begin
  if k = 0 then Exit(v);
  neg := k < 0;
  if neg then k := -k;
  p := 1;
  for i := 1 to k do p := p * 10;
  if neg then Result := v / p else Result := v * p;
end;

function TryParseNumber(out V: Extended): Boolean;
var
  Save: Integer;
  H: string;
  i: Integer; bad: Boolean;
  C: Char;
begin
  Result := False;
  Save := P;
  C := PeekC;

  if C = '$' then begin
    NextC;
    H := '';
    while (P <= Length(S)) and (HexVal(S[P]) >= 0) do begin H := H + S[P]; Inc(P); end;
    if H = '' then begin P := Save; Exit; end;   // bare '$': fall to invalid char
    EvalBaseConst(H, 16, 'hex', V);
    Result := True; Exit;
  end;

  if (C = '0') and (PeekC2 in ['x', 'X']) then begin
    P := P + 2;
    H := '';
    while (P <= Length(S)) and (HexVal(S[P]) >= 0) do begin H := H + S[P]; Inc(P); end;
    if H = '' then begin V := 0; Result := True; Exit; end;   // "0x" -> 0
    // if a non-hex alnum char follows, report it as part of the invalid hex
    if (P <= Length(S)) and (S[P] in ['a'..'z','A'..'Z','0'..'9']) then begin
      H := H + S[P]; Inc(P);
      SetErr('invalid hex: ' + LowerCase(H));
      Result := True; Exit;
    end;
    EvalBaseConst(H, 16, 'hex', V);
    Result := True; Exit;
  end;

  // hex-digit run: catches 12h, 0ABh, 101b, 12o, and plain numbers.
  // h/o/b suffix chars are also hex digits, so collect greedily and then
  // check whether the LAST char is a valid suffix.
  H := '';
  while (P <= Length(S)) and (HexVal(S[P]) >= 0) do begin H := H + S[P]; Inc(P); end;

  if (Length(H) >= 1) and (P <= Length(S)) and (S[P] in ['h', 'H', 'o', 'O', 'b', 'B']) then begin
    C := LowerCase(S[P]); Inc(P);
    case C of
      'h': EvalBaseConst(H, 16, 'hex', V);
      'o': EvalBaseConst(H, 8,  'oct', V);
      'b': EvalBaseConst(H, 2,  'bin', V);
    end;
    Result := True; Exit;
  end;

  // trailing-suffix form: "101b" - the 'b' got absorbed into H
  if (Length(H) >= 2) and (H[Length(H)] in ['h', 'H', 'o', 'O', 'b', 'B']) then begin
    C := LowerCase(H[Length(H)]);
    Delete(H, Length(H), 1);
    case C of
      'h': EvalBaseConst(H, 16, 'hex', V);
      'o': EvalBaseConst(H, 8,  'oct', V);
      'b': EvalBaseConst(H, 2,  'bin', V);
    end;
    Result := True; Exit;
  end;

  // leading-zero octal: 012 = 10
  if (Length(H) > 1) and (H[1] = '0') and (P > Length(S)) then begin
    bad := False;
    for i := 1 to Length(H) do
      if not (H[i] in ['0'..'7']) then begin bad := True; Break; end;
    if not bad then begin
      EvalBaseConst(H, 8, 'oct', V);
      Result := True; Exit;
    end;
  end;

  // decimal / real: rewind and parse with TryParseReal
  P := Save;
  Result := TryParseReal(V);
  if (not Result) and (P <= Length(S)) and (HexVal(S[P]) >= 0) then begin
    SetErr('invalid number: ' + S[P]);
  end;
end;

function ParsePrimary: Extended;
var
  C: Char;
  Name: string;
  V: Extended;
  di: Integer;
  i: Integer;
begin
  Result := 0;
  SkipWS;
  C := PeekC;

  if C = '(' then begin
    NextC;
    Result := ParseExpr(0);
    if Err <> '' then Exit;
    SkipWS;
    if PeekC <> ')' then begin SetErr('invalid brackets'); Exit; end;
    NextC;
    Exit;
  end;

  if C = ')' then begin SetErr('invalid brackets'); Exit; end;

  if C = #0 then begin SetErr('missing expression'); Exit; end;

  if (C in ['0'..'9']) or (C = DecimalSep) or (C = '$') then begin
    LastTokStart := P;
    if TryParseNumber(V) then begin Result := V; Exit; end;
    Exit;
  end;

  if ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or (C = '_') then begin
    LastTokStart := P;
    Name := '';
    while (P <= Length(S)) and
          (((S[P] >= 'a') and (S[P] <= 'z')) or ((S[P] >= 'A') and (S[P] <= 'Z')) or
           ((S[P] >= '0') and (S[P] <= '9')) or (S[P] = '_')) do begin
      Name := Name + S[P]; Inc(P);
    end;
    SkipWS;
    if PeekC = '(' then begin
      NextC;
      Result := EvalCall(Name);
      Exit;
    end;
    if LookupVar(Name, V) then begin Result := V; Exit; end;
    if IsBuiltinName(Name) then begin
      SetErr('invalid expression: ' + Name);
      Exit;
    end;
    SetErr('invalid expression: ' + Name);
    Exit;
  end;

  SetErr('invalid char: ' + C);
end;

function ParseUnary: Extended;
var C: Char;
begin
  SkipWS;
  C := PeekC;
  case C of
    '+': begin NextC; Result := ParseUnary(); end;
    '-': begin NextC; Result := -ParseUnary(); end;
    '~': begin NextC; Result := BitNot(ParseUnary()); end;
    '!': begin NextC; Result := Ord(ParseUnary() = 0); end;
    else Result := ParsePrimary;
  end;
end;

function ParseExpr(MinLev: Integer): Extended;
var
  a, b: Extended;
  Op: string;
  lev: Integer;
begin
  a := ParseUnary;
  if Err <> '' then Exit;
  while True do begin
    SkipWS;
    if not PeekOp(Op) then Break;
    lev := Precedence(Op);
    if (lev = 0) or (lev < MinLev) then Break;
    if (Op = ')') or (Op = ',') or (Op = ';') then Break;
    P := P + Length(Op);   // consume full operator (incl. multi-char)
    SkipWS;
    if P > Length(S) then begin SetErr('missing arg2: ' + Op); Exit; end;
    b := ParseExpr(lev + 1);   // left-assoc: RHS must bind tighter
    if Err <> '' then Exit;
    a := ApplyOp(Op, a, b);
    if Err <> '' then Exit;
  end;
  Result := a;
end;

procedure AddDef(const Name: string; IsFunc: Boolean; NumArgs: Integer;
                 const ArgNames: array of string; const Body: string; Val: Extended);
var i, j: Integer;
begin
  if DefCount >= MaxDefs then begin SetErr('too many definitions'); Exit; end;
  // replace existing
  for i := 0 to DefCount - 1 do
    if Defs[i].Name = Name then begin
      Defs[i].IsFunc := IsFunc;
      Defs[i].NumArgs := NumArgs;
      Defs[i].Body := Body;
      Defs[i].Val := Val;
      for j := 0 to NumArgs - 1 do Defs[i].ArgNames[j] := ArgNames[j];
      Exit;
    end;
  i := DefCount; Inc(DefCount);
  SetLength(Defs, DefCount);
  Defs[i].Name := Name;
  Defs[i].IsFunc := IsFunc;
  Defs[i].NumArgs := NumArgs;
  Defs[i].Body := Body;
  Defs[i].Val := Val;
  for j := 0 to NumArgs - 1 do Defs[i].ArgNames[j] := ArgNames[j];
end;

{ Top-level: [var=val, ...] expr  or  [f(args)=body, ...] expr }
function ParseTopLevel: Extended;
var
  Name, Body: string;
  ArgNames: array[0..63] of string;
  NumArgs: Integer;
  Save: Integer;
  BodyStart: Integer;
  DepthScan: Integer;
  V: Extended;
  i: Integer;
  LooksLikeDef: Boolean;
begin
  Result := 0;
  LocalVars := nil;
  while True do begin
    SkipWS;
    Save := P;

    // detect: identifier ['(' args ')'] '='  (peek only, don't consume on failure)
    LooksLikeDef := False;
    Name := '';
    if (P <= Length(S)) and (((S[P] >= 'a') and (S[P] <= 'z')) or
                             ((S[P] >= 'A') and (S[P] <= 'Z')) or (S[P] = '_')) then begin
      LooksLikeDef := True;   // tentatively; require '=' below
    end;

    if LooksLikeDef then begin
      // scan forward to find '=' at the top level of this def clause
      NumArgs := 0;
      Save := P;
      while (P <= Length(S)) and
            (((S[P] >= 'a') and (S[P] <= 'z')) or ((S[P] >= 'A') and (S[P] <= 'Z')) or
             ((S[P] >= '0') and (S[P] <= '9')) or (S[P] = '_')) do begin
        Name := Name + S[P]; Inc(P);
      end;
      SkipWS;
      if PeekC = '(' then begin
        NextC; SkipWS;
        if PeekC = ')' then begin NextC; end
        else while True do begin
          if NumArgs >= 64 then begin SetErr('too many args: ' + Name); Exit; end;
          ArgNames[NumArgs] := '';
          while (P <= Length(S)) and
                (((S[P] >= 'a') and (S[P] <= 'z')) or ((S[P] >= 'A') and (S[P] <= 'Z')) or
                 ((S[P] >= '0') and (S[P] <= '9')) or (S[P] = '_')) do begin
            ArgNames[NumArgs] := ArgNames[NumArgs] + S[P]; Inc(P);
          end;
          Inc(NumArgs);
          SkipWS;
          if PeekC = ListSepC then begin NextC; SkipWS; Continue; end;
          if PeekC = ')' then begin NextC; Break; end;
          LooksLikeDef := False;  // not a valid def form; treat as expression
          P := Save;
          Break;
        end;
        SkipWS;
        if LooksLikeDef then
          if PeekC <> '=' then begin LooksLikeDef := False; P := Save; end;
      end else begin
        if PeekC <> '=' then begin LooksLikeDef := False; P := Save; end;
      end;
    end;

    if LooksLikeDef then begin
      NextC; SkipWS;
      Body := '';
      if PeekC = ListSepC then begin SetErr('missing expression'); Exit; end;
      BodyStart := P;
      if NumArgs > 0 then begin
        // capture body text up to top-level list separator (paren-depth aware)
        Body := '';
        DepthScan := 0;
        while P <= Length(S) do begin
          if S[P] = '(' then Inc(DepthScan)
          else if S[P] = ')' then begin
            if DepthScan > 0 then Dec(DepthScan) else Break;
          end
          else if (S[P] = ListSepC) and (DepthScan = 0) then Break;
          Body := Body + S[P];
          Inc(P);
        end;
        Body := Trim(Body);
        if Body = '' then begin SetErr('missing expression'); Exit; end;
        AddDef(Name, True, NumArgs, ArgNames, Body, 0);
      end else begin
        V := ParseExpr(0);
        if Err <> '' then Exit;
        AddDef(Name, False, 0, ArgNames, '', V);
      end;
      SkipWS;
      if PeekC = ListSepC then begin NextC; Continue; end;
      if P > Length(S) then begin SetErr('invalid expression: ' + Name); Exit; end;
      Result := ParseExpr(0);
      Exit;
    end;

    // not a definition: parse the final expression
    P := Save;
    Result := ParseExpr(0);
    if Err <> '' then Exit;
    SkipWS;
    if P <= Length(S) then begin
      // trailing garbage
      if S[P] = ListSepC then
        SetErr('invalid var definition: ' + Copy(S, Save, P - Save))
      else
        SetErr('invalid expression: ' + Copy(S, LastTokStart, Length(S) - LastTokStart + 1));
    end;
    Exit;
  end;
end;

{ ---------- output formatting (matches original console) ---------- }

{ The original (ec.exe / Wecw_Proc FormatDec) displays:
    |v| < 1        : 17 decimal places, trailing zeros trimmed
    1 <= |v| < 1e18: 18 significant digits, trailing zeros trimmed
    |v| >= 1e18    : scientific, 15 significant digits, 4-digit exponent
  (e.g. 1/3 -> 0.33333333333333333, 100/3 -> 33.3333333333333333,
   123456789.123456789 -> 123456789.123456789, 2**1000 -> 1.07150860718627E+0301) }

function TrimTrailZeros(const s: string): string;
var i: Integer;
begin
  i := Length(s);
  while (i > 0) and (s[i] = '0') do Dec(i);
  if (i > 0) and (s[i] = '.') then Dec(i);
  Result := Copy(s, 1, i);
end;

function FmtFixed(v: Extended): string;
var
  av: Extended;
  dec: Integer;
  s: string;
  i, intdigits: Integer;
begin
  av := Abs(v);
  if av < 1 then begin
    dec := 17;                     { 17 decimal places }
  end else begin
    { 18 significant digits: count integer digits robustly }
    s := FloatToStrF(av, ffFixed, 0, 17);   { enough decimals to see int part }
    intdigits := 0;
    for i := 1 to Length(s) do
      if s[i] in ['0'..'9'] then Inc(intdigits) else Break;
    dec := 18 - intdigits;
    if dec < 0 then dec := 0;
  end;
  Result := TrimTrailZeros(FloatToStrF(v, ffFixed, 0, dec));
  if (v < 0) and (Result = '0') then Result := '-0';
end;

function FmtNumber(v: Extended): string;
var i64: Int64;
begin
  if IsNan(v) or IsInfinite(v) then begin Result := 'ERROR'; Exit; end;
  if Frac0(v) and (v >= -9.223372036854775808e18) and (v <= 9.223372036854775807e18) then begin
    i64 := Round(v);
    Result := IntToStr(i64);
    Exit;
  end;
  if Abs(v) < 1e18 then
    Result := FmtFixed(v)
  else
    Result := FloatToStrF(v, ffExponent, 15, 4);
end;



{ ---------- interface implementations ---------- }

procedure InitEngine;
begin
  SavedMask := GetExceptionMask;
  SetExceptionMask(SavedMask + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow]);
end;

procedure SetUnsignedHex(b: Boolean);
begin
  UnsignedHex := b;
end;

procedure SetSepMode(m: Integer);
begin
  SepMode := m;
end;

function DecimalSepChar: Char;
begin
  Result := DecimalSep;
end;

function ListSepChar: Char;
begin
  Result := ListSepC;
end;

function EvalExpr(const Expr: string; out V: Extended; out ErrMsg: string): Boolean;
begin
  S := Expr;
  P := 1;
  Err := '';
  Depth := 0;
  V := ParseTopLevel;
  SkipWS;
  if (Err = '') and (P <= Length(S)) then
    Err := 'invalid expression: ' + S[P];
  Result := Err = '';
  if Result then
    ErrMsg := ''
  else
    ErrMsg := Err;
end;

{ 32-bit helpers: match the original's hex/bin/oct result labels.
  The original shows the result as a 32-bit value (truncated to
  8 hex / 32 bin / 11 oct digits), with unsigned interpretation
  when UnsignedHex is on. }

function Trunc32(v: Extended): LongWord;
var i: Int64;
begin
  if IsNan(v) or IsInfinite(v) then begin Result := 0; Exit; end;
  i := Trunc(v);
  Result := LongWord(i and $FFFFFFFF);
end;

function FmtHex32(v: Extended): string;
begin
  if UnsignedHex then
    Result := IntToHex(Trunc32(v), 8)
  else
    Result := IntToHex(LongInt(Trunc32(v)), 8);
end;

function FmtBin32(v: Extended): string;
var u: LongWord; i: Integer;
begin
  u := Trunc32(v);
  Result := '';
  for i := 31 downto 0 do
    Result := Result + Chr(Ord('0') + ((u shr i) and 1));
end;

function FmtOct32(v: Extended): string;
var u: LongWord; i: Integer;
begin
  u := Trunc32(v);
  Result := '';
  for i := 10 downto 0 do
    Result := Result + Chr(Ord('0') + ((u shr (3 * i)) and 7));
end;

function FmtExp(v: Extended): string;
begin
  if IsNan(v) or IsInfinite(v) then begin Result := 'ERROR'; Exit; end;
  Result := FloatToStrF(v, ffExponent, 18, 4);
end;


{ ---------- user definitions API ---------- }

function AddDefDecl(const Decl: string): string;
var
  Tmp: string;
  V: Extended;
  M: string;
begin
  // ParseTopLevel processes "name=value" / "name(args)=body" declarations
  // sequentially and returns the final expression result.  Appending ",0"
  // lets us reuse the whole verified def parser: the declaration is added
  // to Defs if and only if it parses cleanly.
  Tmp := Decl + ListSepC + '0';
  if EvalExpr(Tmp, V, M) then
    Result := ''
  else
    Result := M;
end;

function NumDefs: Integer;
begin
  Result := DefCount;
end;

function DefName(i: Integer): string;
begin
  if (i >= 0) and (i < DefCount) then Result := Defs[i].Name else Result := '';
end;

function DefIsFunc(i: Integer): Boolean;
begin
  if (i >= 0) and (i < DefCount) then Result := Defs[i].IsFunc else Result := False;
end;

function DefDecl(i: Integer): string;
var
  j: Integer;
begin
  if (i < 0) or (i >= DefCount) then begin Result := ''; Exit; end;
  if Defs[i].IsFunc then begin
    Result := Defs[i].Name + '(';
    for j := 0 to Defs[i].NumArgs - 1 do begin
      if j > 0 then Result := Result + ListSepC;
      Result := Result + Defs[i].ArgNames[j];
    end;
    Result := Result + ')=' + Defs[i].Body;
  end else begin
    Result := Defs[i].Name + '=' + FloatToStr(Defs[i].Val);
  end;
end;

procedure DeleteDef(i: Integer);
var j: Integer;
begin
  if (i < 0) or (i >= DefCount) then Exit;
  for j := i to DefCount - 2 do Defs[j] := Defs[j + 1];
  Dec(DefCount);
end;

procedure ClearDefs;
begin
  SetLength(Defs, 0);
  DefCount := 0;
end;

end.
