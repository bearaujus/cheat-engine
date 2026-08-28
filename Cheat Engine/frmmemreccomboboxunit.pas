unit frmMemrecComboboxUnit;

{$mode delphi}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, MemoryRecordUnit, MemoryRecordDropdownUnit, math, betterControls;

type

  { TfrmMemrecCombobox }

  TfrmMemrecCombobox = class(TForm)
    btnCancel: TButton;
    btnOk: TButton;
    cbMemrecCombobox: TComboBox;
    Label1: TLabel;
    Panel1: TPanel;
    procedure btnOkClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    { private declarations }
    valuelist: tstringlist;
    dropdownitems: TDropDownItems;
    memrec: TMemoryRecord;
    function getValue: string;
  public
    { public declarations }
    constructor create(memrec: TMemoryrecord);
    property value: string read getValue;
  end;

var
  frmMemrecCombobox: TfrmMemrecCombobox;

implementation

{$R *.lfm}

resourcestring
  rsAmbiguousDropDownValue = 'Several entries use this description. Select the intended value from the list.';

procedure TfrmMemrecCombobox.FormDestroy(Sender: TObject);
begin
  if valuelist<>nil then
    freeandnil(valuelist);
end;

procedure TfrmMemrecCombobox.FormShow(Sender: TObject);
var i,maxwidth: integer;
begin
  maxwidth:=clientwidth;
  for i:=0 to cbMemrecCombobox.Items.Count-1 do
    maxwidth:=max(maxwidth, cbMemrecCombobox.Canvas.TextWidth(cbMemrecCombobox.items[i]));

  if maxwidth<>clientwidth then
    Constraints.MinWidth:=maxwidth+16;
end;

procedure TfrmMemrecCombobox.btnOkClick(Sender: TObject);
var
  r: TDropDownResolution;
begin
  if cbMemrecCombobox.itemindex<>-1 then
  begin
    modalresult:=mrok;
    exit;
  end;

  if ResolveDropDownInput(dropdownitems, cbMemrecCombobox.Text,
    memrec.DropDownDescriptionOnly, r) then
  begin
    modalresult:=mrok;
    exit;
  end;

  if r.Status=drsAmbiguous then
  begin
    MessageDlg(rsAmbiguousDropDownValue,mtWarning,[mbok],0);
    exit;
  end;

  if memrec.DropDownReadOnly then
    modalresult:=mrcancel //it was readonly and nothing was picked
  else
    modalresult:=mrok;
end;

function TfrmMemrecCombobox.getValue: string;
var
  r: TDropDownResolution;
begin
  if cbMemrecCombobox.itemindex<>-1 then
    result:=valuelist[cbMemrecCombobox.itemindex]
  else if ResolveDropDownInput(dropdownitems, cbMemrecCombobox.Text,
    memrec.DropDownDescriptionOnly, r) then
    result:=r.Value
  else
    result:=cbMemrecCombobox.Text;
end;

constructor TfrmMemrecCombobox.create(memrec: TMemoryrecord);
var i: integer;
begin
  inherited create(application);

  if memrec.DropDownReadOnly then
    cbMemrecCombobox.style:=csDropDownList;

  valuelist:=tstringlist.create;
  setlength(dropdownitems, 0);
  for i:=0 to memrec.DropDownCount-1 do
  begin
    if (memrec.DropDownValue[i]='*') and (i=memrec.DropDownCount-1) then break; //don't add the wildcard if it's the last in the list

    valuelist.add(memrec.DropDownValue[i]);
    setlength(dropdownitems, length(dropdownitems)+1);
    dropdownitems[high(dropdownitems)].Value:=memrec.DropDownValue[i];
    dropdownitems[high(dropdownitems)].Description:=memrec.DropDownDescription[i];
    dropdownitems[high(dropdownitems)].SourceIndex:=i;
    if memrec.DropDownDescriptionOnly then
      cbMemrecCombobox.Items.Add(memrec.DropDownDescription[i])
    else
      cbMemrecCombobox.Items.add(memrec.DropDownValue[i]+' : '+memrec.DropDownDescription[i]);
  end;

  i:=memrec.getCurrentDropDownIndex;
  if (i=-1) and (not memrec.DropDownReadOnly) then //not a known value
    cbMemrecCombobox.Text:=memrec.value
  else
    cbMemrecCombobox.ItemIndex:=i;

  self.memrec:=memrec;

  cbMemrecCombobox.DropDownCount:=min(16, cbMemrecCombobox.items.count);


end;

end.
