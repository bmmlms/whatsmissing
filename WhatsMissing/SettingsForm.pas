unit SettingsForm;

interface

uses
  Classes,
  ComCtrls,
  Constants,
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
  UxTheme,
  StdCtrls,
  SysUtils,
  Windows;

type

  { TColorSettingControl }

  TColorSettingControl = class(TWinControl)
  private
    FLabelDescription: TLabel;
    FComboColorType: TComboBox;
    FPanelColorContainer, FPanelColor: TPanel;

    FColorSetting: TColorSetting;

    procedure UpdateColor;
    procedure ComboReplaceTypeSelect(Sender: TObject);
    procedure PanelColorClick(Sender: TObject);
  protected
    procedure ConfigureComboBox; virtual;

    procedure SetParent(AParent: TWinControl); override;
    procedure DoOnResize; override;
  public
    constructor Create(const AOwner: TComponent; const ColorSetting: TColorSetting); reintroduce;
  end;

  { TfrmSettings }

  TfrmSettings = class(TForm)
    btnSave: TButton;
    chkIndicateNewMessages: TCheckBox;
    chkSuppressConsecutiveNotificationSounds: TCheckBox;
    chkSuppressPresenceAvailable: TCheckBox;
    chkSuppressPresenceComposing: TCheckBox;
    chkHideMaximize: TCheckBox;
    chkShowNotificationIcon: TCheckBox;
    PageControl1: TPageControl;
    pnlIndicator: TPanel;
    pnlIndicator1: TPanel;
    pnlIndicatorColor: TPanel;
    pnlSave: TPanel;
    tbsSettings: TTabSheet;
    tbsColors: TTabSheet;
    procedure btnSaveClick(Sender: TObject);
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

  FMMFSettings := TMMFSettings.Create(True);
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
  i: Integer;
  SettingControl: TColorSettingControl;
  MeasureCheckBox: TCheckBox;
  CheckBoxRect: TRect;
begin
  MeasureCheckBox := TCheckBox.Create(Self);
  try
    MeasureCheckBox.Parent := Self;
    CheckBoxRect := MeasureCheckBox.ClientRect;
  finally
    MeasureCheckBox.Free;
  end;

  chkShowNotificationIcon.Checked := FSettings.ShowNotificationIcon;
  chkIndicateNewMessages.Checked := FSettings.IndicateNewMessages;
  chkHideMaximize.Checked := FSettings.HideMaximize;
  chkSuppressPresenceAvailable.Checked := FSettings.SuppressPresenceAvailable;
  chkSuppressPresenceComposing.Checked := FSettings.SuppressPresenceComposing;
  chkSuppressConsecutiveNotificationSounds.Checked := FSettings.SuppressConsecutiveNotificationSounds;

  chkShowNotificationIconChange(chkShowNotificationIcon);

  chkIndicateNewMessages.BorderSpacing.Left := CheckBoxRect.Width;

  for i := FSettings.ColorSettings.Count - 1 downto 0 do
  begin
    SettingControl := TColorSettingControl.Create(tbsColors, FSettings.ColorSettings[i]);
    SettingControl.Align := alTop;
    SettingControl.Visible := True;
    SettingControl.Height := 10;
    SettingControl.AutoSize := True;
    SettingControl.Parent := tbsColors;
  end;
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
  SettingsChangedEvent: THandle;
  Res: TStartProcessRes;
  MMFLauncher: TMMFLauncher;
begin
  FSettings.ShowNotificationIcon := chkShowNotificationIcon.Checked;
  FSettings.IndicateNewMessages := chkIndicateNewMessages.Checked;
  FSettings.HideMaximize := chkHideMaximize.Checked;
  FSettings.SuppressPresenceAvailable := chkSuppressPresenceAvailable.Checked;
  FSettings.SuppressPresenceComposing := chkSuppressPresenceComposing.Checked;
  FSettings.SuppressConsecutiveNotificationSounds := chkSuppressConsecutiveNotificationSounds.Checked;

  try
    FSettings.Save;
  except
    TFunctions.MessageBox(Handle, 'Error saving settings.', 'Error', MB_ICONERROR);
    Exit;
  end;

  try
    if not TMMF.Exists(MMFNAME_LAUNCHER) then
      Exit;

    MMFLauncher := TMMFLauncher.Create(False);
    SettingsChangedEvent := TFunctions.OpenEvent(EVENT_MODIFY_STATE, False, EVENTNAME_SETTINGS_CHANGED);
    try
      MMFLauncher.Read;
      FSettings.CopyToMMF(MMFLauncher);
      MMFLauncher.Write;

      SetEvent(SettingsChangedEvent);

      if (MMFLauncher.ResourceSettingsChecksum > 0) and (FSettings.ResourceSettingsChecksum <> MMFLauncher.ResourceSettingsChecksum) and TFunctions.AppsRunning(False) then
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
          TFunctions.MessageBox(Handle, 'Error restarting WhatsApp.', 'Error', MB_ICONERROR);

        CloseHandle(Res.ProcessHandle);
        CloseHandle(Res.ThreadHandle);
      end;
    finally
      MMFLauncher.Free;
      CloseHandle(SettingsChangedEvent);
    end;
  finally
    Close;
  end;
end;

procedure TfrmSettings.chkShowNotificationIconChange(Sender: TObject);
begin
  chkIndicateNewMessages.Enabled := chkShowNotificationIcon.Checked;
end;

{ TColorSettingControl }

constructor TColorSettingControl.Create(const AOwner: TComponent; const ColorSetting: TColorSetting);
var
  RightContainer: TPanel;
begin
  inherited Create(AOwner);

  FColorSetting := ColorSetting;

  FLabelDescription := TLabel.Create(Self);
  FLabelDescription.Align := alLeft;
  FLabelDescription.AutoSize := True;
  FLabelDescription.Caption := FColorSetting.Description;
  FLabelDescription.Layout := tlCenter;
  FLabelDescription.Parent := Self;

  RightContainer := TPanel.Create(Self);
  RightContainer.Align := alRight;
  RightContainer.BevelOuter := bvNone;
  RightContainer.BorderStyle := bsNone;
  RightContainer.Color := clNone;
  RightContainer.Parent := Self;

  FComboColorType := TComboBox.Create(Self);
  FComboColorType.Align := alClient;
  FComboColorType.Style := csDropDownList;
  FComboColorType.BorderSpacing.Right := 8;
  FComboColorType.Parent := RightContainer;

  FPanelColorContainer := TPanel.Create(Self);
  FPanelColorContainer.Align := alRight;
  FPanelColorContainer.BevelOuter := bvNone;
  FPanelColorContainer.BorderStyle := bsNone;
  FPanelColorContainer.Parent := RightContainer;

  FPanelColor := TPanel.Create(Self);
  FPanelColor.Align := alClient;
  FPanelColor.BevelOuter := bvNone;
  FPanelColor.BorderStyle := bsSingle;
  FPanelColor.ParentBackground := False;
  FPanelColor.Parent := FPanelColorContainer;

  if (not OsSupportsImmersiveColors) and (FColorSetting.ColorType = ctImmersive) then
    FColorSetting.ColorType := ctNone;

  ConfigureComboBox;

  FComboColorType.ItemIndex := FComboColorType.Items.IndexOfObject(TObject(FColorSetting.ColorType));
  if FComboColorType.ItemIndex = -1 then
    FComboColorType.ItemIndex := 0;

  if (not OsSupportsImmersiveColors) and (FColorSetting.ColorType = ctImmersive) then
    FColorSetting.ColorType := ctNone;


  FComboColorType.OnSelect := ComboReplaceTypeSelect;

  FPanelColor.OnClick := PanelColorClick;

  UpdateColor;
end;

procedure TColorSettingControl.SetParent(AParent: TWinControl);
begin
  inherited;

  FPanelColorContainer.Width := FComboColorType.Height;
end;

procedure TColorSettingControl.DoOnResize;
begin
  inherited DoOnResize;

  if FPanelColor <> nil then
    FPanelColor.Parent.Width := Height;
end;

procedure TColorSettingControl.UpdateColor;
begin
  FPanelColor.Color := FColorSetting.GetColor(caNone);
  FPanelColor.Visible := FColorSetting.ColorType <> ctNone;
end;

procedure TColorSettingControl.ComboReplaceTypeSelect(Sender: TObject);
begin
  FColorSetting.ColorType := TColorType(FComboColorType.Items.Objects[FComboColorType.ItemIndex]);
  UpdateColor;
end;

procedure TColorSettingControl.PanelColorClick(Sender: TObject);
var
  Dlg: TColorDialog;
begin
  Dlg := TColorDialog.Create(Self);
  try
    Dlg.Color := FColorSetting.GetColor(caNone);

    if Dlg.Execute then
    begin
      TPanel(Sender).Color := Dlg.Color;

      FComboColorType.ItemIndex := 2;

      FColorSetting.ColorType := ctCustom;
      FColorSetting.ColorCustom := Dlg.Color;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TColorSettingControl.ConfigureComboBox;
begin
  if FColorSetting.ClassType = TResourceColorSetting then
    FComboColorType.Items.AddObject('Use default', Pointer(ctNone));
  if OsSupportsImmersiveColors then
    FComboColorType.Items.AddObject('Use windows color', Pointer(ctImmersive));
  FComboColorType.Items.AddObject('Use custom color', Pointer(ctCustom));

  FComboColorType.ItemIndex := FComboColorType.Items.IndexOfObject(TObject(FColorSetting.ColorType));
  if FComboColorType.ItemIndex = -1 then
    FComboColorType.ItemIndex := 0;
end;

end.
