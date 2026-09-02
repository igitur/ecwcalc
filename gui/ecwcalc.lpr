program ecwcalc;

{$mode objfpc}{$H+}
{$IFDEF WINDOWS}{$APPTYPE GUI}{$ENDIF}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, LCLType, SysUtils,
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  {$IFDEF UNIX}BaseUnix, Unix,{$ENDIF}
  ecwengine, Config, mainform, cfgform, defform, tinyform;

{$IFDEF WINDOWS}
var
  InstanceMutex: THandle;
function AlreadyRunning: Boolean;
begin
  InstanceMutex := CreateMutexW(nil, False, 'ECWCalc_SingleInstance');
  Result := (InstanceMutex <> 0) and (GetLastError = ERROR_ALREADY_EXISTS);
end;
{$ELSE}
var
  LockFd: Integer = -1;
function AlreadyRunning: Boolean;
const
  LockPath: string = '/tmp/ecwcalc.lock';
begin
  LockFd := FpOpen(PChar(LockPath), O_WRONLY or O_CREAT, 438);
  if LockFd < 0 then begin
    Result := False; // cannot determine; allow start
    Exit;
  end;
  if FpFlock(LockFd, LOCK_EX or LOCK_NB) = 0 then
    Result := False  // we hold the lock; we are the only instance
  else
    Result := True;  // another instance holds it
end;
{$ENDIF}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  InitEngine;
  LoadConfig;
  if (not cfg.AllowMul) and AlreadyRunning then begin
    Application.MessageBox(
      'Another instance of ECW Expression Calculator is already running.',
      'ECW Expression Calculator',
      MB_OK + MB_ICONINFORMATION);
    Halt;
  end;
  if cfg.SmallDialog then
    Application.CreateForm(TTinyForm, TinyFrm)   // small (simplified) form
  else
    Application.CreateForm(TCalcForm, CalcForm);  // full form
  Application.Run;
end.
