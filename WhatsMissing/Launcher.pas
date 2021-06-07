unit Launcher;

interface

uses
  ActiveX,
  Classes,
  Constants,
  Functions,
  Generics.Collections,
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
  WM_PATCH_RESOURCES_DONE = WM_USER + 2;

type
  TResourceThreadParameter = record
    Launcher: Pointer;
    PID: Cardinal;
  end;
  PResourceThreadParameter = ^TResourceThreadParameter;

  TResourceThreadResult = record
    CssError: Boolean;
    JsError: Boolean;
    ResFileHash: Integer;
    MMF: TMMFResources;
  end;
  PResourceThreadResult = ^TResourceThreadResult;

  { TLauncher }

  TLauncher = class
  private
    FExiting: Boolean;
    FLog: TLog;
    FMMFLauncher: TMMFLauncher;
    FHandle: THandle;
    FTaskbarButtonCreatedMsg: Cardinal;
    FWindowClass: TWndClassW;
    FProcessMonitor: TProcessMonitor;
    FSettings: TSettings;
    FResources: TDictionary<Integer, TMMFResources>;
    FResourceThreadHandle: THandle;
    FPatchEvent: THandle;
    FSettingsChangedEvent: THandle;
    FSettingsChangedWaitHandle: THandle;
    FLastUsedWhatsAppHash: Integer;

    class procedure SettingsChanged(lpParameter: PVOID; TimerOrWaitFired: ByteBool); stdcall; static;
    class function WndProcWrapper(hwnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; static;
    class procedure ResourceThreadWrapper(const Parameter: PResourceThreadParameter); stdcall; static;

    function WndProc(uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT;
    procedure WMStart;

    procedure ProcessMonitorProcessExited(const Sender: TObject; const ExePath: string; const Remaining: Integer);
    procedure ResourceThread(const PID: Cardinal);
  public
    constructor Create(const Log: TLog);
    destructor Destroy; override;

    procedure Run;
  end;

implementation

{ TLauncher }

class procedure TLauncher.SettingsChanged(lpParameter: PVOID; TimerOrWaitFired: ByteBool); stdcall;
var
  Launcher: TLauncher;
begin
  Launcher := TLauncher(lpParameter);

  TFunctions.UnregisterWait(Launcher.FSettingsChangedWaitHandle);

  Sleep(1000);

  ResetEvent(Launcher.FSettingsChangedEvent);

  TFunctions.RegisterWaitForSingleObject(@Launcher.FSettingsChangedWaitHandle, Launcher.FSettingsChangedEvent, @SettingsChanged, Launcher, INFINITE, $00000008);
end;

class function TLauncher.WndProcWrapper(hwnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  Result := TLauncher(GetWindowLongPtrW(hwnd, GWLP_USERDATA)).WndProc(uMsg, wParam, lParam);
end;

class procedure TLauncher.ResourceThreadWrapper(const Parameter: PResourceThreadParameter); stdcall;
begin
  TLauncher(Parameter^.Launcher).ResourceThread(Parameter^.PID);
  Dispose(Parameter);
end;

constructor TLauncher.Create(const Log: TLog);
begin
  FLog := Log;

  FMMFLauncher := TMMFLauncher.Create(True);
  FSettings := TSettings.Create(TPaths.SettingsPath);
  FResources := TDictionary<Integer, TMMFResources>.Create;

  FMMFLauncher.WhatsMissingExe32 := ConcatPaths([TPaths.ExeDir, WHATSMISSING_EXENAME_32]);
  FMMFLauncher.WhatsMissingLib32 := ConcatPaths([TPaths.ExeDir, WHATSMISSING_LIBRARYNAME_32]);
  FMMFLauncher.WhatsMissingExe64 := ConcatPaths([TPaths.ExeDir, WHATSMISSING_EXENAME_64]);
  FMMFLauncher.WhatsMissingLib64 := ConcatPaths([TPaths.ExeDir, WHATSMISSING_LIBRARYNAME_64]);

  FSettings.CopyToMMF(FMMFLauncher);

  if (not FileExists(FMMFLauncher.WhatsMissingExe32)) or (not FileExists(FMMFLauncher.WhatsMissingLib32)) then
    raise Exception.Create('Required files not found');

  if TFunctions.IsWindows64Bit and ((not FileExists(FMMFLauncher.WhatsMissingExe64)) or (not FileExists(FMMFLauncher.WhatsMissingLib64))) then
    raise Exception.Create('Required files not found');

  FMMFLauncher.LogFileName := FLog.FileName;
  FMMFLauncher.LauncherPid := GetCurrentProcessId;
  FMMFLauncher.Write;

  FProcessMonitor := TProcessMonitor.Create;
  FProcessMonitor.OnProcessExited := ProcessMonitorProcessExited;

  FSettingsChangedEvent := TFunctions.CreateEvent(nil, True, False, EVENTNAME_SETTINGS_CHANGED);
  TFunctions.RegisterWaitForSingleObject(@FSettingsChangedWaitHandle, FSettingsChangedEvent, PVOID(@SettingsChanged), Self, INFINITE, $00000008);
end;

destructor TLauncher.Destroy;
var
  MMFResources: TMMFResources;
begin
  try
    FMMFLauncher.Read;
    FSettings.Load;
    FSettings.LastUsedWhatsAppHash := FLastUsedWhatsAppHash;
    FSettings.AlwaysOnTop := FMMFLauncher.AlwaysOnTop;
    FSettings.Save;
  except
  end;

  TFunctions.UnregisterWait(FSettingsChangedWaitHandle);
  CloseHandle(FSettingsChangedEvent);

  FMMFLauncher.Free;
  FProcessMonitor.Free;
  FSettings.Free;

  for MMFResources in FResources.Values do
    MMFResources.Free;
  FResources.Free;

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

  FHandle := CreateWindowExW(WS_EX_APPWINDOW, FWindowClass.lpszClassName, 'Starting WhatsApp', 0, Integer.MaxValue, Integer.MaxValue, 0, 0, 0, 0, HInstance, nil);
  if FHandle = 0 then
    raise Exception.Create('CreateWindowExW() failed: %d'.Format([GetLastError]));

  SetWindowLongPtrW(FHandle, GWLP_USERDATA, HANDLE(Self));
  if GetLastError <> 0 then
    raise Exception.Create('SetWindowLongPtrW() failed: %d'.Format([GetLastError]));

  SetLastError(0);
  if (SetWindowLongPtrW(FHandle, GWLP_WNDPROC, LONG_PTR(@WndProcWrapper)) = 0) and (GetLastError <> 0) then
    raise Exception.Create('SetWindowLongPtrW() failed: %d'.Format([GetLastError]));

  TFunctions.SetPropertyStore(FHandle, TPaths.ExePath, TPaths.WhatsAppExePath);

  FTaskbarButtonCreatedMsg := RegisterWindowMessageW('TaskbarButtonCreated');

  PostMessage(FHandle, WM_START, 0, 0);

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
    TFunctions.MessageBox(FHandle, 'WhatsApp could not be started.', '%s error'.Format([APPNAME]), MB_ICONERROR);
    PostQuitMessage(1);
    Exit;
  end;

  FProcessMonitor.Start;

  FProcessMonitor.AddProcessId(Res.ProcessId);

  if not TFunctions.InjectLibrary(FMMFLauncher, Res.ProcessHandle, Res.ThreadHandle) then
  begin
    TerminateProcess(Res.ProcessHandle, 100);

    TFunctions.MessageBox(FHandle, 'Error injecting library.', '%s error'.Format([APPNAME]), MB_ICONERROR);
    PostQuitMessage(1);
    Exit;
  end else
    ResumeThread(Res.ThreadHandle);

  CloseHandle(Res.ProcessHandle);
  CloseHandle(Res.ThreadHandle);

  TFunctions.ModifyAutostartEntry(TFunctions.GetWhatsMissingExePath(FMMFLauncher, TFunctions.IsWindows64Bit));

  ShowWindow(FHandle, SW_SHOW);
end;

function TLauncher.WndProc(uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  Dummy: DWORD;
  ResourceFilePath: string;
  TaskbarList: ITaskbarList3;
  WhatsAppExes: TStringList;
  ThreadParameters: PResourceThreadParameter;
  ThreadResult: TResourceThreadResult;
begin
  Result := 0;

  case uMsg of
    WM_PATCH_RESOURCES:
    begin
      ResourceFilePath := AnsiLowerCaseFileName(TFunctions.GetResourceFilePath(wParam));

      if (not FResources.ContainsKey(ResourceFilePath.GetHashCode)) and (FResourceThreadHandle = 0) then
      begin
        FPatchEvent := TFunctions.CreateEvent(nil, True, False, TMMFResources.GetEventName(ResourceFilePath));

        FLastUsedWhatsAppHash := ResourceFilePath.GetHashCode;

        New(ThreadParameters);
        ThreadParameters.Launcher := Self;
        ThreadParameters.PID := wParam;
        FResourceThreadHandle := CreateThread(nil, 0, @ResourceThreadWrapper, ThreadParameters, 0, Dummy);
      end;
    end;
    WM_PATCH_RESOURCES_DONE:
    begin
      CloseHandle(FResourceThreadHandle);
      FResourceThreadHandle := 0;

      SetEvent(FPatchEvent);
      CloseHandle(FPatchEvent);

      ThreadResult := PResourceThreadResult(wParam)^;

      FResources.Add(ThreadResult.ResFileHash, ThreadResult.MMF);

      if not Assigned(ThreadResult.MMF) then
        TFunctions.MessageBox(FHandle, 'Critical error applying patches.', '%s error'.Format([APPNAME]), MB_ICONERROR)
      else if ThreadResult.CssError or ThreadResult.JsError then
        if FSettings.LastUsedWhatsAppHash <> ThreadResult.ResFileHash then
          TFunctions.MessageBox(FHandle, 'Some patches could not be applied, please update %s.'.Format([APPNAME]), '%s error'.Format([APPNAME]), MB_ICONERROR);
    end;
    WM_CHECK_LINKS:
    begin
      WhatsAppExes := TStringList.Create;
      try
        TFunctions.FindFiles(TPaths.WhatsAppDir, WHATSAPP_EXE, True, WhatsAppExes);
        TFunctions.ModifyShellLinks(WhatsAppExes.ToStringArray, TFunctions.GetWhatsMissingExePath(FMMFLauncher, TFunctions.IsWindows64Bit));
      finally
        WhatsAppExes.Free;
      end;
    end;
    WM_START:
      WMStart;
    WM_CHILD_PROCESS_STARTED:
      FProcessMonitor.AddProcessId(wParam);
    WM_MAINWINDOW_CREATED:
    begin
      FMMFLauncher.Read;
      FMMFLauncher.WhatsAppGuiPid := lParam;
      FMMFLauncher.WhatsAppWindowHandle := wParam;
      FMMFLauncher.Write;
    end;
    WM_WINDOW_SHOWN:
      ShowWindow(FHandle, SW_HIDE);
    WM_NOTIFICATION_ICON:
    begin
      TFunctions.AllowSetForegroundWindow(FMMFLauncher.WhatsAppGuiPid);
      PostMessage(FMMFLauncher.WhatsAppWindowHandle, uMsg, wParam, lParam);
    end;
    WM_EXIT:
    begin
      FExiting := True;
      SendMessage(FHandle, WM_CLOSE, 0, 0);
    end;
    WM_CLOSE:
      if FExiting then
        Exit(DefWindowProc(FHandle, uMsg, wParam, lParam));
    WM_NCDESTROY:
    begin
      TFunctions.ClearPropertyStore(FHandle);
      PostQuitMessage(0);
    end;
    else
      if uMsg = FTaskbarButtonCreatedMsg then
      begin
        if Succeeded(CoCreateInstance(CLSID_TaskbarList, nil, CLSCTX_INPROC_SERVER, IID_ITaskbarList3, TaskbarList)) then
          TaskbarList.SetProgressState(FHandle, TBPF_INDETERMINATE);
        Exit;
      end else
        Exit(DefWindowProc(FHandle, uMsg, wParam, lParam));
  end;
end;

procedure TLauncher.ProcessMonitorProcessExited(const Sender: TObject; const ExePath: string; const Remaining: Integer);
begin
  if AnsiLowerCaseFileName(ExtractFileName(ExePath)).Equals(UPDATE_EXE.ToLower) then
  begin
    FLog.Info('Update process exited, checking shortcuts');
    SendMessage(FHandle, WM_CHECK_LINKS, 0, 0);
  end;

  if Remaining <= 0 then
  begin
    FLog.Info('No child processes remaining, exiting');
    SendMessage(FHandle, WM_EXIT, 0, 0);
  end;
end;

procedure TLauncher.ResourceThread(const PID: Cardinal);
var
  ResourceFilePath: string;
  RP: TResourcePatcher;
  MMFResources: TMMFResources;
  Res: TResourceThreadResult;
begin
  ResourceFilePath := TFunctions.GetResourceFilePath(PID);

  Res.ResFileHash := AnsiLowerCaseFileName(ResourceFilePath).GetHashCode;
  Res.MMF := nil;

  RP := nil;
  MMFResources := nil;
  try
    RP := TResourcePatcher.Create(FSettings, FLog);
    try
      RP.ConsumeFile(ResourceFilePath);

      MMFResources := TMMFResources.Create(ResourceFilePath, True, SizeOf(RP.JSON.Size) + RP.JSON.Size + SizeOf(RP.Resources.Size) + RP.Resources.Size + SizeOf(Cardinal));
      MMFResources.Write(RP.JSON, RP.Resources, RP.ContentOffset);

      FMMFLauncher.Read;
      FMMFLauncher.ResourceSettingsChecksum := FSettings.ResourceSettingsChecksum;
      FMMFLauncher.Write;

      Res.CssError := RP.CssError;
      Res.JsError := RP.JsError;
      Res.MMF := MMFResources;
    finally
      RP.Free;
    end;
  except
    on E: Exception do
    begin
      FLog.Error('ThreadPatchResources(): %s'.Format([E.Message]));

      if Assigned(MMFResources) then
        FreeAndNil(MMFResources);
    end;
  end;

  SendMessage(FHandle, WM_PATCH_RESOURCES_DONE, LONG_PTR(@Res), 0);
end;

end.
