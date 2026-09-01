unit cfgform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
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
  private
    procedure LoadCfg;
    procedure SaveCfg;
    procedure RefreshDefs;
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
