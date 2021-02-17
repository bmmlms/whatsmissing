unit MMF;

interface

uses
  Classes,
  Constants,
  SysUtils,
  Windows;

type
  TMMFStream = class(TMemoryStream)
  private
    FCapacity: PtrInt;
  protected
    function Realloc(var NewCapacity: PtrInt): Pointer; override;
    property Capacity: PtrInt read FCapacity write FCapacity;
  end;

  TMMF = class
  private
    FCriticalSection: TCriticalSection;
    FHandle: THandle;
    FName: string;

    procedure InitSecurityAttributes(const PSA: PSecurityAttributes; const PSD: PSecurityDescriptor);
  protected
    procedure ReadStream(const MS: TMemoryStream); virtual; abstract;
    procedure WriteStream(const MS: TMemoryStream); virtual; abstract;
  public
    class function Exists(const Name: string): Boolean; static;

    constructor Create(const Name: string; const Handle: THandle);
    destructor Destroy; override;

    procedure Read;
    procedure Write;

    property Handle: THandle read FHandle;
  end;

  TMMFLauncher = class(TMMF)
  private
    FLogFileHandle: UInt64;
    FLauncherPid, FWhatsAppGuiPid: Cardinal;
    FLauncherHandle, FLauncherWindowHandle, FWhatsAppWindowHandle: UInt64;
    FWhatsMissingExe32, FWhatsMissingLib32: string;
    FWhatsMissingExe64, FWhatsMissingLib64: string;
  protected
    procedure ReadStream(const MS: TMemoryStream); override;
    procedure WriteStream(const MS: TMemoryStream); override;
  public
    constructor Create(const Handle: THandle = 0);

    property LogFileHandle: UInt64 read FLogFileHandle write FLogFileHandle;
    property LauncherPid: Cardinal read FLauncherPid write FLauncherPid;
    property LauncherHandle: UInt64 read FLauncherHandle write FLauncherHandle;
    property LauncherWindowHandle: UInt64 read FLauncherWindowHandle write FLauncherWindowHandle;
    property WhatsAppGuiPid: Cardinal read FWhatsAppGuiPid write FWhatsAppGuiPid;
    property WhatsAppWindowHandle: UInt64 read FWhatsAppWindowHandle write FWhatsAppWindowHandle;
    property WhatsMissingExe32: string read FWhatsMissingExe32 write FWhatsMissingExe32;
    property WhatsMissingLib32: string read FWhatsMissingLib32 write FWhatsMissingLib32;
    property WhatsMissingExe64: string read FWhatsMissingExe64 write FWhatsMissingExe64;
    property WhatsMissingLib64: string read FWhatsMissingLib64 write FWhatsMissingLib64;
  end;

  TMMFSettings = class(TMMF)
  private
    FSettingsPid: Cardinal;
    FSettingsWindowHandle: UInt64;
  protected
    procedure ReadStream(const MS: TMemoryStream); override;
    procedure WriteStream(const MS: TMemoryStream); override;
  public
    constructor Create;

    property SettingsPid: Cardinal read FSettingsPid write FSettingsPid;
    property SettingsWindowHandle: UInt64 read FSettingsWindowHandle write FSettingsWindowHandle;
  end;

implementation

const
  MMF_SIZE = 8192;

function CreateFileMappingS(hFile: HANDLE; lpFileMappingAttributes: LPSECURITY_ATTRIBUTES; flProtect: DWORD; dwMaximumSizeHigh: DWORD; dwMaximumSizeLow: DWORD; lpName: string): HANDLE;
var
  Name: UnicodeString;
begin
  Name := lpName;
  Result := CreateFileMappingW(hFile, lpFileMappingAttributes, flProtect, dwMaximumSizeHigh, dwMaximumSizeLow, IfThen<PWideChar>(Name = '', nil, PWideChar(Name)));
end;

function OpenFileMappingS(dwDesiredAccess: DWORD; bInheritHandle: WINBOOL; lpName: string): HANDLE;
var
  Name: UnicodeString;
begin
  Name := lpName;
  Result := OpenFileMappingW(dwDesiredAccess, bInheritHandle, IfThen<PWideChar>(Name = '', nil, PWideChar(Name)));
end;

class function TMMF.Exists(const Name: string): Boolean;
var
  Handle: THandle;
begin
  Handle := OpenFileMappingS(FILE_MAP_READ, False, Name);
  if Handle = 0 then
    Exit(False)
  else
  begin
    CloseHandle(Handle);
    Exit(True);
  end;
end;

constructor TMMF.Create(const Name: string; const Handle: THandle);
begin
  InitializeCriticalSection(FCriticalSection);

  FName := Name;
  FHandle := Handle;
end;

destructor TMMF.Destroy;
begin
  if FHandle > 0 then
    CloseHandle(FHandle);

  DeleteCriticalSection(FCriticalSection);

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
  PSA.bInheritHandle := True;
end;

procedure TMMF.Read;
var
  Handle: THandle;
  Mem: Pointer;
  MS: TMMFStream;
begin
  if (FHandle = 0) and (FName = '') then
    raise Exception.Create('(FHandle = 0) and (FName = '''')');

  EnterCriticalSection(FCriticalSection);
  try
    if FHandle = 0 then
    begin
      Handle := OpenFileMappingS(FILE_MAP_READ, False, FName);
      if Handle = 0 then
        raise Exception.Create(Format('OpenFileMapping() failed: %d', [GetLastError]));
    end else
      Handle := FHandle;

    Mem := MapViewOfFile(Handle, FILE_MAP_READ, 0, 0, MMF_SIZE);
    if not Assigned(Mem) then
      raise Exception.Create(Format('MapViewOfFile() failed: %d', [GetLastError]));

    MS := TMMFStream.Create;
    try
      MS.SetPointer(Mem, MMF_SIZE);
      ReadStream(MS);
    finally
      MS.Free;

      UnmapViewOfFile(Mem);

      if FHandle = 0 then
        CloseHandle(Handle);
    end;
  finally
    LeaveCriticalSection(FCriticalSection);
  end;
end;

procedure TMMF.Write;
var
  Handle: THandle;
  Mem: Pointer;
  MS: TMMFStream;
  SA: TSecurityAttributes;
  SD: TSecurityDescriptor;
begin
  if (FHandle = 0) and (FName = '') then
    raise Exception.Create('(FHandle = 0) and (FName = '''')');

  EnterCriticalSection(FCriticalSection);
  try
    if FHandle = 0 then
    begin
      InitSecurityAttributes(@SA, @SD);
      Handle := CreateFileMappingS(INVALID_HANDLE_VALUE, @SA, PAGE_READWRITE, 0, MMF_SIZE, FName);
      if Handle = 0 then
        raise Exception.Create(Format('CreateFileMapping() failed: %d', [GetLastError]));
    end else
      Handle := FHandle;

    Mem := MapViewOfFile(Handle, FILE_MAP_WRITE, 0, 0, MMF_SIZE);
    if not Assigned(Mem) then
      raise Exception.Create(Format('MapViewOfFile() failed: %d', [GetLastError]));

    MS := TMMFStream.Create;
    try
      MS.SetPointer(Mem, MMF_SIZE);
      WriteStream(MS);
    finally
      MS.Free;

      UnmapViewOfFile(Mem);

      if FHandle = 0 then
        FHandle := Handle;
    end;
  finally
    LeaveCriticalSection(FCriticalSection);
  end;
end;

{ TMMFStream }

function TMMFStream.Realloc(var NewCapacity: PtrInt): Pointer;
begin
  Result := nil;
end;

{ TDataLauncher }

constructor TMMFLauncher.Create(const Handle: THandle);
begin
  inherited Create(MMFNAME_LAUNCHER, Handle);
end;

procedure TMMFLauncher.ReadStream(const MS: TMemoryStream);
var
  StrLength: UInt16;
begin
  MS.ReadBuffer(FLogFileHandle, SizeOf(FLogFileHandle));
  MS.ReadBuffer(FLauncherPid, SizeOf(FLauncherPid));
  MS.ReadBuffer(FLauncherHandle, SizeOf(FLauncherHandle));
  MS.ReadBuffer(FLauncherWindowHandle, SizeOf(FLauncherWindowHandle));
  MS.ReadBuffer(FWhatsAppGuiPid, SizeOf(FWhatsAppGuiPid));
  MS.ReadBuffer(FWhatsAppWindowHandle, SizeOf(FWhatsAppWindowHandle));

  MS.ReadBuffer(StrLength, SizeOf(UInt16));
  SetLength(FWhatsMissingExe32, StrLength);
  MS.ReadBuffer(FWhatsMissingExe32[1], StrLength);

  MS.ReadBuffer(StrLength, SizeOf(UInt16));
  SetLength(FWhatsMissingLib32, StrLength);
  MS.ReadBuffer(FWhatsMissingLib32[1], StrLength);

  MS.ReadBuffer(StrLength, SizeOf(UInt16));
  SetLength(FWhatsMissingExe64, StrLength);
  MS.ReadBuffer(FWhatsMissingExe64[1], StrLength);

  MS.ReadBuffer(StrLength, SizeOf(UInt16));
  SetLength(FWhatsMissingLib64, StrLength);
  MS.ReadBuffer(FWhatsMissingLib64[1], StrLength);
end;

procedure TMMFLauncher.WriteStream(const MS: TMemoryStream);
var
  StrLength: UInt16;
begin
  MS.WriteBuffer(FLogFileHandle, SizeOf(FLogFileHandle));
  MS.WriteBuffer(FLauncherPid, SizeOf(FLauncherPid));
  MS.WriteBuffer(FLauncherHandle, SizeOf(FLauncherHandle));
  MS.WriteBuffer(FLauncherWindowHandle, SizeOf(FLauncherWindowHandle));
  MS.WriteBuffer(FWhatsAppGuiPid, SizeOf(FWhatsAppGuiPid));
  MS.WriteBuffer(FWhatsAppWindowHandle, SizeOf(FWhatsAppWindowHandle));

  StrLength := Length(FWhatsMissingExe32);
  MS.WriteBuffer(StrLength, SizeOf(UInt16));
  MS.WriteBuffer(FWhatsMissingExe32[1], StrLength);

  StrLength := Length(FWhatsMissingLib32);
  MS.WriteBuffer(StrLength, SizeOf(UInt16));
  MS.WriteBuffer(FWhatsMissingLib32[1], StrLength);

  StrLength := Length(FWhatsMissingExe64);
  MS.WriteBuffer(StrLength, SizeOf(UInt16));
  MS.WriteBuffer(FWhatsMissingExe64[1], StrLength);

  StrLength := Length(FWhatsMissingLib64);
  MS.WriteBuffer(StrLength, SizeOf(UInt16));
  MS.WriteBuffer(FWhatsMissingLib64[1], StrLength);
end;

{ TDataSettings }

constructor TMMFSettings.Create;
begin
  inherited Create(MMFNAME_SETTINGS, 0);
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

end.

