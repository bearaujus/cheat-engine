unit MemoryRecordDropdownUnit;

{$mode delphi}

interface

uses
  Classes, SysUtils;

type
  TDropDownItem = record
    Value: string;
    Description: string;
    SourceIndex: integer;
  end;

  TDropDownItems = array of TDropDownItem;
  TDropDownIndexArray = array of integer;

  TDropDownResolveStatus = (
    drsNoMatch,
    drsValueMatch,
    drsDescriptionMatch,
    drsDisplayMatch,
    drsAmbiguous
  );

  TDropDownResolution = record
    Status: TDropDownResolveStatus;
    Value: string;
    MatchIndex: integer;
    CandidateIndexes: TDropDownIndexArray;
  end;

function DropDownTextEquals(const A, B: string): boolean;
function DropDownDisplayText(const Item: TDropDownItem;
  DescriptionOnly: boolean): string;
function ResolveDropDownInput(const Items: TDropDownItems;
  const Input: string; DescriptionOnly: boolean;
  out Resolution: TDropDownResolution): boolean;
function FilterDropDownItems(const Items: TDropDownItems;
  const Query: string; DescriptionOnly: boolean): TDropDownIndexArray;

implementation

function DropDownTextEquals(const A, B: string): boolean;
begin
  Result := CompareText(A, B) = 0;
end;

function DropDownDisplayText(const Item: TDropDownItem;
  DescriptionOnly: boolean): string;
begin
  if DescriptionOnly then
    Result := Item.Description
  else
    Result := Item.Value + ' : ' + Item.Description;
end;

procedure ResetResolution(out Resolution: TDropDownResolution);
begin
  Resolution.Status := drsNoMatch;
  Resolution.Value := '';
  Resolution.MatchIndex := -1;
  SetLength(Resolution.CandidateIndexes, 0);
end;

procedure AddCandidate(var Candidates: TDropDownIndexArray; Index: integer);
var
  L: integer;
begin
  L := Length(Candidates);
  SetLength(Candidates, L + 1);
  Candidates[L] := Index;
end;

function IsSamePair(const A, B: TDropDownItem): boolean;
begin
  Result := DropDownTextEquals(A.Value, B.Value) and
    DropDownTextEquals(A.Description, B.Description);
end;

function IsDuplicatePair(const Items: TDropDownItems; Index: integer): boolean;
var
  I: integer;
begin
  Result := false;
  for I := 0 to Index - 1 do
    if IsSamePair(Items[I], Items[Index]) then
      exit(true);
end;

function ResolveDropDownInput(const Items: TDropDownItems;
  const Input: string; DescriptionOnly: boolean;
  out Resolution: TDropDownResolution): boolean;
var
  I: integer;
  Lookup: string;
  FirstDescriptionIndex: integer;
  DescriptionValue: string;
  HasConflictingDescriptionValue: boolean;
  DisplayText: string;
  SeparatorIndex: integer;
  PairValue, PairDescription: string;
begin
  ResetResolution(Resolution);
  Lookup := Trim(Input);
  if Lookup = '' then
    exit(false);

  { A raw backing value always wins.  This preserves the historical meaning of
    editable dropdown input, even when another item happens to use that text as
    its description. }
  for I := 0 to High(Items) do
    if DropDownTextEquals(Lookup, Items[I].Value) then
    begin
      Resolution.Status := drsValueMatch;
      Resolution.Value := Items[I].Value;
      Resolution.MatchIndex := I;
      exit(true);
    end;

  { Accept the rendered pair with flexible whitespace around its separator.
    This also makes copied rows portable between description-only and full
    dropdown presentation modes. }
  SeparatorIndex := Pos(':', Lookup);
  if SeparatorIndex > 0 then
  begin
    PairValue := Trim(Copy(Lookup, 1, SeparatorIndex - 1));
    PairDescription := Trim(Copy(Lookup, SeparatorIndex + 1,
      Length(Lookup)));
    for I := 0 to High(Items) do
      if DropDownTextEquals(PairValue, Items[I].Value) and
        DropDownTextEquals(PairDescription, Items[I].Description) then
      begin
        Resolution.Status := drsDisplayMatch;
        Resolution.Value := Items[I].Value;
        Resolution.MatchIndex := I;
        exit(true);
      end;
  end;

  { A fully rendered value/description pair is unambiguous even when several
    entries share the same human-readable description. }
  for I := 0 to High(Items) do
  begin
    DisplayText := DropDownDisplayText(Items[I], DescriptionOnly);
    if ((not DescriptionOnly) and DropDownTextEquals(Lookup, DisplayText)) or
      DropDownTextEquals(Lookup,
        Items[I].Value + ' : ' + Items[I].Description) or
      DropDownTextEquals(Lookup,
        Items[I].Value + ':' + Items[I].Description) then
    begin
      Resolution.Status := drsDisplayMatch;
      Resolution.Value := Items[I].Value;
      Resolution.MatchIndex := I;
      exit(true);
    end;
  end;

  FirstDescriptionIndex := -1;
  DescriptionValue := '';
  HasConflictingDescriptionValue := false;
  for I := 0 to High(Items) do
    if DropDownTextEquals(Lookup, Items[I].Description) then
    begin
      if not IsDuplicatePair(Items, I) then
        AddCandidate(Resolution.CandidateIndexes, I);

      if FirstDescriptionIndex = -1 then
      begin
        FirstDescriptionIndex := I;
        DescriptionValue := Items[I].Value;
      end
      else if not DropDownTextEquals(DescriptionValue, Items[I].Value) then
        HasConflictingDescriptionValue := true;
    end;

  if FirstDescriptionIndex <> -1 then
  begin
    if HasConflictingDescriptionValue then
    begin
      Resolution.Status := drsAmbiguous;
      Resolution.MatchIndex := -1;
      Result := false;
    end
    else
    begin
      Resolution.Status := drsDescriptionMatch;
      Resolution.Value := Items[FirstDescriptionIndex].Value;
      Resolution.MatchIndex := FirstDescriptionIndex;
      Result := true;
    end;
    exit;
  end;

  Result := false;
end;

function StartsWithText(const Text, Prefix: string): boolean;
begin
  Result := (Prefix <> '') and
    (CompareText(Copy(Text, 1, Length(Prefix)), Prefix) = 0);
end;

function ContainsText(const Text, Fragment: string): boolean;
begin
  Result := (Fragment <> '') and
    (Pos(AnsiUpperCase(Fragment), AnsiUpperCase(Text)) > 0);
end;

function MatchRank(const Item: TDropDownItem; const Query: string;
  DescriptionOnly: boolean): integer;
var
  DisplayText: string;
begin
  DisplayText := DropDownDisplayText(Item, DescriptionOnly);

  if DropDownTextEquals(Item.Description, Query) or
     DropDownTextEquals(Item.Value, Query) or
     DropDownTextEquals(DisplayText, Query) then
    exit(0);

  if StartsWithText(Item.Description, Query) then
    exit(1);
  if StartsWithText(Item.Value, Query) then
    exit(2);
  if ContainsText(Item.Description, Query) then
    exit(3);
  if ContainsText(Item.Value, Query) or ContainsText(DisplayText, Query) then
    exit(4);

  Result := -1;
end;

function FilterDropDownItems(const Items: TDropDownItems;
  const Query: string; DescriptionOnly: boolean): TDropDownIndexArray;
var
  Rank, I, L: integer;
  Lookup: string;
begin
  Result := nil;
  Lookup := Trim(Query);

  for Rank := 0 to 4 do
    for I := 0 to High(Items) do
      if (not IsDuplicatePair(Items, I)) and
        (((Lookup = '') and (Rank = 0)) or
         ((Lookup <> '') and (MatchRank(Items[I], Lookup,
           DescriptionOnly) = Rank))) then
      begin
        L := Length(Result);
        SetLength(Result, L + 1);
        Result[L] := I;
      end;
end;

end.
