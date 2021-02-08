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
  TResourcePatchAction = (rpaNone, rpaImmersive, rpaCustom);

  TResourcePatchBase = class
    abstract
  private
  public
    function Execute(const Source: string; const Color: TColor): string; virtual; abstract;
  end;

  TResourcePatchColor = class(TResourcePatchBase)
  private
    FSearchColor: TColor;
  public
    constructor Create(const SearchColor: TColor);

    function Execute(const Source: string; const Color: TColor): string; override;

    property SearchColor: TColor read FSearchColor;
  end;

  TResourcePatchText = class(TResourcePatchBase)
  private
    FSearchText: string;
    FReplaceText: string;
    FUseRGBNotation: Boolean;
  public
    constructor Create(const SearchText, ReplaceText: string; const UseRGBNotation: Boolean);

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
    FColorImmersive: Integer;
    FAction: TResourcePatchAction;
    FPatches: TResourcePatchArray;
  public
    constructor Create(const ID: Integer; const Description: string; const ColorCustom: TColor; const ColorImmersive: Integer; const Action: TResourcePatchAction; const Patches: TResourcePatchArray);
    destructor Destroy; override;

    function Execute(const Source: string; const Color: TColor): string;

    property ID: Integer read FID;
    property Description: string read FDescription;
    property ColorCustom: TColor read FColorCustom write FColorCustom;
    property ColorImmersive: Integer read FColorImmersive write FColorImmersive;
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
  ResourcePatch: TResourcePatchCollection;
begin
  for ResourcePatch in FResourcePatches do
    ResourcePatch.Free;

  FResourcePatches.Free;

  inherited;
end;

procedure TSettings.Load;
var
  JSONEnum: TJSONEnum;
  JSONObject, JSONObjectResource: TJSONObject;
  JSONArray: TJSONArray;
  ResourcePatch: TResourcePatchCollection;
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
          for ResourcePatch in FResourcePatches do
            if ResourcePatch.ID = JSONObjectResource.Get('ID', -1) then
            begin
              ResourcePatch.Action := TResourcePatchAction(JSONObjectResource.Get('Action', 0));
              ResourcePatch.ColorCustom := JSONObjectResource.Get('ColorCustom', 0);
              ResourcePatch.ColorImmersive := JSONObjectResource.Get('ColorImmersive', 0);
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
  ResourcePatch: TResourcePatchCollection;
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

    for ResourcePatch in FResourcePatches do
    begin
      JSONObjectResource := TJSONObject.Create;
      JSONArray.Add(JSONObjectResource);

      JSONObjectResource.Add('ID', ResourcePatch.ID);
      JSONObjectResource.Add('Action', Integer(ResourcePatch.Action));
      JSONObjectResource.Add('ColorCustom', ResourcePatch.ColorCustom);
      JSONObjectResource.Add('ColorImmersive', Integer(ResourcePatch.ColorImmersive));
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
  ResourcePatch: TResourcePatchCollection;
begin
  FRebuildResources := False;

  for ResourcePatch in FResourcePatches do
    ResourcePatch.Free;
  FResourcePatches.Clear;

  // --teal-lighter
  FResourcePatches.Add(TResourcePatchCollection.Create(1, 'Titlebar', clDefault, Integer(ImmersiveSystemAccent), rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('00bfa5'))]));

  // --intro-border
  FResourcePatches.Add(TResourcePatchCollection.Create(2, 'Intro border', clDefault, Integer(ImmersiveLightBorder), rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('4adf83'))]));

  // --progress-primary
  FResourcePatches.Add(TResourcePatchCollection.Create(3, 'Progressbar', clDefault, Integer(ImmersiveControlLightProgressForeground), rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('00d9bb'))]));

  // --unread-marker-background
  FResourcePatches.Add(TResourcePatchCollection.Create(4, 'Unread message badge', clDefault, Integer(ImmersiveSystemAccentLight3), rpaImmersive, [TResourcePatchColor.Create(TFunctions.HTMLToColor('06d755'))]));

  FResourcePatches.Add(TResourcePatchCollection.Create(8, 'Background of incoming messages', clDefault, Integer(ImmersiveLightChromeLow), rpaImmersive,
    [TResourcePatchText.Create('--incoming-background:#fff;', '--incoming-background:#%COLOR%;', False), TResourcePatchText.Create('--incoming-background-rgb:255,255,255;', '--incoming-background-rgb:%COLOR%;', True)]));

  FResourcePatches.Add(TResourcePatchCollection.Create(9, 'Background of outgoing messages', clDefault, Integer(ImmersiveLightChromeHigh), rpaImmersive,
    [TResourcePatchText.Create('--outgoing-background:#dcf8c6;', '--outgoing-background:#%COLOR%;', False), TResourcePatchText.Create('--outgoing-background-rgb:220,248,198;', '--outgoing-background-rgb:%COLOR%;', True)]));

  FResourcePatches.Add(TResourcePatchCollection.Create(5, 'Minimize button hover color', clDefault, Integer(ImmersiveControlDefaultLightButtonBackgroundHover), rpaImmersive,
    [TResourcePatchText.Create('#windows-title-minimize:hover{background-color:var(--teal-hover)}', '#windows-title-minimize:hover{background-color:#%COLOR%}', False)]));

  FResourcePatches.Add(TResourcePatchCollection.Create(6, 'Maximize button hover color', clDefault, Integer(ImmersiveControlDefaultLightButtonBackgroundHover), rpaImmersive,
    [TResourcePatchText.Create('#windows-title-maximize:hover{background-color:var(--teal-hover)}', '#windows-title-maximize:hover{background-color:#%COLOR%}', False)]));

  FResourcePatches.Add(TResourcePatchCollection.Create(7, 'Close button hover color', clDefault, Integer(ImmersiveHardwareTitleBarCloseButtonHover), rpaImmersive,
    [TResourcePatchText.Create('#windows-title-close:hover{background-color:var(--teal-hover)}', '#windows-title-close:hover{background-color:#%COLOR%}', False)]));

  FShowNotificationIcon := True;
  FIndicateNewMessages := True;
  FIndicatorColor := TFunctions.HTMLToColor('c4314b');
  FAlwaysOnTop := False;
end;

{ TResourcePatchColor }

constructor TResourcePatchColor.Create(const SearchColor: TColor);
begin
  FSearchColor := SearchColor;
end;

function TResourcePatchColor.Execute(const Source: string; const Color: TColor): string;
begin
  Result := Source.Replace(TFunctions.ColorToHTML(SearchColor).ToLower, TFunctions.ColorToHTML(Color), [rfReplaceAll]);
end;

{ TResourcePatchText }

constructor TResourcePatchText.Create(const SearchText, ReplaceText: string; const UseRGBNotation: Boolean);
begin
  FSearchText := SearchText;
  FReplaceText := ReplaceText;
  FUseRGBNotation := UseRGBNotation;
end;

function TResourcePatchText.Execute(const Source: string; const Color: TColor): string;
begin
  Result := Source.Replace(SearchText, ReplaceText.Replace('%COLOR%', IfThen<string>(FUseRGBNotation, TFunctions.ColorToRGBHTML(Color), TFunctions.ColorToHTML(Color).ToLower), []), []);
end;

{ TResourcePatchCollection }

constructor TResourcePatchCollection.Create(const ID: Integer; const Description: string; const ColorCustom: TColor; const ColorImmersive: Integer; const Action: TResourcePatchAction; const Patches: TResourcePatchArray);
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

function TResourcePatchCollection.Execute(const Source: string; const Color: TColor): string;
var
  Patch: TResourcePatchBase;
begin
  Result := Source;
  for Patch in Patches do
    Result := Patch.Execute(Result, Color);
end;

end.
