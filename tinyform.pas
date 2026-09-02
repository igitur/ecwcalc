unit tinyform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Clipbrd,
  ecwengine, Config, cfgform;

type
  TTinyForm = class(TForm)
    Bevel1: TBevel;
    EditIn: TComboBox;
    EditOut: TEdit;
    ButtonEval: TButton;
    ButtonCopy: TButton;
    ButtonSetup: TButton;
    ButtonFmt: TButton;
    procedure EvalClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure SetupClick(Sender: TObject);
    procedure FmtClick(Sender: TObject);
    procedure InChange(Sender: TObject);
  private
    HaveVal: Boolean;
    LastVal: Extended;
    FmtIdx: Integer;               // 0=dec 1=hex 2=bin 3=oct 4=exp
    procedure DoEval;
    procedure ShowResult;
    procedure ShellClose(Sender: TObject; var CloseAction: TCloseAction);
  public
    constructor Create(AOwner: TComponent); override;
    procedure ApplyUiConfig;
    function  Combo: TComboBox;
    procedure ClearHistory(Sender: TObject);
  end;

var
  TinyFrm: TTinyForm;

implementation

{$R *.lfm}

uses
  viewfmt,
  shellswitch;

constructor TTinyForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  OnClose := @ShellClose;
  ApplyUiConfig;
end;

procedure TTinyForm.ShellClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  Application.Terminate;
end;

{ Compact single-line calculator: input combo on top, result edit below.
  '=' evaluates, '#' cycles the display format, '¬' copies the result,
  '¼' opens the configuration dialog. }

procedure TTinyForm.ApplyUiConfig;
begin
  if cfg.StayOnTop then FormStyle := fsStayOnTop else FormStyle := fsNormal;
  ButtonEval.Enabled := not cfg.AutoCalc;
  if cfg.RAlign then
    EditOut.Alignment := taRightJustify
  else
    EditOut.Alignment := taLeftJustify;
  if Trim(EditIn.Text) <> '' then DoEval;
end;

function TTinyForm.Combo: TComboBox;
begin
  Result := EditIn;
end;

procedure TTinyForm.DoEval;
var
  v: Extended;
  M: string;
  s: string;
begin
  s := Trim(EditIn.Text);
  if s = '' then Exit;
  if not EvalExpr(s, v, M) then begin
    EditOut.Text := 'Error: ' + M;
    HaveVal := False;
    Exit;
  end;
  LastVal := v;
  HaveVal := True;
  ShowResult;
end;

procedure TTinyForm.ShowResult;
begin
  if not HaveVal then Exit;
  case FmtIdx of
    1: EditOut.Text := RowHex32(LastVal, cfg.NoLead0);
    2: EditOut.Text := RowBin32(LastVal, cfg.NoLead0);
    3: EditOut.Text := RowOct32(LastVal, cfg.NoLead0);
    4: EditOut.Text := RowExp(LastVal, cfg.Prec, cfg.NoTrail0);
  else
    EditOut.Text := RowDec(LastVal, cfg.Prec, cfg.NoTrail0);
  end;
end;

procedure TTinyForm.InChange(Sender: TObject);
begin
  if cfg.AutoCalc then DoEval;
end;

procedure TTinyForm.EvalClick(Sender: TObject);
var
  s: string;
begin
  DoEval;
  if cfg.HistUpdE then begin
    s := Trim(EditIn.Text);
    if (s <> '') and (EditIn.Items.IndexOf(s) < 0) then
      EditIn.Items.Insert(0, s);
    while EditIn.Items.Count > 11 do
      EditIn.Items.Delete(EditIn.Items.Count - 1);
  end;
end;

procedure TTinyForm.CopyClick(Sender: TObject);
var
  s: string;
begin
  if not HaveVal then Exit;
  if cfg.CopyToClipboard then
    Clipboard.AsText := EditOut.Text
  else
    EditIn.Text := EditOut.Text;
  if cfg.HistUpdC then begin
    s := Trim(EditIn.Text);
    if (s <> '') and (EditIn.Items.IndexOf(s) < 0) then
      EditIn.Items.Insert(0, s);
    while EditIn.Items.Count > 11 do
      EditIn.Items.Delete(EditIn.Items.Count - 1);
  end;
end;

procedure TTinyForm.SetupClick(Sender: TObject);
begin
  if CfgFrm = nil then
    Application.CreateForm(TCfgForm, CfgFrm);
  CfgFrm.OnClearHistory := @ClearHistory;
  if CfgFrm.ShowModal = mrOK then
    AfterSetupClosed(Self);
end;

procedure TTinyForm.FmtClick(Sender: TObject);
begin
  FmtIdx := (FmtIdx + 1) mod 5;
  if HaveVal then ShowResult;
end;

procedure TTinyForm.ClearHistory(Sender: TObject);
begin
  EditIn.Items.Clear;
end;

end.
