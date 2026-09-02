unit shellswitch;

{$mode objfpc}{$H+}

{ Applies newly-saved configuration to the visible calculator shell and swaps
  between the full (TCalcForm) and simplified (TTinyForm) shells when the
  "Small dialog" option was toggled in the Setup dialog. }

interface

uses Forms;

// Call after the Setup dialog closed with mrOK, passing the shell form
// (TCalcForm or TTinyForm) that opened it.
procedure AfterSetupClosed(AForm: TForm);

implementation

uses
  Classes, StdCtrls, mainform, tinyform, cfgform, Config;

function ComboOf(AForm: TForm): TComboBox;
begin
  if AForm is TCalcForm then Result := TCalcForm(AForm).Combo
  else if AForm is TTinyForm then Result := TTinyForm(AForm).Combo
  else Result := nil;
end;

procedure BindClearHistory(AForm: TForm);
begin
  if AForm is TCalcForm then
    CfgFrm.OnClearHistory := @TCalcForm(AForm).ClearHistory
  else if AForm is TTinyForm then
    CfgFrm.OnClearHistory := @TTinyForm(AForm).ClearHistory;
end;

procedure MigrateCombo(Source: TComboBox; Dest: TForm);
var
  tb: TComboBox;
  i: Integer;
begin
  tb := ComboOf(Dest);
  if (Source = nil) or (tb = nil) then Exit;
  tb.Items.BeginUpdate;
  try
    tb.Items.Clear;
    for i := 0 to Source.Items.Count - 1 do
      tb.Items.Add(Source.Items[i]);
  finally
    tb.Items.EndUpdate;
  end;
  tb.Text := Source.Text;
end;

procedure AfterSetupClosed(AForm: TForm);
var
  active: TForm;
  src: TComboBox;
  IsTiny, WantTiny: Boolean;
begin
  if not ((AForm is TCalcForm) or (AForm is TTinyForm)) then Exit;
  active := AForm;
  IsTiny := AForm is TTinyForm;
  WantTiny := cfg.SmallDialog;
  src := ComboOf(AForm);

  if WantTiny <> IsTiny then begin
    if WantTiny then begin
      if TinyFrm = nil then Application.CreateForm(TTinyForm, TinyFrm);
      active := TinyFrm;
    end else begin
      if CalcForm = nil then Application.CreateForm(TCalcForm, CalcForm);
      active := CalcForm;
    end;
    active.Hide;
    MigrateCombo(src, active);
    AForm.Hide;
  end;

  if active is TCalcForm then TCalcForm(active).ApplyUiConfig
  else if active is TTinyForm then TTinyForm(active).ApplyUiConfig;
  BindClearHistory(active);

  if active <> AForm then begin
    active.Show;
    active.BringToFront;
  end;
end;

end.
