unit mainform;

{$mode objfpc}{$H+}
{$HINTS OFF}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Clipbrd,
  Dialogs, ecwengine, cfgform;

type
  TCalcForm = class(TForm)
    EditInput: TComboBox;
    LabelResDec, LabelResHex, LabelResBin, LabelResOct, LabelResExp: TEdit;
    LabelResError: TLabel;
    RadioDec, RadioHex, RadioBin, RadioOct, RadioExp: TRadioButton;
    ButtonEval, ButtonCopy, ButtonSetup, ButtonHelp, ButtonClose: TButton;
    BevelTop, BevelBottom: TBevel;
    procedure ButtonEvalClick(Sender: TObject);
    procedure ButtonCopyClick(Sender: TObject);
    procedure ButtonSetupClick(Sender: TObject);
    procedure ButtonHelpClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
    procedure EditInputChange(Sender: TObject);
    procedure RadioMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  private
    LastClickTick: QWord;
    procedure DoEval;
    function  SelectedFormat: string;
    procedure ShellClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor Create(AOwner: TComponent); override;
    procedure ApplyUiConfig;
    function  Combo: TComboBox;
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

{$R *.lfm}

uses
  Config,          // global config record
  LCLType,
  numfmt,
  shellswitch;

constructor TCalcForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  EditInput.OnKeyDown := @InputKeyDown;
  OnClose := @ShellClose;
  ApplyUiConfig;
end;

procedure TCalcForm.ShellClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  Application.Terminate;
end;

{ ============ display options ============ }

procedure TCalcForm.ApplyUiConfig;
begin
  if cfg.StayOnTop then FormStyle := fsStayOnTop else FormStyle := fsNormal;
  ButtonEval.Visible := not cfg.AutoCalc;
  if cfg.RAlign then begin
    LabelResDec.Alignment := taRightJustify;
    LabelResHex.Alignment := taRightJustify;
    LabelResBin.Alignment := taRightJustify;
    LabelResOct.Alignment := taRightJustify;
    LabelResExp.Alignment := taRightJustify;
  end else begin
    LabelResDec.Alignment := taLeftJustify;
    LabelResHex.Alignment := taLeftJustify;
    LabelResBin.Alignment := taLeftJustify;
    LabelResOct.Alignment := taLeftJustify;
    LabelResExp.Alignment := taLeftJustify;
  end;
  if Trim(EditInput.Text) <> '' then DoEval;
end;

{ ============ behaviour ============ }

function TCalcForm.Combo: TComboBox;
begin
  Result := EditInput;
end;

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
  LabelResDec.Text := numfmt.Format(v, AutoOpt(cfg.Prec, cfg.NoTrail0));
  LabelResHex.Text := numfmt.Format(v, RadixOpt(nmHex, cfg.NoLead0, cfg.UnsignedHex));
  LabelResBin.Text := numfmt.Format(v, RadixOpt(nmBin, cfg.NoLead0, cfg.UnsignedHex));
  LabelResOct.Text := numfmt.Format(v, RadixOpt(nmOct, cfg.NoLead0, cfg.UnsignedHex));
  LabelResExp.Text := numfmt.Format(v, ExpOpt(cfg.Prec));
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

procedure TCalcForm.InputKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_RETURN then begin
    Key := 0;
    ButtonEvalClick(Sender);   // Enter == Evaluate (works while the button is hidden)
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
  if CfgFrm = nil then
    Application.CreateForm(TCfgForm, CfgFrm);
  CfgFrm.OnClearHistory := @ClearHistory;
  if CfgFrm.ShowModal = mrOK then
    AfterSetupClosed(Self);
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
