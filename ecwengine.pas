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
procedure MoveDef(i: Integer; Dir: Integer);
procedure ClearDefs;

// ecw_defs.ini persistence (one declaration per line, same format as the
// original ECW 'Definitions' file).  LoadDefsFile appends to the current
// set; returns number of lines parsed.  SaveDefsFile rewrites the file.
function  LoadDefsFile(const AFileName: string): Integer;
function  SaveDefsFile(const AFileName: string): Boolean;

implementation

{ ============================================================================
  ECW Expression Calculator — FreePascal reimplementation
  Reverse-engineered from ecw.exe (v1.04-era, Delphi 3 RTL) and verified
  live against the original console engine (ec.exe v1.03b3) under Wine.

  CLI front end: ./ec.lpr  (build with ./build.sh cli)
  ============================================================================ }

const
  SavedMask: TFPUExceptionMask = [];

const
  MaxArgs = 4000;
  MaxDefs = 256;
  MaxDepth = 32;

type
  TUserDef = record
    Name: string;
    IsFunc: Boolean;
    NumArgs: Integer;
    ArgNames: array[0..63] of string;
    Body: string;
    Val: Extended;
    Raw: string;        // original "name(args)=body" / "name=value" text
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

function PeekC3: Char; inline;
begin
  if P + 2 > Length(S) then Result := #0 else Result := S[P + 2];
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

{ ---- integer-arg semantics, matching StdMath v1.06 (_int.pas) ----
  IsReal  : Abs(Frac(x)) > 1e-18      -> 'illegal real argN'
  IsDWord : Int(x) within int32       -> 'overflow in int argN'
  All bit/div/mod ops are 32-bit on LongInt. }

function IsRealX(v: Extended): Boolean; inline;
begin
  Result := Abs(Frac(v)) > 1e-18;
end;

function IsDWordX(v: Extended): Boolean;
begin
  Result := (Int(v) >= -2147483648.0) and (Int(v) <= 2147483647.0);
end;

function ToIntN(v: Extended; const Op: string; ArgNo: Integer; out n: LongInt): Boolean;
begin
  Result := False;
  if IsRealX(v) then begin
    if ArgNo = 1 then SetErr('illegal real arg1: ' + Op)
                else SetErr('illegal real arg2: ' + Op);
    Exit;
  end;
  if not IsDWordX(v) then begin
    if ArgNo = 1 then SetErr('overflow in int arg1: ' + Op)
                else SetErr('overflow in int arg2: ' + Op);
    Exit;
  end;
  n := Trunc(v);
  Result := True;
end;

function BitNot(v: Extended): Extended;
var n2: LongInt;
begin
  if not ToIntN(v, '~', 2, n2) then Exit(0);
  Result := Extended(LongInt(not n2));
end;

function BitOp2(const Op: string; a, b: Extended): Extended;
var n1, n2, c: LongInt; u: UInt32;
begin
  Result := 0;
  if not ToIntN(a, Op, 1, n1) then Exit;
  if not ToIntN(b, Op, 2, n2) then Exit;
  case Op of
    '&' : Result := Extended(LongInt(n1 and n2));
    '|' : Result := Extended(LongInt(n1 or  n2));
    '^' : Result := Extended(LongInt(n1 xor n2));
    '<<': begin
            if n2 < 0 then begin SetErr('illegal arg2<0: <<'); Exit; end;
            if n2 > 31 then Result := 0
            else Result := Extended(LongInt(LongInt(n1) shl n2));
          end;
    '>>': begin
            if n2 < 0 then begin SetErr('illegal arg2<0: >>'); Exit; end;
            if n2 > 31 then Result := 0
            else Result := Extended(LongInt(UInt32(n1) shr n2));
          end;
    '>>>': begin
            if n2 < 0 then begin SetErr('illegal arg2<0: >>>'); Exit; end;
            if n2 > 31 then c := 31 else c := n2;
            u := UInt32(n1);
            if c = 0 then Result := Extended(LongInt(n1))
            else if n1 < 0 then
              Result := Extended(LongInt((u shr c) or ($FFFFFFFF shl (32 - c))))
            else
              Result := Extended(LongInt(u shr c));
          end;
  end;
end;

const
  MReal = 1.1e4932;                 // StdMath v1.06 'M' (max ~ extended)

{ _Ln / _Exp of StdMath v1.06 (_std.pas): error strings carry the
  function name separately, so we pass a suffix. }
function ChkLn(x: Extended; const Suf: string): Extended;
begin
  Result := 0;
  if x < 0 then begin SetErr('illegal arg<0: ' + Suf); Exit; end;
  if x < 1 / MReal then begin SetErr('overflow: ' + Suf); Exit; end;
  Result := Ln(x);
end;

function ChkExp(x: Extended; const Suf: string): Extended;
{ FPC `Exp` is correctly rounded at all magnitudes (<=1 ulp error) and is
  deliberately KEPT here: the v1.06 oracle's exp uses the Delphi 3 x87
  FLDL2E/F2XM1 reduction whose error grows with |x| (457 ulp at 11356).
  Do NOT replace with an oracle-emulating x87 sequence - see
  tests/accepted_differences.jsonl (fpc-exp-x87-reduction). }
begin
  Result := 0;
  if x > Ln(MReal) then begin SetErr('overflow: ' + Suf); Exit; end;
  if x < -Ln(MReal) then Result := 0
  else Result := Exp(x);
end;

{ _Mul of StdMath v1.06 (_std.pas) }
function ChkMul(a, b: Extended; const Suf: string): Extended;
var a1, a2: Extended;
begin
  Result := 1;
  if Err <> '' then Exit;
  a1 := Abs(a); a2 := Abs(b);
  if ((a2 > 1) and (a1 > MReal / a2)) or ((a1 > 1) and (a2 > MReal / a1)) then
  begin SetErr('overflow: ' + Suf); Exit; end;
  Result := a * b;
end;

{ _Div of StdMath v1.06 (_std.pas) }
function ChkDiv(a, b: Extended; const Suf: string): Extended;
var a1, a2: Extended;
begin
  Result := 1;
  if Err <> '' then Exit;
  a1 := Abs(a); a2 := Abs(b);
  if (a2 = 0) or ((a1 > 1) and (a1 / MReal > a2)) or
     ((a2 < 1) and (a1 > MReal * a2)) then
  begin SetErr('overflow: ' + Suf); Exit; end;
  Result := a / b;
end;

{ _Pow of StdMath v1.06: real-exponent path }
function PowR(x1, x2: Extended): Extended;
var t: Extended;
begin
  Result := 0;
  if Err <> '' then Exit;
  if x1 < 0 then begin SetErr('illegal arg1<0: **'); Exit; end;
  if (x1 < 1 / MReal) and (x2 >= 1) then begin Result := 0; Exit; end;
  t := ChkLn(x1, '**');
  if Err <> '' then Exit;
  t := ChkMul(x2, t, '**');
  if Err <> '' then Exit;
  Result := ChkExp(t, '**');
end;

function PowE(x, y: Extended): Extended;
var
  MaxRes: Extended;
  DoCheck: Boolean;
  i, n: LongInt;
  r: Extended;
begin
  Result := 0;
  if y = 0 then begin Result := 1; Exit; end;          // x2=0 -> 1
  if (x = 0) and (y > 0) then begin Result := 0; Exit; end;
  if IsRealX(y) or (Abs(y) > 1e4) then begin            // _PowR
    Result := PowR(x, y);
    if Err <> '' then Exit(0);
    if IsInfinite(Result) or IsNan(Result) then SetErr('overflow: **');
    Exit;
  end;
  // integer exponent: _PowI (linear multiply, overflow pre-checked)
  n := Trunc(y);
  DoCheck := Abs(x) > 1;
  if DoCheck then MaxRes := Abs(MReal / x) else MaxRes := 0;
  r := 1;
  if n < 0 then i := -n else i := n;
  while i > 0 do begin
    if DoCheck and (Abs(r) > MaxRes) then begin
      if n > 0 then begin SetErr('overflow: **'); Exit(0); end
      else begin Result := 0; Exit; end;
    end;
    r := r * x;
    Dec(i);
  end;
  if n < 0 then r := ChkDiv(1, r, '**');
  if Err <> '' then Exit(0);
  Result := r;
  if IsInfinite(Result) or IsNan(Result) then SetErr('overflow: **');
end;

function Fact(a: Extended): Extended;
var i: Integer; r: Extended;
begin
  if IsRealX(a) then begin SetErr('illegal real arg: fact'); Exit(0); end;
  if a < 0 then begin SetErr('illegal arg<0: fact'); Exit(0); end;
  if a > 1754 then begin SetErr('overflow: fact'); Exit(0); end;
  r := 1;
  for i := 2 to Trunc(a) do r := r * i;
  Result := r;
end;

{ ---- StdMath v1.06 _angle.pas: large-angle guard + Fix0 (<1e-18 -> 0) ---- }
const
  M_ASin1 = 1 - 1e-19;          // _ASin threshold
  M_TanH1 = 1000.0;             // _TanH threshold
  Ln2 = 0.69314718055994530942;

const
  MaxExtD: Extended = 1.189731495357231765e4932;   // true 80-bit extended max

{ 'e' constant: nearest-extended of true e (46-digit literal). Deliberately
  KEPT accurate: the v1.06 oracle stores e as the 19-digit literal
  2.718281828459045235 (E19), 1 ulp low, which makes oracle e*e round down
  (e**2 = ...022 vs exp(2) = ...023). Do NOT shorten to match the oracle -
  see tests/accepted_differences.jsonl (fpc-e-constant). }
function GetE: Extended;
const
  E0: Extended = 2.7182818284590452353602874713526624977572470937;
begin
  Result := E0;
end;

function AngleOK(x: Extended; const Suf: string): Boolean;
begin
  Result := Abs(x) <= 1e17;
  if not Result then SetErr('overflow in arg: ' + Suf);
end;

function F_Sin(x: Extended; const Suf: string): Extended;
begin
  Result := 0;
  if Err <> '' then Exit;
  if not AngleOK(x, Suf) then Exit;
  Result := Sin(x);
  if Abs(Result) < 1e-18 then Result := 0;
end;

function F_Cos(x: Extended; const Suf: string): Extended;
begin
  Result := 0;
  if Err <> '' then Exit;
  if not AngleOK(x, Suf) then Exit;
  Result := Cos(x);
  if Abs(Result) < 1e-18 then Result := 0;
end;

function F_Sqrt(x: Extended; const Suf: string): Extended;
begin
  Result := 0;
  if x < 0 then SetErr('illegal arg<0: ' + Suf)
  else Result := Sqrt(x);
end;

function F_ASin(x: Extended; const Suf: string): Extended;
begin
  Result := 0;
  if Abs(x) > 1 then begin SetErr('illegal |arg|>1: ' + Suf); Exit; end;
  if x > M_ASin1 then Result := Pi / 2
  else if x < -M_ASin1 then Result := -Pi / 2
  else Result := ArcTan(ChkDiv(x, Sqrt(1 - x * x), Suf));
end;

function F_ACos(x: Extended; const Suf: string): Extended;
begin
  Result := Pi / 2 - F_ASin(x, Suf);
end;

function F_ATanH(x: Extended; const Suf: string): Extended;
begin
  if Abs(x) > 1 then begin SetErr('illegal |arg|>1: ' + Suf); Exit(0); end;
  if x < 0 then Result := -F_ATanH(-x, Suf)
  else Result := ChkLn(ChkDiv(1 + x, 1 - x, Suf), Suf) / 2;
end;

function F_ACotH(x: Extended; const Suf: string): Extended;
begin
  if Abs(x) < 1 then begin SetErr('illegal |arg|<1: ' + Suf); Exit(0); end;
  if x < 0 then Result := -F_ACotH(-x, Suf)
  else Result := ChkLn(ChkDiv(x + 1, x - 1, Suf), Suf) / 2;
end;

function F_ASinH(x: Extended; const Suf: string): Extended;
begin
  if x < 0 then Result := -F_ASinH(-x, Suf)
  else if x > 1e10 then Result := Ln2 + Ln(x)
  else Result := Ln(x + Sqrt(x * x + 1));
end;

function F_ACosH(x: Extended; const Suf: string): Extended;
begin
  Result := 0;
  if x < 1 then begin SetErr('illegal arg<1: ' + Suf); Exit; end;
  if x > 1e10 then Result := Ln2 + Ln(x)
  else Result := Ln(x + Sqrt(x * x - 1));
end;

function F_SinH(x: Extended; const Suf: string): Extended;
var t1, t2: Extended;
begin
  t1 := ChkExp(x, Suf);
  t2 := ChkExp(-x, Suf);
  if Err <> '' then Exit(0);
  Result := (t1 - t2) / 2;
end;

function F_CosH(x: Extended; const Suf: string): Extended;
var t1, t2: Extended;
begin
  t1 := ChkExp(x, Suf);
  t2 := ChkExp(-x, Suf);
  if Err <> '' then Exit(0);
  Result := (t1 + t2) / 2;
end;

function F_TanH(x: Extended): Extended;
var y: Extended;
begin
  Result := 1;
  if x > M_TanH1 then Exit
  else if x < -M_TanH1 then Exit(-1);
  y := Exp(2 * x);
  Result := (y - 1) / (y + 1);
end;

function F_Round(x: Extended): Extended;
begin
  if x < 0 then Exit(-F_Round(-x));
  Result := Int(x);
  if Frac(x) >= 0.5 then Result := Result + 1;
end;

function F_Ceil(x: Extended): Extended;
begin
  Result := Int(x);
  if Frac(x) > 0 then Result := Result + 1;
end;

function F_Floor(x: Extended): Extended;
begin
  Result := Int(x);
  if Frac(x) < 0 then Result := Result - 1;
end;

function F_NormAngle(x, factor: Extended; const Suf: string): Extended;
begin
  Result := 0;
  if not AngleOK(x, Suf) then Exit;
  Result := x - Int(x / factor) * factor;
  if Result < 0 then Result := Result + factor;
end;

function CallStd(a: Extended; const Fn: string): Extended;
var t: Extended;
begin
  Result := 0;
  case Fn of
    'sin'  : Result := F_Sin(a, Fn);
    'cos'  : Result := F_Cos(a, Fn);
    'tan','tg': Result := ChkDiv(F_Sin(a, Fn), F_Cos(a, Fn), Fn);
    'cot','ctg': Result := ChkDiv(F_Cos(a, Fn), F_Sin(a, Fn), Fn);
    'sec'  : Result := ChkDiv(1, F_Cos(a, Fn), Fn);
    'csc'  : Result := ChkDiv(1, F_Sin(a, Fn), Fn);
    'asin' : Result := F_ASin(a, Fn);
    'acos' : Result := F_ACos(a, Fn);
    'atan' : Result := ArcTan(a);
    'acot' : Result := Pi / 2 - ArcTan(a);
    'asec' : begin t := ChkDiv(1, a, Fn); if Err = '' then Result := F_ACos(t, Fn); end;
    'acsc' : begin t := ChkDiv(1, a, Fn); if Err = '' then Result := F_ASin(t, Fn); end;
    'sinh','sh'  : Result := F_SinH(a, Fn);
    'cosh','ch'  : Result := F_CosH(a, Fn);
    'tanh','th'  : Result := F_TanH(a);
    'coth','cth' : Result := ChkDiv(1, F_TanH(a), Fn);
    'sech' : Result := ChkDiv(1, F_CosH(a, Fn), Fn);
    'csch' : Result := ChkDiv(1, F_SinH(a, Fn), Fn);
    'asinh': Result := F_ASinH(a, Fn);
    'acosh': Result := F_ACosH(a, Fn);
    'atanh': Result := F_ATanH(a, Fn);
    'acoth': Result := F_ACotH(a, Fn);
    'asech': begin t := ChkDiv(1, a, Fn); if Err = '' then Result := F_ACosH(t, Fn); end;
    'acsch': begin t := ChkDiv(1, a, Fn); if Err = '' then Result := F_ASinH(t, Fn); end;
    'exp'  : Result := ChkExp(a, Fn);
    'ln','log' : Result := ChkLn(a, Fn);
    'lg','log10' : begin t := ChkLn(a, Fn); if Err = '' then Result := t / Ln(10); end;
    'log2' : begin t := ChkLn(a, Fn); if Err = '' then Result := t / Ln(2); end;
    'sqr'  : Result := a * a;
    'sqrt' : Result := F_Sqrt(a, Fn);
    'fact' : Result := Fact(a);
    'abs'  : Result := Abs(a);
    'sign' : if a > 0 then Result := 1 else if a < 0 then Result := -1 else Result := 0;
    'int'  : Result := Int(a);
    'frac' : Result := Frac(a);
    'round': Result := F_Round(a);
    'ceil' : Result := F_Ceil(a);
    'floor': Result := F_Floor(a);
    'rad'  : Result := a * (Pi / 180);
    'deg'  : Result := ChkMul(a, 180 / Pi, Fn);
    'ndeg' : Result := F_NormAngle(a, 360, Fn);
    'nrad' : Result := F_NormAngle(a, 2 * Pi, Fn);
    else Result := 0; SetErr('unknown function: ' + Fn);
  end;
  if (IsInfinite(Result) or IsNan(Result)) and (Err = '') then SetErr('overflow: ' + Fn);
end;

function CallList(const Fn: string; const A: array of Extended): Extended;
var i, n: Integer; r, s: Extended; n1, n2: LongInt;
begin
  n := Length(A);
  case Fn of
    'log' : begin
              if n <> 2 then begin SetErr('invalid arg list: log'); Exit(0); end;
              Result := ChkDiv(ChkLn(A[1], Fn), ChkLn(A[0], Fn), Fn);
            end;
    'gcd' : begin
              for i := 0 to n - 1 do begin
                if IsRealX(A[i]) then begin SetErr('illegal real arg: gcd'); Exit(0); end;
                if not IsDWordX(A[i]) then begin SetErr('overflow in int arg: gcd'); Exit(0); end;
              end;
              n1 := Trunc(A[0]);
              for i := 1 to n - 1 do begin
                n2 := Abs(Trunc(A[i]));
                n1 := Abs(n1);
                while n2 <> 0 do begin
                  r := n1 mod n2; n1 := n2; n2 := Trunc(r);
                end;
              end;
              Result := Abs(n1);
            end;
    'lcm' : begin
              for i := 0 to n - 1 do begin
                if IsRealX(A[i]) then begin SetErr('illegal real arg: lcm'); Exit(0); end;
                if not IsDWordX(A[i]) then begin SetErr('overflow in int arg: lcm'); Exit(0); end;
              end;
              r := Abs(A[0]);
              for i := 1 to n - 1 do begin
                if (r = 0) or (A[i] = 0) then begin r := 0; Continue; end;
                n1 := Trunc(r);
                n2 := Abs(Trunc(A[i]));
                while n2 <> 0 do begin
                  s := n1 mod n2; n1 := n2; n2 := Trunc(s);
                end;
                r := Abs((Trunc(r) div n1) * Trunc(A[i]));
              end;
              Result := r;
            end;
    'poly': begin
              // poly(x, a0, a1, ...) = a0 + a1*x + a2*x**2 + ...
              Result := A[n - 1];
              for i := n - 1 downto 2 do
                Result := Result * A[0] + A[i - 1];
            end;
    'sum' : begin Result := 0; for i := 0 to n - 1 do Result := Result + A[i]; end;
    'prod','mul' : begin Result := 1; for i := 0 to n - 1 do Result := Result * A[i]; end;
    'avg' : begin Result := 0; for i := 0 to n - 1 do Result := Result + A[i]; Result := Result / n; end;
    'sumsq': begin Result := 0; for i := 0 to n - 1 do Result := Result + A[i] * A[i]; end;
    'gavg': begin
              for i := 0 to n - 1 do if A[i] < 0 then begin SetErr('illegal arg<0: gavg'); Exit(0); end;
              Result := 1; for i := 0 to n - 1 do Result := Result * A[i];
              Result := PowE(Result, 1 / Extended(n));
            end;
    'havg': begin
              for i := 0 to n - 1 do if A[i] < 0 then begin SetErr('illegal arg<0: havg'); Exit(0); end;
              Result := 0;
              for i := 0 to n - 1 do Result := Result + 1 / A[i];
              Result := n / Result;
            end;
    'qavg','rms': begin
              Result := 0; for i := 0 to n - 1 do Result := Result + A[i] * A[i];
              Result := Sqrt(Result / n);
            end;
    'norm': begin
              Result := 0; for i := 0 to n - 1 do Result := Result + A[i] * A[i];
              Result := Sqrt(Result);
            end;
    'vart': begin
              s := 0; for i := 0 to n - 1 do s := s + A[i];
              s := s / n;
              Result := 0; for i := 0 to n - 1 do begin
                r := A[i] - s;
                Result := Result + r * r;
              end;
            end;
    'varp','var' : begin
              s := 0; for i := 0 to n - 1 do s := s + A[i];
              s := s / n;
              Result := 0; for i := 0 to n - 1 do begin
                r := A[i] - s;
                Result := Result + r * r;
              end;
              Result := Result / n;
            end;
    'vars': begin
              s := 0; for i := 0 to n - 1 do s := s + A[i];
              s := s / n;
              Result := 0; for i := 0 to n - 1 do begin
                r := A[i] - s;
                Result := Result + r * r;
              end;
              Result := Result / (n - 1);
            end;
    'std' : begin
              s := 0; for i := 0 to n - 1 do s := s + A[i];
              s := s / n;
              Result := 0; for i := 0 to n - 1 do begin
                r := A[i] - s;
                Result := Result + r * r;
              end;
              Result := Sqrt(Result / (n - 1));
            end;
    'stdp': begin
              s := 0; for i := 0 to n - 1 do s := s + A[i];
              s := s / n;
              Result := 0; for i := 0 to n - 1 do begin
                r := A[i] - s;
                Result := Result + r * r;
              end;
              Result := Sqrt(Result / n);
            end;
    'min' : begin Result := A[0]; for i := 1 to n - 1 do if A[i] < Result then Result := A[i]; end;
    'max' : begin Result := A[0]; for i := 1 to n - 1 do if A[i] > Result then Result := A[i]; end;
    else Result := 0; SetErr('unknown list function: ' + Fn);
  end;
  if (IsInfinite(Result) or IsNan(Result)) and (Err = '') then SetErr('overflow: ' + Fn);
end;

function IsListFunc(const N: string): Boolean;
begin
  Result := (N = 'sum') or (N = 'sumsq') or (N = 'prod') or (N = 'mul') or
            (N = 'avg') or (N = 'gavg') or (N = 'havg') or (N = 'qavg') or
            (N = 'rms') or (N = 'norm') or (N = 'vart') or (N = 'varp') or
            (N = 'var') or (N = 'vars') or (N = 'std') or (N = 'stdp') or
            (N = 'min') or (N = 'max') or (N = 'gcd') or (N = 'lcm') or
            (N = 'log') or (N = 'poly');
end;

function IsBuiltinName(const N: string): Boolean;
const B: array[0..72] of string =
  ('sin','cos','tan','tg','cot','ctg','sec','csc',
   'asin','acos','atan','acot','asec','acsc',
   'sinh','sh','cosh','ch','tanh','th','coth','cth','sech','csch',
   'asinh','acosh','atanh','acoth','asech','acsch',
   'exp','ln','log','lg','log10','log2','sqr','sqrt','fact','abs','sign',
   'int','frac','round','ceil','floor','rad','deg','ndeg','nrad',
   'sum','sumsq','prod','mul','avg','gavg','havg','qavg','rms','norm',
   'vart','varp','var','vars','std','stdp','min','max','gcd','lcm','poly',
   'pi','e');
var i: Integer;
begin
  Result := False;
  for i := Low(B) to High(B) do
    if B[i] = N then begin Result := True; Exit; end;
end;

function LookupVar(const N: string; out V: Extended): Boolean;
var i: Integer;
begin
  for i := High(LocalVars) downto 0 do
    if CompareText(LocalVars[i].Name, N) = 0 then begin V := LocalVars[i].Val; Exit(True); end;
  for i := 0 to DefCount - 1 do
    if (not Defs[i].IsFunc) and (CompareText(Defs[i].Name, N) = 0) then begin V := Defs[i].Val; Exit(True); end;
  if N = 'pi' then begin V := Pi; Exit(True); end;
  if N = 'e'  then begin V := GetE; Exit(True); end;
  Result := False;
end;

function FindUserFunc(const N: string; WantArgs: Integer; out Idx: Integer): Boolean;
var i: Integer;
begin
  for i := 0 to DefCount - 1 do
    if Defs[i].IsFunc and (Defs[i].NumArgs = WantArgs) and (CompareText(Defs[i].Name, N) = 0) then
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

  Result := CallList(Name, Copy(Args, 0, n));
end;

function Precedence(const Op: string): Integer;
begin
  case Op of
    '**'                  : Result := 60;
    '*','/','//','%'      : Result := 50;
    '+','-'               : Result := 40;
    '&','|','^','&&','||','^^','<<','>>','>>>' : Result := 30;
    '=','==','<>','!=','<','>','<=','>=' : Result := 20;
    else Result := 0;
  end;
end;

function PeekOp(out Op: string): Boolean;
var c1: Char;
begin
  c1 := PeekC;
  case c1 of
    '*': if PeekC2 = '*' then Op := '**' else Op := '*';
    '/': if PeekC2 = '/' then Op := '//' else Op := '/';
    '<': if PeekC2 = '=' then Op := '<='
         else if PeekC2 = '>' then Op := '<>'
         else if PeekC2 = '<' then Op := '<<' else Op := '<';
    '>': if PeekC2 = '=' then Op := '>='
         else if (PeekC2 = '>') and (PeekC3 = '>') then Op := '>>>'
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
var n1, n2: LongInt;
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
            if not ToIntN(a, '//', 1, n1) then Exit(0);
            if not ToIntN(b, '//', 2, n2) then Exit(0);
            if n2 = 0 then begin SetErr('illegal arg2=0: //'); Exit(0); end;
            Result := Extended(n1 div n2);
           end;
    '%'  : begin
            if not ToIntN(a, '%', 1, n1) then Exit(0);
            if not ToIntN(b, '%', 2, n2) then Exit(0);
            if n2 = 0 then begin SetErr('illegal arg2=0: %'); Exit(0); end;
            Result := Extended(n1 mod n2);
           end;
    '&','|','^','<<','>>','>>>' : Result := BitOp2(Op, a, b);
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
  d: Extended;
  E: Int64;
  fracDigits: Integer;
  signe: Integer;
  had: Boolean;
  C: Char;
  Tok: string;
begin
  Result := False;
  V := 0;
  if P > Length(S) then Exit;
  C := PeekC;
  if not ((C in ['0'..'9']) or (C = DecimalSep)) then Exit;

  Start := P;
  d := 0; had := False;
  { integer part }
  while (P <= Length(S)) and (S[P] in ['0'..'9']) do begin
    d := d * 10 + (Ord(S[P]) - 48);
    Inc(P); had := True;
  end;
  { fraction part }
  fracDigits := 0;
  if (P <= Length(S)) and (S[P] = DecimalSep) then begin
    Inc(P);
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do begin
      d := d * 10 + (Ord(S[P]) - 48);
      Inc(P); had := True; Inc(fracDigits);
    end;
  end;
  if not had then begin Result := False; Exit; end;

  { exponent suffix }
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
      Result := True;
      Exit;
    end;
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do begin
      if E < 1000000000 then E := E * 10 + (Ord(S[P]) - 48);
      Inc(P);
    end;
    E := E * signe;
  end;

  Tok := Copy(S, Start, P - Start);
  { v1.06 rejects |written exponent| >= 5000 at parse time }
  if (E >= 5000) or (E <= -5000) then begin
    SetErr('invalid expression: ' + Tok);
    Result := True;
    Exit;
  end;

  { scale integer mantissa by 10^(E - fracDigits) }
  if (E - fracDigits) <> 0 then
    V := ScalePow10(d, Integer(E - fracDigits))
  else
    V := d;

  { literal magnitude above the true extended maximum is a parse error }
  if (d <> 0) and (IsInfinite(V) or (V > MaxExtD)) then begin
    SetErr('invalid expression: ' + Tok);
    Result := True;
    Exit;
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
    Name := LowerCase(Name);       // v1.06: identifiers are case-insensitive
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
  Result := a;
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
    Result := a;
    if Err <> '' then Exit;
  end;
end;

procedure AddDef(const Name: string; IsFunc: Boolean; NumArgs: Integer;
                 const ArgNames: array of string; const Body: string; Val: Extended;
                 const RawDecl: string);
var i, j: Integer;
begin
  if DefCount >= MaxDefs then begin SetErr('too many definitions'); Exit; end;
  // replace existing
  for i := 0 to DefCount - 1 do
    if CompareText(Defs[i].Name, Name) = 0 then begin
      Defs[i].IsFunc := IsFunc;
      Defs[i].NumArgs := NumArgs;
      Defs[i].Body := Body;
      Defs[i].Val := Val;
      Defs[i].Raw := RawDecl;
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
  Defs[i].Raw := RawDecl;
  for j := 0 to NumArgs - 1 do Defs[i].ArgNames[j] := ArgNames[j];
end;

{ Top-level: [var=val, ...] expr  or  [f(args)=body, ...] expr }
function ParseTopLevel: Extended;
var
  Name, Body, RawDecl: string;
  ArgNames: array[0..63] of string;
  NumArgs: Integer;
  Save: Integer;
  DeclStart: Integer;
  DepthScan: Integer;
  V: Extended;
  i: Integer;
  LooksLikeDef: Boolean;
begin
  Result := 0;
  LocalVars := nil;
  NumArgs := 0;
  for i := 0 to High(ArgNames) do ArgNames[i] := '';
  while True do begin
    SkipWS;
    Save := P;
    DeclStart := P;

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
        RawDecl := Trim(Copy(S, DeclStart, P - DeclStart));
        AddDef(Name, True, NumArgs, ArgNames, Body, 0, RawDecl);
      end else begin
        V := ParseExpr(0);
        if Err <> '' then Exit;
        RawDecl := Trim(Copy(S, DeclStart, P - DeclStart));
        AddDef(Name, False, 0, ArgNames, '', V, RawDecl);
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
var i, p: Integer;
begin
  p := Pos('.', s);
  if p = 0 then begin Result := s; Exit; end;   // integer-looking: keep digits
  i := Length(s);
  while (i > p) and (s[i] = '0') do Dec(i);
  if i = p then Dec(i);
  Result := Copy(s, 1, i);
end;

{ scientific with an 18-significant-digit mantissa and a sign+4-digit
  exponent (FPC FloatToStrF caps ffExponent mantissas at 17 sig digits) }
function FmtSci18(v: Extended): string;
var
  av, s, p: Extended;
  e0, i, a, b: Integer;
  P18: Extended;
  mant, es: string;
begin
  Result := '';
  if v < 0 then begin Result := '-'; av := -v; end else av := v;
  e0 := Trunc(Log10(av));
  p := 1;
  if e0 > 0 then begin
    { 10^18 is exactly representable in Extended: chunk the exponent so the
      power-of-ten is built with ~e0/18 (<= 275) roundings, not e0 of them. }
    P18 := 1e18;
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
  mant := FloatToStrF(s, ffFixed, 0, 17);
  if (Length(mant) >= 2) and (mant[1] = '1') and (mant[2] = '0') then begin
    Inc(e0);
    p := p * 10;
    s := av / p;
    mant := FloatToStrF(s, ffFixed, 0, 17);
  end;
  es := IntToStr(Abs(e0));
  while Length(es) < 4 do es := '0' + es;
  if e0 < 0 then es := '-' + es else es := '+' + es;
  Result := Result + mant + 'E' + es;
end;

function IsNegZero(v: Extended): Boolean;
begin
  Result := (v = 0) and (1 / v < 0);
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
  { exact integer within +/-1e18 -> plain integer digits }
  if Frac0(v) and (v >= -1e18) and (v <= 1e18) then begin
    if IsNegZero(v) then begin Result := '-0'; Exit; end;
    i64 := Round(v);
    Result := IntToStr(i64);
    Exit;
  end;
  if Abs(v) <= 1e18 then
    Result := FmtFixed(v)
  else
    Result := FmtSci18(v);
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
  The original shows the result as a 32-bit value (8 hex / 32 bin /
  11 oct digits, full width), with unsigned interpretation when
  UnsignedHex is on.  When the integer part does not fit in a signed
  32-bit value the original prints 'overflow' instead of a number. }

function Trunc32(v: Extended): LongWord;
var i: Int64;
begin
  if IsNan(v) or IsInfinite(v) then begin Result := 0; Exit; end;
  i := Trunc(v);
  Result := LongWord(i and $FFFFFFFF);
end;

function Int32RangeOK(v: Extended): Boolean;
begin
  Result := False;
  if IsNan(v) or IsInfinite(v) then Exit;
  Result := (Int(v) >= -2147483648.0) and (Int(v) <= 2147483647.0);
end;

function FmtHex32(v: Extended): string;
begin
  if not Int32RangeOK(v) then begin Result := 'overflow'; Exit; end;
  if UnsignedHex then
    Result := IntToHex(Trunc32(v), 8)
  else
    Result := IntToHex(LongInt(Trunc32(v)), 8);
end;

function FmtBin32(v: Extended): string;
var u: LongWord; i: Integer;
begin
  if not Int32RangeOK(v) then begin Result := 'overflow'; Exit; end;
  u := Trunc32(v);
  Result := '';
  for i := 31 downto 0 do
    Result := Result + Chr(Ord('0') + ((u shr i) and 1));
end;

function FmtOct32(v: Extended): string;
var u: LongWord; i: Integer;
begin
  if not Int32RangeOK(v) then begin Result := 'overflow'; Exit; end;
  u := Trunc32(v);
  Result := '';
  for i := 10 downto 0 do
    Result := Result + Chr(Ord('0') + ((u shr (3 * i)) and 7));
end;

function FmtExp(v: Extended): string;
var
  av, s, p, q: Extended;
  e0, i, a, b: Integer;
  P18: Extended;
  mant, es, sg: string;
begin
  if IsNan(v) or IsInfinite(v) then begin Result := 'ERROR'; Exit; end;
  if v = 0 then begin Result := FloatToStrF(v, ffExponent, 18, 4); Exit; end;
  sg := '';
  if v < 0 then begin sg := '-'; av := -v; end else av := v;
  e0 := Trunc(Log10(av));
  q := 1;
  if e0 <> 0 then begin
    a := Abs(e0) div 18;
    b := Abs(e0) mod 18;
    P18 := 1e18;
    for i := 1 to a do q := q * P18;
    for i := 1 to b do q := q * 10;
  end;
  if e0 >= 0 then p := q else p := 1 / q;
  s := av / p;
  while s >= 10 do begin Inc(e0); if e0 >= 0 then p := p * 10 else p := p / 10; s := av / p; end;
  while s < 1 do begin Dec(e0); p := p / 10; s := av / p; end;
  mant := FloatToStrF(s, ffFixed, 0, 17);
  if (Length(mant) >= 2) and (mant[1] = '1') and (mant[2] = '0') then begin
    Inc(e0);
    p := p * 10;
    s := av / p;
    mant := FloatToStrF(s, ffFixed, 0, 17);
  end;
  es := IntToStr(Abs(e0));
  while Length(es) < 4 do es := '0' + es;
  if e0 < 0 then es := '-' + es else es := '+' + es;
  Result := sg + mant + 'E' + es;
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
  if Defs[i].Raw <> '' then begin Result := Defs[i].Raw; Exit; end;
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

procedure MoveDef(i: Integer; Dir: Integer);
var
  k: Integer;
  Tmp: TUserDef;
begin
  if (i < 0) or (i >= DefCount) then Exit;
  k := i + Dir;
  if (k < 0) or (k >= DefCount) then Exit;
  Tmp := Defs[i]; Defs[i] := Defs[k]; Defs[k] := Tmp;
end;

procedure ClearDefs;
begin
  SetLength(Defs, 0);
  DefCount := 0;
end;

function LoadDefsFile(const AFileName: string): Integer;
var
  f: Text;
  Line: string;
  m: string;
begin
  Result := 0;
  if not FileExists(AFileName) then Exit;
  AssignFile(f, AFileName);
  {$I-}
  Reset(f);
  {$I+}
  if IOResult <> 0 then Exit;
  while not Eof(f) do begin
    ReadLn(f, Line);
    Line := Trim(Line);
    if Line = '' then Continue;
    if Line[1] = ';' then Continue;      // comment
    m := AddDefDecl(Line);
    if m = '' then Inc(Result);
  end;
  CloseFile(f);
end;

function SaveDefsFile(const AFileName: string): Boolean;
var
  f: Text;
  i: Integer;
begin
  AssignFile(f, AFileName);
  {$I-}
  Rewrite(f);
  {$I+}
  if IOResult <> 0 then Exit(False);
  for i := 0 to DefCount - 1 do
    WriteLn(f, DefDecl(i));
  CloseFile(f);
  Result := True;
end;

end.
