unit TestMemoryRecordDropdown;

{$mode delphi}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, MemoryRecordDropdownUnit;

type
  TMemoryRecordDropdownTests = class(TTestCase)
  private
    function Item(const Value, Description: string;
      SourceIndex: integer): TDropDownItem;
  published
    procedure ResolvesBackingValue;
    procedure ResolvesUniqueDescription;
    procedure ResolvesRenderedPair;
    procedure ResolvesRenderedPairWhitespace;
    procedure ResolvesColonInBackingValuePair;
    procedure BackingValueTakesPrecedence;
    procedure TreatsIdenticalDuplicatesAsOneValue;
    procedure ReportsConflictingDescriptionsAsAmbiguous;
    procedure DoesNotResolvePartialDescription;
    procedure FiltersPrefixBeforeSubstring;
    procedure FiltersBackingValues;
  end;

implementation

function TMemoryRecordDropdownTests.Item(const Value, Description: string;
  SourceIndex: integer): TDropDownItem;
begin
  Result.Value := Value;
  Result.Description := Description;
  Result.SourceIndex := SourceIndex;
end;

procedure TMemoryRecordDropdownTests.ResolvesBackingValue;
var
  Items: TDropDownItems;
  Resolution: TDropDownResolution;
begin
  SetLength(Items, 1);
  Items[0] := Item('DC584F60', 'DMG Cap', 0);

  AssertTrue(ResolveDropDownInput(Items, 'dc584f60', true, Resolution));
  AssertEquals(Ord(drsValueMatch), Ord(Resolution.Status));
  AssertEquals('DC584F60', Resolution.Value);
end;

procedure TMemoryRecordDropdownTests.ResolvesUniqueDescription;
var
  Items: TDropDownItems;
  Resolution: TDropDownResolution;
begin
  SetLength(Items, 2);
  Items[0] := Item('CEB700EE', 'Stun Power', 0);
  Items[1] := Item('DC584F60', 'DMG Cap', 1);

  AssertTrue(ResolveDropDownInput(Items, '  DMG Cap  ', true, Resolution));
  AssertEquals(Ord(drsDescriptionMatch), Ord(Resolution.Status));
  AssertEquals('DC584F60', Resolution.Value);
  AssertEquals(1, Resolution.MatchIndex);
end;

procedure TMemoryRecordDropdownTests.ResolvesRenderedPair;
var
  Items: TDropDownItems;
  Resolution: TDropDownResolution;
begin
  SetLength(Items, 1);
  Items[0] := Item('DC584F60', 'DMG Cap', 0);

  AssertTrue(ResolveDropDownInput(Items, 'DC584F60 : DMG Cap', false,
    Resolution));
  AssertEquals(Ord(drsDisplayMatch), Ord(Resolution.Status));
  AssertEquals('DC584F60', Resolution.Value);
end;

procedure TMemoryRecordDropdownTests.ResolvesRenderedPairWhitespace;
var
  Items: TDropDownItems;
  Resolution: TDropDownResolution;
begin
  SetLength(Items, 1);
  Items[0] := Item('DC584F60', 'DMG Cap', 0);

  AssertTrue(ResolveDropDownInput(Items, ' DC584F60:  DMG Cap ', true,
    Resolution));
  AssertEquals(Ord(drsDisplayMatch), Ord(Resolution.Status));
  AssertEquals('DC584F60', Resolution.Value);
end;

procedure TMemoryRecordDropdownTests.ResolvesColonInBackingValuePair;
var
  Items: TDropDownItems;
  Resolution: TDropDownResolution;
begin
  SetLength(Items, 1);
  Items[0] := Item('item:rare', 'Rare item', 0);

  AssertTrue(ResolveDropDownInput(Items, 'item:rare : Rare item', true,
    Resolution));
  AssertEquals(Ord(drsDisplayMatch), Ord(Resolution.Status));
  AssertEquals('item:rare', Resolution.Value);
end;

procedure TMemoryRecordDropdownTests.BackingValueTakesPrecedence;
var
  Items: TDropDownItems;
  Resolution: TDropDownResolution;
begin
  SetLength(Items, 2);
  Items[0] := Item('DMG Cap', 'Literal backing value', 0);
  Items[1] := Item('DC584F60', 'DMG Cap', 1);

  AssertTrue(ResolveDropDownInput(Items, 'DMG Cap', true, Resolution));
  AssertEquals(Ord(drsValueMatch), Ord(Resolution.Status));
  AssertEquals('DMG Cap', Resolution.Value);
end;

procedure TMemoryRecordDropdownTests.TreatsIdenticalDuplicatesAsOneValue;
var
  Items: TDropDownItems;
  Resolution: TDropDownResolution;
  Filtered: TDropDownIndexArray;
begin
  SetLength(Items, 2);
  Items[0] := Item('9C2399DA', 'Aegis V+', 0);
  Items[1] := Item('9C2399DA', 'Aegis V+', 1);

  AssertTrue(ResolveDropDownInput(Items, 'Aegis V+', true, Resolution));
  AssertEquals(Ord(drsDescriptionMatch), Ord(Resolution.Status));
  AssertEquals('9C2399DA', Resolution.Value);

  Filtered := FilterDropDownItems(Items, '', true);
  AssertEquals(1, Length(Filtered));
  AssertEquals(0, Filtered[0]);
end;

procedure TMemoryRecordDropdownTests.ReportsConflictingDescriptionsAsAmbiguous;
var
  Items: TDropDownItems;
  Resolution: TDropDownResolution;
begin
  SetLength(Items, 2);
  Items[0] := Item('73D34F1B', 'Gateway-Star Sword', 0);
  Items[1] := Item('FA5F32D5', 'Gateway-Star Sword', 1);

  AssertFalse(ResolveDropDownInput(Items, 'Gateway-Star Sword', true,
    Resolution));
  AssertEquals(Ord(drsAmbiguous), Ord(Resolution.Status));
  AssertEquals(2, Length(Resolution.CandidateIndexes));
end;

procedure TMemoryRecordDropdownTests.DoesNotResolvePartialDescription;
var
  Items: TDropDownItems;
  Resolution: TDropDownResolution;
begin
  SetLength(Items, 1);
  Items[0] := Item('DC584F60', 'DMG Cap', 0);

  AssertFalse(ResolveDropDownInput(Items, 'DMG', true, Resolution));
  AssertEquals(Ord(drsNoMatch), Ord(Resolution.Status));
end;

procedure TMemoryRecordDropdownTests.FiltersPrefixBeforeSubstring;
var
  Items: TDropDownItems;
  Filtered: TDropDownIndexArray;
begin
  SetLength(Items, 3);
  Items[0] := Item('1', 'Maximum DMG Cap', 0);
  Items[1] := Item('2', 'DMG Cap', 1);
  Items[2] := Item('3', 'Other', 2);

  Filtered := FilterDropDownItems(Items, 'DMG', true);
  AssertEquals(2, Length(Filtered));
  AssertEquals(1, Filtered[0]);
  AssertEquals(0, Filtered[1]);
end;

procedure TMemoryRecordDropdownTests.FiltersBackingValues;
var
  Items: TDropDownItems;
  Filtered: TDropDownIndexArray;
begin
  SetLength(Items, 2);
  Items[0] := Item('CEB700EE', 'Stun Power', 0);
  Items[1] := Item('DC584F60', 'DMG Cap', 1);

  Filtered := FilterDropDownItems(Items, 'DC58', true);
  AssertEquals(1, Length(Filtered));
  AssertEquals(1, Filtered[0]);
end;

initialization
  RegisterTest(TMemoryRecordDropdownTests);

end.
