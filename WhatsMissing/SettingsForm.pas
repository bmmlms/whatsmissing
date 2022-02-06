unit SettingsForm;

interface

uses
  Classes,
  ComboEx,
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
  StdCtrls, Buttons,
  SysUtils,
  UxTheme,
  Windows;

type

  { TColorSettingControl }

  TColorSettingControl = class(TWinControl)
  private
    FLabelDescription: TLabel;
    FComboColorType: TComboBoxEx;
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
    Bevel1: TBevel;
    btnSave: TBitBtn;
    chkShowUnreadMessagesBadge: TCheckBox;
    chkExcludeUnreadMessagesMutedChats: TCheckBox;
    chkUsePreRenderedOverlays: TCheckBox;
    chkSuppressConsecutiveNotificationSounds: TCheckBox;
    chkSuppressPresenceAvailable: TCheckBox;
    chkSuppressPresenceComposing: TCheckBox;
    chkHideMaximize: TCheckBox;
    chkShowNotificationIcon: TCheckBox;
    PageControl1: TPageControl;
    pnlSave: TPanel;
    sbColors: TScrollBox;
    tbsSettings: TTabSheet;
    tbsColors: TTabSheet;
    procedure btnSaveClick(Sender: TObject);
    procedure CheckBoxChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormShow(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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
  chkShowUnreadMessagesBadge.Checked := FSettings.ShowUnreadMessagesBadge;
  chkUsePreRenderedOverlays.Checked := FSettings.UsePreRenderedOverlays;
  chkExcludeUnreadMessagesMutedChats.Checked := FSettings.ExcludeUnreadMessagesMutedChats;
  chkHideMaximize.Checked := FSettings.HideMaximize;
  chkSuppressPresenceAvailable.Checked := FSettings.SuppressPresenceAvailable;
  chkSuppressPresenceComposing.Checked := FSettings.SuppressPresenceComposing;
  chkSuppressConsecutiveNotificationSounds.Checked := FSettings.SuppressConsecutiveNotificationSounds;

  CheckBoxChange(nil);

  chkShowUnreadMessagesBadge.BorderSpacing.Left := CheckBoxRect.Width;
  chkUsePreRenderedOverlays.BorderSpacing.Left := CheckBoxRect.Width;
  chkExcludeUnreadMessagesMutedChats.BorderSpacing.Left := CheckBoxRect.Width;

  for i := FSettings.ColorSettings.Count - 1 downto 0 do
  begin
    SettingControl := TColorSettingControl.Create(sbColors, FSettings.ColorSettings[i]);
    SettingControl.Align := alTop;
    SettingControl.Visible := True;
    SettingControl.Height := 10;
    SettingControl.AutoSize := True;
    SettingControl.Parent := sbColors;
    if i < FSettings.ColorSettings.Count - 1 then
      SettingControl.BorderSpacing.Bottom := 4;
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

procedure TfrmSettings.btnSaveClick(Sender: TObject);
var
  SettingsChangedEvent: THandle;
  Res: TStartProcessRes;
  MMFLauncher: TMMFLauncher;
  SaveSettings: TSettings;
  ColorSetting, SaveColorSetting: TColorSetting;
begin
  SaveSettings := TSettings.Create(TPaths.SettingsPath);
  try
    for ColorSetting in FSettings.ColorSettings do
      for SaveColorSetting in SaveSettings.ColorSettings do
        if ColorSetting.ID = SaveColorSetting.ID then
        begin
          SaveColorSetting.ColorCustom := ColorSetting.ColorCustom;
          SaveColorSetting.ColorType := ColorSetting.ColorType;
          Break;
        end;

    SaveSettings.ShowNotificationIcon := chkShowNotificationIcon.Checked;
    SaveSettings.ShowUnreadMessagesBadge := chkShowUnreadMessagesBadge.Checked;
    SaveSettings.UsePreRenderedOverlays := chkUsePreRenderedOverlays.Checked;
    SaveSettings.ExcludeUnreadMessagesMutedChats := chkExcludeUnreadMessagesMutedChats.Checked;
    SaveSettings.HideMaximize := chkHideMaximize.Checked;
    SaveSettings.SuppressPresenceAvailable := chkSuppressPresenceAvailable.Checked;
    SaveSettings.SuppressPresenceComposing := chkSuppressPresenceComposing.Checked;
    SaveSettings.SuppressConsecutiveNotificationSounds := chkSuppressConsecutiveNotificationSounds.Checked;

    try
      SaveSettings.Save;
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
        SaveSettings.CopyToMMF(MMFLauncher);
        MMFLauncher.Write;

        SetEvent(SettingsChangedEvent);

        if (MMFLauncher.ResourceSettingsChecksum > 0) and (SaveSettings.ResourceSettingsChecksum <> MMFLauncher.ResourceSettingsChecksum) and TFunctions.AppsRunning(False) then
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
  finally
    SaveSettings.Free;
  end;
end;

procedure TfrmSettings.CheckBoxChange(Sender: TObject);
begin
  if (Sender = nil) or (Sender = chkShowNotificationIcon) then
    chkShowUnreadMessagesBadge.Enabled := chkShowNotificationIcon.Checked;

  if (Sender = nil) or (Sender = chkShowNotificationIcon) or (Sender = chkShowUnreadMessagesBadge) then
  begin
    chkUsePreRenderedOverlays.Enabled := chkShowNotificationIcon.Checked and chkShowUnreadMessagesBadge.Checked;
    chkExcludeUnreadMessagesMutedChats.Enabled := chkShowNotificationIcon.Checked and chkShowUnreadMessagesBadge.Checked;
  end;
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

  FComboColorType := TComboBoxEx.Create(Self);
  FComboColorType.Align := alClient;
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

  if (FColorSetting.ColorDefault = clNone) and (FColorSetting.ColorType = ctNone) then
    if OsSupportsImmersiveColors then
      FColorSetting.ColorType := ctImmersive
    else
      FColorSetting.ColorType := ctCustom;

  ConfigureComboBox;

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

  if Assigned(FPanelColor) then
    FPanelColor.Parent.Width := Height;
end;

procedure TColorSettingControl.UpdateColor;
begin
  FPanelColor.Color := FColorSetting.GetColor(caNone);
end;

procedure TColorSettingControl.ComboReplaceTypeSelect(Sender: TObject);
begin
  FColorSetting.ColorType := TColorType(FComboColorType.ItemsEx[FComboColorType.ItemIndex].Data);
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
var
  i: Integer;
begin
  if FColorSetting.ClassType = TResourceColorSetting then
    FComboColorType.ItemsEx.AddItem('Use default', -1, -1, -1, -1, Pointer(ctNone));
  if OsSupportsImmersiveColors then
    FComboColorType.ItemsEx.AddItem('Use windows color', -1, -1, -1, -1, Pointer(ctImmersive));
  FComboColorType.ItemsEx.AddItem('Use custom color', -1, -1, -1, -1, Pointer(ctCustom));

  for i := 0 to FComboColorType.ItemsEx.Count - 1 do
    if FComboColorType.ItemsEx[i].Data = Pointer(FColorSetting.ColorType) then
    begin
      FComboColorType.ItemIndex := i;
      Break;
    end;

  if FComboColorType.ItemIndex = -1 then
    FComboColorType.ItemIndex := 0;
end;

end.
