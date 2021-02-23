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
  LauncherHandle, DetachEvent: THandle;

procedure MainWindowCreated(Handle: THandle);
begin
  Window := TWindow.Create(Handle, MMFLauncher, Log);
end;

procedure WatchLauncher;
var
  Res: Cardinal;
  WaitHandles: TWOHandleArray;
begin
  WaitHandles[0] := LauncherHandle;
  WaitHandles[1] := DetachEvent;
  Res := WaitForMultipleObjects(2, @WaitHandles, False, INFINITE);
  if Res = WAIT_OBJECT_0 then
  begin
    if Assigned(Log) then
      Log.Info('Launcher was terminated, exiting');
    ExitProcess(1);
  end;
end;

procedure ProcessAttach;
var
  WatchThreadId: Cardinal;
  ExeName: string;
begin
  try
    TFunctions.Init;
    TPaths.Init;

    ExeName := AnsiLowerCaseFileName(ExtractFileName(TPaths.ExePath));
    if (ExeName <> WHATSAPP_EXE) and (ExeName <> UPDATE_EXE) then
      Exit;

    MMFLauncher := TMMFLauncher.Create;
    MMFLauncher.Read;

    LauncherHandle := OpenProcess(SYNCHRONIZE, False, MMFLauncher.LauncherPid);
    if LauncherHandle = 0 then
      raise Exception.Create('Error opening launcher process,');

    Log := TLog.Create(MMFLauncher.LogFileName);
    Log.Info(Format('Injected into process %d, executable %s', [GetCurrentProcessId, ExtractFileName(TPaths.ExePath)]));

    SendMessage(MMFLauncher.LauncherWindowHandle, WM_CHILD_PROCESS_STARTED, GetCurrentProcessId, 0);

    THooks.Initialize(MMFLauncher, Log);
    @THooks.OnMainWindowCreated := @MainWindowCreated;

    if ExeName = WHATSAPP_EXE then
    begin
      SendMessage(MMFLauncher.LauncherWindowHandle, WM_CHECK_RESOURCES, 0, 0);

      DetachEvent := CreateEvent(nil, False, False, nil);
      CreateThread(nil, 0, @WatchLauncher, nil, 0, WatchThreadId);
    end;
  except
    on E: Exception do
    begin
      if Assigned(Log) then
        Log.Error(Format('Library: %s', [E.Message]));
      ExitProcess(1);
    end;
  end;
end;

procedure ProcessDetach;
begin
  CloseHandle(LauncherHandle);

  if Assigned(Window) then
    Window.Free;

  if Assigned(MMFLauncher) then
    MMFLauncher.Free;

  if Assigned(Log) then
    Log.Free;

  if DetachEvent > 0 then
    SetEvent(DetachEvent);
end;

{$R *.res}

begin
  IsMultiThread := True;

  Dll_Process_Detach_Hook := @ProcessDetach;

  ProcessAttach;
end.

