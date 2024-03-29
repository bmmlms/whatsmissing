unit Functions;

interface

uses
  ActiveX,
  Classes,
  Constants,
  MMF,
  Paths,
  Registry,
  ShlObj,
  StrUtils,
  SysUtils,
  Windows;

type
  TColor = -$7FFFFFFF-1..$7FFFFFFF;

  TCardinalArray = array of Cardinal;

  TStartProcessRes = record
    ProcessHandle: THandle;
    ThreadHandle: THandle;
    ProcessId: Cardinal;
    Success: Boolean;
  end;

  TWindowProcessRes = record
    PIDs: TCardinalArray;
    WindowHandle: THandle;
    Success: Boolean;
  end;

  TEnumProcesses = function(lpidProcess: LPDWORD; cb: DWORD; var cbNeeded: DWORD): BOOL; stdcall;
  TAllowSetForegroundWindow = function(dwProcessId: DWORD): BOOL; stdcall;
  TSetCurrentProcessExplicitAppUserModelID = function(AppID: PCWSTR): HRESULT;
  TQueryFullProcessImageNameW = function(hProcess: THandle; dwFlags: DWORD; lpImageFileName: LPWSTR; nSize: PDWORD): DWORD; stdcall;
  TIsWow64Process2 = function(hProcess: THandle; pProcessMachine: PUSHORT; pNativeMachine: PUSHORT): BOOL; stdcall;
  TQueueUserAPC = function(pfnAPC: Pointer; hThread: HANDLE; dwData: ULONG_PTR): DWORD; stdcall;
  TSHGetPropertyStoreForWindow = function(hwnd: HWND; const riid: REFIID; var ppv: Pointer): HRESULT; stdcall;
  TRegisterWaitForSingleObject = function(phNewWaitObject: PHANDLE; hObject: HANDLE; Callback: PVOID; Context: PVOID; dwMilliseconds, dwFlags: ULONG): BOOL; stdcall;
  TUnregisterWait = function(WaitHandle: HANDLE): BOOL; stdcall;

  { TFunctions }

  TFunctions = class
  private
    class var
    FEnumProcesses: TEnumProcesses;
    FAllowSetForegroundWindow: TAllowSetForegroundWindow;
    FSetCurrentProcessExplicitAppUserModelID: TSetCurrentProcessExplicitAppUserModelID;
    FQueryFullProcessImageNameW: TQueryFullProcessImageNameW;
    FIsWow64Process2: TIsWow64Process2;
    FQueueUserAPC: TQueueUserAPC;
    FSHGetPropertyStoreForWindow: TSHGetPropertyStoreForWindow;
    FRegisterWaitForSingleObject: TRegisterWaitForSingleObject;
    FUnregisterWait: TUnregisterWait;
  public
    class procedure Init; static;

    // Wrappers for windows functions
    class function MessageBox(hWnd: HWND; Text: string; Caption: string; uType: UINT): LongInt; static;
    class function CreateFile(FileName: string; dwDesiredAccess: DWORD; dwShareMode: DWORD; lpSecurityAttributes: LPSECURITY_ATTRIBUTES; dwCreationDisposition: DWORD; dwFlagsAndAttributes: DWORD; hTemplateFile: HANDLE): HANDLE; static;
    class function CreateEvent(lpEventAttributes: LPSECURITY_ATTRIBUTES; bManualReset: WINBOOL; bInitialState: WINBOOL; Name: string): HANDLE;
    class function OpenEvent(dwDesiredAccess: DWORD; bInheritHandle: WINBOOL; Name: string): HANDLE;
    class function TryOpenEvent(dwDesiredAccess: DWORD; bInheritHandle: WINBOOL; Name: string): HANDLE;
    class function CreateMutex(lpMutexAttributes: LPSECURITY_ATTRIBUTES; bInitialOwner: WINBOOL; Name: string): HANDLE;
    class function CreateFileMapping(hFile: HANDLE; lpFileMappingAttributes: LPSECURITY_ATTRIBUTES; flProtect: DWORD; dwMaximumSizeHigh: DWORD; dwMaximumSizeLow: DWORD; Name: string): HANDLE;
    class function OpenFileMapping(dwDesiredAccess: DWORD; bInheritHandle: WINBOOL; Name: string): HANDLE;

    class function GetSpecialFolder(const csidl: ShortInt): string; static;
    class function GetTempPath: string; static;
    class function HTMLToColor(const Color: string): TColor; static;
    class function ColorToHTML(const Color: TColor): string; static;
    class function ColorToRGBHTML(const Color: TColor): string; static;
    class function GetResourceFilePath(const PID: Cardinal): string; static;
    class function InjectLibrary(const MMFLauncher: TMMFLauncher; const ProcessHandle, ThreadHandle: THandle): Boolean; static;
    class function SetPropertyStore(const Handle: THandle; const ExePath, IconPath: string): Boolean; static;
    class function ClearPropertyStore(const Handle: THandle): Boolean; static;
    class function GetPidExePath(PID: Cardinal): string; static;
    class function GetExePath(ProcessHandle: THandle): string; static;
    class function IsWindows64Bit: Boolean; static;
    class function IsProcess64Bit(const Handle: THandle): Boolean; static;
    class function GetWhatsMissingExePath(const MMFLauncher: TMMFLauncher; const X64: Boolean): string; static;
    class function GetWhatsMissingLibPath(const MMFLauncher: TMMFLauncher; const X64: Boolean): string; static;
    class function StartProcess(const ExePath: string; Args: string; const InheritHandles, Suspended: Boolean): TStartProcessRes; static;
    class function FindCmdLineSwitch(const Name: string; var Value: string): Boolean; static; overload;
    class function FindCmdLineSwitch(const Name: string): Boolean; static; overload;
    class property RegisterWaitForSingleObject: TRegisterWaitForSingleObject read FRegisterWaitForSingleObject;
    class property UnregisterWait: TUnregisterWait read FUnregisterWait;

    // Functions only used by Launcher/Setup
    class procedure CheckWhatsAppInstalled; static;
    class function GetRunningExePids(const FilePath: string): TCardinalArray; static;
    class function GetRunningWhatsApp: TWindowProcessRes; static;
    class function AppsRunning(const ConsiderSettings: Boolean): Boolean; static;
    class function CloseApps(const ConsiderSettings: Boolean): Boolean; static;
    class procedure FindFiles(const Dir, Pattern: string; const Recurse: Boolean; const FileList: TStringList); static;
    class function GetShellLinkPath(const LinkFile: string): string; static;
    class procedure ModifyShellLink(const LinkFile: string; const ExecutablePath: string); static;
    class procedure ModifyShellLinks(const FromCurrentPaths: array of string; const NewPath: string); static;
    class procedure RunUninstall(const Quiet: Boolean); static;
    class procedure ModifyAutostartEntry(const Value: string); static;
    class function GetWhatsAppAutostartCommand: string; static;
    class function GetFileVersion(const FileName: string): string; static;

    class procedure SetCurrentProcessExplicitAppUserModelID(AppID: string); static;

    class property AllowSetForegroundWindow: TAllowSetForegroundWindow read FAllowSetForegroundWindow;
  end;

implementation

const
  IID_IPropertyStore: TGUID = '{886d8eeb-8cf2-4446-8d02-cdba1dbdcf99}';

  PKEY_AppUserModel_RelaunchCommand: PROPERTYKEY = (fmtid: '{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}'; pid: 2);
  PKEY_AppUserModel_RelaunchDisplayNameResource: PROPERTYKEY = (fmtid: '{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}'; pid: 4);
  PKEY_AppUserModel_RelaunchIconResource: PROPERTYKEY = (fmtid: '{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}'; pid: 3);
  PKEY_AppUserModel_ID: PROPERTYKEY = (fmtid: '{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}'; pid: 5);

class procedure TFunctions.Init;
var
  ModuleHandle: HMODULE;
begin
  FEnumProcesses := GetProcAddress(GetModuleHandle('kernelbase.dll'), 'EnumProcesses');
  FQueryFullProcessImageNameW := GetProcAddress(GetModuleHandle('kernelbase.dll'), 'QueryFullProcessImageNameW');
  FIsWow64Process2 := GetProcAddress(GetModuleHandle('kernelbase.dll'), 'IsWow64Process2');
  FQueueUserAPC := GetProcAddress(GetModuleHandle('kernelbase.dll'), 'QueueUserAPC');
  FAllowSetForegroundWindow := GetProcAddress(GetModuleHandle('user32.dll'), 'AllowSetForegroundWindow');
  FRegisterWaitForSingleObject := GetProcAddress(GetModuleHandle('kernel32.dll'), 'RegisterWaitForSingleObject');
  FUnregisterWait := GetProcAddress(GetModuleHandle('kernel32.dll'), 'UnregisterWait');

  ModuleHandle := LoadLibraryA('shell32.dll');
  FSetCurrentProcessExplicitAppUserModelID := GetProcAddress(ModuleHandle, 'SetCurrentProcessExplicitAppUserModelID');
  FSHGetPropertyStoreForWindow := GetProcAddress(ModuleHandle, 'SHGetPropertyStoreForWindow');

  if (not Assigned(FEnumProcesses)) or (not Assigned(FQueryFullProcessImageNameW)) or (not Assigned(FIsWow64Process2)) or (not Assigned(FQueueUserAPC)) or (not Assigned(FAllowSetForegroundWindow)) or
    (not Assigned(FSetCurrentProcessExplicitAppUserModelID)) or (not Assigned(FSHGetPropertyStoreForWindow)) or (not Assigned(FRegisterWaitForSingleObject)) or (not Assigned(FUnregisterWait)) then
    raise Exception.Create('A required function could not be found, your windows version is most likely unsupported.');
end;

class function TFunctions.MessageBox(hWnd: HWND; Text: string; Caption: string; uType: UINT): LongInt;
begin
  Result := MessageBoxW(hWnd, PWideChar(UnicodeString(Text)), PWideChar(UnicodeString(Caption)), uType);
end;

class function TFunctions.CreateFile(FileName: string; dwDesiredAccess: DWORD; dwShareMode: DWORD; lpSecurityAttributes: LPSECURITY_ATTRIBUTES; dwCreationDisposition: DWORD; dwFlagsAndAttributes: DWORD; hTemplateFile: HANDLE): HANDLE;
begin
  Result := CreateFileW(PWideChar(UnicodeString(FileName)), dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
  if Result = INVALID_HANDLE_VALUE then
    raise Exception.Create('CreateFileW() failed: %d'.Format([GetLastError]));
end;

class function TFunctions.CreateEvent(lpEventAttributes: LPSECURITY_ATTRIBUTES; bManualReset: WINBOOL; bInitialState: WINBOOL; Name: string): HANDLE;
begin
  Result := CreateEventW(lpEventAttributes, bManualReset, bInitialState, IfThen<PWideChar>(Name = '', nil, PWideChar(UnicodeString(Name))));
  if Result = 0 then
    raise Exception.Create('CreateEventW() failed: %d'.Format([GetLastError]));
end;

class function TFunctions.OpenEvent(dwDesiredAccess: DWORD; bInheritHandle: WINBOOL; Name: string): HANDLE;
begin
  Result := TryOpenEvent(dwDesiredAccess, bInheritHandle, Name);
  if Result = 0 then
    raise Exception.Create('OpenEventW() failed: %d'.Format([GetLastError]));
end;

class function TFunctions.TryOpenEvent(dwDesiredAccess: DWORD; bInheritHandle: WINBOOL; Name: string): HANDLE;
begin
  Result := OpenEventW(dwDesiredAccess, bInheritHandle, PWideChar(UnicodeString(Name)));
end;

class function TFunctions.CreateMutex(lpMutexAttributes: LPSECURITY_ATTRIBUTES; bInitialOwner: WINBOOL; Name: string): HANDLE;
begin
  Result := CreateMutexW(lpMutexAttributes, bInitialOwner, PWideChar(UnicodeString(Name)));
  if Result = 0 then
    raise Exception.Create('CreateMutexW() failed: %d'.Format([GetLastError]));
end;

class function TFunctions.CreateFileMapping(hFile: HANDLE; lpFileMappingAttributes: LPSECURITY_ATTRIBUTES; flProtect: DWORD; dwMaximumSizeHigh: DWORD; dwMaximumSizeLow: DWORD; Name: string): HANDLE;
begin
  Result := CreateFileMappingW(hFile, lpFileMappingAttributes, flProtect, dwMaximumSizeHigh, dwMaximumSizeLow, IfThen<PWideChar>(Name = '', nil, PWideChar(UnicodeString(Name))));
  if Result = 0 then
    raise Exception.Create('CreateFileMappingW() failed: %d'.Format([GetLastError]));
end;

class function TFunctions.OpenFileMapping(dwDesiredAccess: DWORD; bInheritHandle: WINBOOL; Name: string): HANDLE;
begin
  Result := OpenFileMappingW(dwDesiredAccess, bInheritHandle, IfThen<PWideChar>(Name = '', nil, PWideChar(UnicodeString(Name))));
  if Result = 0 then
    raise Exception.Create(('OpenFileMappingW() failed: %d').Format([GetLastError]));
end;

class function TFunctions.GetSpecialFolder(const csidl: ShortInt): string;
var
  Buf: UnicodeString = '';
begin
  SetLength(Buf, 1024);
  if Failed(SHGetFolderPathW(0, csidl, 0, SHGFP_TYPE_CURRENT, PWideChar(Buf))) then
    raise Exception.Create('SHGetFolderPathW() failed');
  Result := PWideChar(Buf);
end;

class function TFunctions.GetTempPath: string;
var
  Buf: UnicodeString = '';
begin
  SetLength(Buf, MAX_PATH + 1);
  SetLength(Buf, GetTempPathW(Length(Buf), PWideChar(Buf)));
  Result := PWideChar(Buf);
end;

class function TFunctions.HTMLToColor(const Color: string): TColor;
var
  R, G, B: Byte;
  Arr: TStringArray;
begin
  if Color[1] = '#' then
  begin
    if Color.Length = 4 then
    begin
      R := StrToInt('$' + Color[2] + Color[2]);
      G := StrToInt('$' + Color[3] + Color[3]);
      B := StrToInt('$' + Color[4] + Color[4]);
      Exit(RGB(R, G, B));
    end
    else if Color.Length = 7 then
    begin
      R := StrToInt('$' + Copy(Color, 2, 2));
      G := StrToInt('$' + Copy(Color, 4, 2));
      B := StrToInt('$' + Copy(Color, 6, 2));
      Exit(RGB(R, G, B));
    end;
  end else
  begin
    Arr := Color.Split([',']);
    if Length(Arr) = 3 then
    begin
      R := StrToIntDef(Arr[0], 0);
      G := StrToIntDef(Arr[1], 0);
      B := StrToIntDef(Arr[2], 0);
      Exit(RGB(R, G, B));
    end;
  end;

  raise Exception.Create('Invalid color');
end;

class function TFunctions.ColorToHTML(const Color: TColor): string;
begin
  Result := '#%.2x%.2x%.2x'.Format([GetRValue(Color), GetGValue(Color), GetBValue(Color)]);
end;

class function TFunctions.ColorToRGBHTML(const Color: TColor): string;
begin
  Result := IntToStr(Color and $FF) + ',' + IntToStr((Color shr 8) and $FF) + ',' + IntToStr((Color shr 16) and $FF);
end;

class function TFunctions.GetResourceFilePath(const PID: Cardinal): string;
begin
  Result := ConcatPaths([ExtractFileDir(TFunctions.GetPidExePath(PID)), 'resources\app.asar']);
  if Result.StartsWith('\\?\', True) then
    Result := Result.Substring(4);
end;

class function TFunctions.InjectLibrary(const MMFLauncher: TMMFLauncher; const ProcessHandle, ThreadHandle: THandle): Boolean;
var
  MemSize: Cardinal;
  LL, TargetMemory: Pointer;
  InjectorPath: string;
  LibraryPath: UnicodeString;
  ExitCode: DWORD = 0;
  Written: DWORD = 0;
  Res: TStartProcessRes;
begin
  Result := False;

  InjectorPath := GetWhatsMissingExePath(MMFLauncher, IsProcess64Bit(ProcessHandle));
  LibraryPath := GetWhatsMissingLibPath(MMFLauncher, IsProcess64Bit(ProcessHandle));

  if IsProcess64Bit(GetCurrentProcess) <> IsProcess64Bit(ProcessHandle) then
  begin
    SetHandleInformation(ProcessHandle, HANDLE_FLAG_INHERIT, 1);
    SetHandleInformation(ThreadHandle, HANDLE_FLAG_INHERIT, 1);

    Res := StartProcess(InjectorPath, '-%s -%s %d -%s %d'.Format([INJECT_ARG, PROCESSHANDLE_ARG, ProcessHandle, THREADHANDLE_ARG, ThreadHandle]), True, False);
    if not Res.Success then
      Exit;

    WaitForSingleObject(Res.ProcessHandle, INFINITE);
    if not GetExitCodeProcess(Res.ProcessHandle, ExitCode) then
      Exit;

    CloseHandle(Res.ProcessHandle);
    CloseHandle(Res.ThreadHandle);

    Result := ExitCode = 0;
  end else
  begin
    MemSize := Length(LibraryPath) * 2 + 2;
    TargetMemory := VirtualAllocEx(ProcessHandle, nil, MemSize, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
    LL := GetProcAddress(GetModuleHandle('kernel32.dll'), 'LoadLibraryW');
    if Assigned(LL) and Assigned(TargetMemory) then
      if WriteProcessMemory(ProcessHandle, TargetMemory, PWideChar(LibraryPath), MemSize, @Written) and (Written = MemSize) then
        Result := FQueueUserAPC(LL, ThreadHandle, UIntPtr(TargetMemory)) <> 0;
  end;
end;

class function TFunctions.SetPropertyStore(const Handle: THandle; const ExePath, IconPath: string): Boolean;
var
  Res: HRESULT;
  PS: IPropertyStore;
  P: Pointer = nil;
  Variant: TPropVariant;
begin
  Result := True;

  Res := FSHGetPropertyStoreForWindow(Handle, IID_IPropertyStore, P);
  if Failed(Res) then
    Exit(False);

  PS := IPropertyStore(P);
  Variant.vt := VT_BSTR;

  Variant.bstrVal := SysAllocString(PWideChar(UnicodeString(ExePath)));
  if Failed(PS.SetValue(@PKEY_AppUserModel_RelaunchCommand, @Variant)) then
    Result := False;
  SysFreeString(Variant.pbstrVal);

  Variant.bstrVal := SysAllocString(PWideChar('WhatsApp'));
  if Failed(PS.SetValue(@PKEY_AppUserModel_RelaunchDisplayNameResource, @Variant)) then
    Result := False;
  SysFreeString(Variant.pbstrVal);

  Variant.bstrVal := SysAllocString(PWideChar(UnicodeString(IconPath)));
  if Failed(PS.SetValue(@PKEY_AppUserModel_RelaunchIconResource, @Variant)) then
    Result := False;
  SysFreeString(Variant.pbstrVal);

  Variant.bstrVal := SysAllocString(PWideChar(UnicodeString(WHATSAPP_APP_MODEL_ID)));
  if Failed(PS.SetValue(@PKEY_AppUserModel_ID, @Variant)) then
    Result := False;
  SysFreeString(Variant.pbstrVal);

  if Failed(PS.Commit) then
    Result := False;
end;

class function TFunctions.ClearPropertyStore(const Handle: THandle): Boolean;
var
  Res: HRESULT;
  PS: IPropertyStore;
  P: Pointer = nil;
  Variant: TPropVariant;
begin
  Result := True;

  Res := FSHGetPropertyStoreForWindow(Handle, IID_IPropertyStore, P);
  if Failed(Res) then
    Exit(False);

  PS := IPropertyStore(P);
  Variant.vt := VT_EMPTY;

  if Failed(PS.SetValue(@PKEY_AppUserModel_RelaunchCommand, @Variant)) then
    Result := False;

  if Failed(PS.SetValue(@PKEY_AppUserModel_RelaunchDisplayNameResource, @Variant)) then
    Result := False;

  if Failed(PS.SetValue(@PKEY_AppUserModel_RelaunchIconResource, @Variant)) then
    Result := False;

  if Failed(PS.SetValue(@PKEY_AppUserModel_ID, @Variant)) then
    Result := False;

  if Failed(PS.Commit) then
    Result := False;
end;

class function TFunctions.GetPidExePath(PID: Cardinal): string;
var
  ProcHandle: THandle;
begin
  ProcHandle := OpenProcess(PROCESS_QUERY_INFORMATION, False, Pid);
  if ProcHandle = 0 then
    raise Exception.Create('OpenProcess() failed: %d'.Format([GetLastError]));

  try
    Result := GetExePath(ProcHandle);
  finally
    CloseHandle(ProcHandle);
  end;
end;

class function TFunctions.GetExePath(ProcessHandle: THandle): string;
var
  Size: DWORD;
  Buf: UnicodeString = '';
begin
  Size := 1024;
  SetLength(Buf, Size * 2);

  if FQueryFullProcessImageNameW(ProcessHandle, 0, PWideChar(Buf), @Size) = 0 then
    raise Exception.Create('QueryFullProcessImageNameW() failed: %d'.Format([GetLastError]));

  Result := PWideChar(Buf);
end;

class function TFunctions.IsWindows64Bit: Boolean;
var
  ProcessMachine, NativeMachine: USHORT;
begin
  FIsWow64Process2(GetCurrentProcess, @ProcessMachine, @NativeMachine);
  Result := NativeMachine = IMAGE_FILE_MACHINE_AMD64;
end;

class function TFunctions.IsProcess64Bit(const Handle: THandle): Boolean;
var
  ProcessMachine, NativeMachine: USHORT;
begin
  FIsWow64Process2(Handle, @ProcessMachine, @NativeMachine);
  Result := ProcessMachine = IMAGE_FILE_MACHINE_UNKNOWN;
end;

class function TFunctions.GetWhatsMissingExePath(const MMFLauncher: TMMFLauncher; const X64: Boolean): string;
begin
  if X64 then
    Result := MMFLauncher.WhatsMissingExe64
  else
    Result := MMFLauncher.WhatsMissingExe32;
end;

class function TFunctions.GetWhatsMissingLibPath(const MMFLauncher: TMMFLauncher; const X64: Boolean): string;
begin
  if X64 then
    Result := MMFLauncher.WhatsMissingLib64
  else
    Result := MMFLauncher.WhatsMissingLib32;
end;

class function TFunctions.StartProcess(const ExePath: string; Args: string; const InheritHandles, Suspended: Boolean): TStartProcessRes;
var
  Flags: DWORD;
  SI: Windows.STARTUPINFOW;
  PI: Windows.PROCESS_INFORMATION = (hProcess: 0; hThread: 0; dwProcessId: 0; dwThreadId: 0);
begin
  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);

  if Suspended then
    Flags := CREATE_SUSPENDED
  else
    Flags := 0;

  Result.Success := CreateProcessW(PWideChar(UnicodeString(ExePath)), PWideChar(UnicodeString('"%s" %s'.Format([ExePath, Args]))), nil, nil, InheritHandles, Flags, nil, nil, SI, PI);
  if Result.Success then
  begin
    Result.ProcessHandle := PI.hProcess;
    Result.ThreadHandle := PI.hThread;
    Result.ProcessId := PI.dwProcessId;
  end;
end;

class function TFunctions.FindCmdLineSwitch(const Name: string; var Value: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  Value := '';
  for i := 1 to ParamCount do
    if ParamStr(i).Equals('-' + Name) then
    begin
      Value := ParamStr(i + 1);
      Exit(True);
    end;
end;

class function TFunctions.FindCmdLineSwitch(const Name: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if ParamStr(i).Equals('-' + Name) then
      Exit(True);
end;

class procedure TFunctions.CheckWhatsAppInstalled;
begin
  if not DirectoryExists(TPaths.WhatsAppDir) then
    raise Exception.Create('WhatsApp installation directory expected at "%s" could not be found. Please install WhatsApp before installing/running %s.'.Format([TPaths.WhatsAppDir, APPNAME]));

  if not FileExists(TPaths.WhatsAppExePath) then
    raise Exception.Create('WhatsApp executable expected at "%s" could not be found. Please install WhatsApp before installing/running %s.'.Format([TPaths.WhatsAppExePath, APPNAME]));
end;

class function TFunctions.GetRunningExePids(const FilePath: string): TCardinalArray;
const
  PidCount: DWORD = 2048;
var
  Pids: array of DWORD = [];
  Pid: DWORD;
  cbNeeded: DWORD = 0;
  ProcHandle: THandle;
begin
  Result := [];
  SetLength(Pids, PidCount);
  if FEnumProcesses(@Pids[0], SizeOf(DWORD) * PidCount, cbNeeded) then
  begin
    if cbNeeded > SizeOf(DWORD) * PidCount then
      raise Exception.Create('Error enumerating processes');

    SetLength(Pids, cbNeeded div SizeOf(DWORD));

    for Pid in Pids do
    begin
      ProcHandle := OpenProcess(PROCESS_QUERY_INFORMATION, False, Pid);
      if ProcHandle = 0 then
        Continue;

      try
        if GetExePath(ProcHandle).ToLower.Equals(FilePath.ToLower) then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := Pid;
        end;
      finally
        CloseHandle(ProcHandle);
      end;
    end;
  end;
end;

class function TFunctions.GetRunningWhatsApp: TWindowProcessRes;
var
  PID: DWORD = 0;
  ProcHandle: THandle;
  ExePath: string;
begin
  Result.Success := False;
  Result.WindowHandle := FindWindowW(WHATSAPP_CLASSNAME, WHATSAPP_WINDOWNAME);
  if Result.WindowHandle > 0 then
  begin
    GetWindowThreadProcessId(Result.WindowHandle, PID);
    ProcHandle := OpenProcess(PROCESS_QUERY_INFORMATION, False, PID);
    if ProcHandle = 0 then
      Exit;

    try
      ExePath := GetExePath(ProcHandle);
      Result.PIDs := GetRunningExePids(ExePath);
      Result.Success := True;
    finally
      CloseHandle(ProcHandle);
    end;
  end;
end;

class function TFunctions.AppsRunning(const ConsiderSettings: Boolean): Boolean;
begin
  Result := GetRunningWhatsApp.Success or TMMF.Exists(MMFNAME_LAUNCHER) or (ConsiderSettings and TMMF.Exists(MMFNAME_SETTINGS));
end;

class function TFunctions.CloseApps(const ConsiderSettings: Boolean): Boolean;
var
  PID: Cardinal;
  Handle: THandle;
  WhatsAppRunning: TWindowProcessRes;
  WindowHandles: array of Cardinal;
  ProcHandles: array of THandle;
  WaitRes: Cardinal;
  MMFLauncher: TMMFLauncher;
  MMFSettings: TMMFSettings;

  procedure AddWindowOrPid(const WindowHandle: THandle; const PID: Cardinal);
  var
    ProcHandle: THandle;
  begin
    if WindowHandle > 0 then
    begin
      SetLength(WindowHandles, Length(WindowHandles) + 1);
      WindowHandles[High(WindowHandles)] := WindowHandle;
    end;

    if PID > 0 then
    begin
      ProcHandle := OpenProcess(SYNCHRONIZE, False, PID);
      if ProcHandle > 0 then
      begin
        SetLength(ProcHandles, Length(ProcHandles) + 1);
        ProcHandles[High(ProcHandles)] := ProcHandle;
      end;
    end;
  end;

begin
  MMFLauncher := nil;
  MMFSettings := nil;

  if TMMF.Exists(MMFNAME_LAUNCHER) then
    MMFLauncher := TMMFLauncher.Create(False);

  if ConsiderSettings and TMMF.Exists(MMFNAME_SETTINGS) then
    MMFSettings := TMMFSettings.Create(False);

  try
    Result := False;

    SetLength(WindowHandles, 0);
    SetLength(ProcHandles, 0);

    if Assigned(MMFSettings) then
    begin
      MMFSettings.Read;
      AddWindowOrPid(MMFSettings.SettingsWindowHandle, MMFSettings.SettingsPid);
    end;

    WhatsAppRunning := GetRunningWhatsApp;

    if WhatsAppRunning.Success then
      for PID in WhatsAppRunning.PIDs do
        AddWindowOrPid(0, PID);

    if Assigned(MMFLauncher) then
    begin
      MMFLauncher.ReadMinimal;
      if WhatsAppRunning.Success then
        AddWindowOrPid(MMFLauncher.WhatsAppWindowHandle, MMFLauncher.LauncherPid)
      else
        AddWindowOrPid(MMFLauncher.LauncherWindowHandle, MMFLauncher.LauncherPid);
    end else if WhatsAppRunning.Success then
      AddWindowOrPid(WhatsAppRunning.WindowHandle, 0);

    for Handle in WindowHandles do
    begin
      PostMessage(Handle, WM_EXIT, 0, 0);
      PostMessage(Handle, WM_CLOSE, 0, 0);
    end;

    WaitRes := WaitForMultipleObjects(Length(ProcHandles), @ProcHandles[0], True, 5000);

    if (WaitRes = WAIT_OBJECT_0) then
      Result := True;

    for Handle in ProcHandles do
      CloseHandle(Handle);
  finally
    FreeAndNil(MMFLauncher);
    FreeAndNil(MMFSettings);
  end;
end;

class procedure TFunctions.FindFiles(const Dir, Pattern: string; const Recurse: Boolean; const FileList: TStringList);
var
  SR: TSearchRec;
begin
  if SysUtils.FindFirst(ConcatPaths([Dir, '*']), faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Attr and faDirectory) = 0 then
        begin
          if IsWild(SR.Name, Pattern, True) then
            FileList.Add(ConcatPaths([Dir, SR.Name]));
        end else if Recurse and (SR.Name <> '.') and (SR.Name <> '..') then
          FindFiles(ConcatPaths([Dir, SR.Name]), Pattern, True, FileList);
      until FindNext(SR) <> 0;
    finally
      SysUtils.FindClose(SR);
    end;
end;

class function TFunctions.GetShellLinkPath(const LinkFile: string): string;
var
  SL: IShellLinkW;
  PF: IPersistFile;
  Arg: WideString;
begin
  if Failed(CoCreateInstance(CLSID_ShellLink, nil, CLSCTX_INPROC_SERVER, IID_IShellLinkW, SL)) then
    raise Exception.Create('CoCreateInstance() failed');

  PF := SL as IPersistFile;
  Arg := LinkFile;
  if Failed(PF.Load(PWideChar(Arg), STGM_READ)) then
    raise Exception.Create('IPersistFile.Load() failed');

  SL.Resolve(0, SLR_NO_UI);

  SetLength(Arg, MAX_PATH * 2);
  SL.GetPath(@Arg[1], MAX_PATH, nil, 0);

  Result := PWideChar(Arg);
end;

class procedure TFunctions.ModifyShellLink(const LinkFile: string; const ExecutablePath: string);
var
  SL: IShellLinkW;
  PF: IPersistFile;
  Arg: WideString;
begin
  if Failed(CoCreateInstance(CLSID_ShellLink, nil, CLSCTX_INPROC_SERVER, IID_IShellLinkW, SL)) then
    raise Exception.Create('CoCreateInstance() failed');

  PF := SL as IPersistFile;
  Arg := LinkFile;
  if Failed(PF.Load(PWideChar(Arg), STGM_READ)) then
    raise Exception.Create('IPersistFile.Load() failed');

  SL.Resolve(0, SLR_NO_UI);

  Arg := ExecutablePath;
  if Failed(SL.SetPath(PWideChar(Arg))) then
    raise Exception.Create('IShellLinkW.SetPath() failed');

  Arg := ExtractFileDir(ExecutablePath);
  if Failed(SL.SetWorkingDirectory(PWideChar(Arg))) then
    raise Exception.Create('IShellLinkW.SetworkingDirectory() failed');

  Arg := LinkFile;
  if Failed(PF.Save(PWideChar(Arg), True)) then
    raise Exception.Create('IPersistFile.Save() failed');
end;

class procedure TFunctions.ModifyShellLinks(const FromCurrentPaths: array of string; const NewPath: string);
var
  LinkFile, LinkPath, CurrentPath: string;
  Files: TStringList;
begin
  Files := TStringList.Create;
  try
    FindFiles(TPaths.DesktopDir, '*.lnk', True, Files);
    FindFiles(TPaths.StartMenuDir, '*.lnk', True, Files);
    FindFiles(TPaths.UserPinnedDir, '*.lnk', True, Files);

    for LinkFile in Files do
      try
        LinkPath := GetShellLinkPath(LinkFile);
        for CurrentPath in FromCurrentPaths do
          if SameText(LinkPath, CurrentPath) then
            ModifyShellLink(LinkFile, NewPath);
      except
      end;
  finally
    Files.Free;
  end;
end;

class procedure TFunctions.RunUninstall(const Quiet: Boolean);

  procedure UninstallFile(const FileName: string);
  begin
    if not SysUtils.DeleteFile(FileName) then
      RemoveDir(FileName);
  end;

var
  Reg: TRegistry;
begin
  if (not Quiet) and TFunctions.AppsRunning(True) then
  begin
    if MessageBox(0, 'Uninstall cannot continue since WhatsApp/%s is currently running.'#13#10'Click "Yes" to close WhatsApp/%s, click "No" to cancel.'.Format([APPNAME, APPNAME]), 'Question', MB_ICONQUESTION or MB_YESNO) = IDNO then
      Exit;

    if not TFunctions.CloseApps(True) then
      raise Exception.Create('WhatsApp/%s could not be closed'.Format([APPNAME]));
  end;

  TFunctions.ModifyShellLinks([ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_32]), ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_64])], TPaths.WhatsAppExePath);

  UninstallFile(ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_32]));
  UninstallFile(ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_LIBRARYNAME_32]));
  UninstallFile(ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_EXENAME_64]));
  UninstallFile(ConcatPaths([TPaths.WhatsMissingDir, WHATSMISSING_LIBRARYNAME_64]));
  UninstallFile(TPaths.WhatsMissingDir);

  UninstallFile(TPaths.SettingsPath);
  UninstallFile(ExtractFileDir(TPaths.SettingsPath));

  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    Reg.DeleteKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WhatsMissing');

    if Reg.OpenKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Run', False) and Reg.ValueExists(WHATSAPP_APP_MODEL_ID) then
      Reg.WriteString(WHATSAPP_APP_MODEL_ID, GetWhatsAppAutostartCommand);
  finally
    Reg.Free;
  end;
end;

class procedure TFunctions.ModifyAutostartEntry(const Value: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;

  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Run', False) and Reg.ValueExists(WHATSAPP_APP_MODEL_ID) then
      Reg.WriteString(WHATSAPP_APP_MODEL_ID, Value);
  finally
    Reg.Free;
  end;
end;

class function TFunctions.GetWhatsAppAutostartCommand: string;
begin
  Result := '%s --processStart "%s"'.Format([ConcatPaths([TPaths.WhatsAppDir, UPDATE_EXE]), WHATSAPP_EXE]);
end;

class function TFunctions.GetFileVersion(const FileName: string): string;
var
  VerInfoSize: Integer;
  VerValueSize: DWord = 0;
  Dummy: DWord = 0;
  VerInfo: Pointer;
  VerValue: PVSFixedFileInfo = nil;
begin
  VerInfoSize := GetFileVersionInfoSizeW(PWideChar(UnicodeString(FileName)), Dummy);
  if VerInfoSize <> 0 then
  begin
    GetMem(VerInfo, VerInfoSize);
    try
      if GetFileVersionInfoW(PWideChar(UnicodeString(FileName)), 0, VerInfoSize, VerInfo) then
        if VerQueryValue(VerInfo, '\', Pointer(VerValue), VerValueSize) then
          Exit('%d.%d.%d.%d'.Format([VerValue.dwFileVersionMS shr 16, VerValue.dwFileVersionMS and $FFFF, VerValue.dwFileVersionLS shr 16, VerValue.dwFileVersionLS and $FFFF]));
    finally
      FreeMem(VerInfo, VerInfoSize);
    end;
  end;

  raise Exception.Create('Error reading file version.');
end;

class procedure TFunctions.SetCurrentProcessExplicitAppUserModelID(AppID: string);
begin
  if FSetCurrentProcessExplicitAppUserModelID(PWideChar(UnicodeString(AppID))) <> S_OK then
    raise Exception.Create('SetCurrentProcessExplicitAppUserModelID() failed');
end;

end.
