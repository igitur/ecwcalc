unit tinyform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Clipbrd,
  ecwengine, Config, cfgform;

type
  TTinyForm = class(TForm)
    EditOut: TEdit;
    EditIn: TComboBox;
    ButtonCopy, ButtonEval, ButtonSetup, ButtonFmt: TButton;
    procedure EvalClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure SetupClick(Sender: TObject);
    procedure FmtClick(Sender: TObject);
    procedure InChange(Sender: TObject);
  private
    procedure DoEval;
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

{$R *.lfm}

{ The tiny form mirrors the original TTinyForm: a compact calculator with
  Symbol-font buttons (copy / evaluate / setup / format). }

constructor TTinyForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
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
