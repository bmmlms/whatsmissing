unit Settings;

interface

uses
  Classes,
  fpjson,
  jsonparser,
  Graphics,
  Functions,
  Generics.Collections,
  SysUtils;

{$I ImmersiveType.inc}

// TODO: das hier ist nicht mehr shared. gehört nun zum exe-projekt only.

type
  TResourcePatchColorAdjustment = (caDarken10 = -50, caDarken5 = -25, caDarken3 = -15, caDarken2 = -10, caDarken = -5, caNone = 0, caLighten = 5, caLighten2 = 10, caLighten3 = 15, caLighten5 = 25);
  TResourcePatchTarget = (rptCss, rptJs);

  TResourcePatch = class
  private
    FSearchText: string;
    FReplaceText: string;
    FRGBNotation: Boolean;
    FColorAdjustment: TResourcePatchColorAdjustment;
    FTarget: TResourcePatchTarget;
    FReplaceFlags: TReplaceFlags;
  public
    constructor Create(const SearchColor: string); overload;
    constructor Create(const SearchText, ReplaceText: string); overload;

    function RBG: TResourcePatch;
    function Darken: TResourcePatch;
    function Darken3: TResourcePatch;
    function Darken5: TResourcePatch;
    function Darken10: TResourcePatch;
    function Lighten3: TResourcePatch;
    function JS: TResourcePatch;

    function Execute(const Source: string; const Color: TColor): string;

    property ColorAdjustment: TResourcePatchColorAdjustment read FColorAdjustment;
    property Target: TResourcePatchTarget read FTarget;
  end;

  TResourcePatchArray = array of TResourcePatch;

  TResourcePatchAction = (rpaNone, rpaImmersive, rpaCustom);

  TResourcePatchCollection = class
  private
    FID: Integer;
    FDescription: string;
    FColorCustom: TColor;
    FColorImmersive: TImmersiveColorType;
    FAction: TResourcePatchAction;
    FPatches: TResourcePatchArray;
  public
    constructor Create(const ID: Integer; const Description: string; const ColorCustom: TColor; const ColorImmersive: TImmersiveColorType; const Action: TResourcePatchAction; const Patches: TResourcePatchArray);
    destructor Destroy; override;

    property ID: Integer read FID;
    property Description: string read FDescription;
    property ColorCustom: TColor read FColorCustom write FColorCustom;
    property ColorImmersive: TImmersiveColorType read FColorImmersive write FColorImmersive;
    property Action: TResourcePatchAction read FAction write FAction;
    property Patches: TResourcePatchArray read FPatches;
  end;

  TSettings = class
  private
    FFilePath: string;

    FLastUsedVersion: string;
    FLastResourceChecksum: UInt16;

    FResourcePatches: TList<TResourcePatchCollection>;

    FShowNotificationIcon: Boolean;
    FIndicateNewMessages: Boolean;
    FIndicatorColor: TColor;
    FHideMaximize: Boolean;
    FAlwaysOnTop: Boolean;
    FDontSendPresence: Boolean;
    FDontSendTyping: Boolean;

    procedure Reset;
  public
    constructor Create(const FilePath: string);
    destructor Destroy; override;

    procedure Load;
    procedure Save;

    property LastUsedVersion: string read FLastUsedVersion write FLastUsedVersion;
    property LastResourceChecksum: UInt16 read FLastResourceChecksum write FLastResourceChecksum;

    property ResourcePatches: TList<TResourcePatchCollection> read FResourcePatches;

    property ShowNotificationIcon: Boolean read FShowNotificationIcon write FShowNotificationIcon;
    property IndicateNewMessages: Boolean read FIndicateNewMessages write FIndicateNewMessages;
    property IndicatorColor: TColor read FIndicatorColor write FIndicatorColor;
    property HideMaximize: Boolean read FHideMaximize write FHideMaximize;
    property AlwaysOnTop: Boolean read FAlwaysOnTop write FAlwaysOnTop;
    property DontSendPresence: Boolean read FDontSendPresence write FDontSendPresence;
    property DontSendTyping: Boolean read FDontSendTyping write FDontSendTyping;
  end;

implementation

constructor TSettings.Create(const FilePath: string);
begin
  FFilePath := FilePath;

  FResourcePatches := TList<TResourcePatchCollection>.Create;

  Reset;

  Load;
end;

destructor TSettings.Destroy;
var
  ResourcePatchCollection: TResourcePatchCollection;
begin
  for ResourcePatchCollection in FResourcePatches do
    ResourcePatchCollection.Free;

  FResourcePatches.Free;

  inherited;
end;

procedure TSettings.Load;
var
  JSONEnum: TJSONEnum;
  JSONObject, JSONObjectResource: TJSONObject;
  JSONArray: TJSONArray;
  ResourcePatchCollection: TResourcePatchCollection;
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
        FLastUsedVersion := JSONObject.Get('LastUsedVersion', FLastUsedVersion);
        FLastResourceChecksum := JSONObject.Get('LastResourceChecksum', FLastResourceChecksum);
        FShowNotificationIcon := JSONObject.Get('ShowNotificationIcon', FShowNotificationIcon);
        FIndicateNewMessages := JSONObject.Get('IndicateNewMessages', FIndicateNewMessages);
        FIndicatorColor := JSONObject.Get('IndicatorColor', FIndicatorColor);
        FHideMaximize := JSONObject.Get('HideMaximize', FHideMaximize);
        FAlwaysOnTop := JSONObject.Get('AlwaysOnTop', FAlwaysOnTop);
        FDontSendPresence := JSONObject.Get('DontSendPresence', FDontSendPresence);
        FDontSendTyping := JSONObject.Get('DontSendTyping', FDontSendTyping);

        JSONArray := JSONObject.Get('ResourcePatches', TJSONArray(nil));

        for JSONEnum in JSONArray do
        begin
          JSONObjectResource := TJSONObject(JSONEnum.Value);
          for ResourcePatchCollection in FResourcePatches do
            if ResourcePatchCollection.ID = JSONObjectResource.Get('ID', -1) then
            begin
              ResourcePatchCollection.Action := TResourcePatchAction(JSONObjectResource.Get('Action', 0));
              ResourcePatchCollection.ColorCustom := JSONObjectResource.Get('ColorCustom', 0);
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
  ResourcePatchCollection: TResourcePatchCollection;
  FS: TFileStream;
begin
  if not DirectoryExists(ExtractFileDir(FFilePath)) then
    if not CreateDir(ExtractFileDir(FFilePath)) then
      raise Exception.Create('Error creating settings directory');

  JSONObject := TJSONObject.Create;
  try
    JSONObject.Add('LastUsedVersion', FLastUsedVersion);
    JSONObject.Add('LastResourceChecksum', FLastResourceChecksum);
    JSONObject.Add('ShowNotificationIcon', FShowNotificationIcon);
    JSONObject.Add('IndicateNewMessages', FIndicateNewMessages);
    JSONObject.Add('IndicatorColor', FIndicatorColor);
    JSONObject.Add('HideMaximize', FHideMaximize);
    JSONObject.Add('AlwaysOnTop', FAlwaysOnTop);
    JSONObject.Add('DontSendPresence', FDontSendPresence);
    JSONObject.Add('DontSendTyping', FDontSendTyping);

    JSONArray := TJSONArray.Create;
    JSONObject.Add('ResourcePatches', JSONArray);

    for ResourcePatchCollection in FResourcePatches do
    begin
      JSONObjectResource := TJSONObject.Create;
      JSONArray.Add(JSONObjectResource);

      JSONObjectResource.Add('ID', ResourcePatchCollection.ID);
      JSONObjectResource.Add('Action', Integer(ResourcePatchCollection.Action));
      JSONObjectResource.Add('ColorCustom', ResourcePatchCollection.ColorCustom);
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

procedure TSettings.Reset;
const
  clDefault = $20000000;
var
  ResourcePatchCollection: TResourcePatchCollection;
begin
  for ResourcePatchCollection in FResourcePatches do
    ResourcePatchCollection.Free;
  FResourcePatches.Clear;

  // --teal-lighter
  FResourcePatches.Add(TResourcePatchCollection.Create(1, 'Titlebar', clDefault, ImmersiveSystemAccent, rpaImmersive, [TResourcePatch.Create('00bfa5')]));

  // --badge-pending, --teal, --active-tab-marker, --app-background-stripe, --checkbox-background, --highlight, --panel-background-colored-deeper
  FResourcePatches.Add(TResourcePatchCollection.Create(10, 'Panel background', clDefault, ImmersiveSaturatedBackground, rpaImmersive, [TResourcePatch.Create('009688')]));

  // --intro-border
  FResourcePatches.Add(TResourcePatchCollection.Create(2, 'Intro border', clDefault, ImmersiveLightBorder, rpaImmersive, [TResourcePatch.Create('4adf83')]));

  // --progress-primary
  FResourcePatches.Add(TResourcePatchCollection.Create(3, 'Progressbar', clDefault, ImmersiveControlLightProgressForeground, rpaImmersive, [TResourcePatch.Create('00d9bb')]));

  // --unread-marker-background
  FResourcePatches.Add(TResourcePatchCollection.Create(4, 'Unread message badge', clDefault, ImmersiveLightWUWarning, rpaImmersive, [TResourcePatch.Create('06d755')]));

  // --ptt-green
  FResourcePatches.Add(TResourcePatchCollection.Create(11, 'New voice mail icon', clDefault, ImmersiveLightWUWarning, rpaImmersive, [TResourcePatch.Create('09d261'), TResourcePatch.Create('09D261').JS]));

  // --ptt-blue, --icon-ack
  FResourcePatches.Add(TResourcePatchCollection.Create(12, 'Acknowledged icons', clDefault, ImmersiveLightWUNormal, rpaImmersive, [TResourcePatch.Create('4fc3f7')]));

  // --typing
  FResourcePatches.Add(TResourcePatchCollection.Create(13, '"Typing..." notification', clDefault, ImmersiveSaturatedCommandRowPressed, rpaImmersive, [TResourcePatch.Create('07bc4c')]));

  FResourcePatches.Add(TResourcePatchCollection.Create(14, 'Primary button background', clDefault, ImmersiveControlDefaultLightButtonBackgroundRest, rpaImmersive,
    [TResourcePatch.Create('--button-primary-background:#05cd51;', '--button-primary-background:#%COLOR%;'), TResourcePatch.Create('--button-primary-background-hover:#06d253;', '--button-primary-background-hover:#%COLOR%;').Darken3]));

  FResourcePatches.Add(TResourcePatchCollection.Create(15, 'Secondary button background', clDefault, ImmersiveControlLightButtonBackgroundRest, rpaImmersive,
    [TResourcePatch.Create('--button-secondary-background:#fff;', '--button-secondary-background:#%COLOR%;'), TResourcePatch.Create('--button-secondary-background-hover:#fff;', '--button-secondary-background-hover:#%COLOR%;').Darken3]));

  FResourcePatches.Add(TResourcePatchCollection.Create(16, 'Secondary button text', clDefault, ImmersiveControlLightAppButtonTextRest, rpaImmersive,
    [TResourcePatch.Create('--button-secondary:#07bc4c;', '--button-secondary:#%COLOR%;'), TResourcePatch.Create('--button-secondary-hover:#05cd51;', '--button-secondary-hover:#%COLOR%;').Lighten3]));

  FResourcePatches.Add(TResourcePatchCollection.Create(8, 'Background of incoming messages', clDefault, ImmersiveLightChromeMedium, rpaImmersive,
    [TResourcePatch.Create('--incoming-background:#fff;', '--incoming-background:#%COLOR%;'), TResourcePatch.Create('--incoming-background-rgb:255,255,255;', '--incoming-background-rgb:%COLOR%;').RBG,
    TResourcePatch.Create('--incoming-background-deeper:#f0f0f0;', '--incoming-background-deeper:#%COLOR%;').Darken, TResourcePatch.Create('--incoming-background-deeper-rgb:240,240,240;',
    '--incoming-background-deeper-rgb:%COLOR%;').RBG.Darken, TResourcePatch.Create('--audio-track-incoming:#e6e6e6;', '--audio-track-incoming:#%COLOR%;').Darken3,
    TResourcePatch.Create('--audio-progress-incoming:#31c76a;', '--audio-progress-incoming:#%COLOR%;').Darken10, TResourcePatch.Create('--audio-progress-played-incoming:#30b6f6;', '--audio-progress-played-incoming:#%COLOR%;').Darken10]));

  FResourcePatches.Add(TResourcePatchCollection.Create(9, 'Background of outgoing messages', clDefault, ImmersiveLightChromeWhite, rpaImmersive,
    [TResourcePatch.Create('--outgoing-background:#dcf8c6;', '--outgoing-background:#%COLOR%;'), TResourcePatch.Create('--outgoing-background-rgb:220,248,198;', '--outgoing-background-rgb:%COLOR%;').RBG,
    TResourcePatch.Create('--outgoing-background-deeper:#cfe9ba;', '--outgoing-background-deeper:#%COLOR%;').Darken, TResourcePatch.Create('--outgoing-background-deeper-rgb:207,233,186;',
    '--outgoing-background-deeper-rgb:%COLOR%;').RBG.Darken, TResourcePatch.Create('--audio-track-outgoing:#c6dfb2;', '--audio-track-outgoing:#%COLOR%;').Darken3,
    TResourcePatch.Create('--audio-progress-outgoing:#889a7b;', '--audio-progress-outgoing:#%COLOR%;').Darken10, TResourcePatch.Create('--audio-progress-played-outgoing:#2ab5eb;', '--audio-progress-played-outgoing:#%COLOR%;').Darken10]));

  FResourcePatches.Add(TResourcePatchCollection.Create(5, 'Minimize button hover color', clDefault, ImmersiveControlDefaultLightButtonBackgroundHover, rpaImmersive,
    [TResourcePatch.Create('#windows-title-minimize:hover{background-color:var(--teal-hover)}', '#windows-title-minimize:hover{background-color:#%COLOR%}')]));

  FResourcePatches.Add(TResourcePatchCollection.Create(6, 'Maximize button hover color', clDefault, ImmersiveControlDefaultLightButtonBackgroundHover, rpaImmersive,
    [TResourcePatch.Create('#windows-title-maximize:hover{background-color:var(--teal-hover)}', '#windows-title-maximize:hover{background-color:#%COLOR%}')]));

  FResourcePatches.Add(TResourcePatchCollection.Create(7, 'Close button hover color', clDefault, ImmersiveHardwareTitleBarCloseButtonHover, rpaImmersive,
    [TResourcePatch.Create('#windows-title-close:hover{background-color:var(--teal-hover)}', '#windows-title-close:hover{background-color:#%COLOR%}')]));

  FShowNotificationIcon := True;
  FIndicateNewMessages := True;
  FIndicatorColor := TFunctions.HTMLToColor('fe9500');
  FHideMaximize := False;
  FAlwaysOnTop := False;
  FDontSendPresence := False;
  FDontSendTyping := False;
end;

{ TResourcePatch }

constructor TResourcePatch.Create(const SearchColor: string);
begin
  FSearchText := SearchColor;
  FReplaceText := '%COLOR%';
  FReplaceFlags := [rfReplaceAll];
  FColorAdjustment := caNone;
end;

constructor TResourcePatch.Create(const SearchText, ReplaceText: string);
begin
  FSearchText := SearchText;
  FReplaceText := ReplaceText;
  FColorAdjustment := caNone;
end;

function TResourcePatch.RBG: TResourcePatch;
begin
  Result := Self;
  FRGBNotation := True;
end;

function TResourcePatch.Darken: TResourcePatch;
begin
  Result := Self;
  FColorAdjustment := caDarken;
end;

function TResourcePatch.Darken3: TResourcePatch;
begin
  Result := Self;
  FColorAdjustment := caDarken3;
end;

function TResourcePatch.Darken5: TResourcePatch;
begin
  Result := Self;
  FColorAdjustment := caDarken5;
end;

function TResourcePatch.Darken10: TResourcePatch;
begin
  Result := Self;
  FColorAdjustment := caDarken10;
end;

function TResourcePatch.Lighten3: TResourcePatch;
begin
  Result := Self;
  FColorAdjustment := caLighten3;
end;

function TResourcePatch.JS: TResourcePatch;
begin
  Result := Self;
  FTarget := rptJs;
end;

function TResourcePatch.Execute(const Source: string; const Color: TColor): string;
begin
  Result := Source.Replace(FSearchText, FReplaceText.Replace('%COLOR%', IfThen<string>(FRGBNotation, TFunctions.ColorToRGBHTML(Color), TFunctions.ColorToHTML(Color)), []), FReplaceFlags);
end;

{ TResourcePatchCollection }

constructor TResourcePatchCollection.Create(const ID: Integer; const Description: string; const ColorCustom: TColor; const ColorImmersive: TImmersiveColorType; const Action: TResourcePatchAction; const Patches: TResourcePatchArray);
begin
  FID := ID;
  FDescription := Description;
  FColorCustom := ColorCustom;
  FColorImmersive := ColorImmersive;
  FAction := Action;
  FPatches := Patches;
end;

destructor TResourcePatchCollection.Destroy;
var
  ResourcePatch: TResourcePatch;
begin
  for ResourcePatch in Patches do
    ResourcePatch.Free;
end;

end.
