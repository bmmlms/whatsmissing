unit Log;

interface

uses
  Constants,
  Functions,
  Paths,
  SysUtils,
  Windows;

type
  TLog = class
  private
    FFileName: string;
    FHandle: THandle;
    procedure Write(const Msg: string);
  public
    constructor Create(const Filename: string); overload;
    constructor Create(const Handle: THandle); overload;
    destructor Destroy; override;
    procedure Info(const Msg: string);
    procedure Debug(const Msg: string);
    procedure Error(const Msg: string);

    property FileName: string read FFileName;
    property Handle: THandle read FHandle;
  end;

implementation

{ TLog }

constructor TLog.Create(const FileName: string);
var
  W: Cardinal;
  Handle: THandle;
begin
  if FHandle <> 0 then
    raise Exception.Create('FHandle <> 0');

  FFileName := FileName;
  Handle := TFunctions.CreateFile(FileName, FILE_APPEND_DATA, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if Handle = INVALID_HANDLE_VALUE then
    raise Exception.Create(Format('Error opening log file "%s"', [FileName]));
  if GetLastError <> ERROR_ALREADY_EXISTS then
    WriteFile(Handle, UTF8_BOM[0], Length(UTF8_BOM), W, nil);
  SetHandleInformation(Handle, HANDLE_FLAG_INHERIT, 1);
  FHandle := Handle;
end;

constructor TLog.Create(const Handle: THandle);
begin
  if FHandle <> 0 then
    raise Exception.Create('FHandle <> 0');

  FHandle := Handle;
end;

destructor TLog.Destroy;
begin
  CloseHandle(FHandle);

  inherited;
end;

procedure TLog.Debug(const Msg: string);
begin
  Write(Format('%s - %s', ['DEBUG', Msg]));
end;

procedure TLog.Info(const Msg: string);
begin
  Write(Format('%s - %s', ['INFO', Msg]));
end;

procedure TLog.Error(const Msg: string);
begin
  Write(Format('%s - %s', ['ERROR', Msg]));
end;

procedure TLog.Write(const Msg: string);
var
  W: Cardinal;
  Bytes: TBytes;
begin
  if (FHandle = 0) or (FHandle = INVALID_HANDLE_VALUE) then
    raise Exception.Create('Log file not opened');

  Bytes := TEncoding.UTF8.GetBytes(Format('%s - %s [%d] - %s'#13#10, [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), ExtractFileName(TPaths.ExePath.ToUpper), GetCurrentProcessId, Msg]));

  WriteFile(FHandle, Bytes[0], Length(Bytes), W, nil);
end;

end.
