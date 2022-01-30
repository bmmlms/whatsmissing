{$mode objfpc}{$H+}

uses
  Classes,
  SysUtils,
  windows;

var
  i: Integer;
  InStream: TFileStream;
  OutTocStream: THandleStream;
begin
  OutTocStream := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
  OutTocStream.WriteByte(ParamCount div 2);

  i := 1;
  while i < ParamCount do
  begin
    OutTocStream.WriteAnsiString(ParamStr(i + 1));
    
    InStream := TFileStream.Create(ParamStr(i), fmOpenRead);
    OutTocStream.WriteDWord(InStream.Size);
    InStream.Free;

    Inc(i, 2);
  end;

  OutTocStream.Free;
end.
