unit tinyform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Clipbrd,
  ecwengine, Config, cfgform;

type
  TTinyForm = class(TForm)
  private
    EditOut: TEdit;
    EditIn: TComboBox;
    ButtonCopy, ButtonEval, ButtonSetup, ButtonFmt: TButton;
    procedure BuildControls;
    procedure DoEval;
    procedure EvalClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure SetupClick(Sender: TObject);
    procedure FmtClick(Sender: TObject);
    procedure InChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

{ The tiny form mirrors the original TTinyForm: a compact calculator with
  Symbol-font buttons (copy / evaluate / setup / format). }

constructor TTinyForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'Calculator';
  ClientWidth := 213;
  ClientHeight := 50;
  Position := poScreenCenter;
  Font.Name := 'MS Sans Serif';
  Font.Size := 8;
  BuildControls;
end;

procedure TTinyForm.BuildControls;
begin
  EditOut := TEdit.Create(Self); EditOut.Parent := Self;
  EditOut.Left := 4; EditOut.Top := 4; EditOut.Width := 120;
  EditOut.Font.Name := 'Courier New'; EditOut.Font.Size := 9;
  EditOut.ReadOnly := True; EditOut.ParentColor := True;
  EditOut.Text := '0';

  EditIn := TComboBox.Create(Self); EditIn.Parent := Self;
  EditIn.Left := 4; EditIn.Top := 26; EditIn.Width := 120;
  EditIn.DropDownCount := 11;
  EditIn.OnChange := @InChange;

  ButtonCopy := TButton.Create(Self); ButtonCopy.Parent := Self;
  ButtonCopy.Left := 128; ButtonCopy.Top := 4; ButtonCopy.Width := 40;
  ButtonCopy.Caption := #172;   { Symbol-font 'copy' glyph }
  ButtonCopy.OnClick := @CopyClick;

  ButtonEval := TButton.Create(Self); ButtonEval.Parent := Self;
  ButtonEval.Left := 172; ButtonEval.Top := 4; ButtonEval.Width := 37;
  ButtonEval.Caption := '=';
  ButtonEval.Font.Name := 'Courier New';
  ButtonEval.OnClick := @EvalClick;

  ButtonSetup := TButton.Create(Self); ButtonSetup.Parent := Self;
  ButtonSetup.Left := 128; ButtonSetup.Top := 26; ButtonSetup.Width := 40;
  ButtonSetup.Caption := #188;   { Symbol-font 'setup' glyph }
  ButtonSetup.Font.Style := [fsBold];
  ButtonSetup.OnClick := @SetupClick;

  ButtonFmt := TButton.Create(Self); ButtonFmt.Parent := Self;
  ButtonFmt.Left := 172; ButtonFmt.Top := 26; ButtonFmt.Width := 37;
  ButtonFmt.Caption := '#';
  ButtonFmt.OnClick := @FmtClick;
end;

procedure TTinyForm.InChange(Sender: TObject);
begin
  if cfg.AutoCalc then DoEval;
end;

procedure TTinyForm.DoEval;
var
  v: Extended;
  M: string;
  s: string;
begin
  s := Trim(EditIn.Text);
  if s = '' then Exit;
  if EvalExpr(s, v, M) then
    EditOut.Text := FmtNumber(v)
  else
    EditOut.Text := 'Error: ' + M;
  if EditIn.Items.IndexOf(s) < 0 then
    EditIn.Items.Insert(0, s);
  while EditIn.Items.Count > 11 do
    EditIn.Items.Delete(EditIn.Items.Count - 1);
end;

procedure TTinyForm.EvalClick(Sender: TObject);
begin
  DoEval;
end;

procedure TTinyForm.CopyClick(Sender: TObject);
begin
  Clipboard.AsText := EditOut.Text;
end;

procedure TTinyForm.SetupClick(Sender: TObject);
begin
  if CfgFrm = nil then
    Application.CreateForm(TCfgForm, CfgFrm);
  CfgFrm.ShowModal;
end;

procedure TTinyForm.FmtClick(Sender: TObject);
begin
  // toggle through Dec/Hex/Bin/Oct/Exp display of the current result
  if cfg.NoLead0 then begin
    cfg.NoLead0 := False;
    EditOut.Text := FmtNumber(0);
  end else
    EditOut.Text := 'fmt';
end;

end.
