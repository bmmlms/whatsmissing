program WhatsMissing_Setup;

uses
  ActiveX,
  Classes,
  Constants,
  Functions,
  Paths,
  Registry,
  SysUtils,
  Windows;

{$R *.res}

type
  TFileData = record
    Name: string;
    Start: Cardinal;
    Size: Cardinal;
  end;

  TFileDataArray = array of TFileData;

function ReadArchive(var Files: TFileDataArray; ArchiveStream: TMemoryStream): Boolean;
var
  i: Integer;
  ResStream: TResourceStream;
  OutputSize: UInt32;
  Count, ByteCount: Cardinal;
begin
  Result := False;
  try
    ResStream := TResourceStream.Create(HInstance, 'FILES', RT_RCDATA);
    try
      Count := ResStream.ReadByte;

      SetLength(Files, Count);
      ByteCount := 0;

      for i := 0 to Count - 1 do
      begin
        Files[i].Name := ResStream.ReadAnsiString;
        Files[i].Start := ByteCount;
        Files[i].Size := ResStream.ReadDWord;
        Inc(ByteCount, Files[i].Size);
      end;

      ArchiveStream.CopyFrom(ResStream, ByteCount);

      Result := True;
    finally
      ResStream.Free;
    end;
  except
  end;
end;

function WriteFile(const Files: TFileDataArray; const ArchiveStream: TMemoryStream; const ArchiveFilename, Filename: string): Boolean;
var
  i: Integer;
  FileStream: TFileStream;
begin
  Result := False;

  for i := 0 to High(Files) do
    if Files[i].Name = ArchiveFilename then
    begin
      FileStream := TFileStream.Create(Filename, fmCreate);
      try
        ArchiveStream.Position := Files[i].Start;
        FileStream.CopyFrom(ArchiveStream, Files[i].Size);
      finally
        FileStream.Free;
      end;
      Exit(True);
    end;
end;

procedure CreateUninstallEntry(const Executable: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;

  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WhatsMissing', True) then
      Exit;

    Reg.WriteString('DisplayIcon', Executable);
    Reg.WriteString('DisplayName', APPNAME);
    Reg.WriteString('DisplayVersion', TFunctions.GetFileVersion(TPaths.ExePath));
    Reg.WriteString('InstallDate', FormatDateTime('yyyyMMdd', Now));
    Reg.WriteString('InstallLocation', ExtractFileDir(Executable));
    Reg.WriteInteger('NoModify', 1);
    Reg.WriteInteger('NoRepair', 1);
    Reg.WriteString('UninstallString', '%s -%s'.Format([Executable, PREPARE_UNINSTALL_ARG]));
    Reg.WriteString('Publisher', 'bmmlms');
  finally
    Reg.Free;
  end;
end;

procedure Install;
var
  Res: TStartProcessRes;
  WhatsMissingExecutable: string;
  WhatsAppExes: TStringList;
  Files: TFileDataArray = [];
  ArchiveStream: TMemoryStream;
begin
  if not DirectoryExists(TPaths.WhatsMissingDir) then
    if not CreateDir(TPaths.WhatsMissingDir) then
      raise Exception.Create('Error creating installation directory');

  ArchiveStream := TMemoryStream.Create;
  try
    if not ReadArchive(Files, ArchiveStream) then
      raise Exception.Create('Error extracting files');

    if not WriteFile(Files, ArchiveStream, 'EXE_32', ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_32])) then
      raise Exception.Create('Error installing executable');

    if not WriteFile(Files, ArchiveStream, 'LIB_32', ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_LIBRARYNAME_32])) then
      raise Exception.Create('Error installing library');

    if TFunctions.IsWindows64Bit then
    begin
      WhatsMissingExecutable := ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_64]);

      if not WriteFile(Files, ArchiveStream, 'EXE_64', ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_64])) then
        raise Exception.Create('Error installing executable');

      if not WriteFile(Files, ArchiveStream, 'LIB_64', ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_LIBRARYNAME_64])) then
        raise Exception.Create('Error installing library');
    end else
      WhatsMissingExecutable := ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_32]);
  finally
    ArchiveStream.Free;
  end;

  WhatsAppExes := TStringList.Create;
  try
    TFunctions.FindFiles(TPaths.WhatsAppDir, WHATSAPP_EXE, True, WhatsAppExes);
    TFunctions.ModifyShellLinks(WhatsAppExes.ToStringArray, WhatsMissingExecutable);
  finally
    WhatsAppExes.Free;
  end;

  CreateUninstallEntry(WhatsMissingExecutable);

  if TFunctions.MessageBox(0, 'Installation completed successfully.'#13#10'Do you want to start WhatsApp now?', 'Question', MB_ICONQUESTION or MB_YESNO) = IDYES then
  begin
    Res := TFunctions.StartProcess(WhatsMissingExecutable, '', False, False);
    if not Res.Success then
      MessageBox(0, 'Error starting WhatsApp.', 'Error', MB_ICONERROR);

    CloseHandle(Res.ProcessHandle);
    CloseHandle(Res.ThreadHandle);
  end;
end;

begin
  try
    TPaths.Init;
    TFunctions.Init;

    TFunctions.CheckWhatsAppInstalled;

    if TFunctions.MessageBox(0, 'This will install/update %s.'#13#10'Do you want to continue?'.Format([APPNAME]), 'Question', MB_ICONQUESTION or MB_YESNO) = IDNO then
      Exit;

    if TFunctions.AppsRunning(True) then
    begin
      if TFunctions.MessageBox(0, 'Setup cannot continue since WhatsApp/%s is currently running.'#13#10'Click "Yes" to close WhatsApp/%s, click "No" to cancel.'.Format([APPNAME, APPNAME]),
        'Question', MB_ICONQUESTION or MB_YESNO) = IDNO then
        Exit;

      if not TFunctions.CloseApps(True) then
        raise Exception.Create('WhatsApp/%s could not be closed'.Format([APPNAME]));
    end;

    if not Succeeded(CoInitialize(nil)) then
      raise Exception.Create('CoInitialize() failed');

    try
      try
        Install;
      except
        try
          TFunctions.RunUninstall(True);
        except
        end;
        raise;
      end;
    finally
      CoUninitialize;
    end;

    ExitProcess(0);
  except
    on E: Exception do
    begin
      if not E.Message.EndsWith('.') then
        E.Message := E.Message + '.';

      TFunctions.MessageBox(0, 'Error installing %s: %s'.Format([APPNAME, E.Message]), 'Error', MB_ICONERROR);

      ExitProcess(1);
    end;
  end;
end.
