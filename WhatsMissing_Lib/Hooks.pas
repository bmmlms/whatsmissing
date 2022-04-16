unit Hooks;

interface

uses
  Classes,
  Constants,
  DDetours,
  fpjson,
  Functions,
  Generics.Collections,
  jsonparser,
  Log,
  MMF,
  Paths,
  SysUtils,
  VirtualFile,
  Windows;

type
  HSTRING = type HANDLE;

  TCreateProcessInternalW = function(hToken: HANDLE; lpApplicationName: LPCWSTR; lpCommandLine: LPWSTR; lpProcessAttributes, lpThreadAttributes: LPSECURITY_ATTRIBUTES; bInheritHandles: BOOL;
    dwCreationFlags: DWORD; lpEnvironment: LPVOID; lpCurrentDirectory: LPCWSTR; lpStartupInfo: LPSTARTUPINFOW; lpProcessInformation: LPPROCESS_INFORMATION; hNewToken: PHANDLE): BOOL; stdcall;
  TRegisterClassExW = function(WndClass: PWndClassExW): ATOM; stdcall;
  TCreateWindowExW = function(dwExStyle: DWORD; lpClassName, lpWindowName: LPCWSTR; dwStyle: DWORD; X, Y, nWidth, nHeight: Integer; hWndParent: HWND; hMenu: HMENU; hInstance: HINST; lpParam: LPVOID): HWND; stdcall;
  TShowWindow = function(hWnd: HWND; nCmdShow: longint): WINBOOL; stdcall;
  TCreateFileW = function(lpFileName: LPCWSTR; dwDesiredAccess, dwShareMode: DWORD; lpSecurityAttributes: PSecurityAttributes; dwCreationDisposition, dwFlagsAndAttributes: DWORD; hTemplateFile: HANDLE): HANDLE; stdcall;
  TReadFile = function(hFile: HANDLE; lpBuffer: LPVOID; nNumberOfBytesToRead: DWORD; lpNumberOfBytesRead: LPDWORD; lpOverlapped: LPOVERLAPPED): BOOL; stdcall;
  TWriteFile = function(hFile: HANDLE; lpBuffer: LPVOID; nNumberOfBytesToWrite: DWORD; lpNumberOfBytesWritten: PDWORD; lpOverlapped: POverlapped): BOOL; stdcall;
  TGetFileType = function(hFile: HANDLE): DWORD; stdcall;
  TCloseHandle = function(hObject: HANDLE): WINBOOL; stdcall;
  TGetFileSizeEx = function(hFile: HANDLE; lpFileSize: PLARGE_INTEGER): BOOL; stdcall;
  TRegSetValueExW = function(hKey: HKEY; lpValueName: LPCWSTR; Reserved: DWORD; dwType: DWORD; lpData: Pointer; cbData: DWORD): LONG; stdcall;
  TRegQueryValueExW = function(hKey: HKEY; lpValueName: LPCWSTR; lpReserved: LPDWORD; lpType: LPDWORD; lpData: LPBYTE; lpcbData: LPDWORD): LONG; stdcall;
  TSetWindowLong = function(hWnd: HWND; nIndex: longint; dwNewLong: LONG): LONG; stdcall;

  TVirtualFileData = record
    Handle: THandle;
    Instance: TVirtualFile;
  end;

  { THooks }

  THooks = class
  private
  class var
    FMMFLauncher: TMMFLauncher;
    FLog: TLog;
    FResourceError: Boolean;
    FMainWindowClass: ATOM;
    FMainWindowHandle, FWACommunicationHandle: THandle;
    FResourcesFile: string;
    FWAMethodResult: TJSONData;
    FVirtualFiles: TList<TVirtualFileData>;
    FMMFResources: TMMFResources;
    FCommunicationLock, FVirtualFilesLock: TCriticalSection;

    OCreateProcessInternalW: TCreateProcessInternalW;
    ORegisterClassExW: TRegisterClassExW;
    OCreateWindowExW: TCreateWindowExW;
    OShowWindow: TShowWindow;
    OCreateFileW: TCreateFileW;
    OReadFile: TReadFile;
    OWriteFile: TWriteFile;
    OGetFileType: TGetFileType;
    OCloseHandle: TCloseHandle;
    OGetFileSizeEx: TGetFileSizeEx;
    ORegSetValueExW: TRegSetValueExW;
    ORegQueryValueExW: TRegQueryValueExW;
    OSetWindowLongW: TSetWindowLong;

    class function HCreateProcessInternalW(hToken: HANDLE; lpApplicationName: LPCWSTR; lpCommandLine: LPWSTR; lpProcessAttributes, lpThreadAttributes: LPSECURITY_ATTRIBUTES;
      bInheritHandles: BOOL; dwCreationFlags: DWORD; lpEnvironment: LPVOID; lpCurrentDirectory: LPCWSTR; lpStartupInfo: LPSTARTUPINFOW; lpProcessInformation: LPPROCESS_INFORMATION; hNewToken: PHANDLE): BOOL; stdcall; static;
    class function HRegisterClassExW(WndClass: PWndClassExW): ATOM; stdcall; static;
    class function HCreateWindowExW(dwExStyle: DWORD; lpClassName, lpWindowName: LPCWSTR; dwStyle: DWORD; X, Y, nWidth, nHeight: Integer; hWndParent: HWND; hMenu: HMENU; hInstance: HINST; lpParam: LPVOID): HWND; stdcall; static;
    class function HShowWindow(hWnd: HWND; nCmdShow: longint): WINBOOL; stdcall; static;
    class function HCreateFileW(lpFileName: LPCWSTR; dwDesiredAccess, dwShareMode: DWORD; lpSecurityAttributes: PSecurityAttributes; dwCreationDisposition, dwFlagsAndAttributes: DWORD; hTemplateFile: HANDLE): HANDLE; stdcall; static;
    class function HReadFile(hFile: HANDLE; lpBuffer: LPVOID; nNumberOfBytesToRead: DWORD; lpNumberOfBytesRead: LPDWORD; lpOverlapped: LPOVERLAPPED): BOOL; stdcall; static;
    class function HWriteFile(hFile: HANDLE; lpBuffer: LPVOID; nNumberOfBytesToWrite: DWORD; lpNumberOfBytesWritten: PDWORD; lpOverlapped: POverlapped): BOOL; stdcall; static;
    class function HGetFileType(hFile: HANDLE): DWORD; stdcall; static;
    class function HCloseHandle(hObject: HANDLE): WINBOOL; stdcall; static;
    class function HGetFileSizeEx(hFile: HANDLE; lpFileSize: PLARGE_INTEGER): BOOL; stdcall; static;
    class function HRegSetValueExW(hKey: HKEY; lpValueName: LPCWSTR; Reserved: DWORD; dwType: DWORD; lpData: Pointer; cbData: DWORD): LONG; stdcall; static;
    class function HRegQueryValueExW(hKey: HKEY; lpValueName: LPCWSTR; lpReserved: LPDWORD; lpType: LPDWORD; lpData: LPBYTE; lpcbData: LPDWORD): LONG; stdcall; static;
    class function HSetWindowLongW(hWnd: HWND; nIndex: longint; dwNewLong: LONG): LONG; stdcall; static;
  public
  class var
    OnMainWindowCreated:
    procedure(Handle: THandle);

    class procedure Initialize(const Log: TLog); static;
  end;

implementation

{ THooks }

class procedure THooks.Initialize(const Log: TLog);
var
  Func: Pointer;
begin
  FLog := Log;

  FMMFLauncher := TMMFLauncher.Create(False);
  FMMFLauncher.Read;

  InitializeCriticalSection(FCommunicationLock);
  InitializeCriticalSection(FVirtualFilesLock);
  FVirtualFiles := TList<TVirtualFileData>.Create;

  FResourcesFile := AnsiLowerCaseFileName(ConcatPaths([TPaths.ExeDir, 'resources\app.asar']));

  Func := GetProcAddress(GetModuleHandle('kernelbase.dll'), 'CreateProcessInternalW');
  @OCreateProcessInternalW := InterceptCreate(Func, @HCreateProcessInternalW);

  @ORegisterClassExW := InterceptCreate(@RegisterClassExW, @HRegisterClassExW);
  @OShowWindow := InterceptCreate(@ShowWindow, @HShowWindow);
  @OCreateFileW := InterceptCreate(@CreateFileW, @HCreateFileW);
  @OReadFile := InterceptCreate(@ReadFile, @HReadFile);
  @OWriteFile := InterceptCreate(@WriteFile, @HWriteFile);
  @OGetFileType := InterceptCreate(@GetFileType, @HGetFileType);
  @OCloseHandle := InterceptCreate(@CloseHandle, @HCloseHandle);

  Func := GetProcAddress(GetModuleHandle('kernelbase.dll'), 'GetFileSizeEx');
  @OGetFileSizeEx := InterceptCreate(Func, @HGetFileSizeEx);

  Func := GetProcAddress(GetModuleHandle('user32.dll'), 'CreateWindowExW');
  @OCreateWindowExW := InterceptCreate(Func, @HCreateWindowExW);

  @ORegSetValueExW := InterceptCreate(@RegSetValueExW, @HRegSetValueExW);
  @ORegQueryValueExW := InterceptCreate(@RegQueryValueExW, @HRegQueryValueExW);

  @OSetWindowLongW := InterceptCreate(@SetWindowLongW, @HSetWindowLongW);
end;

class function THooks.HCreateProcessInternalW(hToken: HANDLE; lpApplicationName: LPCWSTR; lpCommandLine: LPWSTR; lpProcessAttributes, lpThreadAttributes: LPSECURITY_ATTRIBUTES;
  bInheritHandles: BOOL; dwCreationFlags: DWORD; lpEnvironment: LPVOID; lpCurrentDirectory: LPCWSTR; lpStartupInfo: LPSTARTUPINFOW; lpProcessInformation: LPPROCESS_INFORMATION; hNewToken: PHANDLE): BOOL; stdcall;
var
  LastError: Cardinal;
begin
  if string(lpApplicationName).Trim.ToLower.Equals(FMMFLauncher.WhatsMissingExe32.ToLower) or string(lpApplicationName).Trim.ToLower.Equals(FMMFLauncher.WhatsMissingExe64.ToLower) or
    string(lpCommandLine).ToLower.Contains('--squirrel-obsolete') then
    Exit(OCreateProcessInternalW(hToken, lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation, hNewToken));

  Result := OCreateProcessInternalW(hToken, lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags or CREATE_SUSPENDED, lpEnvironment,
    lpCurrentDirectory, lpStartupInfo, lpProcessInformation, hNewToken);

  LastError := GetLastError;

  if Result then
  begin
    FLog.Info('CreateProcessInternalW(): PID %d / "%s" / "%s"'.Format([lpProcessInformation.dwProcessId, lpApplicationName, lpCommandLine]));

    if not TFunctions.InjectLibrary(FMMFLauncher, lpProcessInformation.hProcess, lpProcessInformation.hThread) then
      FLog.Error('CreateProcessInternalW(): Failed to inject library');

    if not (dwCreationFlags and CREATE_SUSPENDED = CREATE_SUSPENDED) then
      ResumeThread(lpProcessInformation.hThread);
  end;

  SetLastError(LastError);
end;

class function THooks.HRegisterClassExW(WndClass: PWndClassExW): ATOM; stdcall;
var
  LastError: Cardinal;
begin
  Result := ORegisterClassExW(WndClass);
  LastError := GetLastError;

  if (Result > 0) and (string(WndClass.lpszClassName) = string(WHATSAPP_CLASSNAME)) then
  begin
    FLog.Info('RegisterClassExW(): Found main window class %d'.Format([Result]));

    InterceptRemove(@ORegisterClassExW);

    FMainWindowClass := Result;
  end;

  SetLastError(LastError);
end;

class function THooks.HCreateWindowExW(dwExStyle: DWORD; lpClassName, lpWindowName: LPCWSTR; dwStyle: DWORD; X, Y, nWidth, nHeight: Integer; hWndParent: HWND; hMenu: HMENU; hInstance: HINST; lpParam: LPVOID): HWND; stdcall;
var
  LastError: Cardinal;
begin
  Result := OCreateWindowExW(dwExStyle, lpClassName, lpWindowName, dwStyle, X, Y, nWidth, nHeight, hWndParent, hMenu, hInstance, lpParam);

  LastError := GetLastError;

  if (FMainWindowHandle = 0) and (Result > 0) and (HiWord(NativeUInt(lpClassName)) = 0) and (ATOM(lpClassName) = FMainWindowClass) then
  begin
    FLog.Info('CreateWindowExW(): Found main window with handle %d'.Format([Result]));

    InterceptRemove(@OCreateWindowExW);

    FMainWindowHandle := Result;

    PostMessage(FMMFLauncher.LauncherWindowHandle, WM_MAINWINDOW_CREATED, Result, GetCurrentProcessId);

    OnMainWindowCreated(Result);
  end;

  SetLastError(LastError);
end;

class function THooks.HShowWindow(hWnd: HWND; nCmdShow: longint): WINBOOL; stdcall;
var
  LastError: Cardinal;
begin
  Result := OShowWindow(hWnd, nCmdShow);

  LastError := GetLastError;

  if GetParent(hWnd) = 0 then
  begin
    FLog.Info('ShowWindow(): First top level window with handle %d shown'.Format([hWnd]));

    InterceptRemove(@OShowWindow);
    SendMessage(FMMFLauncher.LauncherWindowHandle, WM_WINDOW_SHOWN, 0, 0);
  end;

  SetLastError(LastError);
end;

class function THooks.HCreateFileW(lpFileName: LPCWSTR; dwDesiredAccess, dwShareMode: DWORD; lpSecurityAttributes: PSecurityAttributes; dwCreationDisposition, dwFlagsAndAttributes: DWORD; hTemplateFile: HANDLE): HANDLE; stdcall;
var
  VirtualFileData: TVirtualFileData;
  Event: THandle;
begin
  if string(lpFileName) = '\\.\wacommunication' then
  begin
    if FWACommunicationHandle > 0 then
      Exit(FWACommunicationHandle);

    FWACommunicationHandle := OpenProcess(PROCESS_QUERY_INFORMATION, False, GetCurrentProcessId);

    FLog.Debug('CreateFileW(): Communication file opened with handle %d'.Format([FWACommunicationHandle]));

    Exit(FWACommunicationHandle);
  end;

  if (not FResourceError) and (string(lpFileName).EndsWith(FResourcesFile, True)) and (dwDesiredAccess <> $AFFEAFFE) then
  begin
    Result := OCreateFileW(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
    if Result <> INVALID_HANDLE_VALUE then
    begin
      if FMMFResources = nil then
      begin
        Event := TFunctions.TryOpenEvent(SYNCHRONIZE, False, TMMFResources.GetEventName(FResourcesFile));
        if Event <> 0 then
        begin
          FLog.Debug('Waiting for resources');

          if WaitForSingleObject(Event, 10000) <> WAIT_OBJECT_0 then
          begin
            TFunctions.MessageBox(FMMFLauncher.LauncherWindowHandle, 'Error waiting for resources.', '%s error'.Format([APPNAME]), MB_ICONERROR);
            ExitProcess(100);
          end;

          CloseHandle(Event);

          FLog.Debug('Resources ready');
        end;

        try
          FMMFResources := TMMFResources.Create(FResourcesFile, False, 0);
          FMMFResources.Read;
        except
          FResourceError := True;

          FLog.Error('Error reading resources');

          if Assigned(FMMFResources) then
            FreeAndNil(FMMFResources);
        end;
      end;

      if not FResourceError then
      begin
        VirtualFileData.Handle := Result;
        VirtualFileData.Instance := TVirtualFile.Create;
        VirtualFileData.Instance.AddRegion(TVirtualFileRegionMemory.Create(FMMFResources.JSON.Memory, FMMFResources.JSON.Size));
        VirtualFileData.Instance.AddRegion(TVirtualFileRegionDisk.Create(FResourcesFile, FMMFResources.ContentOffset));
        VirtualFileData.Instance.AddRegion(TVirtualFileRegionMemory.Create(FMMFResources.Resources.Memory, FMMFResources.Resources.Size));

        EnterCriticalSection(FVirtualFilesLock);
        try
          FVirtualFiles.Add(VirtualFileData);
        finally
          LeaveCriticalSection(FVirtualFilesLock);
        end;
      end;
    end;

    SetLastError(0);

    Exit;
  end;

  if dwDesiredAccess = $AFFEAFFE then
    dwDesiredAccess := GENERIC_READ;

  Exit(OCreateFileW(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile));
end;

class function THooks.HReadFile(hFile: HANDLE; lpBuffer: LPVOID; nNumberOfBytesToRead: DWORD; lpNumberOfBytesRead: LPDWORD; lpOverlapped: LPOVERLAPPED): BOOL; stdcall;
var
  JSONStr: string;
  VirtualFileData: TVirtualFileData;
begin
  if hFile = FWACommunicationHandle then
  begin
    FMMFLauncher.Read;

    if Assigned(FWAMethodResult) then
    begin
      FWAMethodResult.CompressedJSON := True;

      JSONStr := FWAMethodResult.AsJSON;

      FLog.Debug('Method call result: %s'.Format([JSONStr]));

      FreeAndNil(FWAMethodResult);
    end else
      JSONStr := '{}';

    if nNumberOfBytesToRead < JSONStr.Length then
      raise Exception.Create('Buffer too small');

    // Important for JSON.parse()
    FillChar(lpBuffer^, nNumberOfBytesToRead, ' ');

    CopyMemory(lpBuffer, @JSONStr[1], JSONStr.Length);

    lpNumberOfBytesRead^ := nNumberOfBytesToRead;

    LeaveCriticalSection(FCommunicationLock);

    Exit(True);
  end;

  if not FResourceError then
  begin
    EnterCriticalSection(FVirtualFilesLock);
    try
      for VirtualFileData in FVirtualFiles do
        if VirtualFileData.Handle = hFile then
        begin
          Result := True;

          if Assigned(lpOverlapped) then
            VirtualFileData.Instance.Position := lpOverlapped.Offset;

          VirtualFileData.Instance.Read(lpBuffer, nNumberOfBytesToRead, lpNumberOfBytesRead);

          SetLastError(IfThen<DWORD>(Result, 0, ERROR_CANTREAD));

          Exit;
        end;
    finally
      LeaveCriticalSection(FVirtualFilesLock);
    end;
  end;

  Result := OReadFile(hFile, lpBuffer, nNumberOfBytesToRead, lpNumberOfBytesRead, lpOverlapped);
end;

class function THooks.HWriteFile(hFile: HANDLE; lpBuffer: LPVOID; nNumberOfBytesToWrite: DWORD; lpNumberOfBytesWritten: PDWORD; lpOverlapped: POverlapped): BOOL; stdcall;
var
  JSONObject: TJSONObject;
  JSONData: TJSONData;
  Chat: TChat;
  JSON: TMemoryStream;
begin
  if hFile = FWACommunicationHandle then
  begin
    if Assigned(FWAMethodResult) then
      raise Exception.Create('Assigned(FWAMethodResult)');

    EnterCriticalSection(FCommunicationLock);

    JSON := TMemoryStream.Create;
    try
      JSON.WriteBuffer(lpBuffer^, nNumberOfBytesToWrite);

      JSON.Position := 0;
      JSONObject := TJSONObject(GetJSON(JSON, True));

      JSONObject.CompressedJSON := True;
      FLog.Debug('Data from WhatsApp: %s'.Format([JSONObject.AsJSON]));

      if not JSONObject.Find('data', JSONData) then
        raise Exception.Create('Received invalid data');

      try
        if JSONObject.Strings['method'] = 'ask_notification_sound' then
        begin
          // WhatsApp is about to play the notification sound for a received message
          // {"method":"ask_notification_sound","data":"0000000000000@c.us"}

          FLog.Debug('Found notification sound query');

          if FMMFLauncher.SuppressConsecutiveNotificationSounds then
          begin
            Chat := FMMFLauncher.Chats.Get(JSONData.Value);

            if Chat.LastNotificationSound > Trunc(GetTickCount64 / 1000) - 60 then
              FWAMethodResult := TJSONBoolean.Create(False);

            FLog.Debug('Setting LastNotificationSound for "%s"'.Format([JSONData.Value]));
            Chat.LastNotificationSound := Trunc(GetTickCount64 / 1000);
            FMMFLauncher.Write;
          end;

          if not Assigned(FWAMethodResult) then
            FWAMethodResult := TJSONBoolean.Create(True);
        end;
      finally
        JSONObject.Free;
      end;
    finally
      JSON.Free;
    end;

    lpNumberOfBytesWritten^ := nNumberOfBytesToWrite;

    Exit(True);
  end;

  Result := OWriteFile(hFile, lpBuffer, nNumberOfBytesToWrite, lpNumberOfBytesWritten, lpOverlapped);
end;

class function THooks.HGetFileType(hFile: HANDLE): DWORD; stdcall;
begin
  if hFile = FWACommunicationHandle then
    Exit(FILE_TYPE_DISK);

  Exit(OGetFileType(hFile));
end;

class function THooks.HCloseHandle(hObject: HANDLE): WINBOOL; stdcall;
var
  i: Integer;
begin
  if not FResourceError then
  begin
    EnterCriticalSection(FVirtualFilesLock);
    try
      for i := 0 to FVirtualFiles.Count - 1 do
        if FVirtualFiles[i].Handle = hObject then
        begin
          FVirtualFiles[i].Instance.Free;
          FVirtualFiles.Delete(i);
          Break;
        end;
    finally
      LeaveCriticalSection(FVirtualFilesLock);
    end;
  end;

  Result := OCloseHandle(hObject);
end;

class function THooks.HGetFileSizeEx(hFile: HANDLE; lpFileSize: PLARGE_INTEGER): BOOL; stdcall;
var
  VirtualFileData: TVirtualFileData;
begin
  if not FResourceError then
  begin
    EnterCriticalSection(FVirtualFilesLock);
    try
      for VirtualFileData in FVirtualFiles do
        if VirtualFileData.Handle = hFile then
        begin
          lpFileSize^.QuadPart := VirtualFileData.Instance.Size;
          Exit(True);
        end;
    finally
      LeaveCriticalSection(FVirtualFilesLock);
    end;
  end;

  Result := OGetFileSizeEx(hFile, lpFilesize);
end;

class function THooks.HRegSetValueExW(hKey: HKEY; lpValueName: LPCWSTR; Reserved: DWORD; dwType: DWORD; lpData: Pointer; cbData: DWORD): LONG; stdcall;
var
  UnicodeData: UnicodeString;
begin
  if string(lpValueName).Equals(WHATSAPP_APP_MODEL_ID) and (dwType = REG_SZ) and (string(LPCWSTR(lpData)).ToLower.Equals(TFunctions.GetWhatsAppAutostartCommand.ToLower)) then
  begin
    FLog.Info('RegSetValueExW(): Writing modified autostart registry value');

    UnicodeData := TFunctions.GetWhatsMissingExePath(FMMFLauncher, TFunctions.IsWindows64Bit);

    Exit(ORegSetValueExW(hKey, lpValueName, Reserved, dwType, PWideChar(UnicodeData), ByteLength(UnicodeData) + 2));
  end;

  Result := ORegSetValueExW(hKey, lpValueName, Reserved, dwType, lpData, cbData);
end;

class function THooks.HRegQueryValueExW(hKey: HKEY; lpValueName: LPCWSTR; lpReserved: LPDWORD; lpType: LPDWORD; lpData: LPBYTE; lpcbData: LPDWORD): LONG; stdcall;
var
  DataUnicode: UnicodeString;
begin
  if string(lpValueName).Equals(WHATSAPP_APP_MODEL_ID) and Assigned(lpType) and (lpType^ = REG_SZ) and Assigned(lpData) and Assigned(lpcbData)
    and (ORegQueryValueExW(hKey, lpValueName, lpReserved, lpType, lpData, lpcbData) = ERROR_SUCCESS)
    and string(LPCWSTR(lpData)).ToLower.Equals(TFunctions.GetWhatsMissingExePath(FMMFLauncher, TFunctions.IsWindows64Bit).ToLower) then
  begin
    FLog.Info('RegQueryValueExW(): Modifying read autostart registry value');

    FLog.Debug(TFunctions.GetWhatsAppAutostartCommand);

    DataUnicode := TFunctions.GetWhatsAppAutostartCommand;
    StrCopy(PWideChar(lpData), PWideChar(DataUnicode));
    lpcbData^ := ByteLength(DataUnicode) + 2;

    Exit(ERROR_SUCCESS);
  end;

  Result := ORegQueryValueExW(hKey, lpValueName, lpReserved, lpType, lpData, lpcbData);
end;

class function THooks.HSetWindowLongW(hWnd: HWND; nIndex: longint; dwNewLong: LONG): LONG; stdcall;
var
  LastError: Cardinal;
begin
  if not FMMFLauncher.UseRegularTitleBar then
    Exit(OSetWindowLongW(hWnd, nIndex, dwNewLong));

  if (hWnd = FMainWindowHandle) and (nIndex = GWL_STYLE) then
  begin
    dwNewLong := WS_OVERLAPPEDWINDOW;
    if FMMFLauncher.HideMaximize then
      dwNewLong := dwNewLong and not WS_MAXIMIZEBOX;
  end;

  Result := OSetWindowLongW(hWnd, nIndex, dwNewLong);

  LastError := GetLastError;

  if (hWnd = FMainWindowHandle) and (Result <> 0) then
    SetWindowPos(FMainWindowHandle, 0, 0, 0, 0, 0, SWP_NOACTIVATE or SWP_NOZORDER or SWP_NOMOVE or SWP_NOSIZE or SWP_FRAMECHANGED);

  SetLastError(LastError);
end;

end.
