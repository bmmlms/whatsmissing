unit Settings;

interface

uses
  Classes,
  fpjson,
  Functions,
  Generics.Collections,
  jsonparser,
  SysUtils;

{$I ImmersiveType.inc}

type
  TColorAdjustment = (caDarken5 = -25, caDarken3 = -15, caDarken2 = -10, caDarken = -5, caNone = 0, caLighten = 5, caLighten2 = 10, caLighten3 = 15, caLighten5 = 25);
  TResourcePatchAction = (rpaNone, rpaImmersive, rpaCustom);

  TResourcePatchBase = class
    abstract
  private
    FColorAdjustment: TColorAdjustment;
  protected
    constructor Create(const ColorAdjustment: TColorAdjustment);
  public
    function Execute(const Source: string; const Color: TColor): string; virtual; abstract;

    property ColorAdjustment: TColorAdjustment read FColorAdjustment;
  end;

  TResourcePatchColor = class(TResourcePatchBase)
  private
    FSearchColor: TColor;
  public
    constructor Create(const SearchColor: TColor; const ColorAdjustment: TColorAdjustment = caNone); reintroduce;

    function Execute(const Source: string; const Color: TColor): string; override;

    property SearchColor: TColor read FSearchColor;
  end;

  TResourcePatchText = class(TResourcePatchBase)
  private
    FSearchText: string;
    FReplaceText: string;
    FUseRGBNotation: Boolean;
  public
    constructor Create(const SearchText, ReplaceText: string; const UseRGBNotation: Boolean; const ColorAdjustment: TColorAdjustment = caNone); reintroduce;

    function Execute(const Source: string; const Color: TColor): string; override;

    property SearchText: string read FSearchText;
    property ReplaceText: string read FReplaceText;
  end;

  TResourcePatchArray = array of TResourcePatchBase;

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

    FRebuildResources: Boolean;

    FResourcePatches: TList<TResourcePatchCollection>;

    FShowNotificationIcon: Boolean;
    FIndicateNewMessages: Boolean;
    FIndicatorColor: TColor;
    FHideMaximize: Boolean;
    FAlwaysOnTop: Boolean;

    procedure Reset;
  public
    constructor Create(const FilePath: string);
    destructor Destroy; override;

    procedure Load;
    procedure Save;

    property RebuildResources: Boolean read FRebuildResources write FRebuildResources;

    property ResourcePatches: TList<TResourcePatchCollection> read FResourcePatches;

    property ShowNotificationIcon: Boolean read FShowNotificationIcon write FShowNotificationIcon;
    property IndicateNewMessages: Boolean read FIndicateNewMessages write FIndicateNewMessages;
    property IndicatorColor: TColor read FIndicatorColor write FIndicatorColor;
    property HideMaximize: Boolean read FHideMaximize write FHideMaximize;
    property AlwaysOnTop: Boolean read FAlwaysOnTop write FAlwaysOnTop;
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
        FRebuildResources := JSONObject.Get('RebuildResources', False);
        FShowNotificationIcon := JSONObject.Get('ShowNotificationIcon', True);
        FIndicateNewMessages := JSONObject.Get('IndicateNewMessages', False);
        FIndicatorColor := JSONObject.Get('IndicatorColor');
        FHideMaximize := JSONObject.Get('HideMaximize', False);
        FAlwaysOnTop := JSONObject.Get('AlwaysOnTop', False);

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
    JSONObject.Add('RebuildResources', FRebuildResources);
    JSONObject.Add('ShowNotificationIcon', FShowNotificationIcon);
    JSONObject.Add('IndicateNewMessages', FIndicateNewMessages);
    JSONObject.Add('IndicatorColor', FIndicatorColor);
    JSONObject.Add('HideMaximize', FHideMaximize);
    JSONObject.Add('AlwaysOnTop', FAlwaysOnTop);

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
  FRebuildResources := False;

  for ResourcePatchCollection in FResourcePatches do
    ResourcePatchCollection.Free;
  FResourcePatches.Clear;

  // --teal-lighter
  FResourcePatches.Add(TResourcePatchCollection.Create(1, 'Titlebar', clDefault, ImmersiveSystemAccent, rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('00bfa5'))]));

  // --badge-pending, --teal, --active-tab-marker, --app-background-stripe, --checkbox-background, --highlight, --panel-background-colored-deeper
  FResourcePatches.Add(TResourcePatchCollection.Create(10, 'Panel background', clDefault, ImmersiveSaturatedBackground, rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('009688'))]));

  // --intro-border
  FResourcePatches.Add(TResourcePatchCollection.Create(2, 'Intro border', clDefault, ImmersiveLightBorder, rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('4adf83'))]));

  // --progress-primary
  FResourcePatches.Add(TResourcePatchCollection.Create(3, 'Progressbar', clDefault, ImmersiveControlLightProgressForeground, rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('00d9bb'))]));

  // --unread-marker-background
  FResourcePatches.Add(TResourcePatchCollection.Create(4, 'Unread message badge', clDefault, ImmersiveLightWUNormal, rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('06d755'))]));

  // --ptt-green
  FResourcePatches.Add(TResourcePatchCollection.Create(11, 'New voice mail icon', clDefault, ImmersiveLightWUNormal, rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('09d261'))]));

  // --ptt-blue, --icon-ack
  FResourcePatches.Add(TResourcePatchCollection.Create(12, 'Heard voice mail icon', clDefault, ImmersiveLightWUWarning, rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('4fc3f7'))]));

  FResourcePatches.Add(TResourcePatchCollection.Create(8, 'Background of incoming messages', clDefault, ImmersiveLightChromeMedium, rpaImmersive,
    [TResourcePatchText.Create('--incoming-background:#fff;', '--incoming-background:#%COLOR%;', False), TResourcePatchText.Create('--incoming-background-rgb:255,255,255;',
    '--incoming-background-rgb:%COLOR%;', True), TResourcePatchText.Create('--incoming-background-deeper:#f0f0f0;', '--incoming-background-deeper:#%COLOR%;', False, caDarken),
    TResourcePatchText.Create('--incoming-background-deeper-rgb:240,240,240;', '--incoming-background-deeper-rgb:%COLOR%;', True, caDarken), TResourcePatchText.Create(
    '--audio-track-incoming:#e6e6e6;', '--audio-track-incoming:#%COLOR%;', False, caDarken3), TResourcePatchText.Create('--audio-progress-incoming:#31c76a;', '--audio-progress-incoming:#%COLOR%;', False, caDarken5),
    TResourcePatchText.Create('--audio-progress-played-incoming:#30b6f6;', '--audio-progress-played-incoming:#%COLOR%;', False, caDarken5)]));

  FResourcePatches.Add(TResourcePatchCollection.Create(9, 'Background of outgoing messages', clDefault, ImmersiveLightChromeWhite, rpaImmersive,
    [TResourcePatchText.Create('--outgoing-background:#dcf8c6;', '--outgoing-background:#%COLOR%;', False), TResourcePatchText.Create('--outgoing-background-rgb:220,248,198;',
    '--outgoing-background-rgb:%COLOR%;', True), TResourcePatchText.Create('--outgoing-background-deeper:#cfe9ba;', '--outgoing-background-deeper:#%COLOR%;', False, caDarken),
    TResourcePatchText.Create('--outgoing-background-deeper-rgb:207,233,186;', '--outgoing-background-deeper-rgb:%COLOR%;', True, caDarken), TResourcePatchText.Create(
    '--audio-track-outgoing:#c6dfb2;', '--audio-track-outgoing:#%COLOR%;', False, caDarken3), TResourcePatchText.Create('--audio-progress-outgoing:#889a7b;', '--audio-progress-outgoing:#%COLOR%;', False, caDarken5),
    TResourcePatchText.Create('--audio-progress-played-outgoing:#2ab5eb;', '--audio-progress-played-outgoing:#%COLOR%;', False, caDarken5)]));

  FResourcePatches.Add(TResourcePatchCollection.Create(5, 'Minimize button hover color', clDefault, ImmersiveControlDefaultLightButtonBackgroundHover, rpaImmersive,
    [TResourcePatchText.Create('#windows-title-minimize:hover{background-color:var(--teal-hover)}', '#windows-title-minimize:hover{background-color:#%COLOR%}', False)]));

  FResourcePatches.Add(TResourcePatchCollection.Create(6, 'Maximize button hover color', clDefault, ImmersiveControlDefaultLightButtonBackgroundHover, rpaImmersive,
    [TResourcePatchText.Create('#windows-title-maximize:hover{background-color:var(--teal-hover)}', '#windows-title-maximize:hover{background-color:#%COLOR%}', False)]));

  FResourcePatches.Add(TResourcePatchCollection.Create(7, 'Close button hover color', clDefault, ImmersiveHardwareTitleBarCloseButtonHover, rpaImmersive,
    [TResourcePatchText.Create('#windows-title-close:hover{background-color:var(--teal-hover)}', '#windows-title-close:hover{background-color:#%COLOR%}', False)]));

  FShowNotificationIcon := True;
  FIndicateNewMessages := True;
  FIndicatorColor := TFunctions.HTMLToColor('c4314b');
  FAlwaysOnTop := False;
end;

{ TResourcePatchBase }

constructor TResourcePatchBase.Create(const ColorAdjustment: TColorAdjustment);
begin
  FColorAdjustment := ColorAdjustment;
end;

{ TResourcePatchColor }

constructor TResourcePatchColor.Create(const SearchColor: TColor; const ColorAdjustment: TColorAdjustment);
begin
  inherited Create(ColorAdjustment);

  FSearchColor := SearchColor;
end;

function TResourcePatchColor.Execute(const Source: string; const Color: TColor): string;
begin
  Result := Source.Replace(TFunctions.ColorToHTML(SearchColor).ToLower, TFunctions.ColorToHTML(Color), [rfReplaceAll]);
end;

{ TResourcePatchText }

constructor TResourcePatchText.Create(const SearchText, ReplaceText: string; const UseRGBNotation: Boolean; const ColorAdjustment: TColorAdjustment);
begin
  inherited Create(ColorAdjustment);

  FSearchText := SearchText;
  FReplaceText := ReplaceText;
  FUseRGBNotation := UseRGBNotation;
end;

function TResourcePatchText.Execute(const Source: string; const Color: TColor): string;
begin
  Result := Source.Replace(SearchText, ReplaceText.Replace('%COLOR%', IfThen<string>(FUseRGBNotation, TFunctions.ColorToRGBHTML(Color), TFunctions.ColorToHTML(Color).ToLower), []), []);
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
  ResourcePatch: TResourcePatchBase;
begin
  for ResourcePatch in Patches do
    ResourcePatch.Free;
end;

end.
