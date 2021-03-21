program WhatsMissing_Setup;

uses
  ActiveX,
  Classes,
  Constants,
  Functions,
  MMF,
  paszlib,
  Paths,
  Registry,
  SysUtils,
  Windows;

{$R *.res}
{$R resources.rc}

function ExtractStream(InStream: TStream; OutStream: TStream): Integer;
var
  Err: Integer;
  Z: TZStream;
const
  MAX_IN_BUF_SIZE = 4096;
  MAX_OUT_BUF_SIZE = 4096;
var
  InputBuffer: array[0..MAX_IN_BUF_SIZE - 1] of Byte;
  OutputBuffer: array[0..MAX_OUT_BUF_SIZE - 1] of Byte;
  FlushType: LongInt;
begin
  Result := 0;

  FillChar(Z, SizeOf(Z), 0);
  FillChar(InputBuffer, SizeOf(InputBuffer), 0);
  Err := inflateInit(z);

  InStream.Position := 0;
  while InStream.Position < InStream.Size do
  begin
    Z.next_in := @InputBuffer;
    Z.avail_in := InStream.Read(InputBuffer, MAX_IN_BUF_SIZE);

    if InStream.Position = InStream.Size then
      FlushType := Z_FINISH
    else
      FlushType := Z_SYNC_FLUSH;

    repeat
      Z.next_out := @OutputBuffer;
      Z.avail_out := MAX_OUT_BUF_SIZE;

      Err := inflate(Z, FlushType);
      Result += OutStream.Write(OutputBuffer, MAX_OUT_BUF_SIZE - Z.avail_out);
      if Err = Z_STREAM_END then
        Break;
    until Z.avail_out > 0;

    if (Err <> Z_OK) and (Err <> Z_BUF_ERROR) then
      break;
  end;

  Err := inflateEnd(Z);
end;

function ExtractResource(const ResourceName, FilePath: string): Boolean;
var
  ResStream: TResourceStream;
  OutStream: TFileStream;
begin
  Result := False;
  try
    ResStream := TResourceStream.Create(HInstance, ResourceName, RT_RCDATA);
    try
      OutStream := TFileStream.Create(FilePath, fmCreate);
      try
        ExtractStream(ResStream, OutStream);
        Result := True;
      finally
        OutStream.Free;
      end;
    finally
      ResStream.Free;
    end;
  except
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
begin
  if not DirectoryExists(TPaths.WhatsMissingDir) then
    if not CreateDir(TPaths.WhatsMissingDir) then
      raise Exception.Create('Error creating installation directory');

  if not ExtractResource('EXE_32', ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_32])) then
    raise Exception.Create('Error installing executable');

  if not ExtractResource('LIB_32', ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_LIBRARYNAME_32])) then
    raise Exception.Create('Error installing library');

  if TFunctions.IsWindows64Bit then
  begin
    WhatsMissingExecutable := ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_64]);

    if not ExtractResource('EXE_64', ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_64])) then
      raise Exception.Create('Error installing executable');

    if not ExtractResource('LIB_64', ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_LIBRARYNAME_64])) then
      raise Exception.Create('Error installing library');
  end else
    WhatsMissingExecutable := ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_32]);

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
