{$mode delphi}{$H+}

uses
  Classes,
  Graphics,
  GraphUtil,
  Interfaces,
  SysUtils,
  Windows;

procedure FindFiles(const Pattern: string; const FileList: TStringList);
var
  SR: TSearchRec;
begin
  if SysUtils.FindFirst(Pattern, faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Attr and faDirectory) = 0 then
          FileList.Add(ConcatPaths([ExtractFilePath(Pattern), SR.Name]));
      until FindNext(SR) <> 0;
    finally
      SysUtils.FindClose(SR);
    end;
end;

function ProcessImage(const InFile, VarName: string; const Rect: TRect): string;
var
  Idx: Integer = 0;
  P: TPicture;
  B: Graphics.TBitmap;
  Values: array of string;
  RGBQuad: PRGBQUAD;
  H, L, S: Byte;
begin
  P := TPicture.Create;
  B := Graphics.TBitmap.Create;
  try
    B.Width := Rect.Width;
    B.Height := Rect.Height;
    B.PixelFormat := pf32bit;

    P.LoadFromFile(InFile);
    if P.Bitmap.PixelFormat <> pf32bit then
      raise Exception.Create('P.Bitmap.PixelFormat <> pf32bit');

    B.Canvas.CopyRect(TRect.Create(0, 0, Rect.Width, Rect.Height), P.Bitmap.Canvas, Rect);

    SetLength(Values, Rect.Width * Rect.Height * 3);

    RGBQuad := PRGBQUAD(B.RawImage.Data);

    while RGBQuad < Pointer(B.RawImage.Data) + (B.Width * B.Height * SizeOf(TRGBQUAD)) do
    begin
      RGBtoHLS(RGBQuad^.rgbRed, RGBQuad^.rgbGreen, RGBQuad^.rgbBlue, H, L, S);

      if (RGBQuad^.rgbGreen <= 130) then
        Values[Idx] := '$01'
      else
        Values[Idx] := '$00';

      Values[Idx + 1] := '$' + HexStr(L, 2);
      Values[Idx + 2] := '$' + HexStr(RGBQuad^.rgbReserved, 2);

      RGBQuad := PRGBQUAD(NativeUInt(RGBQuad) + SizeOf(TRGBQUAD));

      Inc(Idx, 3);
    end;

    Result := '  %sD: array[0..%d] of Byte = (%s);'#13#10'  %s: TNotificationOverlayInfo = (Width: %d; Height: %d; Data: @%sD);'.Format([VarName, Length(Values) - 1, string.Join(', ', Values), VarName, Rect.Width, Rect.Height, VarName]);
  finally
    P.Free;
    B.Free;
  end;
end;

var
  VarIdx: Integer;
  F, VarName, Consts, SwitchFunc, Res: string;
  FileList: TStringList;
  R, To9, To20, Over20: TRect;
  OutFile: TFileStream;
begin
  Res := '';
  Consts := '';
  SwitchFunc := '';

  To9 := TRect.Create(3, 3, 9 + 3, 9 + 3);
  To20 := TRect.Create(2, 3, 11 + 2, 9 + 3);
  Over20 := TRect.Create(0, 3, 15, 9 + 3);

  FileList := TStringList.Create;
  FindFiles(ParamStr(1), FileList);
  try
    FileList.Sort;

    for F in FileList do
    begin
      WriteLn('Processing "%s"...'.Format([F]));

      VarIdx := FileList.IndexOf(F) + 1;

      if VarIdx <= 9 then
        R := To9
      else if VarIdx <= 20 then
        R := To20
      else
        R := Over20;

      VarName := 'NotificationOverlay%d'.Format([VarIdx]);
      Consts += '%s'#13#10.Format([ProcessImage(F, VarName, R)]);

      if VarIdx < FileList.Count then
        SwitchFunc += '  if Value = %d then'#13#10'    Exit(@%s);'#13#10.Format([VarIdx, VarName])
      else
        SwitchFunc += '  if Value >= %d then'#13#10'    Exit(@%s);'#13#10.Format([VarIdx, VarName]);
    end;

    Res := 'unit NotificationOverlays;'#13#10#13#10'interface'#13#10#13#10'type'#13#10'  TPixelData = record'#13#10'    IsBackground: Boolean;'#13#10'    Lightness, Alpha: Byte;'#13#10'  end;'#13#10'  PPixelData = ^TPixelData;'#13#10#13#10'  TNotificationOverlayInfo = record'#13#10'    Width, Height: Byte;'#13#10'    Data: PPixelData;'#13#10'  end;'#13#10'  PNotificationOverlayInfo = ^TNotificationOverlayInfo;'#13#10#13#10'function GetNotificationOverlay(Value: Integer): PNotificationOverlayInfo;'#13#10#13#10'implementation'#13#10#13#10'const'#13#10'%s'#13#10#13#10'function GetNotificationOverlay(Value: Integer): PNotificationOverlayInfo;'#13#10'begin'#13#10'  Result := nil;'#13#10'%s'#13#10'end;'#13#10#13#10'end.'.Format([Consts.TrimRight, SwitchFunc.TrimRight]);

    OutFile := TFileStream.Create(ParamStr(2), fmCreate);
    try
      OutFile.WriteBuffer(Res[1], Res.Length);
    finally
      OutFile.Free;
    end;
  finally
    FileList.Free;
  end;
end.
