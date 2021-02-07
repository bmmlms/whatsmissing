unit ProcessMonitor;

interface

uses
  Classes,
  Functions,
  Generics.Collections,
  SysUtils,
  Windows;

type
  TProcess = record
    Handle: THandle;
    Id: Cardinal;
    ExePath: string;

    constructor Create(const Handle: THandle; const Id: Cardinal; const ExePath: string);
  end;

  TProcessExited = procedure(const Sender: TObject; const ExePath: string; const Remaining: Integer) of object;

  TProcessMonitor = class(TThread)
  private
    FCriticalSection: TCriticalSection;
    FReloadEvent: THandle;
    FProcesses: TList<TProcess>;

    FOnProcessExited: TProcessExited;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddProcessId(const ProcessId: Cardinal);
    procedure Terminate;

    property OnProcessExited: TProcessExited read FOnProcessExited write FOnProcessExited;
  end;

implementation

{ TProcessMonitor }

constructor TProcessMonitor.Create;
begin
  inherited Create(True);

  InitializeCriticalSection(FCriticalSection);
  FReloadEvent := CreateEvent(nil, False, False, nil);
  FProcesses := TList<TProcess>.Create;
end;

destructor TProcessMonitor.Destroy;
var
  Process: TProcess;
begin
  for Process in FProcesses do
    CloseHandle(Process.Handle);
  FProcesses.Free;

  CloseHandle(FReloadEvent);
  DeleteCriticalSection(FCriticalSection);

  inherited;
end;

procedure TProcessMonitor.AddProcessId(const ProcessId: Cardinal);
var
  Handle: THandle;
begin
  Handle := OpenProcess(Windows.SYNCHRONIZE or PROCESS_QUERY_INFORMATION, False, ProcessId);
  if Handle = 0 then
    Exit;

  EnterCriticalSection(FCriticalSection);
  try
    FProcesses.Add(TProcess.Create(Handle, ProcessId, TFunctions.GetExePath(Handle)));
  finally
    LeaveCriticalSection(FCriticalSection);
  end;

  SetEvent(FReloadEvent);
end;

procedure TProcessMonitor.Terminate;
begin
  inherited;

  SetEvent(FReloadEvent);
end;

procedure TProcessMonitor.Execute;
var
  i: Integer;
  Process: TProcess;
  WaitRes: Cardinal;
  WaitHandles: TWOHandleArray;
begin
  inherited;

  while not Terminated do
  begin
    WaitHandles[0] := FReloadEvent;

    EnterCriticalSection(FCriticalSection);
    try
      for i := 0 to FProcesses.Count - 1 do
        WaitHandles[i + 1] := FProcesses[i].Handle;
    finally
      LeaveCriticalSection(FCriticalSection);
    end;

    WaitRes := WaitForMultipleObjects(FProcesses.Count + 1, @WaitHandles, False, INFINITE);

    if (WaitRes > WAIT_OBJECT_0) and (WaitRes < WAIT_OBJECT_0 + Length(WaitHandles)) then
    begin
      Process := FProcesses[WaitRes - 1];

      CloseHandle(Process.Handle);
      FProcesses.Delete(WaitRes - 1);

      if (not Terminated) and Assigned(FOnProcessExited) then
        FOnProcessExited(Self, Process.ExePath, FProcesses.Count);
    end;
  end;
end;

{ TProcess }

constructor TProcess.Create(const Handle: THandle; const Id: Cardinal; const ExePath: string);
begin
  Self.Handle := Handle;
  Self.Id := Id;
  Self.ExePath := ExePath;
end;

end.
