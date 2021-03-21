library WhatsMissing_Lib;

uses
  Constants,
  Functions,
  Hooks,
  Log,
  MMF,
  Paths,
  SysUtils,
  Window,
  Windows;

{ R *.res}

var
  MMFLauncher: TMMFLauncher;
  Log: TLog;
  Window: TWindow;
  LauncherHandle, LauncherTerminatedWaitHandle: THandle;
  SettingsChangedEvent, SettingsChangedWaitHandle: THandle;

procedure LauncherTerminated(lpParameter: PVOID; TimerOrWaitFired: ByteBool); stdcall;
begin
  if Assigned(Log) then
    Log.Info('Launcher was terminated, exiting');
  ExitProcess(1);
end;

procedure SettingsChanged(lpParameter: PVOID; TimerOrWaitFired: ByteBool); stdcall;
begin
  Log.Info('Reloading settings');

  TFunctions.UnregisterWait(SettingsChangedWaitHandle);

  if Assigned(Window) then
    Window.SettingsChanged(MMFLauncher);
  MMFLauncher.Read;

  while WaitForSingleObject(SettingsChangedEvent, 0) = WAIT_OBJECT_0 do
    Sleep(100);

  TFunctions.RegisterWaitForSingleObject(@SettingsChangedWaitHandle, SettingsChangedEvent, @SettingsChanged, nil, INFINITE, $00000008);
end;

procedure MainWindowCreated(Handle: THandle);
begin
  Window := TWindow.Create(Handle, Log);
end;

procedure ProcessAttach;
var
  ExeName: string;
begin
  try
    TFunctions.Init;
    TPaths.Init;

    ExeName := AnsiLowerCaseFileName(ExtractFileName(TPaths.ExePath));
    if (ExeName <> WHATSAPP_EXE.ToLower) and (ExeName <> UPDATE_EXE.ToLower) then
      Exit;

    try
      MMFLauncher := TMMFLauncher.Create(False);
    except
      Exit;
      {
      on e: exception do
      TFunctions.MessageBox(0, GetCurrentProcessId.ToString, e.Message, 0 );

      Exit;
      end;
      }
    end;
    MMFLauncher.Read;

    LauncherHandle := OpenProcess(SYNCHRONIZE, False, MMFLauncher.LauncherPid);
    if LauncherHandle = 0 then
      raise Exception.Create('Error opening launcher process');

    TFunctions.RegisterWaitForSingleObject(@LauncherTerminatedWaitHandle, LauncherHandle, @LauncherTerminated, nil, INFINITE, $00000008);

    Log := TLog.Create(MMFLauncher.LogFileName);
    Log.Info('Injected into process %d, executable %s'.Format([GetCurrentProcessId, ExtractFileName(TPaths.ExePath)]));

    SendMessage(MMFLauncher.LauncherWindowHandle, WM_CHILD_PROCESS_STARTED, GetCurrentProcessId, 0);

    THooks.Initialize(Log);
    @THooks.OnMainWindowCreated := @MainWindowCreated;

    if ExeName = WHATSAPP_EXE.ToLower then
    begin
      if FileExists(TFunctions.GetResourceFilePath(GetCurrentProcessId)) then
        SendMessage(MMFLauncher.LauncherWindowHandle, WM_PATCH_RESOURCES, GetCurrentProcessId, 0);

      SettingsChangedEvent := TFunctions.OpenEvent(SYNCHRONIZE, False, EVENTNAME_SETTINGS_CHANGED);
      TFunctions.RegisterWaitForSingleObject(@SettingsChangedWaitHandle, SettingsChangedEvent, @SettingsChanged, nil, INFINITE, $00000008);
    end;
  except
    on E: Exception do
    begin
      if not E.Message.EndsWith('.') then
        E.Message := E.Message + '.';

      if Assigned(Log) then
        Log.Error('Library: %s'.Format([E.Message]));

      TFunctions.MessageBox(0, E.Message, '%s error'.Format([APPNAME]), MB_ICONERROR);

      ExitProcess(1);
    end;
  end;
end;

procedure ProcessDetach;
begin
  TFunctions.UnregisterWait(LauncherTerminatedWaitHandle);
  CloseHandle(LauncherHandle);

  TFunctions.UnregisterWait(SettingsChangedWaitHandle);
  CloseHandle(SettingsChangedEvent);

  if Assigned(Window) then
    Window.Free;

  if Assigned(MMFLauncher) then
    MMFLauncher.Free;

  if Assigned(Log) then
    Log.Free;
end;

{$R *.res}

begin
  IsMultiThread := True;

  Dll_Process_Detach_Hook := @ProcessDetach;

  ProcessAttach;
end.

