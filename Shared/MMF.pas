unit MMF;

interface

uses
  Classes,
  Constants,
  SysUtils,
  Generics.Collections,
  Windows;

type
  TColor = -$7FFFFFFF - 1..$7FFFFFFF;

  { TMMFStream }

  TMMFStream = class(TMemoryStream)
  private
    FCapacity: PtrInt;
  protected
    function Realloc(var NewCapacity: PtrInt): Pointer; override;
    property Capacity: PtrInt read FCapacity write FCapacity;
  end;

  { TMMF }

  TMMF = class
  private
    FHandle, FMutex: THandle;
    FName: string;
    FSize: DWORD;

    procedure InitSecurityAttributes(const PSA: PSecurityAttributes; const PSD: PSecurityDescriptor);
  protected
    procedure ReadStream(const MS: TMemoryStream); virtual; abstract;
    procedure WriteStream(const MS: TMemoryStream); virtual; abstract;
  public
    class function Exists(const Name: string): Boolean; static;

    constructor Create(const Name: string; const Owner: Boolean; const Size: DWORD);
    destructor Destroy; override;

    procedure Read; virtual;
    procedure Write; virtual;
  end;

  { TMMFLauncher }

  TMMFLauncher = class(TMMF)
  private
    FLauncherPid, FWhatsAppGuiPid: Cardinal;
    FLauncherWindowHandle, FWhatsAppWindowHandle: UInt64;
    FResourceSettingsChecksum: UInt16;
    FLogFileName: string;
    FWhatsMissingExe32, FWhatsMissingLib32: string;
    FWhatsMissingExe64, FWhatsMissingLib64: string;
    FJIDMessageTimes: TDictionary<string, UInt64>;

    // Things copied from settings
    FShowNotificationIcon: Boolean;
    FIndicateNewMessages: Boolean;
    FIndicatorColor: TColor;
    FHideMaximize: Boolean;
    FAlwaysOnTop: Boolean;
    FSuppressPresenceAvailable: Boolean;
    FSuppressPresenceComposing: Boolean;
    FSuppressConsecutiveNotificationSounds: Boolean;
  protected
    procedure ReadStream(const MS: TMemoryStream); override;
    procedure WriteStream(const MS: TMemoryStream); override;
  public
    constructor Create(const Owner: Boolean);
    destructor Destroy; override;

    property LauncherPid: Cardinal read FLauncherPid write FLauncherPid;
    property LauncherWindowHandle: UInt64 read FLauncherWindowHandle write FLauncherWindowHandle;
    property WhatsAppGuiPid: Cardinal read FWhatsAppGuiPid write FWhatsAppGuiPid;
    property WhatsAppWindowHandle: UInt64 read FWhatsAppWindowHandle write FWhatsAppWindowHandle;
    property ResourceSettingsChecksum: UInt16 read FResourceSettingsChecksum write FResourceSettingsChecksum;
    property LogFileName: string read FLogFileName write FLogFileName;
    property WhatsMissingExe32: string read FWhatsMissingExe32 write FWhatsMissingExe32;
    property WhatsMissingLib32: string read FWhatsMissingLib32 write FWhatsMissingLib32;
    property WhatsMissingExe64: string read FWhatsMissingExe64 write FWhatsMissingExe64;
    property WhatsMissingLib64: string read FWhatsMissingLib64 write FWhatsMissingLib64;
    property JIDMessageTimes: TDictionary<string, UInt64> read FJIDMessageTimes;

    property ShowNotificationIcon: Boolean read FShowNotificationIcon write FShowNotificationIcon;
    property IndicateNewMessages: Boolean read FIndicateNewMessages write FIndicateNewMessages;
    property IndicatorColor: TColor read FIndicatorColor write FIndicatorColor;
    property HideMaximize: Boolean read FHideMaximize write FHideMaximize;
    property AlwaysOnTop: Boolean read FAlwaysOnTop write FAlwaysOnTop;
    property SuppressPresenceAvailable: Boolean read FSuppressPresenceAvailable write FSuppressPresenceAvailable;
    property SuppressPresenceComposing: Boolean read FSuppressPresenceComposing write FSuppressPresenceComposing;
    property SuppressConsecutiveNotificationSounds: Boolean read FSuppressConsecutiveNotificationSounds write FSuppressConsecutiveNotificationSounds;
  end;

  { TMMFSettings }

  TMMFSettings = class(TMMF)
  private
    FSettingsPid: Cardinal;
    FSettingsWindowHandle: UInt64;
  protected
    procedure ReadStream(const MS: TMemoryStream); override;
    procedure WriteStream(const MS: TMemoryStream); override;
  public
    constructor Create(const Owner: Boolean);

    property SettingsPid: Cardinal read FSettingsPid write FSettingsPid;
    property SettingsWindowHandle: UInt64 read FSettingsWindowHandle write FSettingsWindowHandle;
  end;

  { TMMFResources }

  TMMFResources = class(TMMF)
  private
    FJSON: TMemoryStream;
    FResources: TMemoryStream;
    FContentOffset: Cardinal;
  protected
    procedure ReadStream(const MS: TMemoryStream); override;
    procedure WriteStream(const MS: TMemoryStream); override;
  public
    class function GetMMFName(ResourceFilePath: string): string; static;
    class function GetEventName(ResourceFilePath: string): string; static;

    constructor Create(const ResourceFilePath: string; const Owner: Boolean);
    destructor Destroy; override;

    procedure Write(const JSON: TMemoryStream; const Resources: TMemoryStream; const ContentOffset: Cardinal); reintroduce;

    property JSON: TMemoryStream read FJSON;
    property Resources: TMemoryStream read FResources;
    property ContentOffset: Cardinal read FContentOffset;
  end;

implementation

uses
  Functions;

{ TMMF }

class function TMMF.Exists(const Name: string): Boolean;
var
  Handle: THandle;
begin
  try
    Handle := TFunctions.OpenFileMapping(FILE_MAP_READ, False, Name);
  except
    Exit(False);
  end;

  CloseHandle(Handle);
  Exit(True);
end;

constructor TMMF.Create(const Name: string; const Owner: Boolean; const Size: DWORD);
var
  SA: TSecurityAttributes;
  SD: TSecurityDescriptor;
begin
  if Name = '' then
    raise Exception.Create('Name = ''''');

  FName := Name;
  FSize := Size;

  if Owner then
  begin
    InitSecurityAttributes(@SA, @SD);
    FHandle := TFunctions.CreateFileMapping(INVALID_HANDLE_VALUE, @SA, PAGE_READWRITE, 0, Size, FName);
  end else
    FHandle := TFunctions.OpenFileMapping(FILE_MAP_ALL_ACCESS, False, FName);

  try
    FMutex := TFunctions.CreateMutex(nil, False, Name + 'Mutex');
  except
    CloseHandle(FHandle);
    raise;
  end;
end;

destructor TMMF.Destroy;
begin
  CloseHandle(FHandle);
  CloseHandle(FMutex);

  inherited;
end;

procedure TMMF.InitSecurityAttributes(const PSA: PSecurityAttributes; const PSD: PSecurityDescriptor);
begin
  if not InitializeSecurityDescriptor(PSD, SECURITY_DESCRIPTOR_REVISION) then
    raise Exception.Create('Error initializing security descriptor');
  if not SetSecurityDescriptorDacl(PSD, True, nil, False) then
    raise Exception.Create('Error setting security descriptor dacl');
  PSA.nLength := SizeOf(TSecurityAttributes);
  PSA.lpSecurityDescriptor := PSD;
  PSA.bInheritHandle := False;
end;

procedure TMMF.Read;
var
  Mem: Pointer;
  MS: TMMFStream;
begin
  WaitForSingleObject(FMutex, INFINITE);
  try
    Mem := MapViewOfFile(FHandle, FILE_MAP_READ, 0, 0, FSize);
    if not Assigned(Mem) then
      raise Exception.Create('MapViewOfFile() failed: %d'.Format([GetLastError]));

    MS := TMMFStream.Create;
    try
      MS.SetPointer(Mem, FSize);
      ReadStream(MS);
    finally
      MS.Free;

      UnmapViewOfFile(Mem);
    end;
  finally
    ReleaseMutex(FMutex);
  end;
end;

procedure TMMF.Write;
var
  Mem: Pointer;
  MS: TMMFStream;
begin
  WaitForSingleObject(FMutex, INFINITE);
  try
    Mem := MapViewOfFile(FHandle, FILE_MAP_WRITE, 0, 0, FSize);
    if not Assigned(Mem) then
      raise Exception.Create('MapViewOfFile() failed: %d'.Format([GetLastError]));

    MS := TMMFStream.Create;
    try
      MS.SetPointer(Mem, FSize);
      WriteStream(MS);
    finally
      MS.Free;

      UnmapViewOfFile(Mem);
    end;
  finally
    ReleaseMutex(FMutex);
  end;
end;

{ TMMFStream }

function TMMFStream.Realloc(var NewCapacity: PtrInt): Pointer;
begin
  Result := nil;
end;

{ TMMFLauncher }

constructor TMMFLauncher.Create(const Owner: Boolean);
begin
  inherited Create(MMFNAME_LAUNCHER, Owner, 8192);

  FJIDMessageTimes := TDictionary<string, UInt64>.Create;
end;

destructor TMMFLauncher.Destroy;
begin
  FJIDMessageTimes.Free;

  inherited Destroy;
end;

procedure TMMFLauncher.ReadStream(const MS: TMemoryStream);
var
  i: Integer;
  StrLength, Len: UInt16;
  Str: string;
  UI64: UInt64;
begin
  MS.ReadBuffer(FLauncherPid, SizeOf(FLauncherPid));
  MS.ReadBuffer(FLauncherWindowHandle, SizeOf(FLauncherWindowHandle));
  MS.ReadBuffer(FWhatsAppGuiPid, SizeOf(FWhatsAppGuiPid));
  MS.ReadBuffer(FWhatsAppWindowHandle, SizeOf(FWhatsAppWindowHandle));
  MS.ReadBuffer(FResourceSettingsChecksum, SizeOf(FResourceSettingsChecksum));

  MS.ReadBuffer(StrLength, SizeOf(StrLength));
  SetLength(FLogFileName, StrLength);
  MS.ReadBuffer(FLogFileName[1], StrLength);

  MS.ReadBuffer(StrLength, SizeOf(StrLength));
  SetLength(FWhatsMissingExe32, StrLength);
  MS.ReadBuffer(FWhatsMissingExe32[1], StrLength);

  MS.ReadBuffer(StrLength, SizeOf(StrLength));
  SetLength(FWhatsMissingLib32, StrLength);
  MS.ReadBuffer(FWhatsMissingLib32[1], StrLength);

  MS.ReadBuffer(StrLength, SizeOf(StrLength));
  SetLength(FWhatsMissingExe64, StrLength);
  MS.ReadBuffer(FWhatsMissingExe64[1], StrLength);

  MS.ReadBuffer(StrLength, SizeOf(StrLength));
  SetLength(FWhatsMissingLib64, StrLength);
  MS.ReadBuffer(FWhatsMissingLib64[1], StrLength);

  MS.ReadBuffer(Len, SizeOf(UInt16));
  for i := 0 to Len - 1 do
  begin
    MS.ReadBuffer(StrLength, SizeOf(StrLength));
    SetLength(Str, StrLength);
    MS.ReadBuffer(Str[1], StrLength);

    MS.ReadBuffer(UI64, SizeOf(UI64));

    FJIDMessageTimes.AddOrSetValue(Str, UI64);
  end;

  MS.ReadBuffer(FShowNotificationIcon, SizeOf(FShowNotificationIcon));
  MS.ReadBuffer(FIndicateNewMessages, SizeOf(FIndicateNewMessages));
  MS.ReadBuffer(FIndicatorColor, SizeOf(FIndicatorColor));
  MS.ReadBuffer(FHideMaximize, SizeOf(FHideMaximize));
  MS.ReadBuffer(FAlwaysOnTop, SizeOf(FAlwaysOnTop));
  MS.ReadBuffer(FSuppressPresenceAvailable, SizeOf(FSuppressPresenceAvailable));
  MS.ReadBuffer(FSuppressPresenceComposing, SizeOf(FSuppressPresenceComposing));
  MS.ReadBuffer(FSuppressConsecutiveNotificationSounds, SizeOf(FSuppressConsecutiveNotificationSounds));
end;

procedure TMMFLauncher.WriteStream(const MS: TMemoryStream);
var
  StrLength, Len: UInt16;
  Str: string;
  UI64: UInt64;
begin
  MS.WriteBuffer(FLauncherPid, SizeOf(FLauncherPid));
  MS.WriteBuffer(FLauncherWindowHandle, SizeOf(FLauncherWindowHandle));
  MS.WriteBuffer(FWhatsAppGuiPid, SizeOf(FWhatsAppGuiPid));
  MS.WriteBuffer(FWhatsAppWindowHandle, SizeOf(FWhatsAppWindowHandle));
  MS.WriteBuffer(FResourceSettingsChecksum, SizeOf(FResourceSettingsChecksum));

  StrLength := FLogFileName.Length;
  MS.WriteBuffer(StrLength, SizeOf(StrLength));
  MS.WriteBuffer(FLogFileName[1], StrLength);

  StrLength := FWhatsMissingExe32.Length;
  MS.WriteBuffer(StrLength, SizeOf(StrLength));
  MS.WriteBuffer(FWhatsMissingExe32[1], StrLength);

  StrLength := FWhatsMissingLib32.Length;
  MS.WriteBuffer(StrLength, SizeOf(StrLength));
  MS.WriteBuffer(FWhatsMissingLib32[1], StrLength);

  StrLength := FWhatsMissingExe64.Length;
  MS.WriteBuffer(StrLength, SizeOf(StrLength));
  MS.WriteBuffer(FWhatsMissingExe64[1], StrLength);

  StrLength := FWhatsMissingLib64.Length;
  MS.WriteBuffer(StrLength, SizeOf(StrLength));
  MS.WriteBuffer(FWhatsMissingLib64[1], StrLength);

  Len := FJIDMessageTimes.Count;
  MS.WriteBuffer(Len, SizeOf(Len));
  for Str in FJIDMessageTimes.Keys do
  begin
    StrLength := Str.Length;
    MS.WriteBuffer(StrLength, SizeOf(StrLength));
    MS.WriteBuffer(Str[1], StrLength);

    UI64 := FJIDMessageTimes[Str];
    MS.WriteBuffer(UI64, SizeOf(UI64));
  end;

  MS.WriteBuffer(FShowNotificationIcon, SizeOf(FShowNotificationIcon));
  MS.WriteBuffer(FIndicateNewMessages, SizeOf(FIndicateNewMessages));
  MS.WriteBuffer(FIndicatorColor, SizeOf(FIndicatorColor));
  MS.WriteBuffer(FHideMaximize, SizeOf(FHideMaximize));
  MS.WriteBuffer(FAlwaysOnTop, SizeOf(FAlwaysOnTop));
  MS.WriteBuffer(FSuppressPresenceAvailable, SizeOf(FSuppressPresenceAvailable));
  MS.WriteBuffer(FSuppressPresenceComposing, SizeOf(FSuppressPresenceComposing));
  MS.WriteBuffer(FSuppressConsecutiveNotificationSounds, SizeOf(FSuppressConsecutiveNotificationSounds));
end;

{ TMMFSettings }

constructor TMMFSettings.Create(const Owner: Boolean);
begin
  inherited Create(MMFNAME_SETTINGS, Owner, 8192);
end;

procedure TMMFSettings.ReadStream(const MS: TMemoryStream);
begin
  MS.ReadBuffer(FSettingsPid, SizeOf(FSettingsPid));
  MS.ReadBuffer(FSettingsWindowHandle, SizeOf(FSettingsWindowHandle));
end;

procedure TMMFSettings.WriteStream(const MS: TMemoryStream);
begin
  MS.WriteBuffer(FSettingsPid, SizeOf(FSettingsPid));
  MS.WriteBuffer(FSettingsWindowHandle, SizeOf(FSettingsWindowHandle));
end;

{ TMMFResources }

class function TMMFResources.GetMMFName(ResourceFilePath: string): string;
begin
  Result := MMFNAME_RESOURCES.Format([AnsiLowerCaseFileName(ResourceFilePath).GetHashCode]);
end;

class function TMMFResources.GetEventName(ResourceFilePath: string): string;
begin
  Result := EVENTNAME_RESOURCES.Format([AnsiLowerCaseFileName(ResourceFilePath).GetHashCode]);
end;

constructor TMMFResources.Create(const ResourceFilePath: string; const Owner: Boolean);
begin
  inherited Create(GetMMFName(ResourceFilePath), Owner, 1024 * 1024 * 5);

  FJSON := TMemoryStream.Create;
  FResources := TMemoryStream.Create;
end;

destructor TMMFResources.Destroy;
begin
  FJSON.Free;
  FResources.Free;

  inherited Destroy;
end;

procedure TMMFResources.Write(const JSON: TMemoryStream; const Resources: TMemoryStream; const ContentOffset: Cardinal);
begin
  FJSON.CopyFrom(JSON, 0);
  FResources.CopyFrom(Resources, 0);
  FContentOffset := ContentOffset;

  inherited Write;

  FJSON.Clear;
  FResources.Clear;
end;

procedure TMMFResources.ReadStream(const MS: TMemoryStream);
var
  StreamLen: Cardinal;
begin
  MS.ReadBuffer(FContentOffset, SizeOf(FContentOffset));

  FJSON.Clear;
  MS.ReadBuffer(StreamLen, SizeOf(StreamLen));
  FJSON.CopyFrom(MS, StreamLen);

  FResources.Clear;
  MS.ReadBuffer(StreamLen, SizeOf(StreamLen));
  FResources.CopyFrom(MS, StreamLen);
end;

procedure TMMFResources.WriteStream(const MS: TMemoryStream);
var
  StreamLen: Cardinal;
begin
  MS.WriteBuffer(FContentOffset, SizeOf(FContentOffset));

  StreamLen := FJSON.Size;
  MS.WriteBuffer(StreamLen, SizeOf(StreamLen));
  FJSON.Position := 0;
  MS.CopyFrom(FJSON, 0);

  StreamLen := FResources.Size;
  MS.WriteBuffer(StreamLen, SizeOf(StreamLen));
  FResources.Position := 0;
  MS.CopyFrom(FResources, 0);
end;

end.

