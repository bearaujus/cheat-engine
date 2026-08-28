program MemoryRecordDropdownTests;

{$mode delphi}

uses
  Classes, ConsoleTestRunner, TestMemoryRecordDropdown;

type
  TMemoryRecordDropdownTestRunner = class(TTestRunner);

var
  Runner: TMemoryRecordDropdownTestRunner;
begin
  DefaultFormat := fPlain;
  DefaultRunAllTests := true;
  Runner := TMemoryRecordDropdownTestRunner.Create(nil);
  Runner.Initialize;
  Runner.Title := 'Cheat Engine memory-record dropdown tests';
  Runner.Run;
  Runner.Free;
end.
