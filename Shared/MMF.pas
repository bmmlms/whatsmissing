unit MMF;

interface

uses
  Classes,
  Constants,
  DateUtils,
  Generics.Collections,
  SysUtils,
  Windows;

type

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

  { TChat }

  TChat = class
  private
    FJID: string;
    FName: string;
    FMute: Cardinal;
    FSetUnread: Boolean;
    FUnreadMessages: UInt16;
    FLastCommunication: Cardinal;
    FLastNotificationSound: Cardinal;

    procedure FSetName(const Value: string);
    function FGetMuted: Boolean;
  public
    constructor Create(const JID: string); overload;
    constructor Create(const JID, Name: string; const Mute: Cardinal; const SetUnread: Boolean; const UnreadMessages: UInt16; const T: Cardinal; const LastMessageReceived: Cardinal); overload;

    procedure ReadStream(const MS: TMemoryStream);
    procedure WriteStream(const MS: TMemoryStream);

    procedure UpdateLastCommunication;
    procedure SetMute(const Value: Cardinal);
    procedure SetUnreadMessages(const SetUnread: Boolean; const UnreadMessages: UInt16);

    function ToString: string; override;

    property JID: string read FJID;
    property Name: string read FName write FSetName;
    property Muted: Boolean read FGetMuted;
    property SetUnread: Boolean read FSetUnread;
    property UnreadMessages: UInt16 read FUnreadMessages;
    property LastCommunication: Cardinal read FLastCommunication write FLastCommunication;
    property LastNotificationSound: Cardinal read FLastNotificationSound write FLastNotificationSound;
  end;

  { TChatList }

  TChatList = class(TDictionary<string, TChat>)
  public
    destructor Destroy; override;

    procedure Clear; override;

    function Get(const JID: string): TChat;
    procedure GetUnreadChats(const MaxAgeDays: Integer; const MaxToolTipLen: Integer; const ExcludeMuted: Boolean; out Count: Integer; out ToolTip: string);

    procedure ReadStream(const MS: TMemoryStream);
    procedure WriteStream(const MS: TMemoryStream);
  end;

  { TMMFLauncher }

  TMMFLauncher = class(TMMF)
  private
    FReadMinimal: Boolean;

    FLauncherPid, FWhatsAppGuiPid: Cardinal;
    FLauncherWindowHandle, FWhatsAppWindowHandle: UInt64;
    FResourceSettingsChecksum: UInt16;
    FLogFileName: string;
    FWhatsMissingExe32, FWhatsMissingLib32: string;
    FWhatsMissingExe64, FWhatsMissingLib64: string;
    FChats: TChatList;

    // Things copied from settings
    FShowNotificationIcon: Boolean;
    FShowUnreadMessagesBadge: Boolean;
    FExcludeUnreadMessagesMutedChats: Boolean;
    FNotificationIconBadgeColor: LongInt;
    FNotificationIconBadgeTextColor: LongInt;
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

    procedure ReadMinimal;

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
    property Chats: TChatList read FChats;

    property ShowNotificationIcon: Boolean read FShowNotificationIcon write FShowNotificationIcon;
    property ShowUnreadMessagesBadge: Boolean read FShowUnreadMessagesBadge write FShowUnreadMessagesBadge;
    property ExcludeUnreadMessagesMutedChats: Boolean read FExcludeUnreadMessagesMutedChats write FExcludeUnreadMessagesMutedChats;
    property NotificationIconBadgeColor: LongInt read FNotificationIconBadgeColor write FNotificationIconBadgeColor;
    property NotificationIconBadgeTextColor: LongInt read FNotificationIconBadgeTextColor write FNotificationIconBadgeTextColor;
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

    constructor Create(const ResourceFilePath: string; const Owner: Boolean; const Size: DWORD);
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
    FHandle := TFunctions.OpenFileMapping(FILE_MAP_READ or FILE_MAP_WRITE, False, FName);

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
    Mem := MapViewOfFile(FHandle, FILE_MAP_READ, 0, 0, 0);
    if not Assigned(Mem) then
      raise Exception.Create('MapViewOfFile() failed: %d'.Format([GetLastError]));

    MS := TMMFStream.Create;
    try
      MS.SetPointer(Mem, IfThen<PtrInt>(FSize = 0, MaxInt, FSize));
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
    Mem := MapViewOfFile(FHandle, FILE_MAP_WRITE, 0, 0, 0);
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

{ TChat }

constructor TChat.Create(const JID: string);
begin
  FJID := JID;
end;

constructor TChat.Create(const JID, Name: string; const Mute: Cardinal; const SetUnread: Boolean; const UnreadMessages: UInt16; const T: Cardinal; const LastMessageReceived: Cardinal);
begin
  FJID := JID;
  FSetName(Name);
  FMute := Mute;
  FSetUnread := SetUnread;
  FUnreadMessages := UnreadMessages;
  FLastCommunication := T;
  FLastNotificationSound := LastMessageReceived;
end;

procedure TChat.FSetName(const Value: string);
begin
  FName := Value.Replace('?', '').Trim;
end;

function TChat.FGetMuted: Boolean;
begin
  Result := DateTimeToUnix(Now, False) < FMute;
end;

procedure TChat.ReadStream(const MS: TMemoryStream);
begin
  FJID := MS.ReadAnsiString;
  FName := MS.ReadAnsiString;
  FMute := MS.ReadDWord;
  FSetUnread := Boolean(MS.ReadByte);
  FUnreadMessages := MS.ReadWord;
  FLastCommunication := MS.ReadDWord;
  FLastNotificationSound := MS.ReadDWord;
end;

procedure TChat.WriteStream(const MS: TMemoryStream);
begin
  MS.WriteAnsiString(FJID);
  MS.WriteAnsiString(FName);
  MS.WriteDWord(FMute);
  MS.WriteByte(Byte(FSetUnread));
  MS.WriteWord(FUnreadMessages);
  MS.WriteDWord(FLastCommunication);
  MS.WriteDWord(FLastNotificationSound);
end;

procedure TChat.UpdateLastCommunication;
begin
  FLastCommunication := DateTimeToUnix(Now, False)
end;

procedure TChat.SetMute(const Value: Cardinal);
begin
  FMute := Value;
end;

procedure TChat.SetUnreadMessages(const SetUnread: Boolean; const UnreadMessages: UInt16);
begin
  FSetUnread := SetUnread;
  FUnreadMessages := UnreadMessages;
end;

function TChat.ToString: string;
begin
  Result := 'JID %s, Name "%s", Muted %s, MuteExpires %d, SetUnread %s, UnreadMessages %d, T %d, LastMessageReceived %d'
    .Format([FJID, FName, IfThen<string>(FGetMuted, 'True', 'False'), FMute, IfThen<string>(FSetUnread, 'True', 'False'), FUnreadMessages, FLastCommunication, FLastNotificationSound]);
end;

{ TChatList }

destructor TChatList.Destroy;
begin
  Clear;

  inherited Destroy;
end;

procedure TChatList.Clear;
var
  Pair: TPair<string, TChat>;
begin
  for Pair in Self do
    Pair.Value.Free;

  inherited;
end;

function TChatList.Get(const JID: string): TChat;
var
  Chat: TChat;
begin
  if Trim(JID).Length = 0 then
    raise Exception.Create('Trim(JID).Length = 0');

  if TryGetValue(JID, Chat) then
    Exit(Chat);

  Result := TChat.Create(JID);

  Add(JID, Result);
end;

function SortChats(A, B: Pointer): LongInt; register;
begin
  Result := CompareDWord(TChat(B).LastCommunication, TChat(A).LastCommunication, SizeOf(TChat(A).LastCommunication));
end;

procedure TChatList.GetUnreadChats(const MaxAgeDays: Integer; const MaxToolTipLen: Integer; const ExcludeMuted: Boolean; out Count: Integer; out ToolTip: string);
const
  Tail = #13#10'  +%d messages';
var
  Processed: Integer;
  Line: string;
  Chats: TList;
  Chat: TChat;
begin
  Count := 0;
  ToolTip := 'WhatsApp';

  Chats := TList.Create;
  try
    for Chat in Self.Values do
      if (Chat.JID <> 'status@broadcast') and
         (Chat.LastCommunication > DateTimeToUnix(DateUtils.IncDay(Now, -MaxAgeDays), False)) and
         (Chat.SetUnread or (Chat.UnreadMessages > 0)) and
         (not (Chat.Muted and ExcludeMuted)) then
      begin
        Count += IfThen<Integer>(Chat.SetUnread, 1, Chat.UnreadMessages);
        Chats.Add(Chat);
      end;

    Chats.Sort(SortChats);

    Processed := 0;

    for Chat in Chats do
    begin
      if Chat.SetUnread or (Chat.UnreadMessages = 1) then
        Line := #13#10'  %s'.Format([Chat.Name])
      else if Chat.UnreadMessages > 1 then
        Line := #13#10'  %s (%d)'.Format([Chat.Name, Chat.UnreadMessages]);

      if ToolTip.Length + Line.Length + Tail.Length + 2 < MaxToolTipLen then
      begin
        Processed += IfThen<Integer>(Chat.SetUnread, 1, Chat.UnreadMessages);
        ToolTip += Line
      end else
      begin
        ToolTip += Tail.Format([Count - Processed]);
        Break;
      end;
    end;
  finally
    Chats.Free;
  end;
end;

procedure TChatList.ReadStream(const MS: TMemoryStream);
var
  i: Integer;
  Len: UInt16;
  Chat: TChat;
begin
  Clear;

  Len := MS.ReadWord;
  for i := 0 to Len - 1 do
  begin
    Chat := TChat.Create;
    Chat.ReadStream(MS);
    Add(Chat.JID, Chat);
  end;
end;

procedure TChatList.WriteStream(const MS: TMemoryStream);
var
  Chat: TChat;
begin
  MS.WriteWord(Count);

  for Chat in Self.Values do
    Chat.WriteStream(MS);
end;

{ TMMFStream }

function TMMFStream.Realloc(var NewCapacity: PtrInt): Pointer;
begin
  Result := nil;
end;

{ TMMFLauncher }

constructor TMMFLauncher.Create(const Owner: Boolean);
begin
  inherited Create(MMFNAME_LAUNCHER, Owner, 5 * 1024 * 1024);

  FChats := TChatList.Create;
end;

destructor TMMFLauncher.Destroy;
begin
  FChats.Free;

  inherited Destroy;
end;

procedure TMMFLauncher.ReadMinimal;
begin
  FReadMinimal := True;
  try
    Read;
  finally
    FReadMinimal := False;
  end;
end;

procedure TMMFLauncher.ReadStream(const MS: TMemoryStream);
begin
  FLauncherPid := MS.ReadWord;
  FLauncherWindowHandle := MS.ReadQWord;
  FWhatsAppGuiPid := MS.ReadDWord;
  FWhatsAppWindowHandle := MS.ReadQWord;

  if FReadMinimal then
    Exit;

  FResourceSettingsChecksum := MS.ReadWord;

  FLogFileName := MS.ReadAnsiString;
  FWhatsMissingExe32 := MS.ReadAnsiString;
  FWhatsMissingLib32 := MS.ReadAnsiString;
  FWhatsMissingExe64 := MS.ReadAnsiString;
  FWhatsMissingLib64 := MS.ReadAnsiString;

  FChats.ReadStream(MS);

  FShowNotificationIcon := Boolean(MS.ReadByte);
  FShowUnreadMessagesBadge := Boolean(MS.ReadByte);
  FExcludeUnreadMessagesMutedChats := Boolean(MS.ReadByte);
  FNotificationIconBadgeColor := MS.ReadDWord;
  FNotificationIconBadgeTextColor := MS.ReadDWord;
  FHideMaximize := Boolean(MS.ReadByte);
  FAlwaysOnTop := Boolean(MS.ReadByte);

  FSuppressPresenceAvailable := Boolean(MS.ReadByte);
  FSuppressPresenceComposing := Boolean(MS.ReadByte);
  FSuppressConsecutiveNotificationSounds := Boolean(MS.ReadByte);
end;

procedure TMMFLauncher.WriteStream(const MS: TMemoryStream);
begin
  MS.WriteWord(FLauncherPid);
  MS.WriteQWord(FLauncherWindowHandle);
  MS.WriteDWord(FWhatsAppGuiPid);
  MS.WriteQWord(FWhatsAppWindowHandle);
  MS.WriteWord(FResourceSettingsChecksum);

  MS.WriteAnsiString(FLogFileName);
  MS.WriteAnsiString(FWhatsMissingExe32);
  MS.WriteAnsiString(FWhatsMissingLib32);
  MS.WriteAnsiString(FWhatsMissingExe64);
  MS.WriteAnsiString(FWhatsMissingLib64);

  FChats.WriteStream(MS);

  MS.WriteByte(Byte(FShowNotificationIcon));
  MS.WriteByte(Byte(FShowUnreadMessagesBadge));
  MS.WriteByte(Byte(FExcludeUnreadMessagesMutedChats));
  MS.WriteDWord(FNotificationIconBadgeColor);
  MS.WriteDWord(FNotificationIconBadgeTextColor);
  MS.WriteByte(Byte(FHideMaximize));
  MS.WriteByte(Byte(FAlwaysOnTop));
  MS.WriteByte(Byte(FSuppressPresenceAvailable));
  MS.WriteByte(Byte(FSuppressPresenceComposing));
  MS.WriteByte(Byte(FSuppressConsecutiveNotificationSounds));
end;

{ TMMFSettings }

constructor TMMFSettings.Create(const Owner: Boolean);
begin
  inherited Create(MMFNAME_SETTINGS, Owner, 8192);
end;

procedure TMMFSettings.ReadStream(const MS: TMemoryStream);
begin
  FSettingsPid := MS.ReadDWord;
  FSettingsWindowHandle := MS.ReadQWord;
end;

procedure TMMFSettings.WriteStream(const MS: TMemoryStream);
begin
  MS.WriteDWord(FSettingsPid);
  MS.WriteQWord(FSettingsWindowHandle);
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

constructor TMMFResources.Create(const ResourceFilePath: string; const Owner: Boolean; const Size: DWORD);
begin
  inherited Create(GetMMFName(ResourceFilePath), Owner, Size);

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
begin
  FContentOffset := MS.ReadDWord;

  FJSON.Clear;
  FJSON.CopyFrom(MS, MS.ReadQWord);

  FResources.Clear;
  FResources.CopyFrom(MS, MS.ReadQWord);
end;

procedure TMMFResources.WriteStream(const MS: TMemoryStream);
begin
  MS.WriteDWord(FContentOffset);

  MS.WriteQWord(FJSON.Size);
  FJSON.Position := 0;
  MS.CopyFrom(FJSON, 0);

  MS.WriteQWord(FResources.Size);
  FResources.Position := 0;
  MS.CopyFrom(FResources, 0);
end;

end.

