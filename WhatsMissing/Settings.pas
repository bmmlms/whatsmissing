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
  TColorTypeSimple = (ctsDefault, ctsCustom);
  TColorTypeResource = (ctrOriginal, ctrDefault, ctrCustom);
  TColorAdjustment = (caDarken10 = -50, caDarken5 = -25, caDarken3 = -15, caDarken2 = -10, caDarken = -5, caNone = 0, caLighten = 5, caLighten2 = 10, caLighten3 = 15, caLighten5 = 25);

  TColorSettingResourcePatch = class;
  TColorSettingResourcePatchArray = array of TColorSettingResourcePatch;

  { TColorSettingBase }

  TColorSettingBase = class
  protected
    FID: Integer;
    FDescription: string;
    FColorCustom: TColor;
    FColor: TColor;
    FColorImmersive: TImmersiveColorType;
  public
    constructor Create(const ID: Integer; const Description: string; const Color: TColor); overload;
    constructor Create(const ID: Integer; const Description: string; const ColorImmersive: TImmersiveColorType); overload;

    property ID: Integer read FID;
    property Description: string read FDescription;
    property ColorCustom: TColor read FColorCustom write FColorCustom;
    property Color: TColor read FColor write FColor;
    property ColorImmersive: TImmersiveColorType read FColorImmersive;
  end;

  { TColorSettingSimpleStatic }

  TColorSettingSimpleStatic = class(TColorSettingBase)
  protected
    FColorType: TColorTypeSimple;
  public
    constructor Create(const ID: Integer; const Description: string; const Color: TColor); reintroduce;

    function GetColor(const ColorAdjustment: TColorAdjustment): TColor;

    property ColorType: TColorTypeSimple read FColorType write FColorType;
  end;

  { TColorSettingSimpleImmersive }

  TColorSettingSimpleImmersive = class(TColorSettingBase)
  protected
    FColorType: TColorTypeSimple;
  public
    constructor Create(const ID: Integer; const Description: string; const ColorImmersive: TImmersiveColorType); reintroduce;

    function GetColor(const ColorAdjustment: TColorAdjustment): TColor;

    property ColorType: TColorTypeSimple read FColorType write FColorType;
  end;

  { TColorSettingResource }

  TColorSettingResource = class(TColorSettingBase)
  private
    FColorType: TColorTypeResource;
    FPatches: TColorSettingResourcePatchArray;
  public
    constructor Create(const ID: Integer; const Description: string; const ColorImmersive: TImmersiveColorType; const Patches: TColorSettingResourcePatchArray); reintroduce;
    destructor Destroy; override;

    function GetColor(const ColorAdjustment: TColorAdjustment; const DefaultColor: TColor): TColor;

    property ColorType: TColorTypeResource read FColorType write FColorType;
    property Patches: TColorSettingResourcePatchArray read FPatches;
  end;

  { TColorSettingResourcePatch }

  TColorSettingResourcePatch = class
  private
    type
      TPatchOptions = record
        UpdateAllColors: Boolean;
        UpdateInFile: string;
        ColorAdjustment: TColorAdjustment;
        RGBNotation: Boolean;
      end;
  private
  var
    FSingleSelector: string;
    FDeclarationProp: string;
    FOptions: TPatchOptions;
  public
    constructor Create(const DeclarationProp: string); overload;
    constructor Create(const SingleSelector, DeclarationProp: string); overload;

    function GetColor(const Color: TColor): string;

    function RGB: TColorSettingResourcePatch;
    function Darken: TColorSettingResourcePatch;
    function Darken3: TColorSettingResourcePatch;
    function Darken5: TColorSettingResourcePatch;
    function Darken10: TColorSettingResourcePatch;
    function Lighten3: TColorSettingResourcePatch;
    function UpdateAllColors: TColorSettingResourcePatch;
    function UpdateInFile(FilenameWild: string): TColorSettingResourcePatch;

    property SingleSelector: string read FSingleSelector;
    property DeclarationProp: string read FDeclarationProp;
    property Options: TPatchOptions read FOptions;
  end;

  { TSettings }

  TSettings = class
  private
    FFilePath: string;

    FLastUsedWhatsAppHash: Integer;

    FColorSettings: TList<TColorSettingBase>;
    FWindowIconColor: TColorSettingSimpleStatic;
    FNotificationIconColor: TColorSettingSimpleStatic;
    FNotificationIconBadgeColor: TColorSettingSimpleImmersive;
    FNotificationIconBadgeTextColor: TColorSettingSimpleImmersive;

    FShowNotificationIcon: Boolean;
    FShowUnreadMessagesBadge: Boolean;
    FUsePreRenderedOverlays: Boolean;
    FExcludeUnreadMessagesMutedChats: Boolean;
    FRemoveRoundedElementCorners: Boolean;
    FUseSquaredProfileImages: Boolean;
    FUseRegularTitleBar: Boolean;
    FHideMaximize: Boolean;
    FAlwaysOnTop: Boolean;
    FSuppressPresenceAvailable: Boolean;
    FSuppressPresenceComposing: Boolean;
    FSuppressConsecutiveNotifications: Boolean;

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

    property ColorSettings: TList<TColorSettingBase> read FColorSettings;

    property ShowNotificationIcon: Boolean read FShowNotificationIcon write FShowNotificationIcon;
    property ShowUnreadMessagesBadge: Boolean read FShowUnreadMessagesBadge write FShowUnreadMessagesBadge;
    property UsePreRenderedOverlays: Boolean read FUsePreRenderedOverlays write FUsePreRenderedOverlays;
    property ExcludeUnreadMessagesMutedChats: Boolean read FExcludeUnreadMessagesMutedChats write FExcludeUnreadMessagesMutedChats;
    property RemoveRoundedElementCorners: Boolean read FRemoveRoundedElementCorners write FRemoveRoundedElementCorners;
    property UseSquaredProfileImages: Boolean read FUseSquaredProfileImages write FUseSquaredProfileImages;
    property UseRegularTitleBar: Boolean read FUseRegularTitleBar write FUseRegularTitleBar;
    property HideMaximize: Boolean read FHideMaximize write FHideMaximize;
    property AlwaysOnTop: Boolean read FAlwaysOnTop write FAlwaysOnTop;
    property SuppressPresenceAvailable: Boolean read FSuppressPresenceAvailable write FSuppressPresenceAvailable;
    property SuppressPresenceComposing: Boolean read FSuppressPresenceComposing write FSuppressPresenceComposing;
    property SuppressConsecutiveNotifications: Boolean read FSuppressConsecutiveNotifications write FSuppressConsecutiveNotifications;
  end;

implementation

{ TSettings }

constructor TSettings.Create(const FilePath: string);
begin
  FFilePath := FilePath;

  FColorSettings := TList<TColorSettingBase>.Create;

  Reset;

  Load;
end;

destructor TSettings.Destroy;
var
  ColorSetting: TColorSettingBase;
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
  ColorSetting: TColorSettingBase;
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
        FRemoveRoundedElementCorners := JSONObject.Get('RemoveRoundedElementCorners', FRemoveRoundedElementCorners);
        FUseSquaredProfileImages := JSONObject.Get('UseSquaredProfileImages', FUseSquaredProfileImages);
        FUsePreRenderedOverlays := JSONObject.Get('UsePreRenderedOverlays', FUsePreRenderedOverlays);
        FExcludeUnreadMessagesMutedChats := JSONObject.Get('ExcludeUnreadMessagesMutedChats', FExcludeUnreadMessagesMutedChats);
        FUseRegularTitleBar := JSONObject.Get('UseRegularTitleBar', FUseRegularTitleBar);
        FHideMaximize := JSONObject.Get('HideMaximize', FHideMaximize);
        FAlwaysOnTop := JSONObject.Get('AlwaysOnTop', FAlwaysOnTop);
        FSuppressPresenceAvailable := JSONObject.Get('SuppressPresenceAvailable', FSuppressPresenceAvailable);
        FSuppressPresenceComposing := JSONObject.Get('SuppressPresenceComposing', FSuppressPresenceComposing);
        FSuppressConsecutiveNotifications := JSONObject.Get('SuppressConsecutiveNotifications', FSuppressConsecutiveNotifications);

        JSONArray := JSONObject.Get('ResourcePatches', TJSONArray(nil));

        for JSONEnum in JSONArray do
        begin
          JSONObjectResource := TJSONObject(JSONEnum.Value);
          for ColorSetting in FColorSettings do
            if ColorSetting.ID = JSONObjectResource.Get('ID', -1) then
            begin
              ColorSetting.ColorCustom := JSONObjectResource.Get('ColorCustom', 0);

              if ColorSetting is TColorSettingResource then
                TColorSettingResource(ColorSetting).ColorType := TColorTypeResource(JSONObjectResource.Get('Action', Byte(ctrDefault)))
              else if ColorSetting is TColorSettingSimpleStatic then
                TColorSettingSimpleStatic(ColorSetting).ColorType := TColorTypeSimple(JSONObjectResource.Get('Action', Byte(ctsDefault)))
              else
                TColorSettingSimpleImmersive(ColorSetting).ColorType := TColorTypeSimple(JSONObjectResource.Get('Action', Byte(ctsDefault)));

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
  ColorSetting: TColorSettingBase;
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
    JSONObject.Add('UsePreRenderedOverlays', FUsePreRenderedOverlays);
    JSONObject.Add('ExcludeUnreadMessagesMutedChats', FExcludeUnreadMessagesMutedChats);
    JSONObject.Add('RemoveRoundedElementCorners', FRemoveRoundedElementCorners);
    JSONObject.Add('UseSquaredProfileImages', FUseSquaredProfileImages);
    JSONObject.Add('UseRegularTitleBar', FUseRegularTitleBar);
    JSONObject.Add('HideMaximize', FHideMaximize);
    JSONObject.Add('AlwaysOnTop', FAlwaysOnTop);
    JSONObject.Add('SuppressPresenceAvailable', FSuppressPresenceAvailable);
    JSONObject.Add('SuppressPresenceComposing', FSuppressPresenceComposing);
    JSONObject.Add('SuppressConsecutiveNotifications', FSuppressConsecutiveNotifications);

    JSONArray := TJSONArray.Create;
    JSONObject.Add('ResourcePatches', JSONArray);

    for ColorSetting in FColorSettings do
    begin
      JSONObjectResource := TJSONObject.Create;
      JSONArray.Add(JSONObjectResource);

      JSONObjectResource.Add('ID', ColorSetting.ID);
      JSONObjectResource.Add('ColorCustom', ColorSetting.ColorCustom);

      if ColorSetting is TColorSettingResource then
        JSONObjectResource.Add('Action', Integer(TColorSettingResource(ColorSetting).ColorType))
      else if ColorSetting is TColorSettingSimpleStatic then
        JSONObjectResource.Add('Action', Integer(TColorSettingSimpleStatic(ColorSetting).ColorType))
      else
        JSONObjectResource.Add('Action', Integer(TColorSettingSimpleImmersive(ColorSetting).ColorType));
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
  MMF.WindowIconColor := ColorToRGB(FWindowIconColor.GetColor(caNone));
  MMF.ShowNotificationIcon := FShowNotificationIcon;
  MMF.ShowUnreadMessagesBadge := FShowUnreadMessagesBadge;
  MMF.UsePreRenderedOverlays := FUsePreRenderedOverlays;
  MMF.ExcludeUnreadMessagesMutedChats := FExcludeUnreadMessagesMutedChats;
  MMF.NotificationIconColor := ColorToRGB(FNotificationIconColor.GetColor(caNone));
  MMF.NotificationIconBadgeColor := ColorToRGB(FNotificationIconBadgeColor.GetColor(caNone));
  MMF.NotificationIconBadgeTextColor := ColorToRGB(FNotificationIconBadgeTextColor.GetColor(caNone));
  MMF.UseRegularTitleBar := FUseRegularTitleBar;
  MMF.HideMaximize := FHideMaximize;
  MMF.AlwaysOnTop := FAlwaysOnTop;
  MMF.SuppressConsecutiveNotifications := FSuppressConsecutiveNotifications;
end;

procedure TSettings.Reset;
var
  ColorSetting: TColorSettingBase;
begin
  for ColorSetting in FColorSettings do
    ColorSetting.Free;
  FColorSettings.Clear;

  FWindowIconColor := TColorSettingSimpleStatic.Create(503, 'Window icon color', RGBToColor(40, 196, 76));

  FNotificationIconColor := TColorSettingSimpleStatic.Create(502, 'Notification icon color', RGBToColor(40, 196, 76));

  FNotificationIconBadgeColor := TColorSettingSimpleImmersive.Create(500, 'Notification icon badge', ImmersiveLightWUError);

  FNotificationIconBadgeTextColor := TColorSettingSimpleImmersive.Create(501, 'Notification icon badge text', ImmersiveControlLightSelectTextHighlighted);

  FColorSettings.Add(TColorSettingResource.Create(1, 'Titlebar', ImmersiveSystemAccent, [TColorSettingResourcePatch.Create('--teal-lighter').UpdateAllColors]));

  FColorSettings.Add(FWindowIconColor);

  FColorSettings.Add(FNotificationIconColor);

  FColorSettings.Add(FNotificationIconBadgeColor);

  FColorSettings.Add(FNotificationIconBadgeTextColor);

  FColorSettings.Add(TColorSettingResource.Create(18, 'Startup background', ImmersiveApplicationBackground, [TColorSettingResourcePatch.Create('--startup-background'),
    TColorSettingResourcePatch.Create('--startup-background-rgb').RGB,
    TColorSettingResourcePatch.Create('--startup-icon')]));

  FColorSettings.Add(TColorSettingResource.Create(19, 'Intro background', ImmersiveApplicationBackground, [TColorSettingResourcePatch.Create('--intro-background'), TColorSettingResourcePatch.Create('--intro-border').Darken10]));

  FColorSettings.Add(TColorSettingResource.Create(20, 'Panel background', ImmersiveApplicationBackground, [TColorSettingResourcePatch.Create('--panel-header-background'),
    TColorSettingResourcePatch.Create('--panel-input-background'), TColorSettingResourcePatch.Create('--search-input-container-background'),
    TColorSettingResourcePatch.Create('--search-input-container-background-active'), TColorSettingResourcePatch.Create('--rich-text-panel-background'), TColorSettingResourcePatch.Create('--compose-panel-background')]));

  FColorSettings.Add(TColorSettingResource.Create(21, 'Modal background', ImmersiveSaturatedBackground, [
    TColorSettingResourcePatch.Create('--teal'), TColorSettingResourcePatch.Create('--app-background-stripe'),
    TColorSettingResourcePatch.Create('--checkbox-background').Lighten3, TColorSettingResourcePatch.Create('--panel-background-colored').Lighten3.UpdateAllColors]));

  FColorSettings.Add(TColorSettingResource.Create(22, 'Chat list background', ImmersiveApplicationBackground, [TColorSettingResourcePatch.Create('--background-default')]));
  FColorSettings.Add(TColorSettingResource.Create(23, 'Chat list background (hovered)', ImmersiveLightEntityItemBackgroundHover, [TColorSettingResourcePatch.Create('--background-default-hover')]));
  FColorSettings.Add(TColorSettingResource.Create(24, 'Chat list background (focused)', ImmersiveLightEntityItemBackgroundSelected, [TColorSettingResourcePatch.Create('--background-default-active')]));

  FColorSettings.Add(TColorSettingResource.Create(3, 'Progressbar', ImmersiveControlLightProgressForeground, [TColorSettingResourcePatch.Create('--progress-primary')]));

  FColorSettings.Add(TColorSettingResource.Create(25, 'Input background', ImmersiveControlContextMenuBackgroundRest, [TColorSettingResourcePatch.Create('--search-input-background'),
    TColorSettingResourcePatch.Create('--compose-input-background')]));

  FColorSettings.Add(TColorSettingResource.Create(26, 'Icons', ImmersiveControlDefaultLightButtonBackgroundRest, [TColorSettingResourcePatch.Create('--button-round-icon-inverted'),
    TColorSettingResourcePatch.Create('--icon'), TColorSettingResourcePatch.Create('--panel-header-icon'), TColorSettingResourcePatch.Create('--icon-search-back')]));

  FColorSettings.Add(TColorSettingResource.Create(27, 'Unseen status dot', ImmersiveLightWUError, [TColorSettingResourcePatch.Create('--ptt-thumb-incoming-unplayed')]));

  FColorSettings.Add(TColorSettingResource.Create(12, 'Acknowledged icons', ImmersiveLightWUNormal, [TColorSettingResourcePatch.Create('--ptt-blue')]));

  FColorSettings.Add(TColorSettingResource.Create(13, '"Typing..." notification', ImmersiveSaturatedCommandRowPressed, [TColorSettingResourcePatch.Create('--typing')]));

  FColorSettings.Add(TColorSettingResource.Create(4, 'Unread message badge', ImmersiveLightWUError, [TColorSettingResourcePatch.Create('--unread-marker-background')]));

  FColorSettings.Add(TColorSettingResource.Create(11, 'New voice mail icon', ImmersiveLightWUError, [TColorSettingResourcePatch.Create('--ptt-green').UpdateInFile('main.*.js')]));

  FColorSettings.Add(TColorSettingResource.Create(14, 'Primary button background', ImmersiveControlDefaultLightButtonBackgroundRest,
    [TColorSettingResourcePatch.Create('--button-primary-background'), TColorSettingResourcePatch.Create('--button-primary-background-hover').Darken3]));

  FColorSettings.Add(TColorSettingResource.Create(15, 'Secondary button background', ImmersiveControlLightButtonBackgroundRest,
    [TColorSettingResourcePatch.Create('--button-secondary-background'), TColorSettingResourcePatch.Create('--button-secondary-background-hover').Darken3]));

  FColorSettings.Add(TColorSettingResource.Create(16, 'Secondary button text', ImmersiveControlLightAppButtonTextRest, [TColorSettingResourcePatch.Create(
    '--button-secondary'), TColorSettingResourcePatch.Create('--button-secondary-hover').Lighten3]));

  FColorSettings.Add(TColorSettingResource.Create(17, 'Round button background', ImmersiveControlLightButtonBackgroundRest,
    [TColorSettingResourcePatch.Create('--button-round-background'), TColorSettingResourcePatch.Create('--button-round-background-rgb').RGB]));

  FColorSettings.Add(TColorSettingResource.Create(8, 'Background of incoming messages', ImmersiveLightChromeMedium,
    [TColorSettingResourcePatch.Create('--incoming-background'), TColorSettingResourcePatch.Create('--incoming-background-rgb').RGB, TColorSettingResourcePatch.Create('--incoming-background-deeper').Darken,
    TColorSettingResourcePatch.Create('--incoming-background-deeper-rgb').RGB.Darken, TColorSettingResourcePatch.Create('--audio-track-incoming').Darken3, TColorSettingResourcePatch.Create('--audio-progress-incoming').Darken10,
    TColorSettingResourcePatch.Create('--audio-progress-played-incoming').Darken10]));

  FColorSettings.Add(TColorSettingResource.Create(9, 'Background of outgoing messages', ImmersiveLightChromeWhite, [TColorSettingResourcePatch.Create(
    '--outgoing-background'), TColorSettingResourcePatch.Create('--outgoing-background-rgb').RGB,
    TColorSettingResourcePatch.Create('--outgoing-background-deeper').Darken, TColorSettingResourcePatch.Create('--outgoing-background-deeper-rgb').RGB.Darken,
    TColorSettingResourcePatch.Create('--audio-track-outgoing').Darken3, TColorSettingResourcePatch.Create('--audio-progress-outgoing').Darken10, TColorSettingResourcePatch.Create('--audio-progress-played-outgoing').Darken10]));

  FColorSettings.Add(TColorSettingResource.Create(5, 'Minimize button hover color', ImmersiveControlDefaultLightButtonBackgroundHover,
    [TColorSettingResourcePatch.Create('html[dir] #windows-title-minimize:hover', 'background-color')]));

  FColorSettings.Add(TColorSettingResource.Create(6, 'Maximize button hover color', ImmersiveControlDefaultLightButtonBackgroundHover,
    [TColorSettingResourcePatch.Create('html[dir] #windows-title-maximize:hover', 'background-color')]));

  FColorSettings.Add(TColorSettingResource.Create(7, 'Close button hover color', ImmersiveHardwareTitleBarCloseButtonHover,
    [TColorSettingResourcePatch.Create('html[dir] #windows-title-close:hover', 'background-color')]));

  FShowNotificationIcon := True;
  FShowUnreadMessagesBadge := True;
  FUsePreRenderedOverlays := True;
  FExcludeUnreadMessagesMutedChats := False;
  FRemoveRoundedElementCorners := False;
  FUseSquaredProfileImages := False;
  FUseRegularTitleBar := False;
  FHideMaximize := False;
  FAlwaysOnTop := False;
  FSuppressPresenceAvailable := False;
  FSuppressPresenceComposing := False;
  FSuppressConsecutiveNotifications := True;
end;

function TSettings.FGetResourceSettingsChecksum: UInt16;
var
  ColorSetting: TColorSettingBase;
  ResourceColorSetting: TColorSettingResource absolute ColorSetting;
  ColorType: TColorTypeResource;
  MD5Ctx: TMD5Context;
  MD5Digest: TMD5Digest;
  Color: TColor;
  Bool: Boolean;
begin
  MD5Init(MD5Ctx);
  for ColorSetting in FColorSettings do
    if ColorSetting.ClassType = TColorSettingResource then
    begin
      Color := ResourceColorSetting.ColorCustom;
      MD5Update(MD5Ctx, Color, SizeOf(Color));

      ColorType := ResourceColorSetting.ColorType;
      MD5Update(MD5Ctx, ColorType, SizeOf(ColorType));
    end;
  Bool := FRemoveRoundedElementCorners;
  MD5Update(MD5Ctx, Bool, SizeOf(Bool));
  Bool := FUseSquaredProfileImages;
  MD5Update(MD5Ctx, Bool, SizeOf(Bool));
  Bool := FUseRegularTitleBar;
  MD5Update(MD5Ctx, Bool, SizeOf(Bool));
  Bool := FHideMaximize;
  MD5Update(MD5Ctx, Bool, SizeOf(Bool));
  MD5Final(MD5Ctx, MD5Digest);
  Result := PUInt16(@MD5Digest[0])^;
end;

{ TColorSettingBase }

constructor TColorSettingBase.Create(const ID: Integer; const Description: string; const Color: TColor);
begin
  FID := ID;
  FDescription := Description;
  FColor := Color;
end;

constructor TColorSettingBase.Create(const ID: Integer; const Description: string; const ColorImmersive: TImmersiveColorType);
begin
  FID := ID;
  FDescription := Description;
  FColorImmersive := ColorImmersive;
end;

{ TColorSettingSimpleStatic }

constructor TColorSettingSimpleStatic.Create(const ID: Integer; const Description: string; const Color: TColor);
begin
  inherited Create(ID, Description, Color);

  FColorType := ctsDefault;
end;

function TColorSettingSimpleStatic.GetColor(const ColorAdjustment: TColorAdjustment): TColor;
begin
  case FColorType of
    ctsDefault:
      Result := Color;
    ctsCustom:
      Result := ColorCustom;
    else
      raise Exception.Create('GetColor(): Invalid ColorType');
  end;

  Result := ColorAdjustLuma(Result, Integer(ColorAdjustment), True);
end;

{ TColorSettingSimpleImmersive }

constructor TColorSettingSimpleImmersive.Create(const ID: Integer; const Description: string; const ColorImmersive: TImmersiveColorType);
begin
  inherited Create(ID, Description, ColorImmersive);

  FColorType := ctsDefault;
end;

function TColorSettingSimpleImmersive.GetColor(const ColorAdjustment: TColorAdjustment): TColor;
begin
  case FColorType of
    ctsDefault:
      Result := AlphaColorToColor(GetActiveImmersiveColor(ImmersiveColors.TImmersiveColorType(ColorImmersive)));
    ctsCustom:
      Result := ColorCustom;
    else
      raise Exception.Create('GetColor(): Invalid ColorType');
  end;

  Result := ColorAdjustLuma(Result, Integer(ColorAdjustment), True);
end;

{ TColorSettingResource }

constructor TColorSettingResource.Create(const ID: Integer; const Description: string; const ColorImmersive: TImmersiveColorType; const Patches: TColorSettingResourcePatchArray);
begin
  inherited Create(ID, Description, ColorImmersive);

  FPatches := Patches;
  FColorType := ctrDefault;
end;

destructor TColorSettingResource.Destroy;
var
  ResourcePatch: TColorSettingResourcePatch;
begin
  for ResourcePatch in FPatches do
    ResourcePatch.Free;
end;

function TColorSettingResource.GetColor(const ColorAdjustment: TColorAdjustment; const DefaultColor: TColor): TColor;
begin
  case FColorType of
    ctrOriginal:
      Result := DefaultColor;
    ctrDefault:
      Result := AlphaColorToColor(GetActiveImmersiveColor(ImmersiveColors.TImmersiveColorType(ColorImmersive)));
    ctrCustom:
      Result := ColorCustom;
    else
      raise Exception.Create('GetColor(): Invalid ColorType');
  end;

  Result := ColorAdjustLuma(Result, Integer(ColorAdjustment), True);
end;

{ TColorSettingResourcePatch }

constructor TColorSettingResourcePatch.Create(const DeclarationProp: string);
begin
  FSingleSelector := ':root';
  FDeclarationProp := DeclarationProp;
  FOptions.ColorAdjustment := caNone;
end;

constructor TColorSettingResourcePatch.Create(const SingleSelector, DeclarationProp: string);
begin
  FSingleSelector := SingleSelector;
  FDeclarationProp := DeclarationProp;
  FOptions.ColorAdjustment := caNone;
end;

function TColorSettingResourcePatch.GetColor(const Color: TColor): string;
begin
  Result := IfThen<string>(FOptions.RGBNotation, TFunctions.ColorToRGBHTML(Color), TFunctions.ColorToHTML(Color));
end;

function TColorSettingResourcePatch.RGB: TColorSettingResourcePatch;
begin
  Result := Self;
  FOptions.RGBNotation := True;
end;

function TColorSettingResourcePatch.Darken: TColorSettingResourcePatch;
begin
  Result := Self;
  FOptions.ColorAdjustment := caDarken;
end;

function TColorSettingResourcePatch.Darken3: TColorSettingResourcePatch;
begin
  Result := Self;
  FOptions.ColorAdjustment := caDarken3;
end;

function TColorSettingResourcePatch.Darken5: TColorSettingResourcePatch;
begin
  Result := Self;
  FOptions.ColorAdjustment := caDarken5;
end;

function TColorSettingResourcePatch.Darken10: TColorSettingResourcePatch;
begin
  Result := Self;
  FOptions.ColorAdjustment := caDarken10;
end;

function TColorSettingResourcePatch.Lighten3: TColorSettingResourcePatch;
begin
  Result := Self;
  FOptions.ColorAdjustment := caLighten3;
end;

function TColorSettingResourcePatch.UpdateAllColors: TColorSettingResourcePatch;
begin
  Result := Self;
  FOptions.UpdateAllColors := True;
end;

function TColorSettingResourcePatch.UpdateInFile(FilenameWild: string): TColorSettingResourcePatch;
begin
  Result := Self;
  FOptions.UpdateInFile := FilenameWild;
end;

end.
