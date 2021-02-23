{$mode objfpc}{$H+}

uses
  Classes,
  SysUtils,
  paszlib;

function CompressStream(InStream: TStream; OutStream: TStream): Integer;
const
  MAX_IN_BUF_SIZE = 4096;
  MAX_OUT_BUF_SIZE = 4096;
var
  Err: Integer;
  Z: TZStream;
var
  InputBuffer: array[0..MAX_IN_BUF_SIZE - 1] of Byte;
  OutputBuffer: array[0..MAX_OUT_BUF_SIZE - 1] of Byte;
  FlushType: LongInt;
begin
  Result := 0;

  FillChar(InputBuffer, SizeOf(InputBuffer), 0);
  Err := deflateInit(Z, 9);

  InStream.Position := 0;
  while InStream.Position < InStream.Size do
  begin
    Z.next_in := @InputBuffer;
    Z.avail_in := InStream.Read(InputBuffer, MAX_IN_BUF_SIZE);

    if InStream.Position = InStream.Size then
      FlushType := Z_FINISH
    else
      FlushType :=  Z_NO_FLUSH;

    repeat
      Z.next_out := @OutputBuffer;
      Z.avail_out := MAX_OUT_BUF_SIZE;
      Err := deflate(Z, FlushType);
      Result += OutStream.Write(OutputBuffer, MAX_OUT_BUF_SIZE - Z.avail_out);
    until Z.avail_out > 0;

    if (err <> Z_OK) and (err <> Z_BUF_ERROR) then
      Break;
  end;

  Err := deflateEnd(Z);
end;      

var
  InStream, OutStream: TFileStream;
begin
  WriteLn(Format('Compressing "%s"...', [ParamStr(1)]));

  InStream := TFileStream.Create(ParamStr(1), fmOpenRead);
  OutStream := TFileStream.Create(ParamStr(2), fmCreate);

  CompressStream(InStream, OutStream);
  
  InStream.Free;
  OutStream.Free;
end.
