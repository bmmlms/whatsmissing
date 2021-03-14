unit VirtualFile;

interface

uses
  Classes,
  Generics.Collections,
  Windows,
  Functions,
  SysUtils;

type

  { TVirtualFileRegion }

  TVirtualFileRegion = class
  private
    FVirtualStart: Cardinal;
    FVirtualEnd: Cardinal;
    FLength: Cardinal;

    procedure FRead(const Buffer: Pointer; const Start, Length: Cardinal); virtual; abstract;
  end;

  { TVirtualFileRegionDisk }

  TVirtualFileRegionDisk = class(TVirtualFileRegion)
  private
    FFileHandle, FMappingHandle: THandle;
    FMem: Pointer;
    FStart: Cardinal;

    procedure FRead(const Buffer: Pointer; const Start, Length: Cardinal); override;
  public
    constructor Create(const FileName: string; const Start: Cardinal; const Length: Cardinal = 0);
    destructor Destroy; override;
  end;

  { TVirtualFileRegionMemory }

  TVirtualFileRegionMemory = class(TVirtualFileRegion)
  private
    FAddress: Pointer;

    procedure FRead(const Buffer: Pointer; const Start, Length: Cardinal); override;
  public
    constructor Create(const Address: Pointer; const Length: Cardinal);
    destructor Destroy; override;
  end;

  { TVirtualFile }

  TVirtualFile = class
  private
    FPosition: Cardinal;
    FRegions: TList<TVirtualFileRegion>;
    FSize: Cardinal;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddRegion(const Region: TVirtualFileRegion);
    procedure Read(const Buffer: Pointer; const BytesToRead: Cardinal; const BytesRead: PCardinal);

    property Size: Cardinal read FSize;
    property Position: Cardinal read FPosition write FPosition;
  end;

implementation

{ TVirtualFileRegionMemory }

procedure TVirtualFileRegionMemory.FRead(const Buffer: Pointer; const Start, Length: Cardinal);
begin
  CopyMemory(Buffer, FAddress + Start, Length);
end;

constructor TVirtualFileRegionMemory.Create(const Address: Pointer; const Length: Cardinal);
begin
  FAddress := Address;
  FLength := Length;
end;

destructor TVirtualFileRegionMemory.Destroy;
begin
  inherited Destroy;
end;

{ TVirtualFileRegionDisk }

procedure TVirtualFileRegionDisk.FRead(const Buffer: Pointer; const Start, Length: Cardinal);
begin
  CopyMemory(Buffer, FMem + FStart + Start, Length);
end;

constructor TVirtualFileRegionDisk.Create(const FileName: string; const Start: Cardinal; const Length: Cardinal = 0);
begin
  try
    FFileHandle := TFunctions.CreateFile(FileName, $AFFEAFFE, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);

    FMappingHandle := TFunctions.CreateFileMapping(FFileHandle, nil, PAGE_READONLY, 0, 0, '');

    FMem := MapViewOfFile(FMappingHandle, FILE_MAP_READ, 0, 0, 0);
    if not Assigned(FMem) then
      raise Exception.Create('MapViewOfFile() failed: %d'.Format([GetLastError]));

    FStart := Start;

    FLength := Length;
    if FLength = 0 then
      FLength := GetFileSize(FFileHandle, nil) - Start;
  except
    if Assigned(FMem) then
      UnmapViewOfFile(FMem);
    if FMappingHandle > 0 then
      CloseHandle(FMappingHandle);
    if FFileHandle > 0 then
      CloseHandle(FFileHandle);
  end;
end;

destructor TVirtualFileRegionDisk.Destroy;
begin
  UnmapViewOfFile(FMem);
  CloseHandle(FMappingHandle);
  CloseHandle(FFileHandle);

  inherited Destroy;
end;

{ TVirtualFile }

constructor TVirtualFile.Create;
begin
  FRegions := TList<TVirtualFileRegion>.Create;
end;

destructor TVirtualFile.Destroy;
var
  VirtualFileRegion: TVirtualFileRegion;
begin
  for VirtualFileRegion in FRegions do
    VirtualFileRegion.Free;

  FRegions.Free;

  inherited Destroy;
end;

procedure TVirtualFile.AddRegion(const Region: TVirtualFileRegion);
begin
  FRegions.Add(Region);

  Region.FVirtualStart := FSize;
  Region.FVirtualEnd := FSize + Region.FLength;

  FSize += Region.FLength;
end;

procedure TVirtualFile.Read(const Buffer: Pointer; const BytesToRead: Cardinal; const BytesRead: PCardinal);

  function Min(a, b: Cardinal): Cardinal; inline;
  begin
    if a < b then
      Result := a
    else
      Result := b;
  end;

  function InRange(const Value, Min, Max: Cardinal): Boolean; inline;
  begin
    Result := (Value >= Min) and (Value < Max);
  end;

var
  VFR: TVirtualFileRegion;
  BytesLeft, BTR: Cardinal;
begin
  BytesRead^ := 0;
  BytesLeft := BytesToRead;

  for VFR in FRegions do
  begin
    if BytesLeft = 0 then
      Break;

    if InRange(FPosition, VFR.FVirtualStart, VFR.FVirtualEnd) then
    begin
      BTR := Min(BytesLeft, VFR.FLength - (FPosition - VFR.FVirtualStart));

      VFR.FRead(Buffer + (BytesToRead - BytesLeft), FPosition - VFR.FVirtualStart, BTR);

      BytesRead^ += BTR;
      BytesLeft -= BTR;

      FPosition += BTR;;
    end;
  end;
end;

end.


