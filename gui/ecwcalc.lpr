program ecwcalc;

{$mode objfpc}{$H+}
{$IFDEF WINDOWS}{$APPTYPE GUI}{$ENDIF}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, SysUtils, ecwengine, Config, mainform, cfgform, defform, tinyform;

begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Initialize;
  InitEngine;
  LoadConfig;
  Application.CreateForm(TCalcForm, CalcForm);
  Application.Run;
end.
