unit Settings;

interface

uses
  Classes,
  fpjson,
  Functions,
  Generics.Collections,
  Graphics,
  GraphUtil,
  ImmersiveColors,
  jsonparser,
  md5,
  MMF,
  SysUtils;

type
  TColorType = (ctNone, ctImmersive, ctCustom);
  TColorAdjustment = (caDarken10 = -50, caDarken5 = -25, caDarken3 = -15, caDarken2 = -10, caDarken = -5, caNone = 0, caLighten = 5, caLighten2 = 10, caLighten3 = 15, caLighten5 = 25);

  { TColorSetting }

  TColorSetting = class
  protected
    FID: Integer;
    FDescription: string;
    FColorDefault: TColor;
    FColorCustom: TColor;
    FColorImmersive: TImmersiveColorType;
    FColorType: TColorType;
  public
    constructor Create(const ID: Integer; const Description: string; const ColorDefault: TColor; const ColorImmersive: TImmersiveColorType; const Action: TColorType); overload;
    constructor Create(const ID: Integer; const Description: string; const ColorImmersive: TImmersiveColorType; const Action: TColorType); overload;
    destructor Destroy; override;

    function GetColor(const ColorAdjustment: TColorAdjustment): TColor;

    property ID: Integer read FID;
    property Description: string read FDescription;
    property ColorDefault: TColor read FColorDefault write FColorDefault;
    property ColorCustom: TColor read FColorCustom write FColorCustom;
    property ColorImmersive: TImmersiveColorType read FColorImmersive;
    property ColorType: TColorType read FColorType write FColorType;
  end;

  TTarget = (tCss, tJs);

  { TResourceColorSettingPatch }

  TResourceColorSettingPatch = class
  private
    FSearchText: string;
    FReplaceText: string;
    FRGBNotation: Boolean;
    FColorAdjustment: TColorAdjustment;
    FTarget: TTarget;
    FReplaceFlags: TReplaceFlags;
  public
    constructor Create(const SearchColor: string); overload;
    constructor Create(const SearchText, ReplaceText: string); overload;

    function RBG: TResourceColorSettingPatch;
    function Darken: TResourceColorSettingPatch;
    function Darken3: TResourceColorSettingPatch;
    function Darken5: TResourceColorSettingPatch;
    function Darken10: TResourceColorSettingPatch;
    function Lighten3: TResourceColorSettingPatch;
    function JS: TResourceColorSettingPatch;

    function Execute(const Source: string; const Color: TColor; out Count: Integer): string;

    property SearchText: string read FSearchText;
    property ColorAdjustment: TColorAdjustment read FColorAdjustment;
    property Target: TTarget read FTarget;
  end;

  TResourceColorSettingPatchArray = array of TResourceColorSettingPatch;

  { TResourceColorSetting }

  TResourceColorSetting = class(TColorSetting)
  private
    FPatches: TResourceColorSettingPatchArray;
  public
    constructor Create(const ID: Integer; const Description: string; const ColorCustom: TColor; const ColorImmersive: TImmersiveColorType; const Action: TColorType; const Patches: TResourceColorSettingPatchArray);
    destructor Destroy; override;

    property Patches: TResourceColorSettingPatchArray read FPatches;
  end;

  { TSettings }

  TSettings = class
  private
    FFilePath: string;

    FLastUsedWhatsAppHash: Integer;

    FColorSettings: TList<TColorSetting>;
    FNotificationIconBadgeColor: TColorSetting;
    FNotificationIconBadgeTextColor: TColorSetting;

    FShowNotificationIcon: Boolean;
    FShowUnreadMessagesBadge: Boolean;
    FExcludeUnreadMessagesMutedChats: Boolean;
    FHideMaximize: Boolean;
    FAlwaysOnTop: Boolean;
    FSuppressPresenceAvailable: Boolean;
    FSuppressPresenceComposing: Boolean;
    FSuppressConsecutiveNotificationSounds: Boolean;

    procedure Reset;
    function FGetResourceSettingsChecksum: UInt16;
  public
    constructor Create(const FilePath: string);
    destructor Destroy; override;

    procedure Load;
    procedure Save;

    procedure CopyToMMF(MMF: TMMFLauncher);

    property ResourceSettingsChecksum: UInt16 read FGetResourceSettingsChecksum;

    property LastUsedWhatsAppHash: Integer read FLastUsedWhatsAppHash write FLastUsedWhatsAppHash;

    property ColorSettings: TList<TColorSetting> read FColorSettings;

    property ShowNotificationIcon: Boolean read FShowNotificationIcon write FShowNotificationIcon;
    property ShowUnreadMessagesBadge: Boolean read FShowUnreadMessagesBadge write FShowUnreadMessagesBadge;
    property ExcludeUnreadMessagesMutedChats: Boolean read FExcludeUnreadMessagesMutedChats write FExcludeUnreadMessagesMutedChats;
    property HideMaximize: Boolean read FHideMaximize write FHideMaximize;
    property AlwaysOnTop: Boolean read FAlwaysOnTop write FAlwaysOnTop;
    property SuppressPresenceAvailable: Boolean read FSuppressPresenceAvailable write FSuppressPresenceAvailable;
    property SuppressPresenceComposing: Boolean read FSuppressPresenceComposing write FSuppressPresenceComposing;
    property SuppressConsecutiveNotificationSounds: Boolean read FSuppressConsecutiveNotificationSounds write FSuppressConsecutiveNotificationSounds;
  end;

implementation

{ TSettings }

constructor TSettings.Create(const FilePath: string);
begin
  FFilePath := FilePath;

  FColorSettings := TList<TColorSetting>.Create;

  Reset;

  Load;
end;

destructor TSettings.Destroy;
var
  ColorSetting: TColorSetting;
begin
  for ColorSetting in FColorSettings do
    ColorSetting.Free;

  FColorSettings.Free;

  inherited;
end;

procedure TSettings.Load;
var
  JSONEnum: TJSONEnum;
  JSONObject, JSONObjectResource: TJSONObject;
  JSONArray: TJSONArray;
  ColorSetting: TColorSetting;
  FS: TFileStream;
begin
  try
    FS := TFileStream.Create(FFilePath, fmOpenRead);
  except
    Exit;
  end;

  try
    try
      JSONObject := TJSONObject(GetJSON(FS));
      try
        FLastUsedWhatsAppHash := JSONObject.Get('LastUsedWhatsAppHash', FLastUsedWhatsAppHash);
        FShowNotificationIcon := JSONObject.Get('ShowNotificationIcon', FShowNotificationIcon);
        FShowUnreadMessagesBadge := JSONObject.Get('ShowUnreadMessagesBadge', FShowUnreadMessagesBadge);
        FExcludeUnreadMessagesMutedChats := JSONObject.Get('ExcludeUnreadMessagesMutedChats', FExcludeUnreadMessagesMutedChats);
        FHideMaximize := JSONObject.Get('HideMaximize', FHideMaximize);
        FAlwaysOnTop := JSONObject.Get('AlwaysOnTop', FAlwaysOnTop);
        FSuppressPresenceAvailable := JSONObject.Get('SuppressPresenceAvailable', FSuppressPresenceAvailable);
        FSuppressPresenceComposing := JSONObject.Get('SuppressPresenceComposing', FSuppressPresenceComposing);
        FSuppressConsecutiveNotificationSounds := JSONObject.Get('SuppressConsecutiveNotificationSounds', FSuppressConsecutiveNotificationSounds);

        JSONArray := JSONObject.Get('ResourcePatches', TJSONArray(nil));

        for JSONEnum in JSONArray do
        begin
          JSONObjectResource := TJSONObject(JSONEnum.Value);
          for ColorSetting in FColorSettings do
            if ColorSetting.ID = JSONObjectResource.Get('ID', -1) then
            begin
              ColorSetting.ColorType := TColorType(JSONObjectResource.Get('Action', 0));
              ColorSetting.ColorCustom := JSONObjectResource.Get('ColorCustom', 0);
              Break;
            end;
        end;
      finally
        JSONObject.Free;
      end;
    except
      Reset;
    end;
  finally
    FS.Free;
  end;
end;

procedure TSettings.Save;
var
  JSONString: AnsiString;
  JSONObject, JSONObjectResource: TJSONObject;
  JSONArray: TJSONArray;
  ColorSetting: TColorSetting;
  FS: TFileStream;
begin
  if not DirectoryExists(ExtractFileDir(FFilePath)) then
    if not CreateDir(ExtractFileDir(FFilePath)) then
      raise Exception.Create('Error creating settings directory');

  JSONObject := TJSONObject.Create;
  try
    JSONObject.Add('LastUsedWhatsAppHash', FLastUsedWhatsAppHash);
    JSONObject.Add('ShowNotificationIcon', FShowNotificationIcon);
    JSONObject.Add('ShowUnreadMessagesBadge', FShowUnreadMessagesBadge);
    JSONObject.Add('ExcludeUnreadMessagesMutedChats', FExcludeUnreadMessagesMutedChats);
    JSONObject.Add('HideMaximize', FHideMaximize);
    JSONObject.Add('AlwaysOnTop', FAlwaysOnTop);
    JSONObject.Add('SuppressPresenceAvailable', FSuppressPresenceAvailable);
    JSONObject.Add('SuppressPresenceComposing', FSuppressPresenceComposing);
    JSONObject.Add('SuppressConsecutiveNotificationSounds', FSuppressConsecutiveNotificationSounds);

    JSONArray := TJSONArray.Create;
    JSONObject.Add('ResourcePatches', JSONArray);

    for ColorSetting in FColorSettings do
    begin
      JSONObjectResource := TJSONObject.Create;
      JSONArray.Add(JSONObjectResource);

      JSONObjectResource.Add('ID', ColorSetting.ID);
      JSONObjectResource.Add('Action', Integer(ColorSetting.ColorType));
      JSONObjectResource.Add('ColorCustom', ColorSetting.ColorCustom);
    end;

    FS := TFileStream.Create(FFilePath, fmCreate);
    try
      JSONObject.CompressedJSON := True;
      JSONString := JSONObject.AsJSON;
      FS.WriteBuffer(JSONString[1], Length(JSONString));
    finally
      FS.Free;
    end;
  finally
    JSONObject.Free;
  end;
end;

procedure TSettings.CopyToMMF(MMF: TMMFLauncher);
begin
  MMF.ShowNotificationIcon := FShowNotificationIcon;
  MMF.ShowUnreadMessagesBadge := FShowUnreadMessagesBadge;
  MMF.ExcludeUnreadMessagesMutedChats := FExcludeUnreadMessagesMutedChats;
  MMF.NotificationIconBadgeColor := ColorToRGB(FNotificationIconBadgeColor.GetColor(caNone));
  MMF.NotificationIconBadgeTextColor := ColorToRGB(FNotificationIconBadgeTextColor.GetColor(caNone));
  MMF.HideMaximize := FHideMaximize;
  MMF.AlwaysOnTop := FAlwaysOnTop;
  MMF.SuppressPresenceAvailable := FSuppressPresenceAvailable;
  MMF.SuppressPresenceComposing := FSuppressPresenceComposing;
  MMF.SuppressConsecutiveNotificationSounds := FSuppressConsecutiveNotificationSounds;
end;

procedure TSettings.Reset;
var
  ColorSetting: TColorSetting;
begin
  for ColorSetting in FColorSettings do
    ColorSetting.Free;
  FColorSettings.Clear;

  FNotificationIconBadgeColor := TColorSetting.Create(500, 'Notification icon badge', ImmersiveLightWUError, ctImmersive);

  FNotificationIconBadgeTextColor := TColorSetting.Create(501, 'Notification icon badge text', ImmersiveControlLightSelectTextHighlighted, ctImmersive);

  // --teal-lighter
  FColorSettings.Add(TResourceColorSetting.Create(1, 'Titlebar', TFunctions.HTMLToColor('00bfa5'), ImmersiveSystemAccent, ctImmersive, [TResourceColorSettingPatch.Create('00bfa5')]));

  // --badge-pending, --teal, --active-tab-marker, --app-background-stripe, --checkbox-background, --highlight, --panel-background-colored-deeper
  FColorSettings.Add(TResourceColorSetting.Create(10, 'Panel background', TFunctions.HTMLToColor('009688'), ImmersiveSaturatedBackground, ctImmersive, [TResourceColorSettingPatch.Create('009688')]));

  // --intro-border
  FColorSettings.Add(TResourceColorSetting.Create(2, 'Intro border', TFunctions.HTMLToColor('4adf83'), ImmersiveLightBorder, ctImmersive, [TResourceColorSettingPatch.Create('4adf83')]));

  // --progress-primary
  FColorSettings.Add(TResourceColorSetting.Create(3, 'Progressbar', TFunctions.HTMLToColor('00d9bb'), ImmersiveControlLightProgressForeground, ctImmersive, [TResourceColorSettingPatch.Create('00d9bb')]));

  // --unread-marker-background
  FColorSettings.Add(TResourceColorSetting.Create(4, 'Unread message badge', TFunctions.HTMLToColor('06d755'), ImmersiveLightWUError, ctImmersive, [TResourceColorSettingPatch.Create('06d755')]));

  FColorSettings.Add(FNotificationIconBadgeColor);

  FColorSettings.Add(FNotificationIconBadgeTextColor);

  // --ptt-green
  FColorSettings.Add(TResourceColorSetting.Create(11, 'New voice mail icon', TFunctions.HTMLToColor('09d261'), ImmersiveLightWUError, ctImmersive, [TResourceColorSettingPatch.Create('09d261'), TResourceColorSettingPatch.Create('09D261').JS]));

  // --ptt-blue, --icon-ack
  FColorSettings.Add(TResourceColorSetting.Create(12, 'Acknowledged icons', TFunctions.HTMLToColor('4fc3f7'), ImmersiveLightWUNormal, ctImmersive, [TResourceColorSettingPatch.Create('4fc3f7')]));

  // --typing
  FColorSettings.Add(TResourceColorSetting.Create(13, '"Typing..." notification', TFunctions.HTMLToColor('07bc4c'), ImmersiveSaturatedCommandRowPressed, ctImmersive, [TResourceColorSettingPatch.Create('07bc4c')]));

  FColorSettings.Add(TResourceColorSetting.Create(14, 'Primary button background', TFunctions.HTMLToColor('05cd51'), ImmersiveControlDefaultLightButtonBackgroundRest, ctImmersive,
    [TResourceColorSettingPatch.Create('--button-primary-background:#0aa545;', '--button-primary-background:#%COLOR%;'), TResourceColorSettingPatch.Create('--button-primary-background-hover:#0aaa47;',
    '--button-primary-background-hover:#%COLOR%;').Darken3]));

  FColorSettings.Add(TResourceColorSetting.Create(15, 'Secondary button background', TFunctions.HTMLToColor('ffffff'), ImmersiveControlLightButtonBackgroundRest, ctImmersive,
    [TResourceColorSettingPatch.Create('--button-secondary-background:#fff;', '--button-secondary-background:#%COLOR%;'), TResourceColorSettingPatch.Create('--button-secondary-background-hover:#fff;',
    '--button-secondary-background-hover:#%COLOR%;').Darken3]));

  FColorSettings.Add(TResourceColorSetting.Create(16, 'Secondary button text', TFunctions.HTMLToColor('07bc4c'), ImmersiveControlLightAppButtonTextRest, ctImmersive, [TResourceColorSettingPatch.Create(
    '--button-secondary:#0aa545;', '--button-secondary:#%COLOR%;'), TResourceColorSettingPatch.Create('--button-secondary-hover:#0aaa47;', '--button-secondary-hover:#%COLOR%;').Lighten3]));

  FColorSettings.Add(TResourceColorSetting.Create(17, 'Round button background', TFunctions.HTMLToColor('09e85e'), ImmersiveControlLightButtonBackgroundRest, ctImmersive,
    [TResourceColorSettingPatch.Create('--button-round-background:#09e85e;', '--button-round-background:#%COLOR%;'), TResourceColorSettingPatch.Create('--button-round-background-rgb:9,232,94;',
    '--button-round-background-rgb:#%COLOR%;').RBG]));

  FColorSettings.Add(TResourceColorSetting.Create(8, 'Background of incoming messages', TFunctions.HTMLToColor('ffffff'), ImmersiveLightChromeMedium, ctImmersive,
    [TResourceColorSettingPatch.Create('--incoming-background:#fff;', '--incoming-background:#%COLOR%;'), TResourceColorSettingPatch.Create('--incoming-background-rgb:255,255,255;',
    '--incoming-background-rgb:%COLOR%;').RBG, TResourceColorSettingPatch.Create('--incoming-background-deeper:#f7f7f7;', '--incoming-background-deeper:#%COLOR%;').Darken,
    TResourceColorSettingPatch.Create('--incoming-background-deeper-rgb:247,247,247;', '--incoming-background-deeper-rgb:%COLOR%;').RBG.Darken, TResourceColorSettingPatch.Create(
    '--audio-track-incoming:#e6e6e6;', '--audio-track-incoming:#%COLOR%;').Darken3, TResourceColorSettingPatch.Create('--audio-progress-incoming:#31c76a;', '--audio-progress-incoming:#%COLOR%;').Darken10,
    TResourceColorSettingPatch.Create('--audio-progress-played-incoming:#30b6f6;', '--audio-progress-played-incoming:#%COLOR%;').Darken10]));

  FColorSettings.Add(TResourceColorSetting.Create(9, 'Background of outgoing messages', TFunctions.HTMLToColor('dcf8c6'), ImmersiveLightChromeWhite, ctImmersive, [TResourceColorSettingPatch.Create(
    '--outgoing-background:#dcf8c6;', '--outgoing-background:#%COLOR%;'), TResourceColorSettingPatch.Create('--outgoing-background-rgb:220,248,198;', '--outgoing-background-rgb:%COLOR%;').RBG,
    TResourceColorSettingPatch.Create('--outgoing-background-deeper:#d3eebe;', '--outgoing-background-deeper:#%COLOR%;').Darken, TResourceColorSettingPatch.Create('--outgoing-background-deeper-rgb:211,238,190;',
    '--outgoing-background-deeper-rgb:%COLOR%;').RBG.Darken, TResourceColorSettingPatch.Create('--audio-track-outgoing:#c6dfb2;', '--audio-track-outgoing:#%COLOR%;').Darken3,
    TResourceColorSettingPatch.Create('--audio-progress-outgoing:#889a7b;', '--audio-progress-outgoing:#%COLOR%;').Darken10, TResourceColorSettingPatch.Create('--audio-progress-played-outgoing:#2ab5eb;',
    '--audio-progress-played-outgoing:#%COLOR%;').Darken10]));

  FColorSettings.Add(TResourceColorSetting.Create(5, 'Minimize button hover color', TFunctions.HTMLToColor('00ab97'), ImmersiveControlDefaultLightButtonBackgroundHover, ctImmersive,
    [TResourceColorSettingPatch.Create('#windows-title-minimize:hover{background-color:var(--teal-hover)}', '#windows-title-minimize:hover{background-color:#%COLOR%}')]));

  FColorSettings.Add(TResourceColorSetting.Create(6, 'Maximize button hover color', TFunctions.HTMLToColor('00ab97'), ImmersiveControlDefaultLightButtonBackgroundHover, ctImmersive,
    [TResourceColorSettingPatch.Create('#windows-title-maximize:hover{background-color:var(--teal-hover)}', '#windows-title-maximize:hover{background-color:#%COLOR%}')]));

  FColorSettings.Add(TResourceColorSetting.Create(7, 'Close button hover color', TFunctions.HTMLToColor('00ab97'), ImmersiveHardwareTitleBarCloseButtonHover, ctImmersive,
    [TResourceColorSettingPatch.Create('#windows-title-close:hover{background-color:var(--teal-hover)}', '#windows-title-close:hover{background-color:#%COLOR%}')]));

  FShowNotificationIcon := True;
  FShowUnreadMessagesBadge := True;
  FExcludeUnreadMessagesMutedChats := False;
  FHideMaximize := False;
  FAlwaysOnTop := False;
  FSuppressPresenceAvailable := False;
  FSuppressPresenceComposing := False;
  FSuppressConsecutiveNotificationSounds := True;
end;

function TSettings.FGetResourceSettingsChecksum: UInt16;
var
  ColorSetting: TColorSetting;
  ColorType: TColorType;
  MD5Ctx: TMD5Context;
  MD5Digest: TMD5Digest;
  Color: TColor;
  Bool: Boolean;
begin
  MD5Init(MD5Ctx);
  for ColorSetting in FColorSettings do
    if ColorSetting.ClassType = TResourceColorSetting then
    begin
      Color := ColorSetting.GetColor(caNone);
      MD5Update(MD5Ctx, Color, SizeOf(Color));

      ColorType := ColorSetting.ColorType;
      MD5Update(MD5Ctx, ColorType, SizeOf(ColorType));
    end;
  Bool := FHideMaximize;
  MD5Update(MD5Ctx, Bool, SizeOf(Bool));
  MD5Final(MD5Ctx, MD5Digest);
  Result := PUInt16(@MD5Digest[0])^;
end;

{ TColorSetting }

constructor TColorSetting.Create(const ID: Integer; const Description: string; const ColorDefault: TColor; const ColorImmersive: TImmersiveColorType; const Action: TColorType);
begin
  FID := ID;
  FDescription := Description;
  FColorDefault := ColorDefault;
  FColorCustom := ColorDefault;
  FColorImmersive := ColorImmersive;
  FColorType := Action;
end;

constructor TColorSetting.Create(const ID: Integer; const Description: string; const ColorImmersive: TImmersiveColorType; const Action: TColorType);
begin
  Create(ID, Description, clNone, ColorImmersive, Action);
  FColorCustom := GetColor(caNone);
end;

destructor TColorSetting.Destroy;
begin
  inherited Destroy;
end;

function TColorSetting.GetColor(const ColorAdjustment: TColorAdjustment): TColor;
begin
  case FColorType of
    ctNone:
      Result := ColorDefault;
    ctImmersive:
      Result := AlphaColorToColor(GetActiveImmersiveColor(ImmersiveColors.TImmersiveColorType(ColorImmersive)));
    ctCustom:
      Result := ColorCustom;
    else
      raise Exception.Create('GetColor(): Invalid action');
  end;

  Result := ColorAdjustLuma(Result, Integer(ColorAdjustment), True);
end;

{ TResourceColorSettingPatch }

constructor TResourceColorSettingPatch.Create(const SearchColor: string);
begin
  FSearchText := SearchColor;
  FReplaceText := '%COLOR%';
  FReplaceFlags := [rfReplaceAll];
  FColorAdjustment := caNone;
end;

constructor TResourceColorSettingPatch.Create(const SearchText, ReplaceText: string);
begin
  FSearchText := SearchText;
  FReplaceText := ReplaceText;
  FColorAdjustment := caNone;
end;

function TResourceColorSettingPatch.RBG: TResourceColorSettingPatch;
begin
  Result := Self;
  FRGBNotation := True;
end;

function TResourceColorSettingPatch.Darken: TResourceColorSettingPatch;
begin
  Result := Self;
  FColorAdjustment := caDarken;
end;

function TResourceColorSettingPatch.Darken3: TResourceColorSettingPatch;
begin
  Result := Self;
  FColorAdjustment := caDarken3;
end;

function TResourceColorSettingPatch.Darken5: TResourceColorSettingPatch;
begin
  Result := Self;
  FColorAdjustment := caDarken5;
end;

function TResourceColorSettingPatch.Darken10: TResourceColorSettingPatch;
begin
  Result := Self;
  FColorAdjustment := caDarken10;
end;

function TResourceColorSettingPatch.Lighten3: TResourceColorSettingPatch;
begin
  Result := Self;
  FColorAdjustment := caLighten3;
end;

function TResourceColorSettingPatch.JS: TResourceColorSettingPatch;
begin
  Result := Self;
  FTarget := tJs;
end;

function TResourceColorSettingPatch.Execute(const Source: string; const Color: TColor; out Count: Integer): string;
begin
  Result := StringReplace(Source, FSearchText, FReplaceText.Replace('%COLOR%', IfThen<string>(FRGBNotation, TFunctions.ColorToRGBHTML(Color), TFunctions.ColorToHTML(Color)), []), FReplaceFlags, Count);
end;

{ TResourceColorSetting }

constructor TResourceColorSetting.Create(const ID: Integer; const Description: string; const ColorCustom: TColor; const ColorImmersive: TImmersiveColorType; const Action: TColorType; const Patches: TResourceColorSettingPatchArray);
begin
  inherited Create(ID, Description, ColorCustom, ColorImmersive, Action);

  FPatches := Patches;
end;

destructor TResourceColorSetting.Destroy;
var
  ResourcePatch: TResourceColorSettingPatch;
begin
  for ResourcePatch in FPatches do
    ResourcePatch.Free;
end;

end.
