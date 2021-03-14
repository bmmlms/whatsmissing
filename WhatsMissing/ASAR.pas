unit ASAR;

interface

uses
  Classes,
  fpjson,
  Generics.Collections,
  StrUtils,
  SysUtils;

type

  { TASARHeader }

  TASARHeader = class
  private
    FData: TJSONObject;
    FContentOffset: Cardinal;
  public
    constructor Create; overload;
    constructor Create(const Data: TJSONObject); overload;
    destructor Destroy; override;

    procedure Read(Stream: TStream);
    procedure Write(Stream: TStream);

    property Data: TJSONObject read FData;
    property ContentOffset: Cardinal read FContentOffset;
  end;

  TASAR = class;
  TASARDir = class;
  TASARFile = class;

  TASAREntry = class
    abstract
  private
    FName: string;
    FParent: TASARDir;
  protected
    FASAR: TASAR;
  public
    constructor Create(const ASAR: TASAR; const Parent: TASARDir; const Name: string); virtual;

    property Name: string read FName;
  end;

  { TASARDir }

  TASARDir = class(TASAREntry)
  private
    FChildren: TList<TASAREntry>;
  public
    constructor Create(const ASAR: TASAR; const Parent: TASARDir; const Name: string); override;
    destructor Destroy; override;

    function WriteJSON(const Parent: TJSONObject): TJSONObject;
    function FindEntry(const Name: string; T: TClass): TASAREntry;
    procedure RemoveFile(const F: TASARFile);
  end;

  TASARFile = class(TASAREntry)
  private
    FJSONObject: TJSONObject;
    FSize: Cardinal;
    FOffset: Cardinal;
    FExecutable: Boolean;
    FUnpacked: Boolean;
    FContents: TMemoryStream;
    FNewFile: Boolean;

    function FGetSize: Cardinal;
    function FGetContents: TMemoryStream;
    procedure FSetContents(const Value: TMemoryStream);
  public
    constructor Create(const ASAR: TASAR; const Parent: TASARDir; const Name: string); overload; override;
    constructor Create(const ASAR: TASAR; const Parent: TASARDir; const Name: string; const JSONObject: TJSONObject); overload;
    destructor Destroy; override;

    procedure WriteJSON(const Parent: TJSONObject; const Offset: Cardinal);
    function WriteContents(const Offset, DataOffset: Cardinal; const Dest: TMemoryStream): Cardinal;

    property JSONObject: TJSONObject read FJSONObject;
    property Size: Cardinal read FGetSize;
    property Contents: TMemoryStream read FGetContents write FSetContents;
  end;

  TReadInfo = class
  private
    FKeyName: string;
    FDir: TASARDir;
    FJSONObject: TJSONObject;
  public
    constructor Create(const Dir: TASARDir; const KeyName: string; const JSONObject: TJSONObject);

    property KeyName: string read FKeyName;
    property Dir: TASARDir read FDir;
    property JSONObject: TJSONObject read FJSONObject;
  end;

  TWriteInfo = class
  private
    FEntry: TASAREntry;
    FJSONObject: TJSONObject;
  public
    constructor Create(const Entry: TASAREntry; const JSONObject: TJSONObject);

    property Entry: TASAREntry read FEntry;
    property JSONObject: TJSONObject read FJSONObject;
  end;

  TASAR = class
  private
    FContents: TMemoryStream;

    FHeader: TASARHeader;

    FRoot: TASARDir;

    function FGetSize: Cardinal;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Read(const FileName: string);
    procedure Write(const FileName: string);

    property Header: TASARHeader read FHeader;

    property Root: TASARDir read FRoot;

    property Size: Cardinal read FGetSize;
  end;

implementation

 { TASARHeader }

constructor TASARHeader.Create;
begin

end;

constructor TASARHeader.Create(const Data: TJSONObject);
begin
  FData := Data;
end;

destructor TASARHeader.Destroy;
begin
  if Assigned(FData) then
    FData.Free;

  inherited Destroy;
end;

procedure TASARHeader.Read(Stream: TStream);
var
  PickleLen, IndexLen, JSONLen: UInt32;
  JSONString: AnsiString;
begin
  if Assigned(FData) then
    FData.Free;

  Stream.ReadBuffer(PickleLen, SizeOf(UInt32)); // Length of first pickle
  Stream.ReadBuffer(IndexLen, SizeOf(UInt32));  // Value of first pickle
  Stream.ReadBuffer(PickleLen, SizeOf(UInt32)); // Length of second pickle
  Stream.ReadBuffer(JSONLen, SizeOf(UInt32));   // Length of JSON data

  FContentOffset := SizeOf(UInt32) * 2 + IndexLen;

  SetLength(JSONString, JSONLen);
  Stream.Read(JSONString[1], JSONLen);
  FData := TJSONObject(GetJSON(JSONString, False));
end;

procedure TASARHeader.Write(Stream: TStream);
var
  WriteInt: UInt32;
  JSONString: AnsiString;
begin
  FData.CompressedJSON := True;
  JSONString := FData.AsJSON;

  // Length of first pickle
  WriteInt := 4;
  Stream.Write(WriteInt, SizeOf(WriteInt));

  // Value of first pickle
  WriteInt := 4 + 4 + JSONString.Length;
  Stream.Write(WriteInt, SizeOf(WriteInt));

  // Length of second pickle
  WriteInt := 4 + JSONString.Length;
  Stream.Write(WriteInt, SizeOf(WriteInt));

  // Length of JSON data
  WriteInt := JSONString.Length;
  Stream.Write(WriteInt, SizeOf(WriteInt));

  Stream.Write(JSONString[1], JSONString.Length);
end;

{ TASAREntry }

constructor TASAREntry.Create(const ASAR: TASAR; const Parent: TASARDir; const Name: string);
begin
  FASAR := ASAR;
  FParent := Parent;
  FName := Name;
  if Assigned(Parent) then
    Parent.FChildren.Add(Self);
end;

{ TASARDir }

constructor TASARDir.Create(const ASAR: TASAR; const Parent: TASARDir; const Name: string);
begin
  inherited;

  FChildren := TList<TASAREntry>.Create;
end;

destructor TASARDir.Destroy;
var
  ASAREntry: TASAREntry;
begin
  for ASAREntry in FChildren do
    ASAREntry.Free;

  FChildren.Free;

  inherited;
end;

function TASARDir.FindEntry(const Name: string; T: TClass): TASAREntry;
var
  Idx: Integer;
  SearchList: TList<TASAREntry>;
  ASAREntry: TASAREntry;
begin
  Result := nil;
  SearchList := TList<TASAREntry>.Create;
  SearchList.Add(Self);
  try
    Idx := 0;
    while Idx < SearchList.Count do
    begin
      if IsWild(SearchList[Idx].Name, Name, True) and (SearchList[Idx].ClassType = T) then
        Exit(SearchList[Idx]);

      if (SearchList[Idx].ClassType = TASARDir) then
        for ASAREntry in (TASARDir(SearchList[Idx])).FChildren do
          SearchList.Add(ASAREntry);

      Inc(Idx);
    end;
  finally
    SearchList.Free;
  end;
end;

procedure TASARDir.RemoveFile(const F: TASARFile);
begin
  FChildren.Remove(F);
end;

function TASARDir.WriteJSON(const Parent: TJSONObject): TJSONObject;
var
  JSONDir, JSONFiles: TJSONObject;
begin
  if Trim(FName) = '' then
    raise Exception.Create('Trim(FName) = ''''');

  JSONDir := TJSONObject.Create;
  JSONFiles := TJSONObject.Create;

  JSONDir.Add('files', JSONFiles);

  Parent.Add(FName, JSONDir);

  Result := JSONFiles;
end;

{ TASARFile }

constructor TASARFile.Create(const ASAR: TASAR; const Parent: TASARDir; const Name: string);
begin
  inherited;

  FNewFile := True;
end;

constructor TASARFile.Create(const ASAR: TASAR; const Parent: TASARDir; const Name: string; const JSONObject: TJSONObject);
begin
  inherited Create(ASAR, Parent, Name);

  FJSONObject := JSONObject;;
  FSize := JSONObject.Get('size', 0);
  FOffset := StrToInt(JSONObject.Get('offset', '0'));
  FExecutable := JSONObject.Get('executable', False);
  FUnpacked := JSONObject.Get('unpacked', False);
end;

destructor TASARFile.Destroy;
begin
  if Assigned(FContents) then
    FContents.Free;

  inherited;
end;

function TASARFile.FGetContents: TMemoryStream;
begin
  if FUnpacked then
    raise Exception.Create('FUnpacked');

  if Assigned(FContents) then
    Exit(FContents);

  FContents := TMemoryStream.Create;

  if FSize > 0 then
  begin
    FASAR.FContents.Position := FASAR.FHeader.ContentOffset + FOffset;
    FContents.CopyFrom(FASAR.FContents, FSize);
    FContents.Position := 0;
  end;

  Result := FContents;
end;

function TASARFile.FGetSize: Cardinal;
begin
  if FContents = nil then
    Result := FSize
  else
    Result := FContents.Size;
end;

procedure TASARFile.FSetContents(const Value: TMemoryStream);
begin
  if FUnpacked then
    raise Exception.Create('FUnpacked');

  if Assigned(FContents) then
    FContents.Free;

  FContents := Value;
end;

procedure TASARFile.WriteJSON(const Parent: TJSONObject; const Offset: Cardinal);
var
  JSONFile: TJSONObject;
begin
  if Trim(FName) = '' then
    raise Exception.Create('Trim(FName) = ''''');

  if not Assigned(FContents) and FNewFile then
    raise Exception.Create('not Assigned(FContents) and FNewFile');

  JSONFile := TJSONObject.Create;

  JSONFile.Add('size', Size);
  if not FUnpacked then
    JSONFile.Add('offset', IntToStr(Offset));
  if FExecutable then
    JSONFile.Add('executable', FExecutable);
  if FUnpacked then
    JSONFile.Add('unpacked', FUnpacked);

  Parent.Add(FName, JSONFile);
end;

function TASARFile.WriteContents(const Offset, DataOffset: Cardinal; const Dest: TMemoryStream): Cardinal;
var
  OldPos: Cardinal;
begin
  Result := Offset;

  if (Size > 0) and (not FUnpacked) then
    if Assigned(FContents) then
    begin
      OldPos := FContents.Position;
      FContents.Position := 0;
      Dest.CopyFrom(FContents, FContents.Size);
      FContents.Position := OldPos;
      Exit(Offset + FContents.Size);
    end else
    begin
      FASAR.FContents.Position := DataOffset + FOffset;
      Dest.CopyFrom(FASAR.FContents, FSize);
      Result := Offset + Size;
    end;
end;

{ TReadInfo }

constructor TReadInfo.Create(const Dir: TASARDir; const KeyName: string; const JSONObject: TJSONObject);
begin
  FKeyName := KeyName;
  FDir := Dir;
  FJSONObject := JSONObject;
end;

{ TWriteInfo }

constructor TWriteInfo.Create(const Entry: TASAREntry; const JSONObject: TJSONObject);
begin
  FEntry := Entry;
  FJSONObject := JSONObject;
end;

{ TASAR }

constructor TASAR.Create;
begin
  FHeader := TASARHeader.Create;
  FContents := TMemoryStream.Create;
end;

destructor TASAR.Destroy;
begin
  if Assigned(FRoot) then
    FRoot.Free;

  FContents.Free;
  FHeader.Free;

  inherited;
end;

function TASAR.FGetSize: Cardinal;
begin
  Result := FContents.Size;
end;

procedure TASAR.Read(const FileName: string);
var
  i, Idx: Integer;
  DirObj: TASARDir;
  ReadInfo: TReadInfo;
  Items: TList<TReadInfo>;
  Root: TJSONObject;
begin
  FContents.LoadFromFile(FileName);

  Items := TList<TReadInfo>.Create;
  try
    if Assigned(FRoot) then
      FRoot.Free;

    FRoot := TASARDir.Create(Self, nil, '');
    try
      FContents.Position := 0;
      FHeader.Read(FContents);

      Root := TJSONObject(FHeader.Data.Items[0]);
      for i := 0 to Root.Count - 1 do
        Items.Add(TReadInfo.Create(FRoot, Root.Names[i], TJSONObject(Root.Items[i])));

      Idx := 0;
      while Idx < Items.Count do
      begin
        ReadInfo := TReadInfo(Items[Idx]);

        if (ReadInfo.JSONObject.Count = 1) and (ReadInfo.JSONObject.Names[0] = 'files') then
        begin
          DirObj := TASARDir.Create(Self, ReadInfo.Dir, ReadInfo.KeyName);

          for i := 0 to TJSONObject(ReadInfo.JSONObject.Items[0]).Count - 1 do
            Items.Add(TReadInfo.Create(DirObj, TJSONObject(ReadInfo.JSONObject.Items[0]).Names[i], TJSONObject(ReadInfo.JSONObject.Items[0].Items[i])));
        end else
          TASARFile.Create(Self, ReadInfo.Dir, ReadInfo.KeyName, ReadInfo.JSONObject);

        Inc(Idx);
      end;
    except
      FreeAndNil(FRoot);
      raise;
    end;
  finally
    for ReadInfo in Items do
      ReadInfo.Free;

    Items.Free;
  end;
end;

procedure TASAR.Write(const FileName: string);
var
  Idx, Offset: Integer;
  JSONObject, JSONFiles: TJSONObject;
  Dest, DestContents: TMemoryStream;
  Items: TList<TWriteInfo>;
  WriteInfo: TWriteInfo;
  ASAREntry: TASAREntry;
  ASARDir: TASARDir;
  ASARFile: TASARFile;
  FileDir: string;
  Header: TASARHeader;
begin
  Offset := 0;

  Dest := TMemoryStream.Create;
  DestContents := TMemoryStream.Create;

  JSONObject := TJSONObject.Create;

  JSONFiles := TJSONObject.Create;
  JSONObject.Add('files', JSONFiles);

  Items := TList<TWriteInfo>.Create;

  try
    for ASAREntry in FRoot.FChildren do
      Items.Add(TWriteInfo.Create(ASAREntry, JSONFiles));

    Idx := 0;
    while Idx < Items.Count do
    begin
      if Items[Idx].FEntry.ClassType = TASARDir then
      begin
        ASARDir := TASARDir(Items[Idx].Entry);

        JSONFiles := ASARDir.WriteJSON(Items[Idx].JSONObject);

        for ASAREntry in ASARDir.FChildren do
          Items.Add(TWriteInfo.Create(ASAREntry, JSONFiles));
      end else if Items[Idx].Entry.ClassType = TASARFile then
      begin
        ASARFile := TASARFile(Items[Idx].Entry);

        ASARFile.WriteJSON(Items[Idx].JSONObject, Offset);

        Offset := ASARFile.WriteContents(Offset, FHeader.ContentOffset, DestContents);
      end;

      Inc(Idx);
    end;

    Header := TASARHeader.Create(JSONObject);
    try
      Header.Write(Dest);
    finally
      Header.Free;
    end;

    DestContents.Position := 0;
    Dest.CopyFrom(DestContents, DestContents.Size);

    FileDir := ExtractFileDir(FileName);
    if not DirectoryExists(FileDir) then
      if not CreateDir(FileDir) then
        raise Exception.Create('Could not create directory "%s"'.Format([FileDir]));

    Dest.SaveToFile(FileName);
  finally
    Dest.Free;
    DestContents.Free;

    JSONObject.Free;

    for WriteInfo in Items do
      WriteInfo.Free;

    Items.Free;
  end;
end;

end.
