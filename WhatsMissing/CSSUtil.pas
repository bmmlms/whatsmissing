unit CSSUtil;

interface

uses
  Classes,
  Constants,
  Generics.Collections,
  SysUtils;

type
  TChars = set of Char;

  { TCSSValue }

  TCSSValue = class
  private
    FMemory: PAnsiChar;
    FSize: Integer;
    FValue: AnsiString;
    FModified: Boolean;

    function FGetValue: AnsiString;
    procedure FSetValue(const Value: AnsiString);
  public
    constructor Create(const MemStart, MemEnd: PAnsiChar);

    function ValueEquals(Value: AnsiString): Boolean;

    property Value: AnsiString read FGetValue write FSetValue;
    property Modified: Boolean read FModified;
  end;

  { TCSSDeclaration }

  TCSSDeclaration = class
  private
    FProp: TCSSValue;
    FValue: TCSSValue;
  public
    constructor Create(const Prop: TCSSValue; const Value: TCSSValue); overload;
    constructor Create(const Prop: string; const Value: string); overload;
    destructor Destroy; override;

    property Prop: TCSSValue read FProp;
    property Value: TCSSValue read FValue;
  end;

  { TCSSRule }

  TCSSRule = class
  private
    FSelectors: TList<TCSSValue>;
    FDeclarations: TList<TCSSDeclaration>;
  public
    constructor Create;
    destructor Destroy; override;

    function FindDeclarationByProp(const Prop: string): TCSSDeclaration;

    property Selectors: TList<TCSSValue> read FSelectors;
    property Declarations: TList<TCSSDeclaration> read FDeclarations;
  end;

  { TCSSMediaQuery }

  TCSSMediaQuery = class
  private
    FQuery: TCSSValue;
    FRules: TList<TCSSRule>;
  public
    constructor Create;
    destructor Destroy; override;

    property Query: TCSSValue read FQuery;
    property Rules: TList<TCSSRule> read FRules;
  end;

  { TCSSDocument }

  TCSSDocument = class
  private
    FMemStart, FMemEnd, FMemPtr: PAnsiChar;
    FRules: TList<TCSSRule>;
    FMediaQueries: TList<TCSSMediaQuery>;

    procedure Seek(out FirstValid, LastValid: PAnsiChar; const StartChars, ValidChars, StopChars: TChars);
    procedure SkipChars(const Chars: TChars);
    procedure SkipComment;

    procedure Read;
    function ReadValue(StartChars, ValidChars, StopChars: TChars): TCSSValue;
    function ReadRule: TCSSRule;
    function ReadDeclaration: TCSSDeclaration;
    function ReadDeclarationValue: TCSSValue;
    function ReadMediaQuery: TCSSMediaQuery;

    procedure WriteValue(const Value: TCSSValue; const Stream: TMemoryStream);
    procedure WriteRule(const Rule: TCSSRule; const Stream: TMemoryStream);
    procedure WriteDeclaration(const Declaration: TCSSDeclaration; const Stream: TMemoryStream);
    procedure WriteMediaQuery(const MediaQuery: TCSSMediaQuery; const Stream: TMemoryStream);
  public
    class function Read(const Stream: TMemoryStream): TCSSDocument;

    constructor Create(const Stream: TMemoryStream);
    destructor Destroy; override;

    function FindRule(const SingleSelector: string): TCSSRule;
    function FindDeclarationValue(const SingleSelector: string; const DeclarationProp: string): TCSSValue;
    function SetDeclarationValuesByValue(const OldValue, NewValue: string): Integer;
    function GetVariableValue(const Variable: string): string;
    procedure Write(const Stream: TMemoryStream);

    property Rules: TList<TCSSRule> read FRules;
    property MediaQueries: TList<TCSSMediaQuery> read FMediaQueries;
  end;

implementation

const
  Comma = ',';
  Comment = '/*';
  BlockStart = '{';
  BlockEnd = '}';
  FuncStart = '(';
  FuncEnd = ')';
  DeclarationSep = ':';
  DeclarationEnd = ';';
  MediaQueryStart = '@';
  Selector = ['*', '#', '''', '.', '_', '-', '<', '>', '[', '=', ']', '+', 'a' .. 'z', 'A' .. 'Z', '0'..'9', ':', '(', ')', '%'];
  Whitespace = [#13, #10, ' '];
  DeclarationProp = ['-', 'a' .. 'z', 'A' .. 'Z', '0'..'9'];
  Printable = [#32 .. #126];

{ TCSSDocument }

function TCSSDocument.ReadDeclarationValue: TCSSValue;
var
  F, T: PAnsiChar;
  L: Integer = 0;
  FF: PAnsiChar = nil;
  FT: PAnsiChar = nil;
begin
  while FMemPtr < FMemEnd do
  begin
    Seek(F, T, Printable - [DeclarationEnd, BlockEnd] - Whitespace, Printable - [DeclarationEnd, BlockEnd], [DeclarationEnd, BlockEnd, FuncStart, FuncEnd]);

    if not Assigned(FF) then
      FF := F;
    if Assigned(T) then
      FT := T;

    case FMemPtr^ of
      FuncStart:
        Inc(L);
      FuncEnd:
        Dec(L);
      DeclarationEnd, BlockEnd:
        if L = 0 then
          Exit(TCSSValue.Create(FF, FT));
    end;

    Inc(FMemPtr);
  end;

  raise Exception.Create('ReadDeclarationValue(): EOF');
end;

procedure TCSSDocument.Seek(out FirstValid, LastValid: PAnsiChar; const StartChars, ValidChars, StopChars: TChars);
var
  C: TChars;
begin
  FirstValid := nil;
  LastValid := nil;

  C := StartChars + ValidChars + Whitespace + [#128..#255];

  while FMemPtr < FMemEnd do
  begin
    if not Assigned(FirstValid) and (FMemPtr^ in StartChars) then
    begin
      FirstValid := FMemPtr;
      LastValid := FMemPtr;
    end else if Assigned(FirstValid) and (FMemPtr^ in ValidChars) then
      LastValid := FMemPtr;

    if FMemPtr^ in StopChars then
      Exit
    else if not (FMemPtr^ in C) then
      raise Exception.Create('Seek(): Invalid char');

    Inc(FMemPtr);
  end;

  raise Exception.Create('Seek(): EOF');
end;

function TCSSDocument.ReadDeclaration: TCSSDeclaration;
var
  Prop: TCSSValue;
  Value: TCSSValue;
begin
  Prop := ReadValue(DeclarationProp, DeclarationProp, [DeclarationSep]);

  Inc(FMemPtr);

  Value := ReadDeclarationValue;

  if FMemPtr^ = DeclarationEnd then
    Inc(FMemPtr);

  Exit(TCSSDeclaration.Create(Prop, Value));
end;

function TCSSDocument.ReadRule: TCSSRule;
begin
  Result := TCSSRule.Create;

  while (FMemPtr < FMemEnd) and (FMemPtr^ <> BlockStart) do
  begin
    Result.FSelectors.Add(ReadValue(Selector, Selector, [Comma] + [BlockStart]));
    if FMemPtr^ = Comma then
      Inc(FMemPtr);
  end;

  Inc(FMemPtr);

  while (FMemPtr < FMemEnd) and (FMemPtr^ <> BlockEnd) do
  begin
    Result.FDeclarations.Add(ReadDeclaration);
    SkipChars(Whitespace);
  end;

  if FMemPtr^ <> BlockEnd then
    raise Exception.Create('ReadRule(): EOF');

  Inc(FMemPtr);
end;

function TCSSDocument.ReadMediaQuery: TCSSMediaQuery;
begin
  Result := TCSSMediaQuery.Create;

  Result.FQuery := ReadValue([MediaQueryStart], Printable - [BlockStart, DeclarationEnd], [BlockStart] + [DeclarationEnd]);

  if FMemPtr^ = DeclarationEnd then
  begin
    Inc(FMemPtr);

    // This is something like @charset "UTF-8"; we don't want.
    Result.Free;
    Exit(nil);
  end;

  Inc(FMemPtr);

  while (FMemPtr < FMemEnd) and (FMemPtr^ <> BlockEnd) do
  begin
    Result.FRules.Add(ReadRule);
    SkipChars(Whitespace);
  end;

  if FMemPtr^ <> BlockEnd then
    raise Exception.Create('ReadMediaQuery(): EOF');

  Inc(FMemPtr);
end;

procedure TCSSDocument.WriteValue(const Value: TCSSValue;
  const Stream: TMemoryStream);
begin
  if Value.FModified then
    Stream.Write(Value.FValue[1], Value.FValue.Length)
  else
    Stream.Write(Value.FMemory^, Value.FSize);
end;

procedure TCSSDocument.WriteRule(const Rule: TCSSRule;
  const Stream: TMemoryStream);
var
  Selector: TCSSValue;
  Declaration: TCSSDeclaration;
begin
  for Selector in Rule.FSelectors do
  begin
    WriteValue(Selector, Stream);
    if Selector <> Rule.Selectors.Last then
      Stream.WriteByte(Byte(Comma));
  end;

  Stream.WriteByte(Byte(BlockStart));

  for Declaration in Rule.Declarations do
  begin
    WriteDeclaration(Declaration, Stream);
    if Declaration <> Rule.Declarations.Last then
      Stream.WriteByte(Byte(DeclarationEnd));
  end;

  Stream.WriteByte(Byte(BlockEnd));
end;

procedure TCSSDocument.WriteDeclaration(const Declaration: TCSSDeclaration; const Stream: TMemoryStream);
begin
  WriteValue(Declaration.FProp, Stream);
  Stream.WriteByte(Byte(DeclarationSep));
  WriteValue(Declaration.FValue, Stream);
end;

procedure TCSSDocument.WriteMediaQuery(const MediaQuery: TCSSMediaQuery; const Stream: TMemoryStream);
var
  Rule: TCSSRule;
begin
  WriteValue(MediaQuery.FQuery, Stream);

  Stream.WriteByte(Byte(BlockStart));

  for Rule in MediaQuery.Rules do
    WriteRule(Rule, Stream);

  Stream.WriteByte(Byte(BlockEnd));
end;

constructor TCSSDocument.Create(const Stream: TMemoryStream);
begin
  FMemStart := Stream.Memory;
  FMemEnd := Stream.Memory + Stream.Size;
  FMemPtr := Stream.Memory;

  FRules := TList<TCSSRule>.Create;
  FMediaQueries := TList<TCSSMediaQuery>.Create;
end;

destructor TCSSDocument.Destroy;
var
  Obj: TObject;
begin
  for Obj in FRules do
    Obj.Free;

  for Obj in FMediaQueries do
    Obj.Free;

  FRules.Free;

  inherited Destroy;
end;

function TCSSDocument.FindRule(const SingleSelector: string): TCSSRule;
var
  Rule: TCSSRule;
begin
  Result := nil;

  for Rule in FRules do
    if (Rule.FSelectors.Count = 1) and (Rule.Selectors[0].ValueEquals(SingleSelector)) then
      Exit(Rule);
end;

function TCSSDocument.FindDeclarationValue(const SingleSelector: string; const DeclarationProp: string): TCSSValue;
var
  Rule: TCSSRule;
  Declaration: TCSSDeclaration;
begin
  Result := nil;

  Rule := FindRule(SingleSelector);
  if not Assigned(Rule) then
    Exit;

  Declaration := Rule.FindDeclarationByProp(DeclarationProp);
  if not Assigned(Declaration) then
    Exit;

  Result := Declaration.FValue;
end;

function TCSSDocument.SetDeclarationValuesByValue(const OldValue, NewValue: string): Integer;
var
  Rule: TCSSRule;
  Declaration: TCSSDeclaration;
begin
  Result := 0;

  for Rule in FRules do
    for Declaration in Rule.FDeclarations do
      if Declaration.FValue.ValueEquals(OldValue) then
      begin
        Declaration.Value.Value := NewValue;
        Inc(Result);
      end;
end;

function TCSSDocument.GetVariableValue(const Variable: string): string;
var
  Value: TCSSValue;
begin
  Result := Variable;

  if Variable.StartsWith('var(', True) and Variable.EndsWith(')') then
  begin
    Value := FindDeclarationValue(':root', Variable.Substring(4, Variable.Length - 5));
    if Assigned(Value) then
      Exit(Value.Value);

    raise Exception.Create('Variable not found');
  end;
end;

procedure TCSSDocument.Write(const Stream: TMemoryStream);
var
  Rule: TCSSRule;
  MediaQuery: TCSSMediaQuery;
begin
  Stream.Write(UTF8_BOM[0], Length(UTF8_BOM));

  for Rule in FRules do
    WriteRule(Rule, Stream);

  for MediaQuery in FMediaQueries do
    if not MediaQuery.FQuery.Value.Equals('@charset "UTF-8"') then
      WriteMediaQuery(MediaQuery, Stream);
end;

class function TCSSDocument.Read(const Stream: TMemoryStream): TCSSDocument;
begin
  Result := TCSSDocument.Create(Stream);
  try
    Result.Read;
  except
    Result.Free;
    raise;
  end;
end;

function TCSSDocument.ReadValue(StartChars, ValidChars, StopChars: TChars): TCSSValue;
var
  ValueStart: PAnsiChar = nil;
  ValueEnd: PAnsiChar = nil;
begin
  Seek(ValueStart, ValueEnd, StartChars, ValidChars, StopChars);

  if not Assigned(ValueStart) or not Assigned(ValueEnd) then
    raise Exception.Create('ReadValue(): Failed');

  Exit(TCSSValue.Create(ValueStart, ValueEnd));
end;

procedure TCSSDocument.SkipChars(const Chars: TChars);
begin
  while (FMemPtr^ in Chars) and (FMemPtr < FMemEnd) do
    Inc(FMemPtr);

  if FMemPtr = FMemEnd then
    raise Exception.Create('SkipChars(): EOF');
end;

procedure TCSSDocument.SkipComment;
begin
  if (FMemPtr^ = Comment[1]) and (FMemPtr < FMemEnd) and ((FMemPtr + 1)^ = Comment[2]) then
  begin
    while (FMemPtr < FMemEnd - 1) and not ((FMemPtr^ = Comment[2]) and ((FMemPtr + 1)^ = Comment[1])) do
      Inc(FMemPtr);

    if FMemPtr = FMemEnd - 1 then
      raise Exception.Create('SkipComment(): EOF');

    Inc(FMemPtr, 2);
  end;
end;

procedure TCSSDocument.Read;
var
  MediaQuery: TCSSMediaQuery;
begin
  while FMemPtr < FMemEnd do
  begin
    SkipComment;

    if FMemPtr^ = MediaQueryStart then
    begin
      MediaQuery := ReadMediaQuery;
      if Assigned(MediaQuery) then
        FMediaQueries.Add(MediaQuery);
    end else if FMemPtr^ in Selector then
      FRules.Add(ReadRule)
    else if FMemPtr^ in Whitespace then
      Inc(FMemPtr)
    else
      raise Exception.Create('Read(): Invalid char');
  end;
end;

{ TCSSDeclaration }

constructor TCSSDeclaration.Create(const Prop: TCSSValue; const Value: TCSSValue);
begin
  FProp := Prop;
  FValue := Value;
end;

constructor TCSSDeclaration.Create(const Prop: string; const Value: string);
begin
  FProp := TCSSValue.Create(nil, nil);
  FProp.Value := Prop;
  FValue := TCSSValue.Create(nil, nil);
  FValue.Value := Value;
end;

destructor TCSSDeclaration.Destroy;
begin
  FProp.Free;
  FValue.Free;

  inherited Destroy;
end;

{ TCSSValue }

function TCSSValue.FGetValue: AnsisTring;
begin
  if FModified then
    Exit(FValue)
  else
    SetString(Result, FMemory, FSize);
end;

procedure TCSSValue.FSetValue(const Value: AnsiString);
begin
  FModified := True;
  FValue := Value;
end;

constructor TCSSValue.Create(const MemStart, MemEnd: PAnsiChar);
begin
  FMemory := MemStart;
  FSize := MemEnd - MemStart + 1;
end;

function TCSSValue.ValueEquals(Value: AnsiString): Boolean;
begin
  if FModified then
    Exit(FValue.ToLower = Value.ToLower);

  if FSize <> Value.Length then
    Exit(False);

  Result := strlicomp(PAnsiChar(Value), FMemory, FSize) = 0;
end;

{ TCSSRule }

constructor TCSSRule.Create;
begin
  FSelectors := TList<TCSSValue>.Create;
  FDeclarations := TList<TCSSDeclaration>.Create;
end;

destructor TCSSRule.Destroy;
var
  Selector: TCSSValue;
  Declaration: TCSSDeclaration;
begin
  for Selector in FSelectors do
    Selector.Free;

  FSelectors.Free;

  for Declaration in FDeclarations do
    Declaration.Free;

  FDeclarations.Free;

  inherited Destroy;
end;

function TCSSRule.FindDeclarationByProp(const Prop: string): TCSSDeclaration;
var
  Declaration: TCSSDeclaration;
begin
  Result := nil;

  for Declaration in FDeclarations do
    if Declaration.FProp.ValueEquals(Prop) then
      Exit(Declaration);
end;

{ TCSSMediaQuery }

constructor TCSSMediaQuery.Create;
begin
  FRules := TList<TCSSRule>.Create;
end;

destructor TCSSMediaQuery.Destroy;
var
  Rule: TCSSRule;
begin
  FQuery.Free;

  for Rule in FRules do
    Rule.Free;

  FRules.Free;

  inherited Destroy;
end;

end.
