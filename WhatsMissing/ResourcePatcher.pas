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
  SysUtils,
  Windows;

type
  TThreadResourcePatchInfo = record
    Setting: TResourceColorSetting;
    Patch: TResourceColorSettingPatch;
    Matches: LongInt;
  end;
  PThreadResourcePatchInfo = ^TThreadResourcePatchInfo;

  { TResourcePatcher }

  TResourcePatcher = class
  private
  type
    TThreadPatchInfo = record
      Search: string;
      Replace: string;
      ReplaceFlags: TReplaceFlags;
      IsRegEx: Boolean;
      Target: TTarget;
      Matches: LongInt;
    end;
    PThreadPatchInfo = ^TThreadPatchInfo;

    TThreadParameter = record
      ResourcePatchInfos: TList;
      PatchInfos: TList<PThreadPatchInfo>;
      Settings: TSettings;
      AsarFile: TASARFile;
      ASARCriticalSection: PCriticalSection;
      Result: AnsiString;
      Modified: Boolean;
      Exception: string;
    end;
    PThreadParameter = ^TThreadParameter;

  var
    FSettings: TSettings;
    FLog: TLog;

    FJSON: TMemoryStream;
    FResources: TMemoryStream;
    FContentOffset: Cardinal;

    FCssError: Boolean;
    FJsError: Boolean;

    class procedure PatchThread(const Parameters: PThreadParameter); stdcall; static;
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

implementation

{ TResourcePatcher }

class procedure TResourcePatcher.PatchThread(const Parameters: PThreadParameter); stdcall;
var
  StrLen: Int64;
  ReplaceCount: LongInt;
  ThreadPatchInfo: PThreadPatchInfo;
  ThreadResourcePatchInfo: PThreadResourcePatchInfo;
  RegEx: TRegExpr;
begin
  try
    EnterCriticalSection(Parameters.ASARCriticalSection);
    try
      SetString(Parameters.Result, PAnsiChar(Parameters.AsarFile.Contents.Memory), Parameters.AsarFile.Contents.Size);
    finally
      LeaveCriticalSection(Parameters.ASARCriticalSection);
    end;

    for ThreadPatchInfo in Parameters.PatchInfos do
    begin
      if ((ThreadPatchInfo.Target = tJs) and (not Parameters.AsarFile.Name.EndsWith('.js', True))) or ((ThreadPatchInfo.Target = tCss) and (not Parameters.AsarFile.Name.EndsWith('.css', True))) then
        Continue;

      if ThreadPatchInfo.IsRegEx then
      begin
        RegEx := TRegExpr.Create;
        RegEx.ModifierI := True;
        RegEx.ModifierM := True;
        try
          StrLen := Parameters.Result.Length;
          RegEx.Expression := ThreadPatchInfo.Search;
          Parameters.Result := RegEx.Replace(Parameters.Result, ThreadPatchInfo.Replace, True);
          if StrLen <> Parameters.Result.Length then
          begin
            Parameters.Modified := True;
            InterLockedIncrement(ThreadPatchInfo.Matches);
          end;
        finally
          RegEx.Free;
        end;
      end else
      begin
        Parameters.Result := StringReplace(Parameters.Result, ThreadPatchInfo.Search, ThreadPatchInfo.Replace, ThreadPatchInfo.ReplaceFlags, ReplaceCount);
        if ReplaceCount > 0 then
        begin
          Parameters.Modified := True;
          InterLockedExchangeAdd(ThreadPatchInfo.Matches, ReplaceCount);
        end;
      end;
    end;

    for ThreadResourcePatchInfo in Parameters.ResourcePatchInfos do
    begin
      if Parameters.AsarFile.Name.EndsWith('.css', True) and (ThreadResourcePatchInfo.Patch.Target = tCss) then
        Parameters.Result := ThreadResourcePatchInfo.Patch.Execute(Parameters.Result, ThreadResourcePatchInfo.Setting.GetColor(ThreadResourcePatchInfo.Patch.ColorAdjustment), ReplaceCount)
      else if Parameters.AsarFile.Name.EndsWith('.js', True) and (ThreadResourcePatchInfo.Patch.Target = tJs) then
        Parameters.Result := ThreadResourcePatchInfo.Patch.Execute(Parameters.Result, ThreadResourcePatchInfo.Setting.GetColor(ThreadResourcePatchInfo.Patch.ColorAdjustment), ReplaceCount)
      else
        ReplaceCount := 0;

      if ReplaceCount > 0 then
      begin
        Parameters.Modified := True;
        InterLockedExchangeAdd(ThreadResourcePatchInfo.Matches, ReplaceCount);
      end;
    end;
  except
    on E: Exception do
    begin
      Parameters.Exception := E.Message;
    end;
  end;
end;

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

function SortResourcePatchInfos(A, B: PThreadResourcePatchInfo): LongInt; register;
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

const
  FPreloadJsPatch: AnsiString = '(function() { var fs = require("fs"); var h = fs.openSync("\\\\.\\wacommunication", "w+"); window.wmcall = function(method, data) ' +
    '{ var b = Buffer.alloc(1024); fs.writeSync(h, JSON.stringify({ method: method, data: data })); fs.readSync(h, b, 0, 1024, 0); return JSON.parse(b.toString()); }; }());';
  FCssStringReplacements: array[0..5] of TStringReplace = (
    (Search: '#windows-title-minimize.blurred{opacity:.7}'; Replace: '#windows-title-minimize.blurred{opacity:1}'; ReplaceFlags: []),
    (Search: '#windows-title-maximize.blurred{opacity:.7}'; Replace: '#windows-title-maximize.blurred{opacity:1}'; ReplaceFlags: []),
    (Search: '#windows-title-close.blurred{opacity:.7}'; Replace: '#windows-title-close.blurred{opacity:1}'; ReplaceFlags: []),
    (Search: '#windows-title-minimize{position:absolute;'; Replace: '#windows-title-minimize{position:absolute;cursor:default;'; ReplaceFlags: []),
    (Search: '#windows-title-maximize{position:absolute;'; Replace: '#windows-title-maximize{position:absolute;cursor:default;'; ReplaceFlags: []),
    (Search: '#windows-title-close{position:absolute;'; Replace: '#windows-title-close{position:absolute;cursor:default;'; ReplaceFlags: []));
  FJsRegExReplacements: array[0..4] of TRegExReplace = (
    (Search: 'return (.)\.apply\(this,arguments\)}}\(\),this\.write='; Replace: 'return $1.apply(this,arguments).then(function (vv) { window.wmcall("socket_in", vv); return vv; }); }}(),this.write='),
    (Search: 'return (.)\.writeNode\((.),(.)\),(.)\.encrypt\((.)\.toBuffer\(\)\)\}\)\)'; Replace: 'if (!window.wmcall("socket_out", $3)) return; return $1.writeNode($2,$3),$4.encrypt($5.toBuffer())}))'),
    (Search: 'var (.)=this\.parseMsg\((.)\[0\],"relay"\);'; Replace: 'var $1=this.parseMsg($2[0],"relay"); window.wmcall("message", {sent: $1.id.fromMe, jid: $1.id.remote});'),
    (Search: '(.)\.MuteCollection\.getGlobalSounds\(\)&&\((.)\.id'; Replace: 'window.wmcall("ask_notification_sound", $2.id) &&$1.MuteCollection.getGlobalSounds()&&($2.id'),
    (Search: 'SEND_UNAVAILABLE_WAIT:15e3,'; Replace: 'SEND_UNAVAILABLE_WAIT:3e3,'));

var
  Asar: TASAR;
  AsarEntry: TASAREntry;
  AsarPreloadJs: TASARFile;
  FileOffset: Integer;
  PreloadJs: AnsiString;
  ColorSetting: TColorSetting;
  ResourcePatch: TResourceColorSettingPatch;
  StringReplace: TStringReplace;
  RegExReplace: TRegExReplace;
  FileUpdate: TPair<TJSONObject, string>;
  FileUpdates: TDictionary<TJSONObject, string>;
  ThreadPatchInfo: PThreadPatchInfo;
  ThreadPatchInfos: TList<PThreadPatchInfo>;
  ThreadResourcePatchInfo: PThreadResourcePatchInfo;
  ThreadResourcePatchInfos: TList;
  Dummy: DWORD;
  ThreadHandles: array of THandle;
  ThreadParameter: PThreadParameter;
  ThreadParameters: TList<PThreadParameter>;
  ASARCriticalSection: TCriticalSection;

  procedure AddThreadPatchInfo(const Search, Replace: string; const ReplaceFlags: TReplaceFlags; const IsRegEx: Boolean; const Target: TTarget);
  begin
    New(ThreadPatchInfo);
    ZeroMemory(ThreadPatchInfo, SizeOf(TThreadPatchInfo));
    ThreadPatchInfo.Search := Search;
    ThreadPatchInfo.Replace := Replace;
    ThreadPatchInfo.ReplaceFlags := ReplaceFlags;
    ThreadPatchInfo.IsRegEx := IsRegEx;
    ThreadPatchInfo.Target := Target;
    ThreadPatchInfos.Add(ThreadPatchInfo);
  end;

begin
  FLog.Info('Processing file "%s"'.Format([FileName]));

  FJSON.Clear;
  FResources.Clear;

  Asar := TASAR.Create;
  FileUpdates := TDictionary<TJSONObject, string>.Create;
  try
    Asar.Read(Filename);

    FCssError := False;
    FJsError := False;

    AsarPreloadJs := TASARFile(Asar.Root.FindEntry('preload.js', TASARFile));
    if Assigned(AsarPreloadJs) then
      SetString(PreloadJs, PAnsiChar(AsarPreloadJs.Contents.Memory), AsarPreloadJs.Contents.Size)
    else
    begin
      FLog.Error('"preload.js" could not be found');
      FJsError := True;
    end;

    ThreadParameters := TList<PThreadParameter>.Create;
    ThreadPatchInfos := TList<PThreadPatchInfo>.Create;
    ThreadResourcePatchInfos := TList.Create;
    try
      // Sort patches by length so that simple replacements don't render complex replacements invalid if they include the same color
      for ColorSetting in FSettings.ColorSettings do
        if ColorSetting.ColorType <> ctNone then
          if ColorSetting.ClassType = TResourceColorSetting then
            for ResourcePatch in TResourceColorSetting(ColorSetting).Patches do
            begin
              New(ThreadResourcePatchInfo);
              ZeroMemory(ThreadResourcePatchInfo, SizeOf(TThreadResourcePatchInfo));
              ThreadResourcePatchInfo.Patch := ResourcePatch;
              ThreadResourcePatchInfo.Setting := TResourceColorSetting(ColorSetting);
              ThreadResourcePatchInfos.Add(ThreadResourcePatchInfo);
            end;

      ThreadResourcePatchInfos.Sort(@SortResourcePatchInfos);

      if FSettings.HideMaximize then
      begin
        AddThreadPatchInfo('#windows-title-minimize{right:90px}', '#windows-title-minimize{right:45px}', [], False, tCss);
        AddThreadPatchInfo('#windows-title-maximize{position:absolute;width:45px', '#windows-title-maximize{position:absolute;width:0px', [], False, tCss);
      end;

      for StringReplace in FCssStringReplacements do
        AddThreadPatchInfo(StringReplace.Search, StringReplace.Replace, StringReplace.ReplaceFlags, False, tCss);

      if not FJsError then
        for RegExReplace in FJsRegExReplacements do
          AddThreadPatchInfo(RegExReplace.Search, RegExReplace.Replace, [], True, tJs);

      InitializeCriticalSection(ASARCriticalSection);
      try
        FLog.Debug('Starting threads');

        ThreadHandles := [];
        for AsarEntry in Asar.Root.Children do
          if (AsarEntry.ClassType = TASARFile) and (AsarEntry <> AsarPreloadJs) and (AsarEntry.Name.EndsWith('.js', True) or AsarEntry.Name.EndsWith('.css', True)) then
          begin
            New(ThreadParameter);
            ZeroMemory(ThreadParameter, SizeOf(TThreadParameter));
            ThreadParameter.AsarFile := TASARFile(AsarEntry);
            ThreadParameter.ResourcePatchInfos := ThreadResourcePatchInfos;
            ThreadParameter.PatchInfos := ThreadPatchInfos;
            ThreadParameter.Settings := FSettings;
            ThreadParameter.ASARCriticalSection := @ASARCriticalSection;
            ThreadParameters.Add(ThreadParameter);

            SetLength(ThreadHandles, Length(ThreadHandles) + 1);
            ThreadHandles[High(ThreadHandles)] := CreateThread(nil, 0, @PatchThread, ThreadParameter, 0, Dummy);
          end;

        WaitForMultipleObjects(Length(ThreadHandles), @ThreadHandles[0], True, INFINITE);

        FLog.Debug('Finished');
      finally
        DeleteCriticalSection(ASARCriticalSection);
      end;

      FLog.Debug('Patch results:');

      for ThreadPatchInfo in ThreadPatchInfos do
        if ThreadPatchInfo.Matches = 0 then
        begin
          FJsError := FJsError or (ThreadPatchInfo.Target = tJs);
          FCssError := FCssError or (ThreadPatchInfo.Target = tCss);
          FLog.Error('  "%s" could not be found'.Format([ThreadPatchInfo.Search]));
        end else
          FLog.Debug('  Replaced %d occurences of "%s"'.Format([ThreadPatchInfo.Matches, ThreadPatchInfo.Search]));

      for ThreadResourcePatchInfo in ThreadResourcePatchInfos do
        if ThreadResourcePatchInfo.Matches = 0 then
        begin
          FLog.Error('  "%s" (%s) could not be found'.Format([ThreadResourcePatchInfo.Patch.SearchText, ThreadResourcePatchInfo.Setting.Description]));
          FCssError := True;
        end else
          FLog.Debug('  Replaced %d occurences of "%s" (%s)'.Format([ThreadResourcePatchInfo.Matches, ThreadResourcePatchInfo.Patch.SearchText, ThreadResourcePatchInfo.Setting.Description]));

      for ThreadParameter in ThreadParameters do
        if ThreadParameter.Exception <> '' then
          FLog.Debug('Thread excepted: %s'.Format([ThreadParameter.Exception]))
        else if ThreadParameter.Modified and (not (FJsError and ThreadParameter.AsarFile.Name.EndsWith('.js', True))) then
        begin
          FLog.Debug('File "%s" was modified'.Format([ThreadParameter.AsarFile.Name]));
          FileUpdates.Add(ThreadParameter.AsarFile.JSONObject, ThreadParameter.Result);
        end;
    finally
      for ThreadResourcePatchInfo in ThreadResourcePatchInfos do
        Dispose(ThreadResourcePatchInfo);
      ThreadResourcePatchInfos.Free;

      for ThreadPatchInfo in ThreadPatchInfos do
        Dispose(ThreadPatchInfo);
      ThreadPatchInfos.Free;

      for ThreadParameter in ThreadParameters do
        Dispose(ThreadParameter);
      ThreadParameters.Free;
    end;

    if not FJsError then
    begin
      PreloadJs := FPreloadJsPatch + PreloadJs;
      FileUpdates.Add(AsarPreloadJs.JSONObject, PreloadJs);
    end;

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
