unit cfgform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Config, ecwengine, defform;

type
  TCfgForm = class(TForm)
    PageControl: TPageControl;
    TabInt, TabDefs, TabCalc, TabMisc: TTabSheet;
    GroupGeneral, GroupCopy, GroupDisplay: TGroupBox;
    OptAutoCalc, OptSmallDlg, OptOnTop, OptStatus: TCheckBox;
    OptCopyMode0, OptCopyMode1: TRadioButton;
    OptCopyAsIs: TCheckBox;
    OptRAlign, OptNoLead0, OptNoTrail0: TCheckBox;
    LabelPrec: TLabel;
    OptPrec: TEdit;
    BtnOK, BtnCancel: TButton;
    DefList: TListView;
    BtnAdd, BtnEdit, BtnDelete, BtnUp, BtnDown: TButton;
    GroupSep, GroupConst: TGroupBox;
    OptSep0, OptSep1, OptSep2: TRadioButton;
    OptUnsHex: TCheckBox;
    LblSep1, LblSep3, LblConst1: TLabel;
    GroupHist, GroupAppear: TGroupBox;
    OptHistUpdC, OptHistUpdE, OptAllowMul: TCheckBox;
    BtnHistClr: TButton;
    procedure BtnOKClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
    procedure BtnAddClick(Sender: TObject);
    procedure BtnEditClick(Sender: TObject);
    procedure BtnDeleteClick(Sender: TObject);
    procedure BtnUpClick(Sender: TObject);
    procedure BtnDownClick(Sender: TObject);
    procedure BtnHistClrClick(Sender: TObject);
    procedure DefListDblClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    procedure LoadCfg;
    procedure SaveCfg;
    procedure RefreshDefs;
    procedure AdjustGroupChildren(Data: PtrInt);
  public
    OnClearHistory: TNotifyEvent;
    constructor Create(AOwner: TComponent); override;
  end;

var
  CfgFrm: TCfgForm;

implementation

{$R *.lfm}

constructor TCfgForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;

procedure TCfgForm.FormShow(Sender: TObject);
begin
  // LCL positions TGroupBox children in the client area BELOW the caption;
  // the original Delphi DFM positions them from the frame's top edge. Shift
  // each group's children up by the measured caption offset so the layout
  // matches the original. The offset is read from the widgetset (deferred
  // until the form is fully shown), so it stays correct regardless of the
  // active font / screen resolution.
  Application.QueueAsyncCall(@AdjustGroupChildren, 0);
end;

procedure TCfgForm.AdjustGroupChildren(Data: PtrInt);
var
  Off: Integer;
begin
  Off := GroupGeneral.ClientOrigin.Y - (TabInt.ClientOrigin.Y + GroupGeneral.Top);
  if Off > 0 then begin
    OptAutoCalc.Top := OptAutoCalc.Top - Off;
    OptSmallDlg.Top := OptSmallDlg.Top - Off;
    OptStatus.Top   := OptStatus.Top - Off;
    OptOnTop.Top    := OptOnTop.Top - Off;
  end;
  if Off > 0 then begin
    OptCopyMode0.Top := OptCopyMode0.Top - Off;
    OptCopyMode1.Top := OptCopyMode1.Top - Off;
    OptCopyAsIs.Top  := OptCopyAsIs.Top - Off;
  end;
  if Off > 0 then begin
    OptRAlign.Top   := OptRAlign.Top - Off;
    OptNoLead0.Top  := OptNoLead0.Top - Off;
    OptNoTrail0.Top := OptNoTrail0.Top - Off;
    OptPrec.Top     := OptPrec.Top - Off;
    LabelPrec.Top   := LabelPrec.Top - Off;
  end;
  if Off > 0 then begin
    LblSep1.Top    := LblSep1.Top - Off;
    LblSep3.Top    := LblSep3.Top - Off;
    OptSep0.Top    := OptSep0.Top - Off;
    OptSep1.Top    := OptSep1.Top - Off;
    OptSep2.Top    := OptSep2.Top - Off;
    LblConst1.Top  := LblConst1.Top - Off;
    OptUnsHex.Top  := OptUnsHex.Top - Off;
  end;
  if Off > 0 then begin
    OptHistUpdC.Top := OptHistUpdC.Top - Off;
    OptHistUpdE.Top := OptHistUpdE.Top - Off;
    BtnHistClr.Top  := BtnHistClr.Top - Off;
    OptAllowMul.Top := OptAllowMul.Top - Off;
  end;
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
  case cfg.SepMode of
    0: OptSep0.Checked := True;
    1: OptSep1.Checked := True;
    2: OptSep2.Checked := True;
  end;
  OptUnsHex.Checked := cfg.UnsignedHex;
  OptHistUpdC.Checked := cfg.HistUpdC;
  OptHistUpdE.Checked := cfg.HistUpdE;
  OptAllowMul.Checked := cfg.AllowMul;
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
  if OptSep0.Checked then cfg.SepMode := 0
  else if OptSep1.Checked then cfg.SepMode := 1
  else cfg.SepMode := 2;
  cfg.UnsignedHex := OptUnsHex.Checked;
  cfg.HistUpdC := OptHistUpdC.Checked;
  cfg.HistUpdE := OptHistUpdE.Checked;
  cfg.AllowMul := OptAllowMul.Checked;
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

procedure TCfgForm.BtnUpClick(Sender: TObject);
var
  idx: Integer;
begin
  idx := DefList.Selected.Index;
  if (idx <= 0) or (idx >= NumDefs) then Exit;
  MoveDef(idx, -1);
  RefreshDefs;
  DefList.Selected := DefList.Items[idx - 1];
end;

procedure TCfgForm.BtnDownClick(Sender: TObject);
var
  idx: Integer;
begin
  idx := DefList.Selected.Index;
  if (idx < 0) or (idx >= NumDefs - 1) then Exit;
  MoveDef(idx, 1);
  RefreshDefs;
  DefList.Selected := DefList.Items[idx + 1];
end;

procedure TCfgForm.BtnHistClrClick(Sender: TObject);
begin
  if Assigned(OnClearHistory) then OnClearHistory(Self);
end;

end.
