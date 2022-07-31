unit SettingsForm;

interface

uses
  Buttons,
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
  Settings,
  StdCtrls,
  SysUtils,
  UxTheme,
  Windows;

type
  { TColorSettingControlBase }

  TColorSettingControlBase = class(TWinControl)
  protected
    FLabelDescription: TLabel;
    FComboColorType: TComboBoxEx;
    FPanelColorContainer, FPanelColor: TPanel;

    procedure UpdateColor; virtual; abstract;
    procedure ConfigureComboBox; virtual; abstract;
    procedure PanelColorClick(Sender: TObject); virtual; abstract;
    procedure ComboReplaceTypeSelect(Sender: TObject); virtual;

    procedure SetParent(AParent: TWinControl); override;
    procedure DoOnResize; override;
  public
    constructor Create(const AOwner: TComponent; const ColorSetting: TColorSettingBase); reintroduce;
  end;

  { TColorSettingControlSimple }

  TColorSettingControlSimple = class(TColorSettingControlBase)
  private
    FColorSetting: TColorSettingSimple;
  protected
    procedure UpdateColor; override;
    procedure ConfigureComboBox; override;
    procedure ComboReplaceTypeSelect(Sender: TObject); override;
    procedure PanelColorClick(Sender: TObject); override;
  public
    constructor Create(const AOwner: TComponent; const ColorSetting: TColorSettingSimple); reintroduce;
  end;

  { TColorSettingControlResource }

  TColorSettingControlResource = class(TColorSettingControlBase)
  private
    FColorSetting: TColorSettingResource;
    FDefaultColor: TColor;
    FColorAvailable: Boolean;
  protected
    procedure UpdateColor; override;
    procedure ConfigureComboBox; override;
    procedure ComboReplaceTypeSelect(Sender: TObject); override;
    procedure PanelColorClick(Sender: TObject); override;
  public
    constructor Create(const AOwner: TComponent; const ColorSetting: TColorSettingResource; DefaultColor: TColor); reintroduce; overload;
    constructor Create(const AOwner: TComponent; const ColorSetting: TColorSettingResource); reintroduce; overload;
  end;

  { TfrmSettings }

  TfrmSettings = class(TForm)
    Bevel1: TBevel;
    btnSave: TBitBtn;
    chkUseSquaredProfileImages: TCheckBox;
    chkUseRegularTitleBar: TCheckBox;
    chkShowUnreadMessagesBadge: TCheckBox;
    chkExcludeUnreadMessagesMutedChats: TCheckBox;
    chkUsePreRenderedOverlays: TCheckBox;
    chkSuppressConsecutiveNotifications: TCheckBox;
    chkHideMaximize: TCheckBox;
    chkShowNotificationIcon: TCheckBox;
    chkRemoveRoundedElementCorners: TCheckBox;
    ImageList: TImageList;
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

    procedure ScaleDPI(const Control: TControl; const FromDPI: Integer);
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

  ScaleDPI(Self, 96);
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
  SettingControl: TColorSettingControlBase;
  MeasureCheckBox: TCheckBox;
  CheckBoxRect: TRect;
  ColorSetting: TColorSettingBase;
  MMFLauncher: TMMFLauncher;
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
  chkRemoveRoundedElementCorners.Checked := FSettings.RemoveRoundedElementCorners;
  chkUseSquaredProfileImages.Checked := FSettings.UseSquaredProfileImages;
  chkUseRegularTitleBar.Checked := FSettings.UseRegularTitleBar;
  chkHideMaximize.Checked := FSettings.HideMaximize;
  chkSuppressConsecutiveNotifications.Checked := FSettings.SuppressConsecutiveNotifications;

  CheckBoxChange(nil);

  chkShowUnreadMessagesBadge.BorderSpacing.Left := CheckBoxRect.Width;
  chkUsePreRenderedOverlays.BorderSpacing.Left := CheckBoxRect.Width;
  chkExcludeUnreadMessagesMutedChats.BorderSpacing.Left := CheckBoxRect.Width;

  MMFLauncher := TMMFLauncher.Create(False);
  try
    MMFLauncher.Read;
    for i := FSettings.ColorSettings.Count - 1 downto 0 do
    begin
      ColorSetting := FSettings.ColorSettings[i];

      if ColorSetting is TColorSettingSimple then
        SettingControl := TColorSettingControlSimple.Create(sbColors, TColorSettingSimple(ColorSetting))
      else if MMFLauncher.DefaultColors.ContainsKey(ColorSetting.ID) then
        SettingControl := TColorSettingControlResource.Create(sbColors, TColorSettingResource(ColorSetting), MMFLauncher.DefaultColors[ColorSetting.ID])
      else
        SettingControl := TColorSettingControlResource.Create(sbColors, TColorSettingResource(ColorSetting));

      SettingControl.Align := alTop;
      SettingControl.Visible := True;
      SettingControl.Height := 10;
      SettingControl.AutoSize := True;
      SettingControl.Parent := sbColors;

      if i < FSettings.ColorSettings.Count - 1 then
        SettingControl.BorderSpacing.Bottom := 4;
    end;
  finally
    MMFLauncher.Free;
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

procedure TfrmSettings.ScaleDPI(const Control: TControl; const FromDPI: Integer);
var
  n: Integer;
  WinControl: TWinControl;
begin
  if Screen.PixelsPerInch = FromDPI then
    Exit;

  with Control do
  begin
    Left := ScaleX(Left, FromDPI);
    Top := ScaleY(Top, FromDPI);
    Width := ScaleX(Width, FromDPI);
    Height := ScaleY(Height, FromDPI);
    Font.Height := ScaleY(Font.GetTextHeight('Hg'), FromDPI);
  end;

  if Control is TWinControl then
  begin
    WinControl := TWinControl(Control);
    if WinControl.ControlCount > 0 then
      for n := 0 to WinControl.ControlCount - 1 do
        if WinControl.Controls[n] is TControl then
          ScaleDPI(WinControl.Controls[n], FromDPI);
  end;
end;

procedure TfrmSettings.btnSaveClick(Sender: TObject);
var
  SettingsChangedEvent: THandle;
  Res: TStartProcessRes;
  MMFLauncher: TMMFLauncher;
  SaveSettings: TSettings;
  ColorSetting, SaveColorSetting: TColorSettingBase;
begin
  SaveSettings := TSettings.Create(TPaths.SettingsPath);
  try
    for ColorSetting in FSettings.ColorSettings do
      for SaveColorSetting in SaveSettings.ColorSettings do
        if ColorSetting.ID = SaveColorSetting.ID then
        begin
          SaveColorSetting.ColorCustom := ColorSetting.ColorCustom;

          if (ColorSetting is TColorSettingResource) and (SaveColorSetting is TColorSettingResource) then
            TColorSettingResource(SaveColorSetting).ColorType := TColorSettingResource(ColorSetting).ColorType
          else
            TColorSettingSimple(SaveColorSetting).ColorType := TColorSettingSimple(ColorSetting).ColorType;

          Break;
        end;

    SaveSettings.ShowNotificationIcon := chkShowNotificationIcon.Checked;
    SaveSettings.ShowUnreadMessagesBadge := chkShowUnreadMessagesBadge.Checked;
    SaveSettings.UsePreRenderedOverlays := chkUsePreRenderedOverlays.Checked;
    SaveSettings.ExcludeUnreadMessagesMutedChats := chkExcludeUnreadMessagesMutedChats.Checked;
    SaveSettings.RemoveRoundedElementCorners := chkRemoveRoundedElementCorners.Checked;
    SaveSettings.UseSquaredProfileImages := chkUseSquaredProfileImages.Checked;
    SaveSettings.UseRegularTitleBar := chkUseRegularTitleBar.Checked;
    SaveSettings.HideMaximize := chkHideMaximize.Checked;
    SaveSettings.SuppressConsecutiveNotifications := chkSuppressConsecutiveNotifications.Checked;

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

{ TColorSettingControlBase }

constructor TColorSettingControlBase.Create(const AOwner: TComponent; const ColorSetting: TColorSettingBase);
var
  RightContainer: TPanel;
begin
  inherited Create(AOwner);

  FLabelDescription := TLabel.Create(Self);
  FLabelDescription.Align := alLeft;
  FLabelDescription.AutoSize := True;
  FLabelDescription.Caption := ColorSetting.Description;
  FLabelDescription.Layout := tlCenter;
  FLabelDescription.Parent := Self;

  RightContainer := TPanel.Create(Self);
  RightContainer.Align := alRight;
  RightContainer.BevelOuter := bvNone;
  RightContainer.BorderStyle := bsNone;
  RightContainer.Color := clNone;
  RightContainer.Parent := Self;
  RightContainer.Constraints.MinWidth := Trunc(TWinControl(AOwner).Width * 0.4);

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

  FComboColorType.OnSelect := ComboReplaceTypeSelect;
  FPanelColor.OnClick := PanelColorClick;

  ConfigureComboBox;
  UpdateColor;
end;

procedure TColorSettingControlBase.SetParent(AParent: TWinControl);
begin
  inherited;

  FPanelColorContainer.Width := FComboColorType.Height;
end;

procedure TColorSettingControlBase.DoOnResize;
begin
  inherited DoOnResize;

  if Assigned(FPanelColor) then
    FPanelColor.Parent.Width := Height;
end;

procedure TColorSettingControlBase.ComboReplaceTypeSelect(Sender: TObject);
begin
  UpdateColor;
end;

{ TColorSettingControlSimple }

constructor TColorSettingControlSimple.Create(const AOwner: TComponent; const ColorSetting: TColorSettingSimple);
begin
  FColorSetting := ColorSetting;

  if FColorSetting.ColorCustom = 0 then
    FColorSetting.ColorCustom := FColorSetting.GetColor(caNone);

  inherited Create(AOwner, ColorSetting);
end;

procedure TColorSettingControlSimple.UpdateColor;
begin
  FPanelColor.Color := FColorSetting.GetColor(caNone);
end;

procedure TColorSettingControlSimple.ComboReplaceTypeSelect(Sender: TObject);
begin
  FColorSetting.ColorType := TColorTypeSimple(FComboColorType.ItemsEx[FComboColorType.ItemIndex].Data);

  inherited ComboReplaceTypeSelect(Sender);
end;

procedure TColorSettingControlSimple.PanelColorClick(Sender: TObject);
var
  Dlg: TColorDialog;
begin
  Dlg := TColorDialog.Create(Self);
  try
    Dlg.Color := FColorSetting.GetColor(caNone);

    if Dlg.Execute then
    begin
      TPanel(Sender).Color := Dlg.Color;

      FComboColorType.ItemIndex := IfThen<Integer>(OsSupportsImmersiveColors, 1, 0);

      FColorSetting.ColorType := ctsCustom;
      FColorSetting.ColorCustom := Dlg.Color;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TColorSettingControlSimple.ConfigureComboBox;
var
  i: Integer;
begin
  if OsSupportsImmersiveColors then
    FComboColorType.ItemsEx.AddItem('Use windows color', -1, -1, -1, -1, Pointer(ctsImmersive));
  FComboColorType.ItemsEx.AddItem('Use custom color', -1, -1, -1, -1, Pointer(ctsCustom));

  for i := 0 to FComboColorType.ItemsEx.Count - 1 do
    if FComboColorType.ItemsEx[i].Data = Pointer(FColorSetting.ColorType) then
    begin
      FComboColorType.ItemIndex := i;
      Break;
    end;

  if FComboColorType.ItemIndex = -1 then
    FComboColorType.ItemIndex := 0;
end;

{ TColorSettingControlResource }

constructor TColorSettingControlResource.Create(const AOwner: TComponent; const ColorSetting: TColorSettingResource; DefaultColor: TColor);
begin
  FColorSetting := ColorSetting;
  FDefaultColor := DefaultColor;
  FColorAvailable := True;

  if FColorSetting.ColorCustom = 0 then
    FColorSetting.ColorCustom := DefaultColor;

  inherited Create(AOwner, ColorSetting);
end;

constructor TColorSettingControlResource.Create(const AOwner: TComponent; const ColorSetting: TColorSettingResource);
begin
  FColorSetting := ColorSetting;

  inherited Create(AOwner, ColorSetting);

  Enabled := False;
end;

procedure TColorSettingControlResource.UpdateColor;
begin
  if not FColorAvailable then
  begin
    FPanelColor.Color := clWindow;
    Exit;
  end;

  FPanelColor.Color := FColorSetting.GetColor(caNone, FDefaultColor);
end;

procedure TColorSettingControlResource.ComboReplaceTypeSelect(Sender: TObject);
begin
  FColorSetting.ColorType := TColorTypeResource(FComboColorType.ItemsEx[FComboColorType.ItemIndex].Data);

  inherited ComboReplaceTypeSelect(Sender);
end;

procedure TColorSettingControlResource.PanelColorClick(Sender: TObject);
var
  Dlg: TColorDialog;
begin
  if not FColorAvailable then
    Exit;

  Dlg := TColorDialog.Create(Self);
  try
    Dlg.Color := FColorSetting.GetColor(caNone, FDefaultColor);

    if Dlg.Execute then
    begin
      TPanel(Sender).Color := Dlg.Color;

      FComboColorType.ItemIndex := IfThen<Integer>(OsSupportsImmersiveColors, 2, 1);

      FColorSetting.ColorType := ctrCustom;
      FColorSetting.ColorCustom := Dlg.Color;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TColorSettingControlResource.ConfigureComboBox;
var
  i: Integer;
begin
  if not FColorAvailable then
    Exit;

  FComboColorType.ItemsEx.AddItem('Use default', -1, -1, -1, -1, Pointer(ctrOriginal));
  if OsSupportsImmersiveColors then
    FComboColorType.ItemsEx.AddItem('Use windows color', -1, -1, -1, -1, Pointer(ctrImmersive));
  FComboColorType.ItemsEx.AddItem('Use custom color', -1, -1, -1, -1, Pointer(ctrCustom));

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
