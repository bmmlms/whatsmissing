unit Launcher;

interface

uses
  ActiveX,
  Classes,
  Constants,
  Functions,
  Log,
  MMF,
  Paths,
  ProcessMonitor,
  ResourcePatcher,
  Settings,
  ShlObj,
  SysUtils,
  Windows;

const
  IID_ITaskbarList3: TGUID = '{ea1afb91-9e28-4b86-90e9-9e9f8a5eefaf}';

  WM_START = WM_USER + 1;
  WM_CHECK_RESOURCES_ASYNC = WM_USER + 2;
  WM_CHECK_RESOURCES_ASYNC_PROGRESS = WM_USER + 3;

  WCRAP_FILES_FOUND = 0;
  WCRAP_FINISHED = 1;

type
  TLauncher = class
  private
    FLog: TLog;
    FMMFLauncher: TMMFLauncher;
    FHandle: THandle;
    FTaskbarButtonCreatedMsg: Cardinal;
    FWindowClass: TWndClassW;
    FProcessMonitor: TProcessMonitor;
    FSettings: TSettings;

    class function WndProcWrapper(hwnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; static;
    class procedure ThreadCheckResourcesWrapper(const Parameter: Pointer); stdcall; static;

    function WndProc(uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT;
    procedure WMStart;
    procedure WMCheckResources;

    procedure ProcessMonitorProcessExited(const Sender: TObject; const ExePath: string; const Remaining: Integer);
    procedure ThreadCheckResources;
  public
    constructor Create(const Log: TLog);
    destructor Destroy; override;

    procedure Run;
  end;

implementation

{ TLauncher }

class function TLauncher.WndProcWrapper(hwnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  Result := TLauncher(GetPropW(hwnd, WNDPROC_PROPNAME)).WndProc(uMsg, wParam, lParam);
end;

class procedure TLauncher.ThreadCheckResourcesWrapper(const Parameter: Pointer);
begin
  TLauncher(Parameter).ThreadCheckResources;
end;

constructor TLauncher.Create(const Log: TLog);
begin
  FLog := Log;

  FMMFLauncher := TMMFLauncher.Create;

  FMMFLauncher.WhatsMissingExe32 := ConcatPaths([TPaths.ExeDir, WHATSMISSING_EXENAME_32]);
  FMMFLauncher.WhatsMissingLib32 := ConcatPaths([TPaths.ExeDir, WHATSMISSING_LIBRARYNAME_32]);
  FMMFLauncher.WhatsMissingExe64 := ConcatPaths([TPaths.ExeDir, WHATSMISSING_EXENAME_64]);
  FMMFLauncher.WhatsMissingLib64 := ConcatPaths([TPaths.ExeDir, WHATSMISSING_LIBRARYNAME_64]);

  if (not FileExists(FMMFLauncher.WhatsMissingExe32)) or (not FileExists(FMMFLauncher.WhatsMissingLib32)) then
    raise Exception.Create('Required files not found');

  if TFunctions.IsWindows64Bit and ((not FileExists(FMMFLauncher.WhatsMissingExe64)) or (not FileExists(FMMFLauncher.WhatsMissingLib64))) then
    raise Exception.Create('Required files not found');

  FSettings := TSettings.Create(TPaths.SettingsPath);

  FMMFLauncher.LogFileName := FLog.FileName;
  FMMFLauncher.LauncherPid := GetCurrentProcessId;
  FMMFLauncher.Write;

  FProcessMonitor := TProcessMonitor.Create;
  FProcessMonitor.OnProcessExited := ProcessMonitorProcessExited;
end;

destructor TLauncher.Destroy;
begin
  FMMFLauncher.Free;
  FProcessMonitor.Free;
  FSettings.Free;

  inherited;
end;

procedure TLauncher.Run;
var
  Msg: TMsg;
begin
  FLog.Info('Launcher started');

  FWindowClass.lpfnWndProc := @DefWindowProcW;
  FWindowClass.lpszClassName := WHATSMISSING_CLASSNAME;
  FWindowClass.hInstance := HInstance;

  if RegisterClassW(FWindowClass) = 0 then
    raise Exception.Create('Error registering window class');

  FHandle := CreateWindowExW(WS_EX_APPWINDOW, FWindowClass.lpszClassName, APP_NAME, 0, Integer.MaxValue, Integer.MaxValue, 0, 0, 0, 0, HInstance, nil);
  if FHandle = 0 then
    raise Exception.Create(Format('CreateWindowExW() failed: %d', [GetLastError]));

  SetPropW(FHandle, WNDPROC_PROPNAME, HANDLE(Self));

  SetWindowTextW(FHandle, 'Starting WhatsApp');
  TFunctions.SetPropertyStore(FHandle, TPaths.ExePath, TPaths.WhatsAppExePath);

  FTaskbarButtonCreatedMsg := RegisterWindowMessageW('TaskbarButtonCreated');

  SetLastError(0);
  if (SetWindowLongPtrW(FHandle, GWLP_WNDPROC, LONG_PTR(@WndProcWrapper)) = 0) and (GetLastError <> 0) then
    raise Exception.Create(Format('SetWindowLongPtrW() failed: %d', [GetLastError]));

  PostMessage(FHandle, WM_CHECK_RESOURCES_ASYNC, 0, 0);

  while GetMessageW(Msg, 0, 0, 0) do
  begin
    TranslateMessage(@Msg);
    DispatchMessage(@Msg);
  end;

  FProcessMonitor.Terminate;
  FProcessMonitor.WaitFor;
end;

procedure TLauncher.WMStart;
var
  Res: TStartProcessRes;
begin
  FMMFLauncher.LauncherWindowHandle := FHandle;
  FMMFLauncher.Write;

  Res := TFunctions.StartProcess(TPaths.WhatsAppExePath, '', False, True);
  if not Res.Success then
  begin
    TFunctions.MessageBox(0, 'WhatsApp could not be started.', 'Error', MB_ICONERROR);
    PostQuitMessage(1);
    Exit;
  end;

  FProcessMonitor.Start;

  FProcessMonitor.AddProcessId(Res.ProcessId);

  if not TFunctions.InjectLibrary(FMMFLauncher, Res.ProcessHandle, Res.ThreadHandle) then
  begin
    TerminateProcess(Res.ProcessHandle, 100);

    TFunctions.MessageBox(0, 'Error injecting library.', 'Error', MB_ICONERROR);
    PostQuitMessage(1);
    Exit;
  end else
    ResumeThread(Res.ThreadHandle);

  CloseHandle(Res.ProcessHandle);
  CloseHandle(Res.ThreadHandle);
end;

procedure TLauncher.WMCheckResources;
var
  RP: TResourcePatcher;
begin
  FLog.Info('Checking unpatched resources');

  RP := TResourcePatcher.Create(FSettings);
  try
    try
      RP.RunUnpatched;
    except
      on E: Exception do
        FLog.Error(Format('RunUnpatched() failed: %s', [E.Message]));
    end;
  finally
    RP.Free;
  end;
end;

function TLauncher.WndProc(uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  ThreadId: Cardinal;
  TaskbarList: ITaskbarList3;
  WhatsAppExes: TStringList;
begin
  Result := 0;

  case uMsg of
    WM_CHECK_RESOURCES_ASYNC:
    begin
      CreateThread(nil, 0, @ThreadCheckResourcesWrapper, Self, 0, ThreadId);
      Exit;
    end;
    WM_CHECK_RESOURCES_ASYNC_PROGRESS:
    begin
      if wParam = WCRAP_FILES_FOUND then
        ShowWindow(FHandle, SW_SHOW)
      else if wParam = WCRAP_FINISHED then
      begin
        PostMessage(FHandle, WM_START, 0, 0);
        ShowWindow(FHandle, SW_HIDE);
      end;
      Exit;
    end;
    WM_CHECK_RESOURCES:
    begin
      WMCheckResources;
      Exit;
    end;
    WM_CHECK_LINKS:
    begin
      FLog.Info('Checking shortcuts');
      WhatsAppExes := TStringList.Create;
      try
        TFunctions.FindFiles(TPaths.WhatsAppDir, WHATSAPP_EXE, True, WhatsAppExes);
        TFunctions.ModifyShellLinks(WhatsAppExes.ToStringArray, TFunctions.GetWhatsMissingExePath(FMMFLauncher, TFunctions.IsWindows64Bit));
      finally
        WhatsAppExes.Free;
      end;
      Exit;
    end;
    WM_START:
    begin
      WMStart;
      Exit;
    end;
    WM_CHILD_PROCESS_STARTED:
    begin
      FProcessMonitor.AddProcessId(wParam);
      Exit;
    end;
    WM_MAINWINDOW_CREATED:
    begin
      FMMFLauncher.WhatsAppGuiPid := lParam;
      FMMFLauncher.WhatsAppWindowHandle := wParam;
      FMMFLauncher.Write;
      Exit;
    end;
    WM_NOTIFICATION_ICON:
    begin
      TFunctions.AllowSetForegroundWindow(FMMFLauncher.WhatsAppGuiPid);
      PostMessage(FMMFLauncher.WhatsAppWindowHandle, uMsg, wParam, lParam);
      Exit;
    end;
    WM_NCDESTROY:
    begin
      RemovePropW(FHandle, WNDPROC_PROPNAME);
      TFunctions.ClearPropertyStore(FHandle);
      PostQuitMessage(0);
      Exit;
    end;
    else
      if uMsg = FTaskbarButtonCreatedMsg then
      begin
        if Succeeded(CoCreateInstance(CLSID_TaskbarList, nil, CLSCTX_INPROC_SERVER, IID_ITaskbarList3, TaskbarList)) then
          TaskbarList.SetProgressState(FHandle, TBPF_INDETERMINATE);
        Exit;
      end;
  end;

  Result := DefWindowProc(FHandle, uMsg, wParam, lParam);
end;

procedure TLauncher.ProcessMonitorProcessExited(const Sender: TObject; const ExePath: string; const Remaining: Integer);
begin
  if AnsiLowerCaseFileName(ExtractFileName(ExePath)).Equals(UPDATE_EXE) then
  begin
    FLog.Info('Update process exited, checking shortcuts');
    SendMessage(FHandle, WM_CHECK_LINKS, 0, 0);
  end;

  if Remaining <= 0 then
  begin
    FLog.Info('No child processes remaining, exiting');
    SendMessage(FHandle, WM_CLOSE, 0, 0);
  end;
end;

procedure TLauncher.ThreadCheckResources;
var
  RP: TResourcePatcher;
begin
  FLog.Info('Starting resource patching thread');

  RP := TResourcePatcher.Create(FSettings);
  try
    try
      RP.CleanUp;
    except
      on E: Exception do
        FLog.Error(Format('ThreadCheckResources(): Cleanup failed: %s', [E.Message]));
    end;

    FLog.Info('Cleanup finished, searching for unpatched');

    if FSettings.RebuildResources or RP.ExistsUnpatched then
      SendMessage(FHandle, WM_CHECK_RESOURCES_ASYNC_PROGRESS, WCRAP_FILES_FOUND, 0);

    FLog.Info('Done, now rebuilding');

    try
      if FSettings.RebuildResources then
        RP.RunAll
      else
        RP.RunUnpatched;
    except
      on E: Exception do
        FLog.Error(Format('ThreadCheckResources(): Resource patching failed: %s', [E.Message]));
    end;

    FLog.Info('Done');

    FSettings.RebuildResources := False;
    try
      FSettings.Save;
    except
      on E: Exception do
        FLog.Error(Format('ThreadCheckResources(): Error saving settings: %s', [E.Message]));
    end;
  finally
    RP.Free;
  end;

  SendMessage(FHandle, WM_CHECK_RESOURCES_ASYNC_PROGRESS, WCRAP_FINISHED, 0);
end;

end.
