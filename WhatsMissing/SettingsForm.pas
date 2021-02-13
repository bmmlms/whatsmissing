unit SettingsForm;

interface

uses
  Classes,
  Controls,
  Dialogs,
  ExtCtrls,
  Forms,
  Functions,
  Graphics,
  ImmersiveColors,
  MMF,
  Paths,
  ResourcePatcher,
  Settings,
  StdCtrls,
  SysUtils,
  Windows;

type
  TResourcePatchControl = class(TWinControl)
  private
    FLabelDescription: TLabel;
    FComboAction: TComboBox;
    FPanelColor: TPanel;

    FResourcePatchCollection: TResourcePatchCollection;

    procedure UpdateColor;
    procedure ComboReplaceTypeSelect(Sender: TObject);
    procedure PanelColorClick(Sender: TObject);
  protected
    procedure SetParent(AParent: TWinControl); override;
  public
    constructor Create(const AOwner: TComponent; const ResourcePatchCollection: TResourcePatchCollection); reintroduce;
  published
  end;

  { TfrmSettings }

  TfrmSettings = class(TForm)
    btnSave: TButton;
    chkIndicateNewMessages: TCheckBox;
    grpResourcePatches: TGroupBox;
    grpSettings: TGroupBox;
    chkShowNotificationIcon: TCheckBox;
    chkHideMaximize: TCheckBox;
    pnlSave: TPanel;
    pnlIndicator: TPanel;
    pnlIndicatorColor: TPanel;
    procedure btnSaveClick(Sender: TObject);
    procedure chkIndicateNewMessagesChange(Sender: TObject);
    procedure chkShowNotificationIconChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormShow(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pnlIndicatorColorClick(Sender: TObject);
  private
    FSettings: TSettings;
    FMMFSettings: TMMFSettings;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

{$R *.lfm}

{ TfrmSettings }

constructor TfrmSettings.Create(AOwner: TComponent);
begin
  inherited;

  FMMFSettings := TMMFSettings.Create;
  FMMFSettings.SettingsPid := GetCurrentProcessId;
  FMMFSettings.SettingsWindowHandle := Handle;
  FMMFSettings.Write;

  Icon.Handle := LoadIcon(HInstance, IDI_APPLICATION);

  TFunctions.SetPropertyStore(Handle, TPaths.ExePath, TPaths.WhatsAppExePath);

  FSettings := TSettings.Create(TPaths.SettingsPath);
end;

destructor TfrmSettings.Destroy;
begin
  FSettings.Free;
  FMMFSettings.Free;

  TFunctions.ClearPropertyStore(Handle);

  inherited;
end;

procedure TfrmSettings.FormShow(Sender: TObject);
var
  ResourcePatchCollection: TResourcePatchCollection;
  RPC: TResourcePatchControl;
begin
  chkShowNotificationIcon.Checked := FSettings.ShowNotificationIcon;
  chkIndicateNewMessages.Checked := FSettings.IndicateNewMessages;
  pnlIndicatorColor.Color := FSettings.IndicatorColor;
  chkHideMaximize.Checked := FSettings.HideMaximize;

  chkShowNotificationIconChange(chkShowNotificationIcon);

  for ResourcePatchCollection in FSettings.ResourcePatches do
  begin
    RPC := TResourcePatchControl.Create(grpResourcePatches, ResourcePatchCollection);
    RPC.Align := alTop;
    RPC.Visible := True;
    RPC.Height := 10;
    RPC.Top := grpResourcePatches.Height;
    RPC.Parent := grpResourcePatches;

    if grpResourcePatches.ControlCount = 1 then
      RPC.BorderSpacing.Top := 4
    else
      RPC.BorderSpacing.Top := 2;
  end;

  RPC.BorderSpacing.Bottom := 5;

  ClientHeight := ClientHeight - (pnlSave.Top - (grpResourcePatches.Top + grpResourcePatches.Height)) + 8;
end;

procedure TfrmSettings.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
end;

procedure TfrmSettings.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = 27 then
  begin
    Key := 0;
    Close;
  end;
end;

procedure TfrmSettings.pnlIndicatorColorClick(Sender: TObject);
var
  Dlg: TColorDialog;
begin
  Dlg := TColorDialog.Create(Self);
  try
    Dlg.Color := TPanel(Sender).Color;

    if Dlg.Execute then
      TPanel(Sender).Color := Dlg.Color;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmSettings.btnSaveClick(Sender: TObject);
var
  Res: TStartProcessRes;
begin
  FSettings.RebuildResources := True;

  FSettings.ShowNotificationIcon := chkShowNotificationIcon.Checked;
  FSettings.IndicateNewMessages := chkIndicateNewMessages.Checked;
  FSettings.IndicatorColor := pnlIndicatorColor.Color;
  FSettings.HideMaximize := chkHideMaximize.Checked;

  try
    FSettings.Save;
  except
    TFunctions.MessageBox(Handle, 'Error saving settings.', 'Error', MB_ICONERROR);
    Exit;
  end;

  try
    if TFunctions.AppsRunning(False) then
    begin
      if TFunctions.MessageBox(Handle, 'WhatsApp needs to be restarted in order to apply new settings. Do you want to restart WhatsApp now?', 'Question', MB_ICONQUESTION or MB_YESNO or MB_DEFBUTTON1) = idNo then
        Exit;

      if not TFunctions.CloseApps(False) then
      begin
        TFunctions.MessageBox(Handle, 'WhatsApp could not be closed. Please restart WhatsApp manually.', 'Error', MB_ICONERROR);
        Exit;
      end;

      Res := TFunctions.StartProcess(TPaths.ExePath, '', False, False);
      if not Res.Success then
        TFunctions.MessageBox(Handle, 'Error starting WhatsApp.', 'Error', MB_ICONERROR);

      CloseHandle(Res.ProcessHandle);
      CloseHandle(Res.ThreadHandle);
    end;
  finally
    Close;
  end;
end;

procedure TfrmSettings.chkShowNotificationIconChange(Sender: TObject);
begin
  if not chkShowNotificationIcon.Checked then
    chkIndicateNewMessages.Checked := False;
  chkIndicateNewMessages.Enabled := chkShowNotificationIcon.Checked;

  chkIndicateNewMessagesChange(chkIndicateNewMessages);
end;

procedure TfrmSettings.chkIndicateNewMessagesChange(Sender: TObject);
begin
  pnlIndicatorColor.Visible := chkIndicateNewMessages.Checked;
end;

{ TResourcePatchControl }

constructor TResourcePatchControl.Create(const AOwner: TComponent; const ResourcePatchCollection: TResourcePatchCollection);
begin
  inherited Create(AOwner);

  FResourcePatchCollection := ResourcePatchCollection;
end;

procedure TResourcePatchControl.SetParent(AParent: TWinControl);
var
  i: Integer;
  Found: Boolean;
  PanelColorContainer: TPanel;
begin
  inherited;

  if Assigned(FLabelDescription) then
    Exit;

  FLabelDescription := TLabel.Create(Self);
  FLabelDescription.Align := alLeft;
  FLabelDescription.AutoSize := True;
  FLabelDescription.Caption := FResourcePatchCollection.Description;
  FLabelDescription.Layout := tlCenter;
  FLabelDescription.Parent := Self;

  PanelColorContainer := TPanel.Create(Self);
  PanelColorContainer.Align := alRight;
  PanelColorContainer.BevelOuter := bvNone;
  PanelColorContainer.BorderStyle := bsNone;
  PanelColorContainer.Parent := Self;

  FPanelColor := TPanel.Create(Self);
  FPanelColor.Align := alClient;
  FPanelColor.BevelOuter := bvNone;
  FPanelColor.BorderStyle := bsSingle;
  FPanelColor.ParentBackground := False;
  FPanelColor.Parent := PanelColorContainer;

  FComboAction := TComboBox.Create(Self);
  FComboAction.Align := alRight;
  FComboAction.Width := 150;
  FComboAction.Style := csDropDownList;
  FComboAction.BorderSpacing.Right := 8;
  FComboAction.Parent := Self;

  PanelColorContainer.Width := FComboAction.Height;

  FComboAction.Items.AddObject('Use default', Pointer(rpaNone));
  if OsSupportsImmersiveColors then
    FComboAction.Items.AddObject('Use windows color', Pointer(rpaImmersive));
  FComboAction.Items.AddObject('Use custom color', Pointer(rpaCustom));

  Found := False;
  for i := 0 to FComboAction.Items.Count - 1 do
    if TResourcePatchAction(FComboAction.Items.Objects[i]) = FResourcePatchCollection.Action then
    begin
      Found := True;
      FComboAction.ItemIndex := i;
      Break;
    end;

  if not Found then
    FComboAction.ItemIndex := 0;

  FComboAction.OnSelect := ComboReplaceTypeSelect;

  FPanelColor.OnClick := PanelColorClick;

  UpdateColor;

  FLabelDescription.Left := 0;

  Height := FComboAction.Height;
end;

procedure TResourcePatchControl.UpdateColor;
begin
  if (not OsSupportsImmersiveColors) and (FResourcePatchCollection.Action = rpaImmersive) then
    FResourcePatchCollection.Action := rpaNone;

  FPanelColor.Color := TResourcePatcher.GetColor(FResourcePatchCollection, caNone);
  FPanelColor.Visible := FResourcePatchCollection.Action <> rpaNone;
end;

procedure TResourcePatchControl.ComboReplaceTypeSelect(Sender: TObject);
begin
  FResourcePatchCollection.Action := TResourcePatchAction(FComboAction.Items.Objects[FComboAction.ItemIndex]);
  UpdateColor;
end;

procedure TResourcePatchControl.PanelColorClick(Sender: TObject);
var
  Dlg: TColorDialog;
begin
  Dlg := TColorDialog.Create(Self);
  try
    Dlg.Color := TResourcePatcher.GetColor(FResourcePatchCollection, caNone);

    if Dlg.Execute then
    begin
      TPanel(Sender).Color := Dlg.Color;

      FComboAction.ItemIndex := 2;

      FResourcePatchCollection.Action := rpaCustom;
      FResourcePatchCollection.ColorCustom := Dlg.Color;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
