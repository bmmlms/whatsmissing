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
  W: Cardinal = 0;
begin
  FFileName := FileName;
  FHandle := TFunctions.CreateFile(FileName, FILE_APPEND_DATA, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if GetLastError <> ERROR_ALREADY_EXISTS then
    WriteFile(FHandle, UTF8_BOM[0], Length(UTF8_BOM), W, nil);
end;

destructor TLog.Destroy;
begin
  CloseHandle(FHandle);

  inherited;
end;

procedure TLog.Debug(const Msg: string);
begin
  Write('%s - %s'.Format(['DEBUG', Msg]));
end;

procedure TLog.Info(const Msg: string);
begin
  Write('%s - %s'.Format(['INFO', Msg]));
end;

procedure TLog.Error(const Msg: string);
begin
  Write('%s - %s'.Format(['ERROR', Msg]));
end;

procedure TLog.Write(const Msg: string);
var
  W: Cardinal = 0;
  Bytes: TBytes;
begin
  if FHandle = 0 then
    raise Exception.Create('Log file not opened');

  Bytes := TEncoding.UTF8.GetBytes('%s - %s [%d] - %s'#13#10.Format([FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), ExtractFileName(TPaths.ExePath.ToUpper), GetCurrentProcessId, Msg]));

  WriteFile(FHandle, Bytes[0], Length(Bytes), W, nil);
end;

end.
