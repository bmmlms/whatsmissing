unit ResourcePatcher;

interface

uses
  ASAR,
  Classes,
  fpjson,
  Functions,
  Generics.Collections,
  Graphics,
  ImmersiveColors,
  Log,
  Paths,
  RegExpr,
  Settings,
  SysUtils;

type

  { TResourcePatcher }

  TResourcePatcher = class
  private
    FSettings: TSettings;
    FLog: TLog;

    FJSON: TMemoryStream;
    FResources: TMemoryStream;
    FContentOffset: Cardinal;

    FCssError: Boolean;
    FJsError: Boolean;
  public
    constructor Create(const Settings: TSettings; const Log: TLog);
    destructor Destroy; override;

    procedure ConsumeFile(const FileName: string);

    property JSON: TMemoryStream read FJSON;
    property Resources: TMemoryStream read FResources;
    property ContentOffset: Cardinal read FContentOffset;

    property CssError: Boolean read FCssError;
    property JsError: Boolean read FJsError;
  end;

  TResourcePatchInfo = record
    Setting: TResourceColorSetting;
    Patch: TResourceColorSettingPatch;
  end;
  PResourcePatchInfo = ^TResourcePatchInfo;

implementation

{ TResourcePatcher }

constructor TResourcePatcher.Create(const Settings: TSettings; const Log: TLog);
begin
  FSettings := Settings;
  FLog := Log;

  FResources := TMemoryStream.Create;
  FJSON := TMemoryStream.Create;
end;

destructor TResourcePatcher.Destroy;
begin
  FResources.Free;
  FJSON.Free;

  inherited;
end;

function SortResourcePatchInfos(A, B: PResourcePatchInfo): LongInt; register;
begin
  if A.Patch.SearchText.Length > B.Patch.SearchText.Length then
    Result := -1
  else if A.Patch.SearchText.Length < B.Patch.SearchText.Length then
    Result := 1
  else
    Result := 0;
end;

procedure TResourcePatcher.ConsumeFile(const FileName: string);
type
  TStringReplace = record
    Search: string;
    Replace: string;
    ReplaceFlags: TReplaceFlags;
  end;

  TRegExReplace = record
    Search: string;
    Replace: string;
  end;
var
  Asar: TASAR;
  AsarCss, AsarSvgJs, AsarMainJs, AsarPreloadJs: TASARFile;
  ReplaceCount, StrLen, FileOffset: Integer;
  Css, SvgJs, MainJs, PreloadJs: AnsiString;
  ColorSetting: TColorSetting;
  ResourcePatch: TResourceColorSettingPatch;
  StringReplace: TStringReplace;
  RegExReplace: TRegExReplace;
  RegEx: TRegExpr;
  FileUpdate: TPair<TJSONObject, string>;
  FileUpdates: TDictionary<TJSONObject, string>;
  ResourcePatchInfo: PResourcePatchInfo;
  ResourcePatchInfos: TList;
const
  PreloadJsPatch: AnsiString = '(function() { var fs = require("fs"); var h = fs.openSync("\\\\.\\wacommunication", "w+"); window.wmcall = function(method, data) ' +
    '{ var b = Buffer.alloc(1024); fs.writeSync(h, JSON.stringify({ method: method, data: data })); fs.readSync(h, b, 0, 1024, 0); return JSON.parse(b.toString()); }; }());';
  CssStringReplacements: array[0..5] of TStringReplace = (
    (Search: '#windows-title-minimize.blurred{opacity:.7}'; Replace: '#windows-title-minimize.blurred{opacity:1}'; ReplaceFlags: []),
    (Search: '#windows-title-maximize.blurred{opacity:.7}'; Replace: '#windows-title-maximize.blurred{opacity:1}'; ReplaceFlags: []),
    (Search: '#windows-title-close.blurred{opacity:.7}'; Replace: '#windows-title-close.blurred{opacity:1}'; ReplaceFlags: []),
    (Search: '#windows-title-minimize{position:absolute;'; Replace: '#windows-title-minimize{position:absolute;cursor:default;'; ReplaceFlags: []),
    (Search: '#windows-title-maximize{position:absolute;'; Replace: '#windows-title-maximize{position:absolute;cursor:default;'; ReplaceFlags: []),
    (Search: '#windows-title-close{position:absolute;'; Replace: '#windows-title-close{position:absolute;cursor:default;'; ReplaceFlags: []));
  JsRegExReplacements: array[0..3] of TRegExReplace = (
    (Search: 'return (.)\.decrypt\((.)\)\.then\(\(function\((.)\)\{return (.)\.readNode\(new (.)\((.)\)\)';
    Replace: 'return $1.decrypt($2).then((function($3){ var vv = $4.readNode(new $5($6)); window.wmcall("socket_in", vv); return vv;'),
    (Search: 'return (.)\.writeNode\((.),(.)\),(.)\.encrypt\((.)\.toBuffer\(\)\)\}\)\)'; Replace: 'if (!window.wmcall("socket_out", $3)) return; return $1.writeNode($2,$3),$4.encrypt($5.toBuffer())}))'),
    (Search: 'var (.)=this\.parseMsg\((.)\[0\],"relay"\);'; Replace: 'var $1=this.parseMsg($2[0],"relay"); window.wmcall("message", {sent: $1.id.fromMe, jid: $1.id.remote});'),
    (Search: '(.)\.default\.getGlobalSounds\(\)&&\((.)\.id'; Replace: 'window.wmcall("ask_notification_sound", $2.id) &&$1.default.getGlobalSounds()&&($2.id'));
begin
  FLog.Info('Patching file "%s"'.Format([FileName]));

  FJSON.Clear;
  FResources.Clear;

  Asar := TASAR.Create;
  FileUpdates := TDictionary<TJSONObject, string>.Create;
  try
    Asar.Read(Filename);

    AsarCss := TASARFile(Asar.Root.FindEntry('renderer-*.css', TASARFile));
    AsarSvgJs := TASARFile(Asar.Root.FindEntry('svg.*.js', TASARFile));
    AsarMainJs := TASARFile(Asar.Root.FindEntry('bootstrap_main.*.js', TASARFile));
    AsarPreloadJs := TASARFile(Asar.Root.FindEntry('preload.js', TASARFile));

    if Assigned(AsarCss) then
      SetString(Css, PAnsiChar(AsarCss.Contents.Memory), AsarCss.Contents.Size)
    else
      Css := '';

    if Assigned(AsarSvgJs) then
      SetString(SvgJs, PAnsiChar(AsarSvgJs.Contents.Memory), AsarSvgJs.Contents.Size)
    else
      SvgJs := '';

    if Assigned(AsarMainJs) then
      SetString(MainJs, PAnsiChar(AsarMainJs.Contents.Memory), AsarMainJs.Contents.Size)
    else
      MainJs := '';

    if Assigned(AsarPreloadJs) then
      SetString(PreloadJs, PAnsiChar(AsarPreloadJs.Contents.Memory), AsarPreloadJs.Contents.Size)
    else
      PreloadJs := '';

    FCssError := (Css.Length = 0) or (SvgJs.Length = 0);
    FJsError := (MainJs.Length = 0) or (PreloadJs.Length = 0);

    RegEx := TRegExpr.Create;
    RegEx.ModifierI := True;
    RegEx.ModifierM := True;
    try
      for RegExReplace in JsRegExReplacements do
      begin
        StrLen := MainJs.Length;
        RegEx.Expression := RegExReplace.Search;
        MainJs := RegEx.Replace(MainJs, RegExReplace.Replace, True);
        if StrLen = MainJs.Length then
        begin
          FLog.Error('Pattern "%s" could not be found'.Format([RegExReplace.Search]));
          FJsError := True;
          Break;
        end;
      end;
    finally
      RegEx.Free;
    end;

    if not FJsError then
    begin
      PreloadJs := PreloadJsPatch + PreloadJs;

      FileUpdates.Add(AsarMainJs.JSONObject, MainJs);
      FileUpdates.Add(AsarPreloadJs.JSONObject, PreloadJs);
    end;

    ResourcePatchInfos := TList.Create;
    try
      // Sort patches by length so that simple replacements don't render complex replacements invalid if they include the same color
      for ColorSetting in FSettings.ColorSettings do
        if ColorSetting.ColorType <> ctNone then
          if ColorSetting.ClassType = TResourceColorSetting then
            for ResourcePatch in TResourceColorSetting(ColorSetting).Patches do
            begin
              New(ResourcePatchInfo);
              ResourcePatchInfo.Patch := ResourcePatch;
              ResourcePatchInfo.Setting := TResourceColorSetting(ColorSetting);
              ResourcePatchInfos.Add(ResourcePatchInfo);
            end;

      ResourcePatchInfos.Sort(@SortResourcePatchInfos);

      for ResourcePatchInfo in ResourcePatchInfos do
      begin
        if ResourcePatchInfo.Patch.Target = tCss then
          Css := ResourcePatchInfo.Patch.Execute(Css, ResourcePatchInfo.Setting.GetColor(ResourcePatchInfo.Patch.ColorAdjustment), ReplaceCount)
        else if ResourcePatchInfo.Patch.Target = tJs then
          SvgJs := ResourcePatchInfo.Patch.Execute(SvgJs, ResourcePatchInfo.Setting.GetColor(ResourcePatchInfo.Patch.ColorAdjustment), ReplaceCount);

        if ReplaceCount = 0 then
        begin
          FLog.Error('String "%s" (%s) could not be found'.Format([ResourcePatchInfo.Patch.SearchText, ResourcePatchInfo.Setting.Description]));
          FCssError := True;
        end else
          FLog.Debug('Replaced %d occurences of "%s" (%s)'.Format([ReplaceCount, ResourcePatchInfo.Patch.SearchText, ResourcePatchInfo.Setting.Description]));
      end;
    finally
      for ResourcePatchInfo in ResourcePatchInfos do
        Dispose(ResourcePatchInfo);
      ResourcePatchInfos.Free;
    end;

    if FSettings.HideMaximize then
    begin
      Css := Css.Replace('#windows-title-minimize{right:90px}', '#windows-title-minimize{right:45px}', []);
      Css := Css.Replace('#windows-title-maximize{position:absolute;width:45px', '#windows-title-maximize{position:absolute;width:0px', []);
    end;

    for StringReplace in CssStringReplacements do
      Css := Css.Replace(StringReplace.Search, StringReplace.Replace, StringReplace.ReplaceFlags);

    if Css.Length > 0 then
      FileUpdates.Add(AsarCss.JSONObject, Css);
    if SvgJs.Length > 0 then
      FileUpdates.Add(AsarSvgJs.JSONObject, SvgJs);

    FileOffset := Asar.Size - Asar.Header.ContentOffset;
    for FileUpdate in FileUpdates do
    begin
      FileUpdate.Key.Integers['size'] := FileUpdate.Value.Length;
      FileUpdate.Key.Strings['offset'] := IntToStr(FileOffset);

      FResources.Write(FileUpdate.Value[1], FileUpdate.Value.Length);

      FileOffset += FileUpdate.Value.Length;
    end;

    FContentOffset := Asar.Header.ContentOffset;

    Asar.Header.Write(FJSON);
  finally
    FileUpdates.Free;
    Asar.Free;
  end;

  FLog.Info('Patching finished');
end;

end.
