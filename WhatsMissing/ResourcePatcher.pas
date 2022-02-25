unit ResourcePatcher;

interface

uses
  ASAR,
  Classes,
  CSSUtil,
  fpjson,
  Functions,
  Generics.Collections,
  Graphics,
  ImmersiveColors,
  Log,
  Paths,
  RegExpr,
  Settings,
  StrUtils,
  SysUtils;

type

  { TMemoryStreamHelper }

  TMemoryStreamHelper = class helper for TMemoryStream
    procedure AssignFrom(const Source: TMemoryStream); overload;
    procedure AssignFrom(const Source: AnsiString); overload;
    function AsString: AnsiString;
  end;

  { TResourcePatcher }

  TResourcePatcher = class
  private
    FSettings: TSettings;
    FLog: TLog;

    FJSON: TMemoryStream;
    FResources: TMemoryStream;
    FContentOffset: Cardinal;
    FDefaultColors: TDictionary<Integer, TColor>;

    FCssError: Boolean;
    FJsError: Boolean;
  public
    constructor Create(const Settings: TSettings; const Log: TLog);
    destructor Destroy; override;

    procedure ConsumeFile(const FileName: string);

    property JSON: TMemoryStream read FJSON;
    property Resources: TMemoryStream read FResources;
    property ContentOffset: Cardinal read FContentOffset;
    property DefaultColors: TDictionary<Integer, TColor> read FDefaultColors;

    property CssError: Boolean read FCssError;
    property JsError: Boolean read FJsError;
  end;

implementation

{ TMemoryStreamHelper }

procedure TMemoryStreamHelper.AssignFrom(const Source: TMemoryStream);
begin
  Clear;
  CopyFrom(Source, 0);
end;

procedure TMemoryStreamHelper.AssignFrom(const Source: AnsiString);
begin
  Clear;
  Write(Source[1], Source.Length);
end;

function TMemoryStreamHelper.AsString: AnsiString;
begin
  SetString(Result, PAnsiChar(Memory), Size);
end;

{ TResourcePatcher }

constructor TResourcePatcher.Create(const Settings: TSettings; const Log: TLog);
begin
  FSettings := Settings;
  FLog := Log;

  FResources := TMemoryStream.Create;
  FJSON := TMemoryStream.Create;
  FDefaultColors := TDictionary<Integer, TColor>.Create;
end;

destructor TResourcePatcher.Destroy;
begin
  FResources.Free;
  FJSON.Free;
  FDefaultColors.Free;

  inherited;
end;

procedure TResourcePatcher.ConsumeFile(const FileName: string);
type
  TRegExReplace = record
    FilePattern: array of string;
    Search: string;
    Replace: string;
  end;

  TFileInfo = record
    AsarFile: TASARFile;
    CssDocument: TCSSDocument;
    Js: AnsiString;
    Modified: Boolean;
  end;
  PFileInfo = ^TFileInfo;

  function NewFileInfo(const AsarFile: TASARFile; const CssDocument: TCSSDocument; const Js: AnsiString): PFileInfo;
  begin
    New(Result);
    Result.AsarFile := AsarFile;
    Result.CssDocument := CssDocument;
    Result.Js := Js;
    Result.Modified := False;
  end;

  function IsAnyWild(Input: string; Wilds: array of string): Boolean;
  var
    S: string;
  begin
    Result := False;

    for S in Wilds do
      if IsWild(Input, S, True) then
        Exit(True);
  end;

const
  PreloadJsPatch: AnsiString = '(function() { var fs = require("fs"); var h = fs.openSync("\\\\.\\wacommunication", "w+"); window.wmcall = function(method, data) ' +
    '{ var b = Buffer.alloc(1024); fs.writeSync(h, JSON.stringify({ method: method, data: data })); fs.readSync(h, b, 0, 1024, 0); return JSON.parse(b.toString()); }; }());';

  SetOpacityOne: array[0..2] of string = ('#windows-title-minimize.blurred', '#windows-title-maximize.blurred', '#windows-title-close.blurred');

  AddCursorDefault: array[0..2] of string = ('#windows-title-minimize', '#windows-title-maximize', '#windows-title-close');

  JsRegExReplacements: array[0..4] of TRegExReplace = (
    (FilePattern: ['bootstrap_main.*.js']; Search: 'return (.)\.apply\(this,arguments\)}}\(\),this\.write='; Replace: 'return $1.apply(this,arguments).then(function (vv) { window.wmcall("socket_in", vv); return vv; }); }}(),this.write='),
    (FilePattern: ['bootstrap_main.*.js']; Search: 'return (.)\.writeNode\((.),(.)\),(.)\.encrypt\((.)\.toBuffer\(\)\)\}\)\)';
    Replace: 'if (!window.wmcall("socket_out", $3)) return; return $1.writeNode($2,$3),$4.encrypt($5.toBuffer())}))'),
    (FilePattern: ['bootstrap_main.*.js']; Search: 'var (.)=this\.parseMsg\((.)\[0\],"relay"\);'; Replace: 'var $1=this.parseMsg($2[0],"relay"); window.wmcall("message", {sent: $1.id.fromMe, jid: $1.id.remote});'),
    (FilePattern: ['bootstrap_main.*.js']; Search: '(.)\.MuteCollection\.getGlobalSounds\(\)&&\((.)\.id'; Replace: 'window.wmcall("ask_notification_sound", $2.id) &&$1.MuteCollection.getGlobalSounds()&&($2.id'),
    (FilePattern: ['index.worker.js', 'main.js', 'renderer.js', 'voip.js']; Search: 'SEND_UNAVAILABLE_WAIT:15e3,'; Replace: 'SEND_UNAVAILABLE_WAIT:3e3,'));

var
  Asar: TASAR;
  AsarEntry: TASAREntry;
  AsarFile: TASARFile;
  FileOffset: Integer;
  ColorSetting: TColorSettingBase;
  ColorSettingResource: TColorSettingResource absolute ColorSetting;
  ResourcePatch: TColorSettingResourcePatch;
  RegExReplace: TRegExReplace;
  CssRule: TCSSRule;
  CssValue: TCSSValue;
  CssDeclaration: TCSSDeclaration;
  FileInfo: PFileInfo;
  StrLen: Integer;
  FileInfos: TList<PFileInfo>;
  ReplaceCount, PatchReplaceCount: Integer;
  OriginalColorHtml, NewColor, Selector: string;
  OriginalColor: TColor;
  Stream: TMemoryStream;
  RegEx: TRegExpr;
  Found: Boolean;
  Wild: string;
  Wilds: TList<string>;
  OriginalClassesToColors: TDictionary<string, string>;
  OriginalColorToColors: TDictionary<string, string>;
begin
  FLog.Info('Processing file "%s"'.Format([FileName]));

  Wilds := TList<string>.Create;
  Wilds.Add('*.css');

  for RegExReplace in JsRegExReplacements do
    for Wild in RegExReplace.FilePattern do
      if not Wilds.Contains(Wild) then
        Wilds.Add(Wild);

  for ColorSetting in FSettings.ColorSettings do
    if (ColorSetting.ClassType = TColorSettingResource) then
      for ResourcePatch in ColorSettingResource.Patches do
        if (ResourcePatch.Options.UpdateInFile <> '') and not Wilds.Contains(ResourcePatch.Options.UpdateInFile) then
          Wilds.Add(ResourcePatch.Options.UpdateInFile);


  FCssError := False;
  FJsError := False;

  FDefaultColors.Clear;
  FJSON.Clear;
  FResources.Clear;

  Asar := TASAR.Create;
  FileInfos := TList<PFileInfo>.Create;
  OriginalClassesToColors := TDictionary<string, string>.Create;
  OriginalColorToColors := TDictionary<string, string>.Create;

  try
    Asar.Read(Filename);

    // Patch preload.js
    AsarFile := TASARFile(Asar.Root.FindEntry('preload.js', TASARFile));
    if Assigned(AsarFile) then
    begin
      FileInfo := NewFileInfo(AsarFile, nil, PreloadJsPatch + AsarFile.Contents.AsString);
      FileInfo.Modified := True;
      FileInfos.Add(FileInfo);
    end else
    begin
      FLog.Error('"preload.js" could not be found');
      FJsError := True;
    end;

    // Collect interesting files
    for AsarEntry in Asar.Root.Children do
      if (AsarEntry.ClassType = TASARFile) and IsAnyWild(AsarEntry.Name, Wilds.ToArray) then
        if AsarEntry.Name.EndsWith('.css') then
          FileInfos.Add(NewFileInfo(TASARFile(AsarEntry), TCSSDocument.Read(TASARFile(AsarEntry).Contents), ''))
        else if AsarEntry.Name.EndsWith('.js') then
          FileInfos.Add(NewFileInfo(TASARFile(AsarEntry), nil, TAsarFile(AsarEntry).Contents.AsString))
        else
          raise Exception.Create('Invalid file type');

    // Replace variables with values and collect some information
    for ColorSetting in FSettings.ColorSettings do
      if (ColorSetting.ClassType = TColorSettingResource) then
        for ResourcePatch in ColorSettingResource.Patches do
        begin
          Found := False;

          for FileInfo in FileInfos do
            if Assigned(FileInfo.CssDocument) then
            begin
              CssValue := FileInfo.CssDocument.FindDeclarationValue(ResourcePatch.SingleSelector, ResourcePatch.DeclarationProp);
              if not Assigned(CssValue) then
                Continue;

              try
                OriginalColorHtml := FileInfo.CssDocument.GetVariableValue(CssValue.Value);
                OriginalColor := TFunctions.HTMLToColor(OriginalColorHtml);
              except
                Continue;
              end;

              NewColor := ResourcePatch.GetColor(ColorSettingResource.GetColor(ResourcePatch.Options.ColorAdjustment, OriginalColor));

              if not OriginalClassesToColors.ContainsKey(ResourcePatch.DeclarationProp) then
                OriginalClassesToColors.Add(ResourcePatch.DeclarationProp, OriginalColorHtml);

              if not OriginalColorToColors.ContainsKey(OriginalColorHtml) then
                OriginalColorToColors.Add(OriginalColorHtml, NewColor);

              if not FDefaultColors.ContainsKey(ColorSettingResource.ID) then
                FDefaultColors.Add(ColorSettingResource.ID, OriginalColor);

              if ColorSettingResource.ColorType = ctrOriginal then
              begin
                Found := True;
                Break;
              end;

              CssValue.Value := NewColor;

              if not Found then
                FLog.Debug('Replacing %s{%s:%s} with %s ("%s")'.Format([ResourcePatch.SingleSelector, ResourcePatch.DeclarationProp, OriginalColorHtml, NewColor, ColorSettingResource.Description]));

              FileInfo.Modified := True;
              Found := True;
            end;
          if not Found then
          begin
            FCssError := True;
            FLog.Error('%s{%s} ("%s") could not be found'.Format([ResourcePatch.SingleSelector, ResourcePatch.DeclarationProp, ColorSetting.Description]));
          end;
        end;

    // Process UpdateAllColors/UpdateInFile using previously collected information
    for ColorSetting in FSettings.ColorSettings do
      if (ColorSetting.ClassType = TColorSettingResource) then
        for ResourcePatch in ColorSettingResource.Patches do
        begin
          if ResourcePatch.Options.UpdateAllColors then
          begin
            PatchReplaceCount := 0;

            for FileInfo in FileInfos do
              if Assigned(FileInfo.CssDocument) then
              begin
                if not OriginalClassesToColors.ContainsKey(ResourcePatch.DeclarationProp) or not OriginalColorToColors.ContainsKey(OriginalClassesToColors[ResourcePatch.DeclarationProp]) then
                  Continue;

                ReplaceCount := FileInfo.CssDocument.SetDeclarationValuesByValue(OriginalClassesToColors[ResourcePatch.DeclarationProp], OriginalColorToColors[OriginalClassesToColors[ResourcePatch.DeclarationProp]]);

                if ReplaceCount > 0 then
                  FileInfo.Modified := True;

                PatchReplaceCount += ReplaceCount;
              end;

            if PatchReplaceCount > 0 then
              FLog.Debug('Replaced %d occurences of "%s" with "%s"'.Format([PatchReplaceCount, OriginalClassesToColors[ResourcePatch.DeclarationProp], OriginalColorToColors[OriginalClassesToColors[ResourcePatch.DeclarationProp]]]))
            else
            begin
              FCssError := True;
              FLog.Error('"%s" could not be found'.Format([OriginalClassesToColors[ResourcePatch.DeclarationProp]]));
            end;
          end;

          if ResourcePatch.Options.UpdateInFile <> '' then
          begin
            PatchReplaceCount := 0;

            for FileInfo in FileInfos do
              if IsWild(FileInfo.AsarFile.Name, ResourcePatch.Options.UpdateInFile, True) and (FileInfo.Js <> '') then
              begin
                FileInfo.Js := StringReplace(FileInfo.Js, OriginalClassesToColors[ResourcePatch.DeclarationProp], OriginalColorToColors[OriginalClassesToColors[ResourcePatch.DeclarationProp]], [rfIgnoreCase], ReplaceCount);
                if ReplaceCount > 0 then
                begin
                  PatchReplaceCount += ReplaceCount;
                  FileInfo.Modified := True;
                end;
              end;

            if PatchReplaceCount > 0 then
              FLog.Debug('Replaced %d occurences of "%s" with "%s"'.Format([PatchReplaceCount, OriginalClassesToColors[ResourcePatch.DeclarationProp], OriginalColorToColors[OriginalClassesToColors[ResourcePatch.DeclarationProp]]]))
            else
            begin
              FCssError := True;
              FLog.Error('"%s" could not be found'.Format([OriginalClassesToColors[ResourcePatch.DeclarationProp]]));
            end;
          end;
        end;

    // Perform non-color modifications from settings
    for FileInfo in FileInfos do
      if Assigned(FileInfo.CssDocument) then
      begin
        if FSettings.RemoveRoundedElementCorners then
          for CssRule in FileInfo.CssDocument.Rules do
          begin
            CssDeclaration := CssRule.FindDeclarationByProp('border-radius');
            if not Assigned(CssDeclaration) or CssDeclaration.Value.Value.EndsWith('%') then
              Continue;

            CssRule.Declarations.Remove(CssDeclaration);
            CssDeclaration.Free;

            FileInfo.Modified := True;
          end;

        if FSettings.UseSquaredProfileImages then
        begin
          CssRule := TCSSRule.Create;
          CssRule.Selectors.Add(TCSSValue.Create('.message-out img'));
          CssRule.Selectors.Add(TCSSValue.Create('.message-in img'));
          CssRule.Selectors.Add(TCSSValue.Create('#side img'));
          CssRule.Selectors.Add(TCSSValue.Create('.two #main img'));
          CssRule.Declarations.Add(TCSSDeclaration.Create('border-radius', '0!important'));
          FileInfo.CssDocument.Rules.Add(CssRule);
        end;

        if FSettings.UseRegularTitleBar then
        begin
          CssRule := FileInfo.CssDocument.FindRule('html[dir] #windows-title-bar');
          if Assigned(CssRule) then
          begin
            CssRule.Declarations.Add(TCSSDeclaration.Create('display', 'none'));

            FileInfo.Modified := True;
          end;

          CssRule := FileInfo.CssDocument.FindRule('#app.windows-native-app');
          if Assigned(CssRule) then
          begin
            CssDeclaration := CssRule.FindDeclarationByProp('top');
            CssRule.Declarations.Remove(CssDeclaration);
            CssDeclaration.Free;

            CssDeclaration := CssRule.FindDeclarationByProp('height');
            CssRule.Declarations.Remove(CssDeclaration);
            CssDeclaration.Free;

            FileInfo.Modified := True;
          end;
        end else
        begin
          if FSettings.HideMaximize then
          begin
            CssRule := FileInfo.CssDocument.FindRule('html[dir=ltr] #windows-title-minimize');
            if Assigned(CssRule) then
            begin
              CssRule.FindDeclarationByProp('right').Value.Value := '45px';
              FileInfo.Modified := True;
            end;

            CssRule := FileInfo.CssDocument.FindRule('#windows-title-maximize');
            if Assigned(CssRule) then
            begin
              CssRule.FindDeclarationByProp('width').Value.Value := '0px';
              FileInfo.Modified := True;
            end;
          end;

          for Selector in SetOpacityOne do
          begin
            CssRule := FileInfo.CssDocument.FindRule(Selector);
            if Assigned(CssRule) then
            begin
              CssRule.FindDeclarationByProp('opacity').Value.Value := '1';
              FileInfo.Modified := True;
            end;
          end;

          for Selector in AddCursorDefault do
          begin
            CssRule := FileInfo.CssDocument.FindRule(Selector);
            if Assigned(CssRule) then
            begin
              CssRule.Declarations.Add(TCSSDeclaration.Create('cursor', 'default'));
              FileInfo.Modified := True;
            end;
          end;
        end;
      end;

    // Patch JavaScript
    if not FJsError then
      for RegExReplace in JsRegExReplacements do
      begin
        PatchReplaceCount := 0;

        for FileInfo in FileInfos do
          if IsAnyWild(FileInfo.AsarFile.Name, RegExReplace.FilePattern) and (FileInfo.Js <> '') then
          begin
            RegEx := TRegExpr.Create;
            RegEx.ModifierI := True;
            RegEx.ModifierM := True;
            RegEx.Expression := RegExReplace.Search;
            try
              StrLen := FileInfo.Js.Length;
              FileInfo.Js := RegEx.Replace(FileInfo.Js, RegExReplace.Replace, True);

              if FileInfo.Js.Length <> StrLen then
              begin
                FileInfo.Modified := True;
                Inc(PatchReplaceCount);
              end;
            finally
              RegEx.Free;
            end;
          end;

        if PatchReplaceCount > 0 then
          FLog.Debug('Replaced %d occurences of "%s"'.Format([PatchReplaceCount, RegExReplace.Search]))
        else
        begin
          FJsError := True;
          FLog.Error('"%s" could not be found'.Format([RegExReplace.Search]));
        end;
      end;


    FileOffset := Asar.Size - Asar.Header.ContentOffset;

    for FileInfo in FileInfos do
      if FileInfo.Modified then
      begin
        if Assigned(FileInfo.CssDocument) then
        begin
          Stream := TMemoryStream.Create;
          try
            FileInfo.CssDocument.Write(Stream);
            FileInfo.AsarFile.Contents.AssignFrom(Stream);
          finally
            Stream.Free;
          end;
        end else
          FileInfo.AsarFile.Contents.AssignFrom(FileInfo.Js);

        FileInfo.AsarFile.JSONObject.Integers['size'] := FileInfo.AsarFile.Size;
        FileInfo.AsarFile.JSONObject.Strings['offset'] := IntToStr(FileOffset);

        FResources.CopyFrom(FileInfo.AsarFile.Contents, 0);

        FileOffset += FileInfo.AsarFile.Size;

        FLog.Debug('Modified "%s"'.Format([FileInfo.AsarFile.Name]));
      end;

    FContentOffset := Asar.Header.ContentOffset;

    Asar.Header.Write(FJSON);
  finally
    Asar.Free;

    Wilds.Free;
    OriginalClassesToColors.Free;
    OriginalColorToColors.Free;

    for FileInfo in FileInfos do
    begin
      if Assigned(FileInfo.CssDocument) then
        FileInfo.CssDocument.Free;
      Dispose(FileInfo);
    end;
    FileInfos.Free;
  end;

  FLog.Info('Patching finished');
end;

end.
