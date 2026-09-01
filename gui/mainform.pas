unit mainform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Clipbrd,
  Dialogs, ecwengine, cfgform, defform, tinyform;

type
  TCalcForm = class(TForm)
  private
    EditInput: TComboBox;
    LabelResDec, LabelResHex, LabelResBin, LabelResOct, LabelResExp: TEdit;
    LabelResError: TLabel;
    RadioDec, RadioHex, RadioBin, RadioOct, RadioExp: TRadioButton;
    ButtonEval, ButtonCopy, ButtonSetup, ButtonHelp, ButtonClose: TButton;
    LastClickTick: QWord;
    procedure BuildControls;
    procedure ButtonEvalClick(Sender: TObject);
    procedure ButtonCopyClick(Sender: TObject);
    procedure ButtonSetupClick(Sender: TObject);
    procedure ButtonHelpClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
    procedure EditInputChange(Sender: TObject);
    procedure RadioMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure DoEval;
    function  SelectedFormat: string;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateDefsList;
    procedure ClearHistory(Sender: TObject);
    property ResDec: TEdit read LabelResDec;
    property ResHex: TEdit read LabelResHex;
    property ResBin: TEdit read LabelResBin;
    property ResOct: TEdit read LabelResOct;
    property ResExp: TEdit read LabelResExp;
    property ResErr: TLabel read LabelResError;
    property InputCombo: TComboBox read EditInput;
  end;

var
  CalcForm: TCalcForm;

implementation

uses Config;   // global config record

{ ============ layout constants (from the original DFM, pixels at 96dpi) ============ }

constructor TCalcForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'Calculator';
  ClientWidth := 436;
  ClientHeight := 236;
  Position := poScreenCenter;
  Font.Name := 'MS Sans Serif';
  Font.Size := 8;
  KeyPreview := True;
  BuildControls;
end;

procedure TCalcForm.BuildControls;
var
  L: TLabel;
  B: TBevel;
  i: Integer;
begin
  // Expression label
  L := TLabel.Create(Self); L.Parent := Self;
  L.Left := 14; L.Top := 12; L.Caption := 'E&xpression:';

  // Input combo with history
  EditInput := TComboBox.Create(Self); EditInput.Parent := Self;
  EditInput.Left := 14; EditInput.Top := 28; EditInput.Width := 340;
  EditInput.DropDownCount := 11;
  EditInput.OnChange := @EditInputChange;

  // Evaluate button
  ButtonEval := TButton.Create(Self); ButtonEval.Parent := Self;
  ButtonEval.Left := 370; ButtonEval.Top := 26; ButtonEval.Width := 60;
  ButtonEval.Caption := 'E&valuate';
  ButtonEval.OnClick := @ButtonEvalClick;

  // divider
  B := TBevel.Create(Self); B.Parent := Self;
  B.Left := 6; B.Top := 49; B.Width := 356; B.Height := 9;
  B.Shape := bsBottomLine;

  // Copy-as label
  L := TLabel.Create(Self); L.Parent := Self;
  L.Left := 14; L.Top := 64; L.Caption := 'Copy as:';

  // Format radios (dbl-click = copy that format)
  RadioDec := TRadioButton.Create(Self); RadioDec.Parent := Self;
  RadioDec.Left := 16; RadioDec.Top := 81; RadioDec.Caption := '&Dec';
  RadioDec.Checked := True; RadioDec.OnMouseDown := @RadioMouseDown;

  RadioHex := TRadioButton.Create(Self); RadioHex.Parent := Self;
  RadioHex.Left := 16; RadioHex.Top := 101; RadioHex.Caption := '&Hex';
  RadioHex.OnMouseDown := @RadioMouseDown;

  RadioBin := TRadioButton.Create(Self); RadioBin.Parent := Self;
  RadioBin.Left := 16; RadioBin.Top := 121; RadioBin.Caption := '&Bin';
  RadioBin.OnMouseDown := @RadioMouseDown;

  RadioOct := TRadioButton.Create(Self); RadioOct.Parent := Self;
  RadioOct.Left := 16; RadioOct.Top := 141; RadioOct.Caption := '&Oct';
  RadioOct.OnMouseDown := @RadioMouseDown;

  RadioExp := TRadioButton.Create(Self); RadioExp.Parent := Self;
  RadioExp.Left := 16; RadioExp.Top := 161; RadioExp.Caption := '&Exp';
  RadioExp.OnMouseDown := @RadioMouseDown;

  // Result fields (read-only Courier, borderless, like the original)
  LabelResDec := TEdit.Create(Self); LabelResDec.Parent := Self;
  LabelResDec.Left := 68; LabelResDec.Top := 82; LabelResDec.Width := 289;
  LabelResDec.Font.Name := 'Courier New'; LabelResDec.Font.Size := 9;
  LabelResDec.BorderStyle := bsNone; LabelResDec.ReadOnly := True;
  LabelResDec.ParentColor := True; LabelResDec.Text := '0';

  LabelResHex := TEdit.Create(Self); LabelResHex.Parent := Self;
  LabelResHex.Left := 68; LabelResHex.Top := 102; LabelResHex.Width := 289;
  LabelResHex.Font.Name := 'Courier New'; LabelResHex.Font.Size := 9;
  LabelResHex.BorderStyle := bsNone; LabelResHex.ReadOnly := True;
  LabelResHex.ParentColor := True; LabelResHex.Text := '00000000';

  LabelResBin := TEdit.Create(Self); LabelResBin.Parent := Self;
  LabelResBin.Left := 68; LabelResBin.Top := 122; LabelResBin.Width := 289;
  LabelResBin.Font.Name := 'Courier New'; LabelResBin.Font.Size := 9;
  LabelResBin.BorderStyle := bsNone; LabelResBin.ReadOnly := True;
  LabelResBin.ParentColor := True;
  LabelResBin.Text := '00000000000000000000000000000000';

  LabelResOct := TEdit.Create(Self); LabelResOct.Parent := Self;
  LabelResOct.Left := 68; LabelResOct.Top := 142; LabelResOct.Width := 289;
  LabelResOct.Font.Name := 'Courier New'; LabelResOct.Font.Size := 9;
  LabelResOct.BorderStyle := bsNone; LabelResOct.ReadOnly := True;
  LabelResOct.ParentColor := True; LabelResOct.Text := '00000000000';

  LabelResExp := TEdit.Create(Self); LabelResExp.Parent := Self;
  LabelResExp.Left := 68; LabelResExp.Top := 162; LabelResExp.Width := 289;
  LabelResExp.Font.Name := 'Courier New'; LabelResExp.Font.Size := 9;
  LabelResExp.BorderStyle := bsNone; LabelResExp.ReadOnly := True;
  LabelResExp.ParentColor := True;
  LabelResExp.Text := '0.00000000000000000E+0000';

  // right-side buttons
  ButtonCopy := TButton.Create(Self); ButtonCopy.Parent := Self;
  ButtonCopy.Left := 370; ButtonCopy.Top := 56; ButtonCopy.Width := 60;
  ButtonCopy.Caption := '&Copy';
  ButtonCopy.OnClick := @ButtonCopyClick;

  ButtonSetup := TButton.Create(Self); ButtonSetup.Parent := Self;
  ButtonSetup.Left := 370; ButtonSetup.Top := 86; ButtonSetup.Width := 60;
  ButtonSetup.Caption := '&Setup...';
  ButtonSetup.OnClick := @ButtonSetupClick;

  ButtonHelp := TButton.Create(Self); ButtonHelp.Parent := Self;
  ButtonHelp.Left := 370; ButtonHelp.Top := 116; ButtonHelp.Width := 60;
  ButtonHelp.Caption := 'Help';
  ButtonHelp.OnClick := @ButtonHelpClick;

  ButtonClose := TButton.Create(Self); ButtonClose.Parent := Self;
  ButtonClose.Left := 370; ButtonClose.Top := 146; ButtonClose.Width := 60;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  // divider + error status
  B := TBevel.Create(Self); B.Parent := Self;
  B.Left := 6; B.Top := 176; B.Width := 356; B.Height := 9;
  B.Shape := bsBottomLine;

  L := TLabel.Create(Self); L.Parent := Self;
  L.Left := 14; L.Top := 191; L.Caption := 'Error status:';

  LabelResError := TLabel.Create(Self); LabelResError.Parent := Self;
  LabelResError.Left := 14; LabelResError.Top := 207; LabelResError.Width := 340;
  LabelResError.AutoSize := False;
  LabelResError.Caption := 'ok';

  for i := 0 to 0 do ; // silence hint
end;

{ ============ behaviour ============ }

function TCalcForm.SelectedFormat: string;
begin
  if RadioHex.Checked then Result := 'hex'
  else if RadioBin.Checked then Result := 'bin'
  else if RadioOct.Checked then Result := 'oct'
  else if RadioExp.Checked then Result := 'exp'
  else Result := 'dec';
end;

procedure TCalcForm.DoEval;
var
  v: Extended;
  M: string;
  s: string;
begin
  s := Trim(EditInput.Text);
  if s = '' then Exit;
  if not EvalExpr(s, v, M) then begin
    LabelResDec.Text := 'Error';
    LabelResHex.Text := 'Error';
    LabelResBin.Text := 'Error';
    LabelResOct.Text := 'Error';
    LabelResExp.Text := 'Error';
    if cfg.ShowErrorStatus then LabelResError.Caption := M else LabelResError.Caption := '';
    Exit;
  end;
  LabelResDec.Text := FmtNumber(v);
  LabelResHex.Text := FmtHex32(v);
  LabelResBin.Text := FmtBin32(v);
  LabelResOct.Text := FmtOct32(v);
  LabelResExp.Text := FmtExp(v);
  LabelResError.Caption := 'ok';
end;

procedure TCalcForm.ButtonEvalClick(Sender: TObject);
var
  s: string;
begin
  DoEval;
  if cfg.HistUpdE then begin
    s := Trim(EditInput.Text);
    if (s <> '') and (EditInput.Items.IndexOf(s) < 0) then
      EditInput.Items.Insert(0, s);
    while EditInput.Items.Count > 11 do
      EditInput.Items.Delete(EditInput.Items.Count - 1);
  end;
end;

procedure TCalcForm.EditInputChange(Sender: TObject);
begin
  if cfg.AutoCalc then DoEval;
end;

procedure TCalcForm.ButtonCopyClick(Sender: TObject);
var
  t, s: string;
begin
  case SelectedFormat of
    'hex': t := LabelResHex.Text;
    'bin': t := LabelResBin.Text;
    'oct': t := LabelResOct.Text;
    'exp': t := LabelResExp.Text;
    else  t := LabelResDec.Text;
  end;
  if cfg.CopyToClipboard then
    Clipboard.AsText := t
  else
    EditInput.Text := t;
  if cfg.HistUpdC then begin
    s := Trim(EditInput.Text);
    if (s <> '') and (EditInput.Items.IndexOf(s) < 0) then
      EditInput.Items.Insert(0, s);
    while EditInput.Items.Count > 11 do
      EditInput.Items.Delete(EditInput.Items.Count - 1);
  end;
end;

procedure TCalcForm.RadioMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  now: QWord;
begin
  now := GetTickCount64;
  if (now - LastClickTick) < 400 then begin
    TRadioButton(Sender).Checked := True;
    ButtonCopyClick(Sender);
    LastClickTick := 0;
  end else
    LastClickTick := now;
end;

procedure TCalcForm.ButtonSetupClick(Sender: TObject);
begin
  if CfgFrm = nil then begin
    Application.CreateForm(TCfgForm, CfgFrm);
    CfgFrm.OnClearHistory := @ClearHistory;
  end;
  CfgFrm.ShowModal;
end;

procedure TCalcForm.ButtonHelpClick(Sender: TObject);
begin
  ShowMessage(
    'ECW Expression Calculator'#13#10#13#10 +
    'Type an expression such as 2+3*4 or sin(pi/2) and press Evaluate.'#13#10 +
    'Results are shown in Dec, Hex, Bin, Oct and Exp formats.'#13#10 +
    'Copy as selects the format used by the Copy button.'#13#10#13#10 +
    'Operators: + - * / ** // % << >> & | ^ ~ !  (see README)');
end;

procedure TCalcForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TCalcForm.UpdateDefsList;
begin
  // the definitions tab refreshes itself when the config dialog opens
end;

procedure TCalcForm.ClearHistory(Sender: TObject);
begin
  EditInput.Items.Clear;
end;

end.
