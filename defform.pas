unit defform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, Dialogs;

type
  TDefForm = class(TForm)
    Label1, Label2: TLabel;
    EditName, EditBody: TEdit;
    BtnOK, BtnCancel, BtnHelp: TButton;
    procedure BtnOKClick(Sender: TObject);
    procedure BtnHelpClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
  private
    function GetText: string;
    procedure SetText(const V: string);
  public
    constructor Create(AOwner: TComponent); override;
    property DeclText: string read GetText write SetText;
  end;

implementation

{$R *.lfm}

constructor TDefForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
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
