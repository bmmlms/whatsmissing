unit ColorFunctions;

interface

uses
  Classes,
  SysUtils,
  Windows;

type
  TColor = -$7FFFFFFF - 1..$7FFFFFFF;

function ColorToGray(const AColor: TColor): Byte;
procedure ColorToHLS(const AColor: TColor; out H, L, S: Byte);
procedure RGBtoHLS(const R, G, B: Byte; out H, L, S: Byte);
function HLStoColor(const H, L, S: Byte): TColor;
procedure HLStoRGB(const H, L, S: Byte; out R, G, B: Byte);

implementation

function ColorToRGB(Color: TColor): Longint;
begin
  Result := Color and $FFFFFF;
end;

procedure ExtractRGB(RGB: TColorRef; out R, G, B: Byte); inline;
begin
  R := RGB and $FF;
  G := (RGB shr 8) and $FF;
  B := (RGB shr 16) and $FF;
end;

function ColorToGray(const AColor: TColor): Byte;
var
  RGB: TColorRef;
begin
  RGB := ColorToRGB(AColor);
  Result := Trunc(0.222 * (RGB and $FF) + 0.707 * ((RGB shr 8) and $FF) + 0.071 * (RGB shr 16 and $FF));
end;

procedure ColorToHLS(const AColor: TColor; out H, L, S: Byte);
var
  R, G, B: Byte;
  RGB: TColorRef;
begin
  RGB := ColorToRGB(AColor);
  ExtractRGB(RGB, R, G, B);

  RGBtoHLS(R, G, B, H, L, S);
end;

function HLStoColor(const H, L, S: Byte): TColor;
var
  R, G, B: Byte;
begin
  HLStoRGB(H, L, S, R, G, B);
  Result := R or (G shl 8) or (B shl 16);
end;

procedure RGBtoHLS(const R, G, B: Byte; out H, L, S: Byte);
var
  aDelta, aMin, aMax: Byte;
begin
  aMin := min(min(R, G), B);
  aMax := max(max(R, G), B);
  aDelta := aMax - aMin;
  if aDelta > 0 then
    if aMax = B
    then
      H := round(170 + 42.5 * (R - G) / aDelta)   { 2*255/3; 255/6 }
    else if aMax = G
    then
      H := round(85 + 42.5 * (B - R) / aDelta)  { 255/3 }
    else if G >= B
    then
      H := round(42.5 * (G - B) / aDelta)
    else
      H := round(255 + 42.5 * (G - B) / aDelta);
  L := (aMax + aMin) div 2;
  if (L = 0) or (aDelta = 0)
  then
    S := 0
  else if L <= 127
  then
    S := round(255 * aDelta / (aMax + aMin))
  else
    S := round(255 * aDelta / (510 - aMax - aMin));
end;

procedure HLSToRGB(const H, L, S: Byte; out R, G, B: Byte);
var
  hue, chroma, x: Single;
begin
  if S > 0 then
  begin  { color }
    hue := 6 * H / 255;
    chroma := S * (1 - abs(0.0078431372549 * L - 1));  { 2/255 }
    G := trunc(hue);
    B := L - round(0.5 * chroma);
    x := B + chroma * (1 - abs(hue - 1 - G and 254));
    case G of
      0:
      begin
        R := B + round(chroma);
        G := round(x);
      end;
      1:
      begin
        R := round(x);
        G := B + round(chroma);
      end;
      2:
      begin
        R := B;
        G := B + round(chroma);
        B := round(x);
      end;
      3:
      begin
        R := B;
        G := round(x);
        Inc(B, round(chroma));
      end;
      4:
      begin
        R := round(x);
        G := B;
        Inc(B, round(chroma));
      end;
      otherwise
        R := B + round(chroma);
        G := B;
        B := round(x);
    end;
  end else
  begin  { grey }
    R := L;
    G := L;
    B := L;
  end;
end;

procedure ColorRGBToHLS(clrRGB: COLORREF; var Hue, Luminance, Saturation: Word);
var
  H, L, S: Byte;
begin
  ColorToHLS(clrRGB, H, L, S);
  Hue := H;
  Luminance := L;
  Saturation := S;
end;

function ColorHLSToRGB(Hue, Luminance, Saturation: Word): TColorRef;
begin
  Result := HLStoColor(Hue, Luminance, Saturation);
end;

function ColorAdjustLuma(clrRGB: TColor; n: Integer): TColor;
var
  H, L, S: Byte;
begin
  ColorToHLS(clrRGB, H, L, S);
  Result := HLStoColor(H, L + n, S);
end;

end.
