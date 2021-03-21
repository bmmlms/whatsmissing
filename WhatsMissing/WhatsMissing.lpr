program WhatsMissing;

uses
  ActiveX,
  Constants,
  FileUtil,
  Forms,
  Functions,
  ImmersiveColors,
  Interfaces,
  Launcher,
  Log,
  MMF,
  Paths,
  Settings,
  SettingsForm,
  SysUtils,
  Windows;

{$R *.res}
{$R resources.rc}

procedure RunInject;
var
  MMFLauncher: TMMFLauncher;
  ProcessHandle, ThreadHandle: THandle;
  ProcessHandleStr, ThreadHandleStr: string;
begin
  if TFunctions.FindCmdLineSwitch(PROCESSHANDLE_ARG, ProcessHandleStr) and TFunctions.FindCmdLineSwitch(THREADHANDLE_ARG, ThreadHandleStr) then
  begin
    ProcessHandle := StrToInt(ProcessHandleStr);
    ThreadHandle := StrToInt(ThreadHandleStr);

    MMFLauncher := TMMFLauncher.Create(False);
    try
      MMFLauncher.Read;

      if not TFunctions.InjectLibrary(MMFLauncher, ProcessHandle, ThreadHandle) then
        raise Exception.Create('Error injecting library')
    finally
      CloseHandle(ProcessHandle);
      CloseHandle(ThreadHandle);

      MMFLauncher.Free;
    end;
  end else
    raise Exception.Create('Invalid command line arguments');
end;

procedure RunSettings;
var
  F: TfrmSettings;
  MMFSettings: TMMFSettings;
begin
  if TMMF.Exists(MMFNAME_SETTINGS) then
  begin
    MMFSettings := TMMFSettings.Create(False);
    try
      MMFSettings.Read;

      SetForegroundWindow(MMFSettings.SettingsWindowHandle);

      Exit;
    finally
      MMFSettings.Free;
    end;
  end;

  Application.Initialize;
  Application.CaptureExceptions := False;
  Application.Title := APPNAME;
  Application.CreateForm(TfrmSettings, F);
  Application.Run;
end;

procedure RunLauncher(const Log: TLog);
var
  MMFLauncher: TMMFLauncher;
  Launcher: TLauncher;
begin
  if TMMF.Exists(MMFNAME_LAUNCHER) then
  begin
    MMFLauncher := TMMFLauncher.Create(False);
    try
      MMFLauncher.Read;

      TFunctions.AllowSetForegroundWindow(MMFLauncher.WhatsAppGuiPid);
      PostMessage(MMFLauncher.WhatsAppWindowHandle, WM_ACTIVATE_INSTANCE, 0, 0);

      Exit;
    finally
      MMFLauncher.Free;
    end;
  end;

  Launcher := TLauncher.Create(Log);
  try
    Launcher.Run;
  finally
    Launcher.Free;
  end;
end;

var
  IsInject, IsSettings, IsPrepareUninstall, IsUninstall, IsLauncher: Boolean;
  StartProcessRes: TStartProcessRes;
  ProcHandle: THandle;
  UninstallerPath, ParentHandleStr: string;
  Log: TLog;
begin
  IsMultiThread := True;

  if FindCmdLineSwitch(INJECT_ARG) then
    IsInject := True
  else if FindCmdLineSwitch(SETTINGS_ARG) then
    IsSettings := True
  else if FindCmdLineSwitch(PREPARE_UNINSTALL_ARG) then
    IsPrepareUninstall := True
  else if FindCmdLineSwitch(UNINSTALL_ARG) then
    IsUninstall := True
  else
    IsLauncher := True;

  try
    TFunctions.Init;
    TPaths.Init;

    if IsInject then
      RunInject;

    if IsPrepareUninstall then
    begin
      UninstallerPath := ConcatPaths([TPaths.TempDir, '%s_uninstall.exe'.Format([APPNAME])]);
      if not FileUtil.CopyFile(TPaths.ExePath, UninstallerPath, False, False) then
        raise Exception.Create('Error copying uninstaller to "%s"'.Format([UninstallerPath]));

      ProcHandle := OpenProcess(SYNCHRONIZE, True, GetCurrentProcessId);
      try
        StartProcessRes := TFunctions.StartProcess(UninstallerPath, '-%s -%s %d'.Format([UNINSTALL_ARG, UNINSTALL_PARENTHANDLE_ARG, ProcHandle]), True, False);
        if not StartProcessRes.Success then
          raise Exception.Create('Error starting uninstaller "%s"'.Format([UninstallerPath]));

        CloseHandle(StartProcessRes.ProcessHandle);
        CloseHandle(StartProcessRes.ThreadHandle);
      finally
        CloseHandle(ProcHandle);
      end;
    end;

    if not Succeeded(CoInitialize(nil)) then
      raise Exception.Create('CoInitialize() failed');

    if IsUninstall then
    begin
      if not TFunctions.FindCmdLineSwitch(UNINSTALL_PARENTHANDLE_ARG, ParentHandleStr) then
        raise Exception.Create('Invalid command line arguments');

      if WaitForSingleObject(StrToInt(ParentHandleStr), 5000) <> WAIT_OBJECT_0 then
        raise Exception.Create('Error waiting for parent to exit');

      TFunctions.RunUninstall(False);
    end;

    if IsLauncher or IsSettings then
    begin
      TFunctions.CheckWhatsAppInstalled;

      TFunctions.SetCurrentProcessExplicitAppUserModelID(WHATSAPP_APP_MODEL_ID);

      if IsLauncher then
      begin
        SysUtils.DeleteFile(ConcatPaths([TPaths.TempDir, LOGFILE]));

        Log := TLog.Create(ConcatPaths([TPaths.TempDir, LOGFILE]));

        RunLauncher(Log);
      end else
        RunSettings;
    end;

    CoUninitialize;
  except
    on E: Exception do
    begin
      if not E.Message.EndsWith('.') then
        E.Message := E.Message + '.';

      if Assigned(Log) then
      begin
        Log.Error('Main: %s'.Format([E.Message]));
        Log.Free;
      end;

      TFunctions.MessageBox(0, E.Message, '%s error'.Format([APPNAME]), MB_ICONERROR);

      ExitProcess(1);
    end;
  end;

  ExitProcess(0);
end.
