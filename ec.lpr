{ ============================================================================
  ECW Expression Calculator — command-line front end (uses ecwengine)
  Reverse-engineered from ecw.exe (v1.04-era, Delphi 3 RTL) and verified
  live against the original console engine (ec.exe v1.03b3) under Wine.

  Usage:  ./ec "2+3*4"
          ./ec --unsigned "--sep=1" "1,5+2,5"
          ./ec                        (interactive, prompt '> ')
  ============================================================================ }

program ec;

{$mode objfpc}{$H+}

uses
  SysUtils, ecwengine;

procedure RunOne(const Expr: string);
var
  v: Extended;
  M: string;
begin
  if Trim(Expr) = '' then Exit;
  if EvalExpr(Expr, v, M) then
    Writeln(FmtNumber(v))
  else
    Writeln('ERROR: ', M);
end;

var
  i: Integer;
  Arg, S: string;
  Interactive: Boolean;
begin
  InitEngine;
  i := 1;
  Interactive := False;
  while i <= ParamCount do begin
    Arg := ParamStr(i);
    if Arg = '--unsigned' then SetUnsignedHex(True)
    else if Copy(Arg, 1, 6) = '--sep=' then SetSepMode(StrToIntDef(Copy(Arg, 7, 1), 0))
    else if Arg = '-i' then Interactive := True
    else begin
      RunOne(Arg);
      Exit;
    end;
    Inc(i);
  end;

  if Interactive or (ParamCount = 0) then begin
    Interactive := True;
    while not Eof do begin
      Write('> ');
      ReadLn(S);
      if Trim(S) = '' then Continue;
      RunOne(Trim(S));
    end;
  end;
end.
