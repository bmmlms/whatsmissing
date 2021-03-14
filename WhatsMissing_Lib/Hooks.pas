unit Hooks;

interface

uses
  classes,
  Constants,
  DDetours,
  Functions,
  fpjson,
  Log,
  jsonparser,
  MMF,
  VirtualFile,
  Paths,
  Generics.Collections,
  SysUtils,
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
  TRoGetActivationFactory = function(activatableClassId: HSTRING; const iid: TGUID; out outfactory: LPVOID): HRESULT; stdcall;

  TWhatsAppData = record
    MessageType: string;
    MessageSubType: string;
    DataType: string;
    DataSubType: string;
  end;

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
    FMutedChats: TList<string>;
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
    ORoGetActivationFactory: TRoGetActivationFactory;

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
    class function HRoGetActivationFactory(activatableClassId: HSTRING; const iid: TGUID; out outfactory: LPVOID): HRESULT; stdcall; static;
  public
    class var
    OnMainWindowCreated: procedure(Handle: THandle);

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
  FMutedChats := TList<string>.Create;
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
  FileName: string;
  VirtualFileData: TVirtualFileData;
  Event: THandle;
begin
  FileName := lpFileName;

  if FileName = '\\.\wacommunication' then
  begin
    if FWACommunicationHandle > 0 then
      Exit(FWACommunicationHandle);

    FWACommunicationHandle := OpenProcess(PROCESS_QUERY_INFORMATION, False, GetCurrentProcessId);

    FLog.Debug('CreateFileW(): Communication file opened with handle %d'.Format([FWACommunicationHandle]));

    Exit(FWACommunicationHandle);
  end;

  if (not FResourceError) and (FileName.EndsWith(FResourcesFile, True)) and (dwDesiredAccess <> $AFFEAFFE) then
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
          FMMFResources := TMMFResources.Create(FResourcesFile, False);
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

  function ParseWhatsAppData(Data: TJSONData): TWhatsAppData;
  var
    D: TJSONData;
  begin
    D := Data.FindPath('[0]');
    if Assigned(D) and (D.ClassType = TJSONString) then
      Result.MessageType := D.Value;

    D := Data.FindPath('[1].type');
    if Assigned(D) and (D.ClassType = TJSONString) then
      Result.MessageSubType := D.Value;

    D := Data.FindPath('[2][0][0]');
    if Assigned(D) and (D.ClassType = TJSONString) then
      Result.DataType := D.Value;

    D := Data.FindPath('[2][0][1].type');
    if Assigned(D) and (D.ClassType = TJSONString) then
      Result.DataSubType := D.Value;
  end;

const
  MessageRead: PWideChar = 'action,cmd,read,';
var
  P: PByte;
  JSONStr, JID: string;
  JSONObject: TJSONObject;
  JSONArray: TJSONArray;
  JSONData: TJSONData;
  JSONEnum: TJSONEnum;
  WhatsAppData: TWhatsAppData;
begin
  if hFile = FWACommunicationHandle then
  begin
    if Assigned(FWAMethodResult) then
      raise Exception.Create('Assigned(FWAMethodResult)');

    // WhatsAppWindowHandle might be unknown, also we need to refresh the list of muted chats
    FMMFLauncher.Read;

    EnterCriticalSection(FCommunicationLock);

    SetLength(JSONStr, nNumberOfBytesToWrite);
    CopyMemory(@JSONStr[1], lpBuffer, nNumberOfBytesToWrite);

    FLog.Debug('Data from WhatsApp: %s'.Format([JSONStr]));

    JSONObject := TJSONObject(GetJSON(JSONStr, False));
    if not JSONObject.Find('data', JSONData) then
      raise Exception.Create('Received invalid data');

    try
      if (JSONObject.Strings['method'] = 'socket_in') or (JSONObject.Strings['method'] = 'socket_out') then
        WhatsAppData := ParseWhatsAppData(JSONData);

      if JSONObject.Strings['method'] = 'socket_in' then
      begin
        if (WhatsAppData.MessageType = 'response') and (WhatsAppData.MessageSubType = 'chat') and (WhatsAppData.DataType = 'chat') then
        begin
          // This is the initial chat list response, populate list of muted contacts
          // {"method":"socket_in","data":["response",{"type":"chat"},[["chat",{"jid":"000000000000@c.us","count":"0","t":"1555698965","mute":"0","spam":"false"},null], ...

          FLog.Debug('Received initial chat list, reading muted chats');

          FMutedChats.Clear;

          for JSONEnum in TJSONArray(JSONData.FindPath('[2]')) do
          begin
            JSONArray := TJSONArray(JSONEnum.Value);

            if (JSONArray[1].FindPath('mute').Value <> 0) then
            begin
              FLog.Debug('  %s is muted'.Format([JSONArray[1].FindPath('jid').Value]));

              FMutedChats.Add(JSONArray[1].FindPath('jid').Value);
            end;
          end;
        end else if (WhatsAppData.MessageType = 'action') and (WhatsAppData.DataType = 'read') then
        begin
          // A message was read on mobile
          // {"method":"socket_in","data":["action",null,[["read",{"jid":"0000000000000@c.us"},null]]]}

          FLog.Debug('Received message read action');

          PostMessage(FMMFLauncher.WhatsAppWindowHandle, WM_CHAT, WC_READ, 0);
        end else if (WhatsAppData.MessageType = 'action') and (WhatsAppData.DataType = 'chat') and (WhatsAppData.DataSubType = 'mute') then
        begin
          // A contact was muted/unmuted on mobile, mute -1 is forever, 0 is unmuted, otherwise it's the expiration timestamp
          // {"method":"socket_in","data":["action",null,[["chat",{"jid":"0000000000000@c.us","type":"mute","mute":"0"},null]]]}

          if JSONData.FindPath('[2][0][1].mute').Value <> '0' then
          begin
            FLog.Debug('%s was muted'.Format([JSONData.FindPath('[2][0][1].jid').Value]));

            if not FMutedChats.Contains(JSONData.FindPath('[2][0][1].jid').Value) then
              FMutedChats.Add(JSONData.FindPath('[2][0][1].jid').Value);
          end else
          begin
            FLog.Debug('%s was unmuted'.Format([JSONData.FindPath('[2][0][1].jid').Value]));

            FMutedChats.Remove(JSONData.FindPath('[2][0][1].jid').Value);
          end;
        end;
      end else if JSONObject.Strings['method'] = 'socket_out' then
      begin
        if (WhatsAppData.MessageType = 'action') and (WhatsAppData.MessageSubType = 'set') then
        begin
          if WhatsAppData.DataType = 'presence' then
          begin
            if FMMFLauncher.SuppressPresenceAvailable and (WhatsAppData.DataSubType = 'available') then
              FWAMethodResult := TJSONBoolean.Create(False)
            else if FMMFLauncher.SuppressPresenceComposing and (WhatsAppData.DataSubType = 'composing') then
              FWAMethodResult := TJSONBoolean.Create(False);
          end else if (WhatsAppData.DataType = 'chat') and (WhatsAppData.DataSubType = 'mute') then
          begin
            // "mute" specifies the expiration time of the mute (-1 means forever), if "mute" is not set then a contact was unmuted
            if Assigned(JSONData.FindPath('[2][0][1].mute')) then
            begin
              // A contact was muted
              // {"method":"socket_out","data":["action",{"type":"set","epoch":"4"},[["chat",{"type":"mute","mute":"1614750129","jid":"0000000000000@c.us"},null]]]}

              FLog.Debug('%s was muted'.Format([JSONData.FindPath('[2][0][1].jid').Value]));

              if not FMutedChats.Contains(JSONData.FindPath('[2][0][1].jid').Value) then
                FMutedChats.Add(JSONData.FindPath('[2][0][1].jid').Value);
            end else
            begin
              // A contact was unmuted
              // {"method":"socket_out","data":["action",{"type":"set","epoch":"3"},[["chat",{"type":"mute","previous":"1614749783","jid":"0000000000000@c.us"},null]]]}

              FLog.Debug('%s was unmuted'.Format([JSONData.FindPath('[2][0][1].jid').Value]));

              FMutedChats.Remove(JSONData.FindPath('[2][0][1].jid').Value);
            end;
          end;
        end;

        if not Assigned(FWAMethodResult) then
          FWAMethodResult := TJSONBoolean.Create(True)
        else
          FLog.Debug('  Suppressing data');
      end else if JSONObject.Strings['method'] = 'message' then
      begin
        // A chat message was sent/received
        // {"method":"message","data":{"sent":false,"jid":"0000000000000@c.us"}}

        FLog.Debug('Received chat message');

        if JSONData.FindPath('sent').AsBoolean then
        begin
          PostMessage(FMMFLauncher.WhatsAppWindowHandle, WM_CHAT, WC_READ, 0);
        end else if not FMutedChats.Contains(JSONData.FindPath('jid').Value) then
        begin
          PostMessage(FMMFLauncher.WhatsAppWindowHandle, WM_CHAT, WC_RECEIVED, 0);
        end;
      end else if JSONObject.Strings['method'] = 'ask_notification_sound' then
      begin
        // WhatsApp is about to play the notification sound for a received message
        // {"method":"ask_notification_sound","data":"0000000000000@c.us"}

        FLog.Debug('Found received message notification');

        if FMMFLauncher.SuppressConsecutiveNotificationSounds then
          for JID in FMMFLauncher.JIDMessageTimes.Keys do
            if (JSONData.Value = JID) and (FMMFLauncher.JIDMessageTimes[JID] > GetTickCount64 - 60000) and (FMMFLauncher.JIDMessageTimes[JID] <= GetTickCount64) then
            begin
              FWAMethodResult := TJSONBoolean.Create(False);
              Break;
            end;

        if not Assigned(FWAMethodResult) then
          FWAMethodResult := TJSONBoolean.Create(True);

        FMMFLauncher.JIDMessageTimes.AddOrSetValue(JSONData.Value, GetTickCount64);

        FMMFLauncher.Write;
      end;
    finally
      JSONObject.Free;
    end;

    lpNumberOfBytesWritten^ := nNumberOfBytesToWrite;

    Exit(True);
  end else if (FWACommunicationHandle = 0) and (hFile <> FLog.Handle) then
  begin
    P := lpBuffer;
    while P < lpBuffer + (nNumberOfBytesToWrite - (Length(MessageRead) * 2) - 1) do
    begin
      if CompareMem(P, MessageRead, Length(MessageRead) * 2) then
      begin
        FLog.Debug('WriteFile(): Found message read command');

        // Since WhatsAppWindowHandle is not known on MMF creation we might have to read it again
        if FMMFLauncher.WhatsAppWindowHandle = 0 then
          FMMFLauncher.Read;

        PostMessage(FMMFLauncher.WhatsAppWindowHandle, WM_CHAT, WC_READ, 0);

        Break;
      end;
      Inc(P);
    end;
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

class function THooks.HRoGetActivationFactory(activatableClassId: HSTRING; const iid: TGUID; out outfactory: LPVOID): HRESULT; stdcall;
begin
  if (FWACommunicationHandle = 0) and (iid.ToString = '{04124B20-82C6-4229-B109-FD9ED4662B53}') then
  begin
    FLog.Info('RoGetActivationFactory(): Creating notification factory');

    // Since WhatsAppWindowHandle is not known on MMF creation we might have to read it again
    if FMMFLauncher.WhatsAppWindowHandle = 0 then
      FMMFLauncher.Read;

    PostMessage(FMMFLauncher.WhatsAppWindowHandle, WM_CHAT, WC_RECEIVED, 0);
  end;

  Result := ORoGetActivationFactory(activatableClassId, iid, outfactory);
end;

end.
