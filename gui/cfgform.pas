unit cfgform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Config, ecwengine, defform;

type
  TCfgForm = class(TForm)
  private
    PageControl: TPageControl;
    TabInt, TabDefs: TTabSheet;
    // interface tab
    GroupGeneral, GroupCopy, GroupDisplay: TGroupBox;
    OptAutoCalc, OptSmallDlg, OptOnTop, OptStatus: TCheckBox;
    OptCopyMode0, OptCopyMode1: TRadioButton;
    OptCopyAsIs: TCheckBox;
    OptRAlign, OptNoLead0, OptNoTrail0: TCheckBox;
    LabelPrec: TLabel;
    OptPrec: TEdit;
    BtnOK, BtnCancel: TButton;
    // definitions tab
    DefList: TListView;
    BtnAdd, BtnEdit, BtnDelete: TButton;
    procedure BuildControls;
    procedure LoadCfg;
    procedure SaveCfg;
    procedure RefreshDefs;
    procedure BtnOKClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
    procedure BtnAddClick(Sender: TObject);
    procedure BtnEditClick(Sender: TObject);
    procedure BtnDeleteClick(Sender: TObject);
    procedure DefListDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  CfgFrm: TCfgForm;

implementation

constructor TCfgForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'Calculator configuration';
  ClientWidth := 420;
  ClientHeight := 320;
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  BuildControls;
end;

procedure TCfgForm.BuildControls;
var
  B: TButton;
begin
  PageControl := TPageControl.Create(Self); PageControl.Parent := Self;
  PageControl.Left := 8; PageControl.Top := 8; PageControl.Width := 404;
  PageControl.Height := 260;

  { -------- Interface tab -------- }
  TabInt := PageControl.AddTabSheet;
  TabInt.Caption := 'Interface';

  GroupGeneral := TGroupBox.Create(Self); GroupGeneral.Parent := TabInt;
  GroupGeneral.Left := 8; GroupGeneral.Top := 8; GroupGeneral.Width := 380;
  GroupGeneral.Height := 92; GroupGeneral.Caption := ' General settings ';

  OptAutoCalc := TCheckBox.Create(Self); OptAutoCalc.Parent := GroupGeneral;
  OptAutoCalc.Left := 8; OptAutoCalc.Top := 18; OptAutoCalc.Width := 360;
  OptAutoCalc.Caption := '&Automatic calculations (disable ''Evaluate'' button)';

  OptSmallDlg := TCheckBox.Create(Self); OptSmallDlg.Parent := GroupGeneral;
  OptSmallDlg.Left := 8; OptSmallDlg.Top := 40; OptSmallDlg.Width := 360;
  OptSmallDlg.Caption := '&Small dialog (show simplified dialog form)';

  OptOnTop := TCheckBox.Create(Self); OptOnTop.Parent := GroupGeneral;
  OptOnTop.Left := 8; OptOnTop.Top := 62; OptOnTop.Width := 360;
  OptOnTop.Caption := 'Always stay &on top';

  OptStatus := TCheckBox.Create(Self); OptStatus.Parent := GroupGeneral;
  OptStatus.Left := 8; OptStatus.Top := 84; OptStatus.Width := 360;
  OptStatus.Caption := 'S&how error status';

  GroupCopy := TGroupBox.Create(Self); GroupCopy.Parent := TabInt;
  GroupCopy.Left := 8; GroupCopy.Top := 108; GroupCopy.Width := 380;
  GroupCopy.Height := 76; GroupCopy.Caption := ' ''Copy'' button behaviour ';

  OptCopyMode0 := TRadioButton.Create(Self); OptCopyMode0.Parent := GroupCopy;
  OptCopyMode0.Left := 8; OptCopyMode0.Top := 18; OptCopyMode0.Width := 360;
  OptCopyMode0.Caption := 'Copy result into &edit field';

  OptCopyMode1 := TRadioButton.Create(Self); OptCopyMode1.Parent := GroupCopy;
  OptCopyMode1.Left := 8; OptCopyMode1.Top := 40; OptCopyMode1.Width := 360;
  OptCopyMode1.Caption := 'Copy result to &clipboard';

  OptCopyAsIs := TCheckBox.Create(Self); OptCopyAsIs.Parent := GroupCopy;
  OptCopyAsIs.Left := 8; OptCopyAsIs.Top := 62; OptCopyAsIs.Width := 360;
  OptCopyAsIs.Caption := 'Cop&y as is';

  GroupDisplay := TGroupBox.Create(Self); GroupDisplay.Parent := TabInt;
  GroupDisplay.Left := 8; GroupDisplay.Top := 192; GroupDisplay.Width := 380;
  GroupDisplay.Height := 64; GroupDisplay.Caption := ' Results display ';

  LabelPrec := TLabel.Create(Self); LabelPrec.Parent := GroupDisplay;
  LabelPrec.Left := 8; LabelPrec.Top := 22;
  LabelPrec.Caption := '&Digits after decimal point in dec/exp results';

  OptPrec := TEdit.Create(Self); OptPrec.Parent := GroupDisplay;
  OptPrec.Left := 300; OptPrec.Top := 18; OptPrec.Width := 40;
  OptPrec.Text := '17';

  OptRAlign := TCheckBox.Create(Self); OptRAlign.Parent := GroupDisplay;
  OptRAlign.Left := 8; OptRAlign.Top := 44; OptRAlign.Width := 190;
  OptRAlign.Caption := 'Show results &right aligned';

  OptNoLead0 := TCheckBox.Create(Self); OptNoLead0.Parent := GroupDisplay;
  OptNoLead0.Left := 200; OptNoLead0.Top := 44; OptNoLead0.Width := 180;
  OptNoLead0.Caption := 'hex/bin/oct without &leading zeros';

  OptNoTrail0 := TCheckBox.Create(Self); OptNoTrail0.Parent := GroupDisplay;
  OptNoTrail0.Left := 8; OptNoTrail0.Top := 66; OptNoTrail0.Width := 360;
  OptNoTrail0.Caption := 'Show decimal result without &trailing zeros';

  { -------- Definitions tab -------- }
  TabDefs := PageControl.AddTabSheet;
  TabDefs.Caption := 'User variables/functions';

  DefList := TListView.Create(Self); DefList.Parent := TabDefs;
  DefList.Left := 8; DefList.Top := 8; DefList.Width := 290;
  DefList.Height := 220;
  DefList.ViewStyle := vsReport;
  DefList.Columns.Add.Caption := 'Declaration';
  DefList.Columns.Add.Caption := 'Expression';
  DefList.Columns[0].Width := 110;
  DefList.Columns[1].Width := 170;
  DefList.ReadOnly := True; DefList.RowSelect := True;
  DefList.OnDblClick := @DefListDblClick;

  BtnAdd := TButton.Create(Self); BtnAdd.Parent := TabDefs;
  BtnAdd.Left := 306; BtnAdd.Top := 8; BtnAdd.Width := 90;
  BtnAdd.Caption := '&Add...';
  BtnAdd.OnClick := @BtnAddClick;

  BtnEdit := TButton.Create(Self); BtnEdit.Parent := TabDefs;
  BtnEdit.Left := 306; BtnEdit.Top := 40; BtnEdit.Width := 90;
  BtnEdit.Caption := '&Edit';
  BtnEdit.OnClick := @BtnEditClick;

  BtnDelete := TButton.Create(Self); BtnDelete.Parent := TabDefs;
  BtnDelete.Left := 306; BtnDelete.Top := 72; BtnDelete.Width := 90;
  BtnDelete.Caption := '&Delete';
  BtnDelete.OnClick := @BtnDeleteClick;

  { -------- buttons -------- }
  BtnOK := TButton.Create(Self); BtnOK.Parent := Self;
  BtnOK.Left := 240; BtnOK.Top := 280; BtnOK.Width := 80;
  BtnOK.Caption := 'OK'; BtnOK.Default := True;
  BtnOK.OnClick := @BtnOKClick;

  BtnCancel := TButton.Create(Self); BtnCancel.Parent := Self;
  BtnCancel.Left := 330; BtnCancel.Top := 280; BtnCancel.Width := 80;
  BtnCancel.Caption := 'Cancel'; BtnCancel.ModalResult := mrCancel;
  BtnCancel.OnClick := @BtnCancelClick;

  B := TButton.Create(Self); B.Parent := Self;
  B.Left := 240; B.Top := 320; B.Width := 80; B.Visible := False;
  B.Free; // placeholder removed
end;

procedure TCfgForm.LoadCfg;
begin
  OptAutoCalc.Checked := cfg.AutoCalc;
  OptSmallDlg.Checked := cfg.SmallDialog;
  OptOnTop.Checked := cfg.StayOnTop;
  OptStatus.Checked := cfg.ShowErrorStatus;
  OptCopyMode1.Checked := cfg.CopyToClipboard;
  OptCopyMode0.Checked := not cfg.CopyToClipboard;
  OptCopyAsIs.Checked := cfg.CopyAsIs;
  OptPrec.Text := IntToStr(cfg.Prec);
  OptRAlign.Checked := cfg.RAlign;
  OptNoLead0.Checked := cfg.NoLead0;
  OptNoTrail0.Checked := cfg.NoTrail0;
  RefreshDefs;
end;

procedure TCfgForm.SaveCfg;
begin
  cfg.AutoCalc := OptAutoCalc.Checked;
  cfg.SmallDialog := OptSmallDlg.Checked;
  cfg.StayOnTop := OptOnTop.Checked;
  cfg.ShowErrorStatus := OptStatus.Checked;
  cfg.CopyToClipboard := OptCopyMode1.Checked;
  cfg.CopyAsIs := OptCopyAsIs.Checked;
  cfg.Prec := StrToIntDef(OptPrec.Text, 17);
  cfg.RAlign := OptRAlign.Checked;
  cfg.NoLead0 := OptNoLead0.Checked;
  cfg.NoTrail0 := OptNoTrail0.Checked;
end;

procedure TCfgForm.RefreshDefs;
var
  i: Integer;
  it: TListItem;
begin
  DefList.Items.Clear;
  for i := 0 to NumDefs - 1 do begin
    it := DefList.Items.Add;
    it.Caption := DefName(i);
    it.SubItems.Add(DefDecl(i));
  end;
end;

procedure TCfgForm.BtnOKClick(Sender: TObject);
begin
  SaveCfg;
  SaveConfig;
  ApplyConfig;
  ModalResult := mrOK;
end;

procedure TCfgForm.BtnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TCfgForm.BtnAddClick(Sender: TObject);
var
  f: TDefForm;
  decl: string;
  m: string;
begin
  f := TDefForm.Create(Self);
  try
    if f.ShowModal = mrOK then begin
      decl := Trim(f.DeclText);
      if decl <> '' then begin
        m := AddDefDecl(decl);
        if m <> '' then
          ShowMessage('Invalid definition: ' + m)
        else
          RefreshDefs;
      end;
    end;
  finally
    f.Free;
  end;
end;

procedure TCfgForm.BtnEditClick(Sender: TObject);
var
  f: TDefForm;
  idx: Integer;
  m: string;
begin
  idx := DefList.Selected.Index;
  if (idx < 0) or (idx >= NumDefs) then begin ShowMessage('Select a definition first'); Exit; end;
  f := TDefForm.Create(Self);
  try
    f.DeclText := DefDecl(idx);
    if f.ShowModal = mrOK then begin
      m := AddDefDecl(Trim(f.DeclText));
      if m <> '' then ShowMessage('Invalid definition: ' + m)
      else begin
        DeleteDef(idx);
        RefreshDefs;
      end;
    end;
  finally
    f.Free;
  end;
end;

procedure TCfgForm.BtnDeleteClick(Sender: TObject);
var
  idx: Integer;
begin
  idx := DefList.Selected.Index;
  if (idx < 0) or (idx >= NumDefs) then begin ShowMessage('Select a definition first'); Exit; end;
  DeleteDef(idx);
  RefreshDefs;
end;

procedure TCfgForm.DefListDblClick(Sender: TObject);
begin
  BtnEditClick(Sender);
end;

end.
