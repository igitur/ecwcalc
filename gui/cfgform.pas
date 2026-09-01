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
    procedure FormShow(Sender: TObject);
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
  ClientWidth := 436;
  ClientHeight := 346;
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  OnShow := @FormShow;
  BuildControls;
end;

procedure TCfgForm.FormShow(Sender: TObject);
var
  Off: Integer;
  Bmp: TBitmap;
begin
  // LCL positions TGroupBox children in the client area BELOW the caption
  // (win32 offset = TMHeight+3; gtk2/3 similar); the original Delphi DFM
  // positions them from the frame's top edge. Shift each group's children
  // up by the caption offset so the layout matches the original.
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font := Font;
    Off := Bmp.Canvas.TextHeight('Ag') + 3;
  finally
    Bmp.Free;
  end;
  if Off > 0 then begin
    OptAutoCalc.Top := 16 - Off;
    OptSmallDlg.Top := 34 - Off;
    OptStatus.Top   := 52 - Off;
    OptOnTop.Top    := 70 - Off;
  end;
  if Off > 0 then begin
    OptCopyMode0.Top := 16 - Off;
    OptCopyMode1.Top := 34 - Off;
    OptCopyAsIs.Top  := 16 - Off;
  end;
  if Off > 0 then begin
    OptRAlign.Top   := 16 - Off;
    OptNoLead0.Top  := 34 - Off;
    OptNoTrail0.Top := 52 - Off;
    OptPrec.Top     := 72 - Off;
    LabelPrec.Top   := 74 - Off;
  end;
end;

procedure TCfgForm.BuildControls;
var
  B: TButton;
begin
  PageControl := TPageControl.Create(Self); PageControl.Parent := Self;
  PageControl.Left := 6; PageControl.Top := 6; PageControl.Width := 423;
  PageControl.Height := 303;

  { -------- Interface tab -------- }
  TabInt := PageControl.AddTabSheet;
  TabInt.Caption := 'Interface';

  GroupGeneral := TGroupBox.Create(Self); GroupGeneral.Parent := TabInt;
  GroupGeneral.Left := 8; GroupGeneral.Top := 4;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  GroupGeneral.Width := 380; // GTK fonts are wider than MS Sans Serif
  {$ELSE}
  GroupGeneral.Width := 340; // original DFM geometry
  {$ENDIF}
  GroupGeneral.Height := 94; GroupGeneral.Caption := ' General settings ';

  OptAutoCalc := TCheckBox.Create(Self); OptAutoCalc.Parent := GroupGeneral;
  OptAutoCalc.Left := 12; OptAutoCalc.Top := 16;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptAutoCalc.Width := 360;
  {$ELSE}
  OptAutoCalc.Width := 300;
  {$ENDIF}
  OptAutoCalc.Caption := '&Automatic calculations (disable ''Evaluate'' button)';

  OptSmallDlg := TCheckBox.Create(Self); OptSmallDlg.Parent := GroupGeneral;
  OptSmallDlg.Left := 12; OptSmallDlg.Top := 34;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptSmallDlg.Width := 360;
  {$ELSE}
  OptSmallDlg.Width := 300;
  {$ENDIF}
  OptSmallDlg.Caption := '&Small dialog (show simplified dialog form)';

  OptStatus := TCheckBox.Create(Self); OptStatus.Parent := GroupGeneral;
  OptStatus.Left := 12; OptStatus.Top := 52;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptStatus.Width := 360;
  {$ELSE}
  OptStatus.Width := 300;
  {$ENDIF}
  OptStatus.Caption := 'S&how error status';

  OptOnTop := TCheckBox.Create(Self); OptOnTop.Parent := GroupGeneral;
  OptOnTop.Left := 12; OptOnTop.Top := 70;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptOnTop.Width := 360;
  {$ELSE}
  OptOnTop.Width := 300;
  {$ENDIF}
  OptOnTop.Caption := 'Always stay &on top';

  GroupCopy := TGroupBox.Create(Self); GroupCopy.Parent := TabInt;
  GroupCopy.Left := 8; GroupCopy.Top := 104;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  GroupCopy.Width := 380;
  {$ELSE}
  GroupCopy.Width := 340;
  {$ENDIF}
  GroupCopy.Height := 58; GroupCopy.Caption := ' ''Copy'' button behaviour ';

  OptCopyMode0 := TRadioButton.Create(Self); OptCopyMode0.Parent := GroupCopy;
  OptCopyMode0.Left := 12; OptCopyMode0.Top := 16;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptCopyMode0.Width := 200;
  {$ELSE}
  OptCopyMode0.Width := 175;
  {$ENDIF}
  OptCopyMode0.Caption := 'Copy result into &edit field';

  OptCopyMode1 := TRadioButton.Create(Self); OptCopyMode1.Parent := GroupCopy;
  OptCopyMode1.Left := 12; OptCopyMode1.Top := 34;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptCopyMode1.Width := 200;
  {$ELSE}
  OptCopyMode1.Width := 175;
  {$ENDIF}
  OptCopyMode1.Caption := 'Copy result to &clipboard';

  OptCopyAsIs := TCheckBox.Create(Self); OptCopyAsIs.Parent := GroupCopy;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptCopyAsIs.Left := 230;
  {$ELSE}
  OptCopyAsIs.Left := 190;
  {$ENDIF}
  OptCopyAsIs.Top := 16;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptCopyAsIs.Width := 130;
  {$ELSE}
  OptCopyAsIs.Width := 113;
  {$ENDIF}
  OptCopyAsIs.Caption := 'Cop&y as is';

  GroupDisplay := TGroupBox.Create(Self); GroupDisplay.Parent := TabInt;
  GroupDisplay.Left := 8; GroupDisplay.Top := 168;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  GroupDisplay.Width := 380;
  {$ELSE}
  GroupDisplay.Width := 340;
  {$ENDIF}
  GroupDisplay.Height := 100; GroupDisplay.Caption := ' Results display ';

  OptRAlign := TCheckBox.Create(Self); OptRAlign.Parent := GroupDisplay;
  OptRAlign.Left := 12; OptRAlign.Top := 16;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptRAlign.Width := 360;
  {$ELSE}
  OptRAlign.Width := 300;
  {$ENDIF}
  OptRAlign.Caption := 'Show results &right aligned';

  OptNoLead0 := TCheckBox.Create(Self); OptNoLead0.Parent := GroupDisplay;
  OptNoLead0.Left := 12; OptNoLead0.Top := 34;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptNoLead0.Width := 360;
  {$ELSE}
  OptNoLead0.Width := 300;
  {$ENDIF}
  OptNoLead0.Caption := 'Show hex/bin/oct results without &leading zeros';

  OptNoTrail0 := TCheckBox.Create(Self); OptNoTrail0.Parent := GroupDisplay;
  OptNoTrail0.Left := 12; OptNoTrail0.Top := 52;
  {$IF DEFINED(LCLGTK2) OR DEFINED(LCLGTK3)}
  OptNoTrail0.Width := 360;
  {$ELSE}
  OptNoTrail0.Width := 300;
  {$ENDIF}
  OptNoTrail0.Caption := 'Show decimal result without &trailing zeros';

  OptPrec := TEdit.Create(Self); OptPrec.Parent := GroupDisplay;
  OptPrec.Left := 12; OptPrec.Top := 72; OptPrec.Width := 25;
  OptPrec.Text := '17';

  LabelPrec := TLabel.Create(Self); LabelPrec.Parent := GroupDisplay;
  LabelPrec.Left := 42; LabelPrec.Top := 74;
  LabelPrec.Caption := '&Digits after decimal point in dec/exp results';

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
  BtnOK.Left := 192; BtnOK.Top := 316; BtnOK.Width := 75;
  BtnOK.Caption := 'OK'; BtnOK.Default := True;
  BtnOK.OnClick := @BtnOKClick;

  BtnCancel := TButton.Create(Self); BtnCancel.Parent := Self;
  BtnCancel.Left := 273; BtnCancel.Top := 316; BtnCancel.Width := 75;
  BtnCancel.Caption := 'Cancel'; BtnCancel.ModalResult := mrCancel;
  BtnCancel.OnClick := @BtnCancelClick;

  B := TButton.Create(Self); B.Parent := Self;
  B.Left := 354; B.Top := 316; B.Width := 75; B.Visible := False;
  B.Caption := 'Help';
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
