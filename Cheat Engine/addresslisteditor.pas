unit AddresslistEditor;

{
  Inline editor for the value column of the address list.

  Plain values are edited in-place.  Records with a dropdown list get a
  searchable, owner-drawn picker which keeps the human-readable description
  separate from the backing value that is written to memory.
}

{$mode delphi}

interface

uses
  {$ifdef darwin}
  macport, LCLIntf, LMessages, Messages,
  {$endif}
  {$ifdef windows}
  Windows,
  {$endif}
  Classes, SysUtils, Forms, ComCtrls, Controls, StdCtrls, ExtCtrls, Graphics,
  LCLType, Math, MemoryRecordUnit, MemoryRecordDropdownUnit, betterControls;

type
  TAddressListEditor = class(TCustomEdit)
  private
    fOnEditorClose: TNotifyEvent;
    fMemrec: TMemoryRecord;
    fEdited: boolean;
    fClosing: boolean;
    fEditActive: boolean;
    fInitializing: boolean;
    fDeferredExitQueued: boolean;
    fSelectionExplicit: boolean;
    fHoverIndex: integer;
    fCanSelect: boolean;
    fNormalColor: TColor;

    fDropDownItems: TDropDownItems;
    fFilteredIndexes: TDropDownIndexArray;
    fPickerPanel: TPanel;
    fPickerList: TListBox;
    fPickerStatus: TLabel;
    fPickerSummary: string;
    fPickerRowCapacity: integer;
    fErrorPanel: TPanel;
    fErrorLabel: TLabel;

    function Scaled(Value: integer): integer;
    function HasDropDown: boolean;
    function ControlIsInPicker(Control: TControl): boolean;
    function FilteredItemIndex(ListIndex: integer): integer;
    function TryGetValueToApply(out Value: string; out ErrorText: string): boolean;
    function ApplyValue(ShowErrors: boolean=true): boolean;
    procedure BuildDropDownItems;
    procedure CreatePicker;
    procedure RebuildPicker;
    procedure PositionPicker;
    procedure HideError;
    procedure ShowError(const ErrorText: string);
    procedure FinishEdit;
    procedure PickerClick(Sender: TObject);
    procedure PickerMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure PickerMouseLeave(Sender: TObject);
    procedure PickerDrawItem(Control: TWinControl; Index: integer;
      ARect: TRect; State: TOwnerDrawState);
    procedure DeferredExit(Data: PtrInt);
  protected
    procedure DoClose;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure TextChanged; override;
    procedure DoExit; override;
    procedure SetSelStart(Val: integer); override;
    procedure SetSelLength(Val: integer); override;
  public
    procedure UpdatePosition(Left: integer);
    procedure CloseEditor(ApplyChanges: boolean);
    constructor Create(Owner: TTreeView; Memrec: TMemoryRecord;
      Left: integer); overload;
    destructor Destroy; override;
  published
    property Memrec: TMemoryRecord read fMemrec;
    property DropDownActive: boolean read HasDropDown;
    property OnEditorClose: TNotifyEvent read fOnEditorClose write fOnEditorClose;
    property OnDblClick;
  end;

implementation

uses
  Addresslist;

resourcestring
  rsNoMatchingValues = 'No matching values';
  rsMatchingValues = '%d matching values';
  rsAmbiguousDropDownValue = 'Several entries use this description. Select the intended ID.';
  rsSelectDropDownValue = 'Select a value from the list';

function TAddressListEditor.Scaled(Value: integer): integer;
begin
  Result := Max(1, Round(Value * Screen.PixelsPerInch / 96));
end;

function TAddressListEditor.HasDropDown: boolean;
begin
  Result := Length(fDropDownItems) > 0;
end;

function TAddressListEditor.ControlIsInPicker(Control: TControl): boolean;
begin
  Result := false;
  while Control <> nil do
  begin
    if Control = fPickerPanel then
      exit(true);
    Control := Control.Parent;
  end;
end;

function TAddressListEditor.FilteredItemIndex(ListIndex: integer): integer;
begin
  Result := -1;
  if (ListIndex >= 0) and (ListIndex < Length(fFilteredIndexes)) then
    Result := fFilteredIndexes[ListIndex];
end;

procedure TAddressListEditor.SetSelStart(Val: integer);
begin
  if fCanSelect then
    inherited;
end;

procedure TAddressListEditor.SetSelLength(Val: integer);
begin
  if fCanSelect then
    inherited;
end;

procedure TAddressListEditor.HideError;
begin
  Color := fNormalColor;
  Hint := '';
  ShowHint := false;
  if fErrorPanel <> nil then
    fErrorPanel.Visible := false;
end;

procedure TAddressListEditor.ShowError(const ErrorText: string);
var
  R: TRect;
begin
  Color := RGBToColor(80, 25, 25);
  if not ShouldAppsUseDarkMode then
    Color := RGBToColor(255, 225, 225);

  Hint := ErrorText;
  ShowHint := true;

  if fErrorPanel = nil then
  begin
    fErrorPanel := TPanel.Create(Owner);
    fErrorPanel.Parent := TWinControl(Owner);
    fErrorPanel.AutoSize := true;
    fErrorPanel.BevelOuter := bvNone;
    fErrorPanel.BorderWidth := Scaled(1);
    fErrorPanel.Color := Color;
    fErrorPanel.ParentColor := false;

    fErrorLabel := TLabel.Create(fErrorPanel);
    fErrorLabel.Parent := fErrorPanel;
    fErrorLabel.AutoSize := true;
    fErrorLabel.WordWrap := true;
    fErrorLabel.BorderSpacing.Around := Scaled(6);
    fErrorLabel.Font.Color := clRed;
  end;

  fErrorPanel.Color := Color;
  fErrorLabel.Caption := ErrorText;
  fErrorPanel.Left := Left;
  R := fMemrec.TreeNode.DisplayRect(false);
  if Top + Height + fErrorPanel.Height <= TTreeView(Owner).ClientHeight then
    fErrorPanel.Top := Top + Height
  else
    fErrorPanel.Top := Max(0, R.Top - fErrorPanel.Height);
  fErrorPanel.Constraints.MaxWidth := Max(1,
    TTreeView(Owner).ClientWidth - fErrorPanel.Left);
  fErrorLabel.Constraints.MaxWidth := Max(1,
    fErrorPanel.Constraints.MaxWidth - Scaled(14));
  fErrorPanel.Visible := true;
  fErrorPanel.BringToFront;

  fCanSelect := true;
  SelectAll;
  fCanSelect := false;
  SetFocus;
end;

procedure TAddressListEditor.BuildDropDownItems;
var
  I, L: integer;
begin
  SetLength(fDropDownItems, 0);
  for I := 0 to fMemrec.DropDownCount - 1 do
  begin
    if (fMemrec.DropDownValue[I] = '*') and
      (I = fMemrec.DropDownCount - 1) then
      break;

    L := Length(fDropDownItems);
    SetLength(fDropDownItems, L + 1);
    fDropDownItems[L].Value := fMemrec.DropDownValue[I];
    fDropDownItems[L].Description := fMemrec.DropDownDescription[I];
    fDropDownItems[L].SourceIndex := I;
  end;
end;

procedure TAddressListEditor.CreatePicker;
begin
  {Keep the popup at the capacity of the source list. Filtering should change
   its contents, not make the editor jump between ten rows and one row.}
  fPickerRowCapacity := Min(10, Max(1, Length(fDropDownItems)));

  fPickerPanel := TPanel.Create(Owner);
  fPickerPanel.Parent := TWinControl(Owner);
  fPickerPanel.BevelOuter := bvNone;
  fPickerPanel.BorderWidth := Scaled(1);
  fPickerPanel.Color := ColorSet.ButtonBorderColor;
  fPickerPanel.ParentColor := false;
  fPickerPanel.Visible := false;

  fPickerStatus := TLabel.Create(fPickerPanel);
  fPickerStatus.Parent := fPickerPanel;
  fPickerStatus.Align := alBottom;
  fPickerStatus.BorderSpacing.Around := Scaled(5);
  fPickerStatus.AutoSize := false;
  fPickerStatus.Height := Scaled(24);
  fPickerStatus.Layout := tlCenter;
  fPickerStatus.Font.Color := ColorSet.InactiveFontColor;

  fPickerList := TListBox.Create(fPickerPanel);
  fPickerList.Parent := fPickerPanel;
  fPickerList.Align := alClient;
  fPickerList.BorderStyle := bsNone;
  fPickerList.ItemHeight := Scaled(24);
  fPickerList.Style := lbOwnerDrawFixed;
  fPickerList.TabStop := false;
  fPickerList.ParentShowHint := false;
  fPickerList.OnClick := PickerClick;
  fPickerList.OnMouseMove := PickerMouseMove;
  fPickerList.OnMouseLeave := PickerMouseLeave;
  fPickerList.OnDrawItem := PickerDrawItem;
end;

procedure TAddressListEditor.PositionPicker;
var
  DesiredHeight, VisibleRows, PickerWidth, OwnerWidth, OwnerHeight: integer;
begin
  if fPickerPanel = nil then
    exit;

  OwnerWidth := TTreeView(Owner).ClientWidth;
  OwnerHeight := TTreeView(Owner).ClientHeight;
  if (OwnerWidth<=0) or (OwnerHeight<=0) then
    exit;
  VisibleRows := fPickerRowCapacity;
  DesiredHeight := VisibleRows * fPickerList.ItemHeight +
    fPickerStatus.Height + Scaled(2);
  DesiredHeight := Min(DesiredHeight, OwnerHeight);
  PickerWidth := Max(Width, Scaled(360));
  PickerWidth := Min(PickerWidth, OwnerWidth);

  fPickerPanel.Width := PickerWidth;
  fPickerPanel.Height := DesiredHeight;
  fPickerPanel.Left := Min(Left, Max(0, OwnerWidth - PickerWidth));

  if Top + Height + DesiredHeight <= OwnerHeight then
    fPickerPanel.Top := Top + Height
  else
    fPickerPanel.Top := EnsureRange(Top - DesiredHeight, 0,
      Max(0, OwnerHeight - DesiredHeight));

  fPickerPanel.BringToFront;
end;

procedure TAddressListEditor.RebuildPicker;
var
  I, ItemIndex, SelectedItemIndex: integer;
  Resolution: TDropDownResolution;
begin
  if fPickerList = nil then
    exit;

  fHoverIndex := -1;
  fPickerList.Hint := '';
  fPickerList.ShowHint := false;
  SelectedItemIndex := -1;
  fFilteredIndexes := FilterDropDownItems(fDropDownItems, Text,
    fMemrec.DropDownDescriptionOnly);

  if ResolveDropDownInput(fDropDownItems, Text,
    fMemrec.DropDownDescriptionOnly, Resolution) then
    SelectedItemIndex := Resolution.MatchIndex;

  fPickerList.Items.BeginUpdate;
  try
    fPickerList.Items.Clear;
    for I := 0 to High(fFilteredIndexes) do
    begin
      fPickerList.Items.Add(
        fDropDownItems[fFilteredIndexes[I]].Description + ' (' +
        fDropDownItems[fFilteredIndexes[I]].Value + ')');
      if fFilteredIndexes[I] = SelectedItemIndex then
        fPickerList.ItemIndex := I;
    end;

    if (fPickerList.ItemIndex = -1) and (fPickerList.Items.Count > 0) then
      fPickerList.ItemIndex := 0;
  finally
    fPickerList.Items.EndUpdate;
  end;

  if Length(fFilteredIndexes) = 0 then
    fPickerSummary := rsNoMatchingValues
  else if Resolution.Status = drsAmbiguous then
    fPickerSummary := rsAmbiguousDropDownValue
  else
    fPickerSummary := Format(rsMatchingValues,
      [Length(fFilteredIndexes)]);
  fPickerStatus.Caption := fPickerSummary;

  ItemIndex := FilteredItemIndex(fPickerList.ItemIndex);
  if ItemIndex >= 0 then
    fPickerList.MakeCurrentVisible;

  PositionPicker;
  fPickerPanel.Visible := true;
end;

procedure TAddressListEditor.FinishEdit;
begin
  if not fEditActive then
    exit;

  fEditActive := false;
  if fMemrec <> nil then
    fMemrec.EndEdit;
end;

procedure TAddressListEditor.PickerClick(Sender: TObject);
var
  ItemIndex: integer;
begin
  ItemIndex := FilteredItemIndex(fPickerList.ItemIndex);
  if ItemIndex < 0 then
    exit;

  fSelectionExplicit := true;
  fInitializing := true;
  try
    Text := DropDownDisplayText(fDropDownItems[ItemIndex],
      fMemrec.DropDownDescriptionOnly);
  finally
    fInitializing := false;
  end;
  fEdited := true;

  if ApplyValue then
    DoClose;
end;

procedure TAddressListEditor.PickerMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  HoverIndex, ItemIndex: integer;
  Item: TDropDownItem;
begin
  HoverIndex := fPickerList.ItemAtPos(Point(X,Y),true);
  if HoverIndex <> fHoverIndex then
  begin
    fHoverIndex := HoverIndex;
    fPickerList.Invalidate;
  end;

  ItemIndex := FilteredItemIndex(HoverIndex);
  if ItemIndex >= 0 then
  begin
    Item := fDropDownItems[ItemIndex];
    fPickerList.Hint := Item.Description+'  ('+Item.Value+')';
    fPickerList.ShowHint := true;
    fPickerStatus.Caption := Item.Description+'  |  Value: '+Item.Value+
      '  |  Click to apply';
  end
  else
  begin
    fPickerList.Hint := '';
    fPickerList.ShowHint := false;
    fPickerStatus.Caption := fPickerSummary;
  end;
end;

procedure TAddressListEditor.PickerMouseLeave(Sender: TObject);
begin
  if fPickerList=nil then exit;
  fHoverIndex := -1;
  fPickerList.Hint := '';
  fPickerList.ShowHint := false;
  fPickerStatus.Caption := fPickerSummary;
  fPickerList.Invalidate;
end;

procedure TAddressListEditor.PickerDrawItem(Control: TWinControl;
  Index: integer; ARect: TRect; State: TOwnerDrawState);
var
  LB: TListBox;
  ItemIndex, ValueWidth: integer;
  DescriptionRect, ValueRect: TRect;
  TS: TTextStyle;
  Item: TDropDownItem;
  TextColor, SecondaryColor: TColor;
begin
  LB := TListBox(Control);
  ItemIndex := FilteredItemIndex(Index);
  if ItemIndex < 0 then
    exit;
  Item := fDropDownItems[ItemIndex];

  if odSelected in State then
  begin
    LB.Canvas.Brush.Color := clHighlight;
    TextColor := Graphics.clHighlightText;
    SecondaryColor := Graphics.clHighlightText;
  end
  else if Index=fHoverIndex then
  begin
    if ShouldAppsUseDarkMode then
      LB.Canvas.Brush.Color := incColor(ColorSet.TextBackground,14)
    else
      LB.Canvas.Brush.Color := RGBToColor(238,243,248);
    TextColor := ColorSet.FontColor;
    SecondaryColor := ColorSet.InactiveFontColor;
  end
  else
  begin
    LB.Canvas.Brush.Color := ColorSet.TextBackground;
    TextColor := ColorSet.FontColor;
    SecondaryColor := ColorSet.InactiveFontColor;
  end;
  LB.Canvas.FillRect(ARect);
  if Index=fHoverIndex then
  begin
    LB.Canvas.Brush.Style := bsClear;
    LB.Canvas.Pen.Color := ColorSet.FontColor;
    LB.Canvas.Rectangle(ARect);
    LB.Canvas.Brush.Style := bsSolid;
  end;

  InflateRect(ARect, -Scaled(8), 0);
  ValueWidth := Max(Scaled(90), LB.Canvas.TextWidth(Item.Value) + Scaled(8));
  ValueRect := ARect;
  ValueRect.Left := Max(ARect.Left, ARect.Right - ValueWidth);
  DescriptionRect := ARect;
  DescriptionRect.Right := Max(DescriptionRect.Left,
    ValueRect.Left - Scaled(8));

  TS := LB.Canvas.TextStyle;
  TS.Layout := tlCenter;
  TS.EndEllipsis := true;
  TS.SingleLine := true;

  LB.Canvas.Font.Color := TextColor;
  LB.Canvas.TextRect(DescriptionRect, DescriptionRect.Left,
    DescriptionRect.Top, Item.Description, TS);

  TS.Alignment := taRightJustify;
  LB.Canvas.Font.Color := SecondaryColor;
  LB.Canvas.TextRect(ValueRect, ValueRect.Left, ValueRect.Top,
    Item.Value, TS);
end;

function TAddressListEditor.TryGetValueToApply(out Value: string;
  out ErrorText: string): boolean;
var
  Resolution: TDropDownResolution;
  ItemIndex: integer;
begin
  ErrorText := '';
  Value := Text;

  if not HasDropDown then
    exit(true);

  if ResolveDropDownInput(fDropDownItems, Text,
    fMemrec.DropDownDescriptionOnly, Resolution) then
  begin
    Value := Resolution.Value;
    exit(true);
  end;

  ItemIndex := FilteredItemIndex(fPickerList.ItemIndex);
  if fSelectionExplicit and (ItemIndex >= 0) then
  begin
    Value := fDropDownItems[ItemIndex].Value;
    exit(true);
  end;

  if Resolution.Status = drsAmbiguous then
  begin
    ErrorText := rsAmbiguousDropDownValue;
    exit(false);
  end;

  if fMemrec.DropDownReadOnly then
  begin
    ErrorText := rsSelectDropDownValue;
    exit(false);
  end;

  Result := true;
end;

function TAddressListEditor.ApplyValue(ShowErrors: boolean): boolean;
var
  Value, ErrorText: string;
begin
  Result := false;
  if not TryGetValueToApply(Value, ErrorText) then
  begin
    if ShowErrors then
      ShowError(ErrorText);
    exit;
  end;

  try
    fMemrec.Value := Value;
    fEdited := false;
    HideError;
    if fMemrec.TreeNode <> nil then
      fMemrec.TreeNode.Update;
    Result := true;
  except
    on E: Exception do
      if ShowErrors then
        ShowError(E.Message);
  end;
end;

procedure TAddressListEditor.DoClose;
begin
  if fClosing then
    exit;
  fClosing := true;

  Visible := false;
  if fPickerPanel <> nil then
    fPickerPanel.Visible := false;
  if fErrorPanel <> nil then
    fErrorPanel.Visible := false;

  FinishEdit;
  if Assigned(fOnEditorClose) then
    fOnEditorClose(Self);
end;

procedure TAddressListEditor.CloseEditor(ApplyChanges: boolean);
begin
  if fClosing then
    exit;

  {Focus loss is a soft commit. Valid input is applied; incomplete, empty, or
   invalid input is discarded and the previously committed value remains.}
  if ApplyChanges and fEdited then
    ApplyValue(false);
  fEdited := false;
  DoClose;
end;

procedure TAddressListEditor.DblClick;
begin
  { Preserve the long-standing double-click path for ordinary values.  A
    dropdown stays in the new inline picker instead of reopening the legacy
    modal combo box. }
  if not HasDropDown then
  begin
    fEdited := false;
    DoClose;
  end;
  inherited DblClick;
end;

procedure TAddressListEditor.KeyDown(var Key: Word; Shift: TShiftState);
var
  NewIndex: integer;
begin
  case Key of
    VK_ESCAPE:
      begin
        fEdited := false;
        DoClose;
        Key := 0;
      end;

    VK_RETURN:
      begin
        if HasDropDown then
        begin
          { Arrow-key navigation is an explicit choice even though it does not
            rewrite the edit text.  Commit that highlighted backing value when
            Enter is pressed. }
          if fEdited or fSelectionExplicit then
          begin
            if ApplyValue then
              DoClose;
          end
          else
            DoClose;
        end
        else if (not fEdited) or ApplyValue then
          DoClose;
        Key := 0;
      end;

    VK_UP, VK_DOWN:
      begin
        if HasDropDown then
        begin
          NewIndex := fPickerList.ItemIndex;
          if Key = VK_UP then
            Dec(NewIndex)
          else
            Inc(NewIndex);
          NewIndex := EnsureRange(NewIndex, 0,
            Max(0, fPickerList.Items.Count - 1));
          if fPickerList.Items.Count > 0 then
          begin
            fPickerList.ItemIndex := NewIndex;
            fPickerList.MakeCurrentVisible;
            fSelectionExplicit := true;
          end;
          Key := 0;
        end
        else
        begin
          if fEdited and (not ApplyValue) then
          begin
            Key := 0;
            exit;
          end;
          DoClose;
          {$ifdef windows}
          SendMessage(TTreeView(Owner).Handle, WM_KEYDOWN, Key, 0);
          {$endif}
          TAddresslist(TTreeView(Owner).Owner).DoValueChange;
          Key := 0;
        end;
      end;
  else
    inherited KeyDown(Key, Shift);
  end;
end;

procedure TAddressListEditor.TextChanged;
begin
  inherited TextChanged;
  if fInitializing then
    exit;

  fEdited := true;
  fSelectionExplicit := false;
  HideError;
  if HasDropDown then
    RebuildPicker;
end;

procedure TAddressListEditor.DeferredExit(Data: PtrInt);
var
  ActiveControl: TControl;
begin
  fDeferredExitQueued := false;
  if fClosing or (not Visible) then
    exit;

  ActiveControl := nil;
  if Screen.ActiveForm <> nil then
    ActiveControl := Screen.ActiveForm.ActiveControl;

  if (ActiveControl = Self) or ControlIsInPicker(ActiveControl) then
    exit;

  if Application.Terminated then
    CloseEditor(false)
  else
    CloseEditor(true);
end;

procedure TAddressListEditor.DoExit;
begin
  inherited DoExit;
  if not fDeferredExitQueued then
  begin
    fDeferredExitQueued := true;
    Application.QueueAsyncCall(DeferredExit, 0);
  end;
end;

procedure TAddressListEditor.UpdatePosition(Left: integer);
var
  R: TRect;
begin
  Self.Left := EnsureRange(Left, 0,
    Max(0, TTreeView(Owner).ClientWidth - 1));
  R := fMemrec.TreeNode.DisplayRect(true);
  Height := Max(Scaled(24), R.Bottom - R.Top);
  Top := R.Top;

  R := fMemrec.TreeNode.DisplayRect(false);
  Width := Max(1, TTreeView(Owner).ClientWidth - Self.Left);
  PositionPicker;
end;

destructor TAddressListEditor.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  if fPickerPanel <> nil then
    FreeAndNil(fPickerPanel);
  if fErrorPanel <> nil then
    FreeAndNil(fErrorPanel);
  FinishEdit;
  inherited Destroy;
end;

constructor TAddressListEditor.Create(Owner: TTreeView;
  Memrec: TMemoryRecord; Left: integer);
var
  Point: TPoint;
begin
  inherited Create(Owner);

  fMemrec := Memrec;
  fMemrec.BeginEdit;
  fEditActive := true;

  fInitializing := true;
  fClosing := false;
  fEdited := false;
  fSelectionExplicit := false;
  fHoverIndex := -1;
  BuildDropDownItems;

  AutoSize := false;
  BorderStyle := bsSingle;
  Font := Owner.Font;
  fNormalColor := ColorSet.EditBackground;
  if fNormalColor = 0 then
    fNormalColor := clWindow;
  Color := fNormalColor;
  Font.Color := ColorSet.FontColor;
  if Font.Color = 0 then
    Font.Color := clWindowText;

  UpdatePosition(Left);
  Parent := Owner;

  if HasDropDown then
  begin
    Text := fMemrec.DisplayValue;
    CreatePicker;
  end
  else
    Text := fMemrec.Value;

  fInitializing := false;
  fEdited := false;
  SetFocus;

  if HasDropDown then
    RebuildPicker;

  if ((GetKeyState(VK_RETURN) shr 15) and 1) = 1 then
  begin
    fCanSelect := true;
    SelectAll;
    fCanSelect := false;
  end
  else
  begin
    Point := ScreenToClient(Mouse.CursorPos);
    Point.X := Owner.Canvas.TextFitInfo(Text, Point.X);
    Point.Y := 0;
    SetCaretPos(Point);
  end;
end;

end.
