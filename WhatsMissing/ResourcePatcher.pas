unit ResourcePatcher;

interface

uses
  ASAR,
  Classes,
  Functions,
  Graphics,
  GraphUtil,
  ImmersiveColors,
  Paths,
  Settings,
  SysUtils;

type
  TResourcePatcher = class
  private
    FSettings: TSettings;

    FFiles: TStringList;

    procedure PatchFile(const FileName: string);
    procedure CollectFiles;
  public
    constructor Create(Settings: TSettings);
    destructor Destroy; override;

    procedure RunAll;
    procedure RunUnpatched;
    procedure CleanUp;
    function ExistsUnpatched: Boolean;

    class function GetColor(const ResourcePatchCollection: TResourcePatchCollection; const ColorAdjustment: TColorAdjustment): TColor; static;
  end;

implementation

{ TResourcePatcher }

procedure TResourcePatcher.PatchFile(const FileName: string);
type
  TStaticReplace = record
    Search: string;
    Replace: string;
    Multiple: Boolean;
  end;
var
  ASAR: TASAR;
  ASARCSS: TASARFile;
  CSS: AnsiString;
  ResourcePatchCollection: TResourcePatchCollection;
  ResourcePatch: TResourcePatchBase;
  StaticReplace: TStaticReplace;
const
  StaticReplacements: array[0..5] of TStaticReplace = (
    (Search: '#windows-title-minimize.blurred{opacity:.7}'; Replace: '#windows-title-minimize.blurred{opacity:1}'; Multiple: False),
    (Search: '#windows-title-maximize.blurred{opacity:.7}'; Replace: '#windows-title-maximize.blurred{opacity:1}'; Multiple: False),
    (Search: '#windows-title-close.blurred{opacity:.7}'; Replace: '#windows-title-close.blurred{opacity:1}'; Multiple: False),
    (Search: '#windows-title-minimize{position:absolute;'; Replace: '#windows-title-minimize{position:absolute;cursor:default;'; Multiple: False),
    (Search: '#windows-title-maximize{position:absolute;'; Replace: '#windows-title-maximize{position:absolute;cursor:default;'; Multiple: False),
    (Search: '#windows-title-close{position:absolute;'; Replace: '#windows-title-close{position:absolute;cursor:default;'; Multiple: False)
    );
begin
  ASAR := TASAR.Create;
  try
    ASAR.Read(Filename);

    ASARCSS := TASARFile(ASAR.Root.FindEntry('cssm.css', TASARFile));
    if not Assigned(ASARCSS) then
      raise Exception.Create('cssm.css not found');

    SetString(CSS, PAnsiChar(ASARCSS.Contents.Memory), ASARCSS.Contents.Size);

    for ResourcePatchCollection in FSettings.ResourcePatches do
      if ResourcePatchCollection.Action <> rpaNone then
        for ResourcePatch in ResourcePatchCollection.Patches do
          CSS := ResourcePatch.Execute(CSS, GetColor(ResourcePatchCollection, ResourcePatch.ColorAdjustment));

    if FSettings.HideMaximize then
    begin
      CSS := CSS.Replace('#windows-title-minimize{right:90px}', '#windows-title-minimize{right:45px}', []);
      CSS := CSS.Replace('#windows-title-maximize{position:absolute;width:45px', '#windows-title-maximize{position:absolute;width:0px', []);
    end;

    for StaticReplace in StaticReplacements do
      if StaticReplace.Multiple then
        CSS := CSS.Replace(StaticReplace.Search, StaticReplace.Replace, [rfReplaceAll])
      else
        CSS := CSS.Replace(StaticReplace.Search, StaticReplace.Replace, []);

    ASARCSS.Contents.Clear;

    ASARCSS.Contents.Write(CSS[1], Length(CSS));

    ASAR.Write(TFunctions.GetPatchedResourceFilePath(FileName));
  finally
    ASAR.Free;
  end;
end;

procedure TResourcePatcher.CollectFiles;
begin
  FFiles.Clear;
  TFunctions.FindFiles(TPaths.WhatsAppDir, 'app.asar', True, FFiles);
end;

constructor TResourcePatcher.Create(Settings: TSettings);
begin
  FSettings := Settings;
  FFiles := TStringList.Create;
end;

destructor TResourcePatcher.Destroy;
begin
  if Assigned(FFiles) then
    FFiles.Free;

  inherited;
end;

procedure TResourcePatcher.RunAll;
var
  F: string;
begin
  CollectFiles;
  for F in FFiles do
    PatchFile(F);
end;

procedure TResourcePatcher.RunUnpatched;
var
  Patched: Boolean;
  F: string;
begin
  CollectFiles;
  for F in FFiles do
  begin
    Patched := FileExists(TFunctions.GetPatchedResourceFilePath(F));
    if not Patched then
      PatchFile(F);
  end;
end;

procedure TResourcePatcher.CleanUp;
var
  Found: Boolean;
  ResFile, PatchedResFile: string;
  PatchedFiles: TStringList;
begin
  CollectFiles;

  PatchedFiles := TStringList.Create;
  try
    TFunctions.FindFiles(TPaths.PatchedResourceDir, '*.asar', False, PatchedFiles);

    for PatchedResFile in PatchedFiles do
    begin
      Found := False;

      for ResFile in FFiles do
        if TFunctions.GetPatchedResourceFilePath(ResFile).ToLower.Equals(PatchedResFile.ToLower) then
        begin
          Found := True;
          Break;
        end;

      if not Found then
        DeleteFile(PatchedResFile);
    end;
  finally
    PatchedFiles.Free;
  end;
end;

function TResourcePatcher.ExistsUnpatched: Boolean;
var
  F: string;
begin
  Result := False;
  CollectFiles;
  for F in FFiles do
    if not FileExists(TFunctions.GetPatchedResourceFilePath(F)) then
      Exit(True);
end;

class function TResourcePatcher.GetColor(const ResourcePatchCollection: TResourcePatchCollection; const ColorAdjustment: TColorAdjustment): TColor;
begin
  case ResourcePatchCollection.Action of
    rpaNone:
      Result := clNone;
    rpaImmersive:
      Result := AlphaColorToColor(GetActiveImmersiveColor(ImmersiveColors.TImmersiveColorType(ResourcePatchCollection.ColorImmersive)));
    rpaCustom:
      Result := ResourcePatchCollection.ColorCustom;
    else
      raise Exception.Create('GetColor(): Invalid action');
  end;

  Result := ColorAdjustLuma(Result, Integer(ColorAdjustment), True);
end;

end.

