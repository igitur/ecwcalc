unit defform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, Dialogs;

type
  TDefForm = class(TForm)
  private
    Label1, Label2: TLabel;
    EditName, EditBody: TEdit;
    BtnOK, BtnCancel, BtnHelp: TButton;
    function GetText: string;
    procedure SetText(const V: string);
    procedure BuildControls;
    procedure BtnOKClick(Sender: TObject);
    procedure BtnHelpClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    property DeclText: string read GetText write SetText;
  end;

implementation

constructor TDefForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'Definition';
  ClientWidth := 380;
  ClientHeight := 130;
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  BuildControls;
end;

procedure TDefForm.BuildControls;
begin
  Label1 := TLabel.Create(Self); Label1.Parent := Self;
  Label1.Left := 8; Label1.Top := 8;
  Label1.Caption := '&Function or variable declaration:';

  EditName := TEdit.Create(Self); EditName.Parent := Self;
  EditName.Left := 8; EditName.Top := 24; EditName.Width := 364;
  EditName.OnChange := @EditChange;

  Label2 := TLabel.Create(Self); Label2.Parent := Self;
  Label2.Left := 8; Label2.Top := 52;
  Label2.Caption := '&Expression with declared arguments:';

  EditBody := TEdit.Create(Self); EditBody.Parent := Self;
  EditBody.Left := 8; EditBody.Top := 68; EditBody.Width := 364;
  EditBody.OnChange := @EditChange;

  BtnOK := TButton.Create(Self); BtnOK.Parent := Self;
  BtnOK.Left := 120; BtnOK.Top := 100; BtnOK.Width := 80;
  BtnOK.Caption := 'OK'; BtnOK.Default := True;
  BtnOK.Enabled := False;
  BtnOK.OnClick := @BtnOKClick;

  BtnCancel := TButton.Create(Self); BtnCancel.Parent := Self;
  BtnCancel.Left := 210; BtnCancel.Top := 100; BtnCancel.Width := 80;
  BtnCancel.Caption := 'Cancel'; BtnCancel.ModalResult := mrCancel;

  BtnHelp := TButton.Create(Self); BtnHelp.Parent := Self;
  BtnHelp.Left := 300; BtnHelp.Top := 100; BtnHelp.Width := 72;
  BtnHelp.Caption := 'Help';
  BtnHelp.OnClick := @BtnHelpClick;
end;

function TDefForm.GetText: string;
begin
  Result := Trim(EditName.Text);
  if Result <> '' then
    Result := Result + '=' + Trim(EditBody.Text);
end;

procedure TDefForm.SetText(const V: string);
var
  p: Integer;
begin
  p := Pos('=', V);
  if p > 0 then begin
    EditName.Text := Copy(V, 1, p - 1);
    EditBody.Text := Copy(V, p + 1, Length(V));
  end else
    EditName.Text := V;
end;

procedure TDefForm.EditChange(Sender: TObject);
begin
  BtnOK.Enabled := (Trim(EditName.Text) <> '') and (Trim(EditBody.Text) <> '');
end;

procedure TDefForm.BtnOKClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

procedure TDefForm.BtnHelpClick(Sender: TObject);
begin
  ShowMessage('Declaration:  name(arg1,arg2)=expression'#13#10 +
              'or           name=value'#13#10#13#10 +
              'Example:  f(x)=x*x   then use  f(5)');
end;

end.
