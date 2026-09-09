unit tinyform;

{$mode objfpc}{$H+}
{$HINTS OFF}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  Clipbrd, Menus,
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
    FmtIdx: Integer;               // 0=auto(dec/exp) 1=dec 2=hex 3=bin 4=oct 5=exp
    FmtMenu: TPopupMenu;
    procedure DoEval;
    procedure ShowResult;
    procedure ShellClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure BuildFmtMenu;
    procedure FmtMenuClick(Sender: TObject);
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
  BuildFmtMenu;
  ApplyUiConfig;
end;

procedure TTinyForm.ShellClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  Application.Terminate;
end;

{ Compact single-line calculator: input combo on top, result edit below.
  '=' evaluates, '#' opens the display-format menu, '¬' copies the result,
  '¼' opens the configuration dialog. }

procedure TTinyForm.BuildFmtMenu;
const
  Labels: array[0..5] of string =
    ('Auto (dec/exp)', 'Decimal', 'Hexadecimal', 'Binary', 'Octal',
     'Exponential');
var
  i: Integer;
  mi: TMenuItem;
begin
  FmtMenu := TPopupMenu.Create(Self);
  for i := 0 to 5 do begin
    mi := TMenuItem.Create(FmtMenu);
    mi.Caption := Labels[i];
    mi.Tag := i;
    mi.RadioItem := True;
    mi.GroupIndex := 1;
    mi.OnClick := @FmtMenuClick;
    FmtMenu.Items.Add(mi);
  end;
end;

procedure TTinyForm.FmtMenuClick(Sender: TObject);
begin
  FmtIdx := (Sender as TMenuItem).Tag;
  if HaveVal then ShowResult;
end;

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
    1: EditOut.Text := RowDecFixed(LastVal, cfg.Prec, cfg.NoTrail0);
    2: EditOut.Text := RowHex32(LastVal, cfg.NoLead0);
    3: EditOut.Text := RowBin32(LastVal, cfg.NoLead0);
    4: EditOut.Text := RowOct32(LastVal, cfg.NoLead0);
    5: EditOut.Text := RowExp(LastVal, cfg.Prec, cfg.NoTrail0);
  else
    EditOut.Text := RowDec(LastVal, cfg.Prec, cfg.NoTrail0);   // Auto (dec/exp)
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
var
  i: Integer;
  pt: TPoint;
begin
  if FmtMenu = nil then BuildFmtMenu;
  for i := 0 to FmtMenu.Items.Count - 1 do
    FmtMenu.Items[i].Checked := (FmtMenu.Items[i].Tag = FmtIdx);
  pt := ButtonFmt.ClientToScreen(Point(0, ButtonFmt.Height));
  FmtMenu.PopUp(pt.X, pt.Y);
end;

procedure TTinyForm.ClearHistory(Sender: TObject);
begin
  EditIn.Items.Clear;
end;

end.
