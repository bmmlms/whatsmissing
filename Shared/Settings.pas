unit Settings;

interface

uses
  Classes,
  fpjson,
  Functions,
  Generics.Collections,
  jsonparser,
  SysUtils;

type
  TResourcePatchAction = (rpaNone, rpaImmersive, rpaCustom);

  TResourcePatch = class
    abstract
  private
    FID: Integer;
    FDescription: string;
    FColorCustom: TColor;
    FColorImmersive: Integer;
    FAction: TResourcePatchAction;
  public
    constructor Create(const ID: Integer; const Description: string; const ColorCustom: TColor; const ColorImmersive: Integer; const Action: TResourcePatchAction); virtual;

    function Execute(const Source: string; const Color: TColor): string; virtual; abstract;

    property ID: Integer read FID;
    property Description: string read FDescription;
    property ColorCustom: TColor read FColorCustom write FColorCustom;
    property ColorImmersive: Integer read FColorImmersive write FColorImmersive;
    property Action: TResourcePatchAction read FAction write FAction;
  end;

  TResourcePatchColor = class(TResourcePatch)
  private
    FSearchColor: TColor;
  public
    constructor Create(const ID: Integer; const Description: string; const SearchColor, ColorCustom: TColor; const ColorImmersive: Integer; const Action: TResourcePatchAction); reintroduce;

    function Execute(const Source: string; const Color: TColor): string; override;

    property SearchColor: TColor read FSearchColor;
  end;

  TResourcePatchText = class(TResourcePatch)
  private
    FSearchText: string;
    FReplaceText: string;
  public
    constructor Create(const ID: Integer; const Description, SearchText, ReplaceText: string; const ColorCustom: TColor; const ColorImmersive: Integer; const Action: TResourcePatchAction); reintroduce;

    function Execute(const Source: string; const Color: TColor): string; override;

    property SearchText: string read FSearchText;
    property ReplaceText: string read FReplaceText;
  end;

  TSettings = class
  private
    FFilePath: string;

    FRebuildResources: Boolean;

    FResourcePatches: TList<TResourcePatch>;

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

    property ResourcePatches: TList<TResourcePatch> read FResourcePatches;

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

  FResourcePatches := TList<TResourcePatch>.Create;

  Reset;

  Load;
end;

destructor TSettings.Destroy;
var
  ResourcePatch: TResourcePatch;
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
  ResourcePatch: TResourcePatch;
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
  ResourcePatch: TResourcePatch;
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
  ImmersiveSystemAccent = 1203;
  ImmersiveLightBorder = 943;
  ImmersiveControlLightProgressForeground = 326;
  ImmersiveSystemAccentLight3 = 1209;
  ImmersiveControlDefaultLightButtonBackgroundHover = 258;
  ImmersiveHardwareTitleBarCloseButtonHover = 868;

  clDefault = $20000000;
var
  ResourcePatch: TResourcePatch;
begin
  FRebuildResources := False;

  for ResourcePatch in FResourcePatches do
    ResourcePatch.Free;
  FResourcePatches.Clear;

  // --teal-lighter
  FResourcePatches.Add(TResourcePatchColor.Create(1, 'Titlebar', TFunctions.HTMLToColor('00bfa5'), clDefault, Integer(ImmersiveSystemAccent), rpaImmersive));
  // --intro-border
  FResourcePatches.Add(TResourcePatchColor.Create(2, 'Intro border', TFunctions.HTMLToColor('4adf83'), clDefault, Integer(ImmersiveLightBorder), rpaImmersive));
  // --progress-primary
  FResourcePatches.Add(TResourcePatchColor.Create(3, 'Progressbar', TFunctions.HTMLToColor('00d9bb'), clDefault, Integer(ImmersiveControlLightProgressForeground), rpaImmersive));
  // --unread-marker-background
  FResourcePatches.Add(TResourcePatchColor.Create(4, 'Unread message badge', TFunctions.HTMLToColor('06d755'), clDefault, Integer(ImmersiveSystemAccentLight3), rpaImmersive));

  FResourcePatches.Add(TResourcePatchText.Create(5, 'Minimize button hover color', '#windows-title-minimize:hover{background-color:var(--teal-hover)}', '#windows-title-minimize:hover{background-color:#%COLOR%}', clDefault, Integer(ImmersiveControlDefaultLightButtonBackgroundHover), rpaImmersive));
  FResourcePatches.Add(TResourcePatchText.Create(6, 'Maximize button hover color', '#windows-title-maximize:hover{background-color:var(--teal-hover)}', '#windows-title-maximize:hover{background-color:#%COLOR%}', clDefault, Integer(ImmersiveControlDefaultLightButtonBackgroundHover), rpaImmersive));
  FResourcePatches.Add(TResourcePatchText.Create(7, 'Close button hover color', '#windows-title-close:hover{background-color:var(--teal-hover)}', '#windows-title-close:hover{background-color:#%COLOR%}', clDefault, Integer(ImmersiveHardwareTitleBarCloseButtonHover), rpaImmersive));

  FShowNotificationIcon := True;
  FIndicateNewMessages := True;
  FIndicatorColor := TFunctions.HTMLToColor('c4314b');
  FAlwaysOnTop := False;
end;

{ TResourcePatch }

constructor TResourcePatch.Create(const ID: Integer; const Description: string; const ColorCustom: TColor; const ColorImmersive: Integer; const Action: TResourcePatchAction);
begin
  FID := ID;
  FDescription := Description;
  FColorCustom := ColorCustom;
  FColorImmersive := ColorImmersive;
  FAction := Action;
end;

{ TResourcePatchColor }

constructor TResourcePatchColor.Create(const ID: Integer; const Description: string; const SearchColor, ColorCustom: TColor; const ColorImmersive: Integer; const Action: TResourcePatchAction);
begin
  inherited Create(ID, Description, ColorCustom, ColorImmersive, Action);

  FSearchColor := SearchColor;
  FColorCustom := ColorCustom;
  FColorImmersive := ColorImmersive;
end;

function TResourcePatchColor.Execute(const Source: string; const Color: TColor): string;
begin
  Result := Source.Replace(TFunctions.ColorToHTML(SearchColor).ToLower, TFunctions.ColorToHTML(Color), [rfReplaceAll]);
end;

{ TResourcePatchText }

constructor TResourcePatchText.Create(const ID: Integer; const Description, SearchText, ReplaceText: string; const ColorCustom: TColor; const ColorImmersive: Integer; const Action: TResourcePatchAction);
begin
  inherited Create(ID, Description, ColorCustom, ColorImmersive, Action);

  FSearchText := SearchText;
  FReplaceText := ReplaceText;
end;

function TResourcePatchText.Execute(const Source: string; const Color: TColor): string;
begin
  Result := Source.Replace(SearchText, ReplaceText.Replace('%COLOR%', TFunctions.ColorToHTML(Color).ToLower, []), []);
end;

end.
