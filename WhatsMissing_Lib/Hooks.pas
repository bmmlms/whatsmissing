unit Hooks;

interface

uses
  Constants,
  DDetours,
  Functions,
  Log,
  MMF,
  Paths,
  SysUtils,
  Windows;

type
  HSTRING = type THandle;

  TCreateProcessInternalW = function(hToken: HANDLE; lpApplicationName: LPCWSTR; lpCommandLine: LPWSTR; lpProcessAttributes, lpThreadAttributes: LPSECURITY_ATTRIBUTES; bInheritHandles: BOOL;
    dwCreationFlags: DWORD; lpEnvironment: LPVOID; lpCurrentDirectory: LPCWSTR; lpStartupInfo: LPSTARTUPINFOW; lpProcessInformation: LPPROCESS_INFORMATION; hNewToken: PHANDLE): BOOL; stdcall;
  TRegisterClassExW = function(WndClass: PWndClassExW): ATOM; stdcall;
  TCreateWindowExW = function(dwExStyle: DWORD; lpClassName, lpWindowName: LPCWSTR; dwStyle: DWORD; X, Y, nWidth, nHeight: Integer; hWndParent: HWND; hMenu: HMENU; hInstance: HINST; lpParam: LPVOID): HWND; stdcall;
  TCreateFileW = function(lpFileName: LPCWSTR; dwDesiredAccess, dwShareMode: DWORD; lpSecurityAttributes: PSecurityAttributes; dwCreationDisposition, dwFlagsAndAttributes: DWORD; hTemplateFile: THandle): THandle; stdcall;
  TWriteFile = function(hFile: THandle; Buffer: Pointer; nNumberOfBytesToWrite: DWORD; lpNumberOfBytesWritten: PDWORD; lpOverlapped: POverlapped): BOOL; stdcall;
  TGetFileAttributesW = function(lpFileName: LPCWSTR): DWORD; stdcall;
  TRoGetActivationFactory = function(activatableClassId: HSTRING; const iid: TGUID; out outfactory: Pointer): HRESULT; stdcall;

  { THooks }

  THooks = class
  private
    class var
    FMMFLauncher: TMMFLauncher;
    FLog: TLog;
    FMainWindowCreated: Boolean;
    FMainWindowClass: ATOM;
    FMainWindowHandle: THandle;
    FResourcesFile: string;

    OCreateProcessInternalW: TCreateProcessInternalW;
    ORegisterClassExW: TRegisterClassExW;
    OCreateWindowExW: TCreateWindowExW;
    OCreateFileW: TCreateFileW;
    OWriteFile: TWriteFile;
    OGetFileAttributesW: TGetFileAttributesW;
    ORoGetActivationFactory: TRoGetActivationFactory;

    class function HCreateProcessInternalW(hToken: HANDLE; lpApplicationName: LPCWSTR; lpCommandLine: LPWSTR; lpProcessAttributes, lpThreadAttributes: LPSECURITY_ATTRIBUTES;
      bInheritHandles: BOOL; dwCreationFlags: DWORD; lpEnvironment: LPVOID; lpCurrentDirectory: LPCWSTR; lpStartupInfo: LPSTARTUPINFOW; lpProcessInformation: LPPROCESS_INFORMATION; hNewToken: PHANDLE): BOOL; stdcall; static;
    class function HRegisterClassExW(WndClass: PWndClassExW): ATOM; stdcall; static;
    class function HCreateWindowExW(dwExStyle: DWORD; lpClassName, lpWindowName: LPCWSTR; dwStyle: DWORD; X, Y, nWidth, nHeight: Integer; hWndParent: HWND; hMenu: HMENU; hInstance: HINST; lpParam: LPVOID): HWND; stdcall; static;
    class function HCreateFileW(lpFileName: LPCWSTR; dwDesiredAccess, dwShareMode: DWORD; lpSecurityAttributes: PSecurityAttributes; dwCreationDisposition, dwFlagsAndAttributes: DWORD; hTemplateFile: THandle): THandle; stdcall; static;
    class function HWriteFile(hFile: THandle; Buffer: Pointer; nNumberOfBytesToWrite: DWORD; lpNumberOfBytesWritten: PDWORD; lpOverlapped: POverlapped): BOOL; stdcall; static;
    class function HGetFileAttributesW(lpFileName: LPCWSTR): DWORD; stdcall; static;
    class function HRoGetActivationFactory(activatableClassId: HSTRING; const iid: TGUID; out outfactory: Pointer): HRESULT; stdcall; static;
  public
    class var
    OnMainWindowCreated:
    procedure(Handle: THandle);

    class procedure Initialize(const MMFLauncher: TMMFLauncher; const Log: TLog); static;
  end;

implementation

{ THooks }

class procedure THooks.Initialize(const MMFLauncher: TMMFLauncher; const Log: TLog);
var
  Func: Pointer;
begin
  FMMFLauncher := MMFLauncher;
  FLog := Log;

  FResourcesFile := AnsiLowerCaseFileName(ConcatPaths([TPaths.ExeDir, 'resources\app.asar']));

  Func := GetProcAddress(GetModuleHandle('kernelbase.dll'), 'CreateProcessInternalW');
  @OCreateProcessInternalW := InterceptCreate(Func, @HCreateProcessInternalW);
  @ORegisterClassExW := InterceptCreate(@RegisterClassExW, @HRegisterClassExW);
  @OCreateFileW := InterceptCreate(@CreateFileW, @HCreateFileW);
  @OWriteFile := InterceptCreate(@WriteFile, @HWriteFile);
  @OGetFileAttributesW := InterceptCreate(@GetFileAttributesW, @HGetFileAttributesW);

  Func := GetProcAddress(GetModuleHandle('user32.dll'), 'CreateWindowExW');
  @OCreateWindowExW := InterceptCreate(Func, @HCreateWindowExW);

  Func := GetProcAddress(GetModuleHandle('api-ms-win-core-winrt-l1-1-0.dll'), 'RoGetActivationFactory');
  @ORoGetActivationFactory := InterceptCreate(Func, @HRoGetActivationFactory);
end;

class function THooks.HCreateProcessInternalW(hToken: HANDLE; lpApplicationName: LPCWSTR; lpCommandLine: LPWSTR; lpProcessAttributes, lpThreadAttributes: LPSECURITY_ATTRIBUTES;
  bInheritHandles: BOOL; dwCreationFlags: DWORD; lpEnvironment: LPVOID; lpCurrentDirectory: LPCWSTR; lpStartupInfo: LPSTARTUPINFOW; lpProcessInformation: LPPROCESS_INFORMATION; hNewToken: PHANDLE): BOOL; stdcall;
var
  LastError: Cardinal;
  ApplicationName: string;
begin
  ApplicationName := lpApplicationName;
  ApplicationName := ApplicationName.Trim;

  if ApplicationName.ToLower.Equals(FMMFLauncher.WhatsMissingExe32.ToLower) or ApplicationName.ToLower.Equals(FMMFLauncher.WhatsMissingExe64.ToLower) then
    Exit(OCreateProcessInternalW(hToken, lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation, hNewToken));

  Result := OCreateProcessInternalW(hToken, lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags or CREATE_SUSPENDED, lpEnvironment,
    lpCurrentDirectory, lpStartupInfo, lpProcessInformation, hNewToken);

  LastError := GetLastError;

  if Result then
  begin
    FLog.Info(Format('CreateProcessInternalW(): PID %d / "%s" / "%s"', [lpProcessInformation.dwProcessId, lpApplicationName, lpCommandLine]));

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

  if (Result > 0) and (lstrcmpW(WndClass.lpszClassName, WHATSAPP_CLASSNAME) = 0) then
  begin
    FLog.Info(Format('RegisterClassExW(): Found main window class %d', [Result]));

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

  if (not FMainWindowCreated) and (Result > 0) and (HiWord(NativeUInt(lpClassName)) = 0) and (ATOM(lpClassName) = FMainWindowClass) then
  begin
    FLog.Info(Format('CreateWindowExW(): Found main window with handle %d', [Result]));

    FMainWindowHandle := Result;
    FMainWindowCreated := True;

    PostMessage(FMMFLauncher.LauncherWindowHandle, WM_MAINWINDOW_CREATED, Result, GetCurrentProcessId);

    OnMainWindowCreated(Result);
  end;

  SetLastError(LastError);
end;

class function THooks.HCreateFileW(lpFileName: LPCWSTR; dwDesiredAccess, dwShareMode: DWORD; lpSecurityAttributes: PSecurityAttributes; dwCreationDisposition, dwFlagsAndAttributes: DWORD; hTemplateFile: THandle): THandle; stdcall;
var
  FileName, PatchedFileName: string;
  PatchedFileNameUnicode: UnicodeString;
begin
  FileName := lpFileName;
  PatchedFileName := TFunctions.GetPatchedResourceFilePath(lpFileName);

  if not FileName.EndsWith(FResourcesFile, True) then
    Exit(OCreateFileW(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile));

  if not FileExists(PatchedFileName) then
  begin
    FLog.Error(Format('CreateFileW(): Patched resource file "%s" does not exist', [PatchedFileName]));
    Exit(OCreateFileW(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile));
  end;

  PatchedFileNameUnicode := PatchedFileName;
  Result := OCreateFileW(PWideChar(PatchedFileNameUnicode), dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
end;

class function THooks.HWriteFile(hFile: THandle; Buffer: Pointer; nNumberOfBytesToWrite: DWORD; lpNumberOfBytesWritten: PDWORD; lpOverlapped: POverlapped): BOOL; stdcall;
const
  MessageRead: PWideChar = 'action,cmd,read,';
var
  i: NativeUInt;
begin
  if hFile = FLog.Handle then
    Exit(OWriteFile(hFile, Buffer, nNumberOfBytesToWrite, lpNumberOfBytesWritten, lpOverlapped));

  for i := NativeUInt(Buffer) to NativeUInt(Buffer) + (nNumberOfBytesToWrite - (Length(MessageRead) * 2) - 1) do
    if CompareMem(PByte(i), MessageRead, Length(MessageRead) * 2) then
    begin
      FLog.Debug('WriteFile(): Found message read command');

      // Since the WindowHandle is not known on MMF creation we might have to read it again
      if FMMFLauncher.WhatsAppWindowHandle = 0 then
        FMMFLauncher.Read;

      PostMessage(FMMFLauncher.WhatsAppWindowHandle, WM_CHAT, WC_READ, 0);

      Break;
    end;

  Result := OWriteFile(hFile, Buffer, nNumberOfBytesToWrite, lpNumberOfBytesWritten, lpOverlapped);
end;

class function THooks.HGetFileAttributesW(lpFileName: LPCWSTR): DWORD; stdcall;
var
  PatchedFileName: string;
  PatchedFileNameUnicode: UnicodeString;
begin
  PatchedFileName := TFunctions.GetPatchedResourceFilePath(lpFileName);

  if not FResourcesFile.EndsWith(lpFileName, True) then
    Exit(OGetFileAttributesW(lpFileName));

  if not FileExists(PatchedFileName) then
  begin
    FLog.Error(Format('GetFileAttributesW(): Patched resource file "%s" does not exist', [PatchedFileName]));
    Exit(OGetFileAttributesW(lpFileName));
  end;

  PatchedFileNameUnicode := PatchedFileName;
  Result := OGetFileAttributesW(PWideChar(PatchedFileNameUnicode));
end;

class function THooks.HRoGetActivationFactory(activatableClassId: HSTRING; const iid: TGUID; out outfactory: Pointer): HRESULT; stdcall;
begin
  if iid.ToString = '{04124B20-82C6-4229-B109-FD9ED4662B53}' then
  begin
    FLog.Info('RoGetActivationFactory(): Creating notification factory');

    // Since the WindowHandle is not known on MMF creation we might have to read it again
    if FMMFLauncher.WhatsAppWindowHandle = 0 then
      FMMFLauncher.Read;

    PostMessage(FMMFLauncher.WhatsAppWindowHandle, WM_CHAT, WC_RECEIVED, 0);
  end;

  Result := ORoGetActivationFactory(activatableClassId, iid, outfactory);
end;

end.
