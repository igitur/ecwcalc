unit Config;

{$mode objfpc}{$H+}

interface

uses SysUtils, IniFiles, ecwengine;

type
  TAppConfig = record
    AutoCalc: Boolean;        // automatic calculations (disable Evaluate)
    SmallDialog: Boolean;     // show simplified dialog form
    StayOnTop: Boolean;       // always stay on top
    ShowErrorStatus: Boolean; // show error status
    CopyToClipboard: Boolean; // 1=clipboard, 0=edit field
    CopyAsIs: Boolean;        // copy as is
    Prec: Integer;            // digits after decimal point in dec/exp results
    RAlign: Boolean;          // right-aligned results
    NoLead0: Boolean;         // hex/bin/oct without leading zeros
    NoTrail0: Boolean;        // decimal without trailing zeros
    UnsignedHex: Boolean;
    SepMode: Integer;         // 0: '.' ',', 1: ',' ';', 2: '.' ';'
    Loaded: Boolean;
  end;

var
  cfg: TAppConfig;

procedure LoadConfig;
procedure SaveConfig;
procedure ApplyConfig;

implementation

function CfgPath: string;
begin
  Result := ChangeFileExt(ParamStr(0), '.ini');
end;

procedure LoadConfig;
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(CfgPath);
  try
    cfg.AutoCalc := ini.ReadBool('Main', 'AutoCalc', True);
    cfg.SmallDialog := ini.ReadBool('Main', 'SmallDialog', False);
    cfg.StayOnTop := ini.ReadBool('Main', 'StayOnTop', False);
    cfg.ShowErrorStatus := ini.ReadBool('Main', 'ShowErrorStatus', True);
    cfg.CopyToClipboard := ini.ReadBool('Main', 'CopyToClipboard', True);
    cfg.CopyAsIs := ini.ReadBool('Main', 'CopyAsIs', False);
    cfg.Prec := ini.ReadInteger('Main', 'Prec', 17);
    cfg.RAlign := ini.ReadBool('Main', 'RAlign', False);
    cfg.NoLead0 := ini.ReadBool('Main', 'NoLead0', False);
    cfg.NoTrail0 := ini.ReadBool('Main', 'NoTrail0', False);
    cfg.UnsignedHex := ini.ReadBool('Main', 'UnsignedHex', False);
    cfg.SepMode := ini.ReadInteger('Main', 'SepMode', 0);
  finally
    ini.Free;
  end;
  cfg.Loaded := True;
  ApplyConfig;
end;

procedure SaveConfig;
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(CfgPath);
  try
    ini.WriteBool('Main', 'AutoCalc', cfg.AutoCalc);
    ini.WriteBool('Main', 'SmallDialog', cfg.SmallDialog);
    ini.WriteBool('Main', 'StayOnTop', cfg.StayOnTop);
    ini.WriteBool('Main', 'ShowErrorStatus', cfg.ShowErrorStatus);
    ini.WriteBool('Main', 'CopyToClipboard', cfg.CopyToClipboard);
    ini.WriteBool('Main', 'CopyAsIs', cfg.CopyAsIs);
    ini.WriteInteger('Main', 'Prec', cfg.Prec);
    ini.WriteBool('Main', 'RAlign', cfg.RAlign);
    ini.WriteBool('Main', 'NoLead0', cfg.NoLead0);
    ini.WriteBool('Main', 'NoTrail0', cfg.NoTrail0);
    ini.WriteBool('Main', 'UnsignedHex', cfg.UnsignedHex);
    ini.WriteInteger('Main', 'SepMode', cfg.SepMode);
  finally
    ini.Free;
  end;
end;

procedure ApplyConfig;
begin
  SetUnsignedHex(cfg.UnsignedHex);
  SetSepMode(cfg.SepMode);
end;

end.
