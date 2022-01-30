unit Window;

interface

uses
  Constants,
  Functions,
  Log,
  MMF,
  Paths,
  ShellAPI,
  SysUtils,
  Windows;

type
  TNotifyIconDataW = record
  public
    cbSize: DWORD;
    Wnd: HWND;
    uID: UINT;
    uFlags: UINT;
    uCallbackMessage: UINT;
    hIcon: HICON;
    szTip: array [0..127] of WideChar;
    dwState: DWORD;
    dwStateMask: DWORD;
    szInfo: array [0..255] of WideChar;
    uVersion: UINT;
    szInfoTitle: array [0..63] of WideChar;
    dwInfoFlags: DWORD;
  end;

  BITMAPV5HEADER = record
    bV5Size: DWORD;
    bV5Width: Longint;
    bV5Height: Longint;
    bV5Planes: Word;
    bV5BitCount: Word;
    bV5Compression: DWORD;
    bV5SizeImage: DWORD;
    bV5XPelsPerMeter: Longint;
    bV5YPelsPerMeter: Longint;
    bV5ClrUsed: DWORD;
    bV5ClrImportant: DWORD;
    bV5RedMask: DWORD;
    bV5GreenMask: DWORD;
    bV5BlueMask: DWORD;
    bV5AlphaMask: DWORD;
    bV5CSType: DWORD;
    bV5Endpoints: TCIEXYZTriple;
    bV5GammaRed: DWORD;
    bV5GammaGreen: DWORD;
    bV5GammaBlue: DWORD;
    bV5Intent: DWORD;
    bV5ProfileData: DWORD;
    bV5ProfileSize: DWORD;
    bV5Reserved: DWORD;
  end;

  TCreateDIBSection = function(_para1: HDC; const _para2: BITMAPV5HEADER; _para3: UINT; var _para4: Pointer; _para5: HANDLE; _para6: DWORD): HBITMAP; stdcall;

  { TWindow }

  TWindow = class
  private
    FMMFLauncher: TMMFLauncher;
    FLog: TLog;
    FHandle, FNotificationAreaHandle, FLastForegroundWindowHandle, FMouseHook: THandle;
    FOriginalWndProc: Pointer;
    FHideMaximize, FAlwaysOnTop, FNotificationIconVisible, FExiting, FWasInCloseButton, FShown: Boolean;
    FNotifyData: TNotifyIconDataW;
    FNotificationMenu: HMENU;
    FTaskbarCreatedMsg: Cardinal;
    FForegroundForNotificationIcon: Boolean;

    class function WndProcWrapper(hwnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; static;
    class function MouseHookWrapper(Code: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; static;

    function WndProc(uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT;
    function MouseHook(Code: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT;

    procedure MenuPopup(const Menu: HMENU);
    function MenuSelect(const ID: UINT): Boolean;
    procedure ShowOrUpdateNotificationIcon;
    procedure HideNotificationIcon;
    procedure Fade(const FadeIn: Boolean);
    procedure ShowMainWindow;
    procedure HideMainWindow;
    procedure ShowNotificationIconMenu;
    procedure ModifySystemMenu;
    procedure CreateNotificationMenu;
    procedure SetAlwaysOnTop(const Enabled: Boolean);
    function CreateNotificationIcon(const UnreadCount: Integer; const BackgroundColor, TextColor: LongInt): HICON;
  public
    constructor Create(const hwnd: HWND; const Log: TLog);
    destructor Destroy; override;

    procedure SettingsChanged(const OldMMF: TMMFLauncher);
  end;

implementation

const
  WM_OPEN_SETTINGS = WM_USER + 1;
  WM_SETTINGS_CHANGED = WM_USER + 2;

  MENU_ALWAYSONTOP = 1;
  MENU_SETTINGS = 2;
  MENU_EXIT = 3;

{ TWindow }

class function TWindow.WndProcWrapper(hwnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  Result := TWindow(GetPropW(hwnd, WNDPROC_PROPNAME)).WndProc(uMsg, wParam, lParam);
end;

class function TWindow.MouseHookWrapper(Code: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  Hwnd, WindowProp: HANDLE;
begin
  if Code < 0 then
    Exit(CallNextHookEx(0, Code, wParam, lParam));

  Hwnd := PMOUSEHOOKSTRUCT(lParam).hwnd;
  WindowProp := GetPropW(Hwnd, WNDPROC_PROPNAME);

  while (Hwnd <> 0) and (WindowProp = 0) do
  begin
    Hwnd := GetParent(Hwnd);
    WindowProp := GetPropW(Hwnd, WNDPROC_PROPNAME);
  end;

  // This check is required since the hook is for all windows, not just the main window.
  // If i.e. a MessageBox is displayed (which does not have the SetPropW()) no TWindow instance will be available.
  if WindowProp = 0 then
    Exit(CallNextHookEx(0, Code, wParam, lParam));

  Result := TWindow(WindowProp).MouseHook(Code, wParam, lParam);
end;

constructor TWindow.Create(const hwnd: HWND; const Log: TLog);
begin
  FHandle := hwnd;
  FLog := Log;

  FMMFLauncher := TMMFLauncher.Create(False);
  FMMFLauncher.Read;
  FHideMaximize := FMMFLauncher.HideMaximize;

  SetPropW(FHandle, WNDPROC_PROPNAME, HANDLE(Self));

  TFunctions.SetPropertyStore(FHandle, TFunctions.GetWhatsMissingExePath(FMMFLauncher, TFunctions.IsWindows64Bit), TPaths.WhatsAppExePath);

  // Install new WndProc
  FOriginalWndProc := Pointer(SetWindowLongPtrW(FHandle, GWLP_WNDPROC, LONG_PTR(@WndProcWrapper)));

  // Prevent maximizing the window on doubleclick on titlebar
  if FHideMaximize then
    SetWindowLongPtrW(FHandle, GWL_STYLE, GetWindowLongPtr(FHandle, GWL_STYLE) xor WS_MAXIMIZEBOX);

  // Install mouse hook for "X" button in titlebar
  FMouseHook := SetWindowsHookExW(WH_MOUSE, @MouseHookWrapper, 0, GetCurrentThreadId);

  SetAlwaysOnTop(FMMFLauncher.AlwaysOnTop);

  ModifySystemMenu;
  CreateNotificationMenu;

  //  ZeroMemory(@FNotifyData, SizeOf(FNotifyData));

  FTaskbarCreatedMsg := RegisterWindowMessage('TaskbarCreated');
end;

destructor TWindow.Destroy;
begin
  UnhookWindowsHookEx(FMouseHook);

  HideNotificationIcon;
end;

procedure TWindow.SettingsChanged(const OldMMF: TMMFLauncher);
begin
  SendMessage(FHandle, WM_SETTINGS_CHANGED, LONG_PTR(OldMMF), 0);
end;

function TWindow.WndProc(uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  OldMMF: TMMFLauncher;
begin
  case uMsg of
    WM_SYSCOMMAND:
      if MenuSelect(wParam) then
        Exit(0)
      else
        case wParam of
          SC_MAXIMIZE:
            if FHideMaximize then
              Exit(0);
          SC_MINIMIZE:
            // If minimized by clicking "_" in the titlebar the "_" button will look hovered after restoring the window, this fixes it.
            SendMessage(FHandle, WM_MOUSEMOVE, 0, MAKELPARAM(10, 40));
        end;
    WM_INITMENUPOPUP:
      MenuPopup(wParam);
    WM_SHOWWINDOW:
      if Boolean(wParam) and (not FShown) then
      begin
        FShown := True;
        ShowOrUpdateNotificationIcon;
      end;
    WM_CLOSE:
      // Prevent closing of window
      if FNotificationIconVisible and (not FExiting) then
      begin
        HideMainWindow;
        Exit(0);
      end;
    WM_KEYDOWN:
      if FNotificationIconVisible and (wParam = VK_ESCAPE) then
      begin
        HideMainWindow;
        Exit(0);
      end;
    WM_ACTIVATE:
      // If WM_ACTIVATE was received from ShowNotificationIconMenu the Message is not forwarded to WhatsApp to suppress sending of "available" presence
      if FForegroundForNotificationIcon then
        Exit(DefWindowProcW(FHandle, uMsg, wParam, lParam));
    {
    WM_SETFOCUS:
    begin
      PostMessage(FHandle, WM_CHAT, WC_READ, 0);
    end;
    }
    WM_EXIT:
    begin
      FExiting := True;

      HideMainWindow;

      SendMessage(FHandle, WM_CLOSE, 0, 0);
      Exit(0);
    end;
    WM_NCDESTROY:
    begin
      FMMFLauncher.Read;
      FMMFLauncher.AlwaysOnTop := FAlwaysOnTop;
      FMMFLauncher.Write;
      FMMFLauncher.Free;

      HideNotificationIcon;
      RemovePropW(FHandle, WNDPROC_PROPNAME);
      TFunctions.ClearPropertyStore(FHandle);
      DestroyMenu(FNotificationMenu);
    end;
    WM_CHAT:
    begin
      ShowOrUpdateNotificationIcon;
      Exit(0);
    end;
    WM_ACTIVATE_INSTANCE:
    begin
      ShowMainWindow;
      Exit(0);
    end;
    WM_OPEN_SETTINGS:
    begin
      TFunctions.StartProcess(TFunctions.GetWhatsMissingExePath(FMMFLauncher, TFunctions.IsWindows64Bit), '-%s'.Format([SETTINGS_ARG]), False, False);
      Exit(0);
    end;
    WM_SETTINGS_CHANGED:
    begin
      FMMFLauncher.Read;
      OldMMF := TMMFLauncher(wParam);

      if FMMFLauncher.ShowNotificationIcon then
        ShowOrUpdateNotificationIcon
      else
      begin
        if (OldMMF.ShowNotificationIcon <> FMMFLauncher.ShowNotificationIcon) and (not IsWindowVisible(FHandle)) then
          ShowMainWindow;
        HideNotificationIcon;
      end;
    end;
    WM_NOTIFICATION_ICON:
    begin
      case lParam of
        NIN_SELECT:
          if (IsWindowVisible(FHandle) and (IsIconic(FHandle) or (FLastForegroundWindowHandle <> FHandle))) or (not IsWindowVisible(FHandle)) then
          begin
            ShowMainWindow;

            FLastForegroundWindowHandle := FHandle;
          end else
            HideMainWindow;
        WM_MOUSEMOVE:
          if GetForegroundWindow <> FNotificationAreaHandle then
            FLastForegroundWindowHandle := GetForegroundWindow;
        WM_CONTEXTMENU:
          ShowNotificationIconMenu;
      end;
      Exit(0);
    end;
    else
      if uMsg = FTaskbarCreatedMsg then
      begin
        if FMMFLauncher.ShowNotificationIcon then
          ShowOrUpdateNotificationIcon;
        Exit(0);
      end;
  end;

  Result := CallWindowProc(FOriginalWndProc, FHandle, uMsg, wParam, lParam);
end;

function TWindow.MouseHook(Code: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  Rect: TRect;
var
  MHS: PMOUSEHOOKSTRUCT;
begin
  if (wParam = WM_NCLBUTTONDBLCLK) and FHideMaximize then
    Exit(1);

  MHS := PMOUSEHOOKSTRUCT(lParam);

  GetWindowRect(MHS^.hwnd, Rect);
  Rect.Left := Rect.Right - 46;
  Rect.Bottom := Rect.Top + 35;

  if PtInRect(Rect, MHS^.pt) then
  begin
    if wParam = WM_LBUTTONDOWN then
      FWasInCloseButton := True;

    if wParam = WM_LBUTTONUP then
      try
        if FWasInCloseButton then
        begin
          SendMessage(FHandle, WM_CLOSE, 0, 0);
          Exit(1);
        end;
      finally
        FWasInCloseButton := False;
      end;
  end;

  Result := CallNextHookEx(0, Code, wParam, lParam);
end;

procedure TWindow.MenuPopup(const Menu: HMENU);
var
  SystemMenu: HMENU;
  MenuItemInfo: TMENUITEMINFOW;
  Caption: array[0..254] of Byte;
begin
  SystemMenu := GetSystemMenu(FHandle, False);

  if (Menu <> SystemMenu) and (Menu <> FNotificationMenu) then
    Exit;

  MenuItemInfo.cbSize := SizeOf(MenuItemInfo);
  MenuItemInfo.fMask := MIIM_TYPE or MIIM_STATE;
  MenuItemInfo.cch := 255;
  MenuItemInfo.dwTypeData := @Caption[0];

  GetMenuItemInfoW(Menu, MENU_ALWAYSONTOP, False, @MenuItemInfo);

  MenuItemInfo.fState := IfThen<UINT>(FAlwaysOnTop, MFS_CHECKED, MFS_UNHILITE);

  SetMenuItemInfoW(Menu, MENU_ALWAYSONTOP, False, @MenuItemInfo);
end;

function TWindow.MenuSelect(const ID: UINT): Boolean;
begin
  Result := False;

  case ID of
    MENU_ALWAYSONTOP:
    begin
      SetAlwaysOnTop(not FAlwaysOnTop);
      Result := True;
    end;
    MENU_SETTINGS:
    begin
      PostMessage(FHandle, WM_OPEN_SETTINGS, 0, 0);
      Result := True;
    end;
    MENU_EXIT:
    begin
      SendMessage(FHandle, WM_EXIT, 0, 0);
      Result := True;
    end;
  end;
end;

procedure TWindow.ShowOrUpdateNotificationIcon;
const
  Days = 365;
var
  UnreadMessageCount: Integer;
  ToolTip: string;
begin
  FNotificationAreaHandle := FindWindow('Shell_TrayWnd', nil);
  if (not FMMFLauncher.ShowNotificationIcon) or (FNotificationAreaHandle = 0) then
    Exit;

  if FNotificationIconVisible then
    DestroyIcon(FNotifyData.hIcon);

  ZeroMemory(@FNotifyData, SizeOf(FNotifyData));
  FNotifyData.cbSize := SizeOf(FNotifyData);
  FNotifyData.Wnd := FMMFLauncher.LauncherWindowHandle;
  FNotifyData.uID := 1;
  FNotifyData.uFlags := NIF_MESSAGE or NIF_ICON or NIF_TIP;
  FNotifyData.uCallbackMessage := WM_NOTIFICATION_ICON;
  FNotifyData.uVersion := NOTIFYICON_VERSION;

  FMMFLauncher.Read;

  FMMFLauncher.Chats.GetUnreadChats(Days, Length(FNotifyData.szTip), FMMFLauncher.ExcludeUnreadMessagesMutedChats, UnreadMessageCount, ToolTip);

  FNotifyData.hIcon := CreateNotificationIcon(IfThen<Integer>(FMMFLauncher.ShowUnreadMessagesBadge, UnreadMessageCount, 0), FMMFLauncher.NotificationIconBadgeColor, FMMFLauncher.NotificationIconBadgeTextColor);

  StrPLCopy(FNotifyData.szTip, ToolTip, Length(FNotifyData.szTip) - 1);

  if not FNotificationIconVisible then
  begin
    FNotificationIconVisible := Shell_NotifyIconW(NIM_ADD, @FNotifyData);
    if not FNotificationIconVisible then
      DestroyIcon(FNotifyData.hIcon)
    else
      Shell_NotifyIconW(NIM_SETVERSION, @FNotifyData);
  end else
    Shell_NotifyIconW(NIM_MODIFY, @FNotifyData);
end;

procedure TWindow.HideNotificationIcon;
begin
  if not FNotificationIconVisible then
    Exit;

  FNotificationIconVisible := False;
  DestroyIcon(FNotifyData.hIcon);
  Shell_NotifyIconW(NIM_DELETE, @FNotifyData);
end;

procedure TWindow.SetAlwaysOnTop(const Enabled: Boolean);
begin
  FAlwaysOnTop := Enabled;

  if FAlwaysOnTop and (WS_EX_TOPMOST and GetWindowLong(FHandle, GWL_EXSTYLE) = 0) then
  begin
    SetFocus(FHandle);
    SetWindowPos(FHandle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE);
  end else if not FAlwaysOnTop and (WS_EX_TOPMOST and GetWindowLong(FHandle, GWL_EXSTYLE) <> 0) then
    SetWindowPos(FHandle, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE);
end;

procedure TWindow.Fade(const FadeIn: Boolean);
var
  Alpha: Integer;
begin
  if GetWindowLong(FHandle, GWL_EXSTYLE) and WS_EX_LAYERED = 0 then
    SetWindowLong(FHandle, GWL_EXSTYLE, GetWindowLong(FHandle, GWL_EXSTYLE) or WS_EX_LAYERED);

  if FadeIn then
    Alpha := 0
  else
    Alpha := 255;

  while (FadeIn and (Alpha < 255)) or (not FadeIn and (Alpha > 0)) do
  begin
    if FadeIn then
      Alpha := Alpha + 20
    else
      Alpha := Alpha - 20;

    if FadeIn and (Alpha > 255) then
      Alpha := 255
    else if not FadeIn and (Alpha < 0) then
      Alpha := 0;

    SetLayeredWindowAttributes(FHandle, 0, Alpha, LWA_ALPHA);
    Sleep(10);
  end;
end;

procedure TWindow.ShowMainWindow;
var
  FadeIn: Boolean;
begin
  FadeIn := not IsWindowVisible(FHandle);

  if FadeIn then
    SetLayeredWindowAttributes(FHandle, 0, 0, LWA_ALPHA);

  ShowWindow(FHandle, SW_SHOW);

  if FadeIn then
    Fade(True);

  OpenIcon(FHandle);
  SetForegroundWindow(FHandle);
end;

procedure TWindow.HideMainWindow;
begin
  // If closed by clicking "X" in the titlebar the "X" button will look hovered after restoring the window, this fixes it.
  SendMessage(FHandle, WM_MOUSEMOVE, 0, MAKELPARAM(10, 40));

  Fade(False);
  ShowWindow(FHandle, SW_HIDE);
end;

procedure TWindow.ShowNotificationIconMenu;
var
  Point: TPoint;
  Res: Cardinal;
begin
  FForegroundForNotificationIcon := True;
  SetForegroundWindow(FHandle);
  FForegroundForNotificationIcon := False;

  GetCursorPos(Point);

  Res := Cardinal(TrackPopupMenu(FNotificationMenu, TPM_RETURNCMD or TPM_LEFTBUTTON or TPM_BOTTOMALIGN, Point.x, Point.y, 0, FHandle, nil));
  if (not MenuSelect(Res)) and (GetForegroundWindow = FHandle) then
    Shell_NotifyIconW(NIM_SETFOCUS, @FNotifyData);
end;

procedure TWindow.ModifySystemMenu;
var
  Menu: HMENU;
  MenuItemInfo: MENUITEMINFOW;
begin
  Menu := GetSystemMenu(FHandle, False);

  if FHideMaximize then
    DeleteMenu(Menu, SC_MAXIMIZE, MF_BYCOMMAND);

  MenuItemInfo.cbSize := SizeOf(MenuItemInfo);

  MenuItemInfo.fMask := MIIM_STRING or MIIM_ID;
  MenuItemInfo.wID := MENU_ALWAYSONTOP;
  MenuItemInfo.dwTypeData := '&Always on top';
  MenuItemInfo.cch := 14;

  InsertMenuItemW(Menu, SC_CLOSE, False, @MenuItemInfo);

  MenuItemInfo.fMask := MIIM_STRING or MIIM_ID;
  MenuItemInfo.wID := MENU_SETTINGS;
  MenuItemInfo.dwTypeData := 'S&ettings...';
  MenuItemInfo.cch := 11;

  InsertMenuItemW(Menu, SC_CLOSE, False, @MenuItemInfo);

  MenuItemInfo.fMask := MIIM_TYPE;
  MenuItemInfo.fType := MFT_SEPARATOR;

  InsertMenuItemW(Menu, SC_CLOSE, False, @MenuItemInfo);
end;

procedure TWindow.CreateNotificationMenu;
begin
  FNotificationMenu := CreatePopupMenu;
  if FNotificationMenu = 0 then
    Exit;

  AppendMenu(FNotificationMenu, MF_STRING, MENU_ALWAYSONTOP, '&Always on top');

  AppendMenu(FNotificationMenu, MF_STRING, MENU_SETTINGS, 'S&ettings...');

  AppendMenu(FNotificationMenu, MF_SEPARATOR, 0, nil);

  AppendMenu(FNotificationMenu, MF_STRING, MENU_EXIT, '&Close');
end;

function TWindow.CreateNotificationIcon(const UnreadCount: Integer; const BackgroundColor, TextColor: LongInt): HICON;

type
  TByteArray = array of Byte;

  TTextDrawInfo = record
    Font: HFONT;
    LeftPadding, TopPadding: LongInt;
    Width, Height: LongInt;
  end;

  function RGBToColor(R, G, B: Byte): LongInt;
  begin
    Result := (B shl 16) or (G shl 8) or R;
  end;

  function GetBitmapHeader(const Size: TSize): BITMAPV5HEADER;
  begin
    ZeroMemory(@Result, SizeOf(Result));
    Result.bV5Size := SizeOf(Result);
    Result.bV5Width := Size.Width;
    Result.bV5Height := -Size.Height;
    Result.bV5Planes := 1;
    Result.bV5BitCount := 32;
    Result.bV5Compression := BI_RGB;
  end;

  procedure UpdateAlpha(const BitmapStart: PRGBQUAD; const BitmapSize: TSize; const Alpha, NewAlpha: Byte);
  var
    RGBQuad: PRGBQUAD;
  begin
    RGBQuad := BitmapStart;
    while RGBQuad < BitmapStart + BitmapSize.Width * BitmapSize.Height * SizeOf(TRGBQUAD) do
    begin
      if RGBQuad.rgbReserved = Alpha then
        RGBQuad.rgbReserved := NewAlpha;

      Inc(RGBQuad);
    end;
  end;

  procedure AlphaDraw(const Dst, Src: PRGBQUAD; const DstPos: TPoint; const DstSize, SrcSize: TSize);
  var
    DstRgb, SrcRgb: PRGBQUAD;
    OffsetX, Y, SrcCnt: LongInt;
    Alpha: Byte;
  begin
    Y := DstPos.Y;

    OffsetX := DstPos.X;

    SrcRgb := Src;
    DstRgb := (Dst + Y * DstSize.Width) + OffsetX;

    SrcCnt := 0;
    while SrcRgb < Src + SrcSize.Width * SrcSize.Height do
    begin
      Alpha := Trunc(SrcRgb.rgbReserved + (DstRgb.rgbReserved * (255 - SrcRgb.rgbReserved) / 255));

      if Alpha > 0 then
      begin
        DstRgb.rgbRed := Trunc((SrcRgb.rgbRed * SrcRgb.rgbReserved + DstRgb.rgbRed * DstRgb.rgbReserved * (255 - SrcRgb.rgbReserved) / 255) / Alpha);
        DstRgb.rgbGreen := Trunc((SrcRgb.rgbGreen * SrcRgb.rgbReserved + DstRgb.rgbGreen * DstRgb.rgbReserved * (255 - SrcRgb.rgbReserved) / 255) / Alpha);
        DstRgb.rgbBlue := Trunc((SrcRgb.rgbBlue * SrcRgb.rgbReserved + DstRgb.rgbBlue * DstRgb.rgbReserved * (255 - SrcRgb.rgbReserved) / 255) / Alpha);
      end;

      DstRgb.rgbReserved := Alpha;

      Inc(SrcRgb);
      Inc(SrcCnt);

      if SrcCnt mod SrcSize.Width = 0 then
      begin
        Inc(Y);
        DstRgb := (Dst + Y * DstSize.Width) + OffsetX;
      end else
        Inc(DstRgb);
    end;
  end;

  function GetTextDrawInfo(const FontSize: Integer; const Text: string; var TextDrawInfo: TTextDrawInfo): Boolean;
  var
    R: RECT;
    DC, Bmp, Brush, Font, FontOld: Handle;
    BitmapHeader: BITMAPV5HEADER;
    FHeight, X, Y: LongInt;
    BitmapSize: TSize;
    BitmapStart, RGBQuad: PRGBQUAD;
    TopLeft, BottomRight: TPoint;
  begin
    Result := False;

    BitmapSize := TSize.Create(FontSize * 2, FontSize * 2);
    BitmapHeader := GetBitmapHeader(BitmapSize);

    DC := CreateCompatibleDC(0);
    Bmp := TCreateDIBSection(@CreateDIBSection)(DC, BitmapHeader, DIB_RGB_COLORS, BitmapStart, 0, 0);

    SelectObject(DC, Bmp);

    Brush := CreateSolidBrush(BackgroundColor);
    FillRect(DC, TRect.Create(0, 0, BitmapSize.Width, BitmapSize.Height), Brush);
    DeleteObject(Brush);

    FHeight := -MulDiv(FontSize, GetDeviceCaps(DC, LOGPIXELSY), 72);

    Font := CreateFont(FHeight, 0, 0, 0, FW_REGULAR, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH, nil);
    FontOld := SelectObject(DC, Font);

    SetTextColor(DC, TextColor);
    SetBkMode(DC, TRANSPARENT);

    R := TRect.Create(0, 0, BitmapSize.Width, BitmapSize.Height);

    DrawTextW(DC, PWideChar(UnicodeString(Text)), Text.Length, R, DT_TOP or DT_LEFT);

    Font := SelectObject(DC, FontOld);

    TopLeft := TPoint.Create(MAXWORD, MAXWORD);
    BottomRight := TPoint.Create(0, 0);

    RGBQuad := BitmapStart;
    while RGBQuad < BitmapStart + BitmapSize.Width * BitmapSize.Height do
    begin
      if RGBToColor(RGBQuad.rgbRed, RGBQuad.rgbGreen, RGBQuad.rgbBlue) <> BackgroundColor then
      begin
        X := (RGBQuad - BitmapStart) mod BitmapSize.Width;
        Y := (RGBQuad - BitmapStart) div BitmapSize.Height;
        if X < TopLeft.X then
          TopLeft.X := X;
        if Y < TopLeft.Y then
          TopLeft.Y := Y;
        if X > BottomRight.X then
          BottomRight.X := X;
        if Y > BottomRight.Y then
          BottomRight.Y := Y;

        Result := True;
      end;
      Inc(RGBQuad);
    end;

    TextDrawInfo.Font := Font;
    TextDrawInfo.LeftPadding := TopLeft.X;
    TextDrawInfo.TopPadding := TopLeft.Y;
    TextDrawInfo.Width := BottomRight.X - TopLeft.X + 1;
    TextDrawInfo.Height := BottomRight.Y - TopLeft.Y + 1;

    DeleteDC(DC);
    DeleteObject(Bmp);
  end;

  function DrawBadge(const Size: TSize; const TextDrawInfo: TTextDrawInfo; const Str: string): TByteArray;
  var
    FontOld: HFONT;
    R: TRect;
    DC, Bmp, Pen, PenOld, Brush, BrushOld: Handle;
    BitmapStart: PRGBQUAD;
    BitmapHeader: BITMAPV5HEADER;
  begin
    DC := CreateCompatibleDC(0);

    BitmapHeader := GetBitmapHeader(Size);
    Bmp := TCreateDIBSection(@CreateDIBSection)(DC, BitmapHeader, DIB_RGB_COLORS, BitmapStart, 0, 0);

    SelectObject(DC, Bmp);

    Brush := CreateSolidBrush(BackgroundColor);
    FillRect(DC, TRect.Create(0, 0, Size.Width, Size.Height), Brush);
    DeleteObject(Brush);

    UpdateAlpha(BitmapStart, Size, $00, $FF);

    Pen := CreatePen(PS_SOLID, 1, BackgroundColor);
    PenOld := SelectObject(DC, Pen);

    BrushOld := SelectObject(DC, GetStockObject(HOLLOW_BRUSH));
    Rectangle(DC, 0, 0, Size.Width, Size.Height);
    SelectObject(DC, BrushOld);

    UpdateAlpha(BitmapStart, Size, $00, $AA);

    Pen := SelectObject(DC, PenOld);
    DeleteObject(Pen);

    FontOld := SelectObject(DC, TextDrawInfo.Font);
    SetTextColor(DC, TextColor);
    SetBkMode(DC, TRANSPARENT);

    R := TRect.Create(((Size.Width - TextDrawInfo.Width) div 2) - TextDrawInfo.LeftPadding, ((Size.Height - TextDrawInfo.Height) div 2) - TextDrawInfo.TopPadding, Size.Width, Size.Height);

    DrawTextW(DC, PWideChar(UnicodeString(Str)), Str.Length, R, DT_TOP or DT_LEFT);

    SelectObject(DC, FontOld);

    UpdateAlpha(BitmapStart, Size, $00, $FF);

    SetLength(Result, Size.Width * Size.Height * SizeOf(TRGBQUAD));
    CopyMemory(@Result[0], BitmapStart, Length(Result));

    DeleteDC(DC);
    DeleteObject(Bmp);
  end;

const
  BoxPaddingX = 1;
  BoxPaddingY = 1;
var
  DC, Bmp, Icon: Handle;
  Text: string;
  BitmapStart: PRGBQUAD;
  BitmapHeader: BITMAPV5HEADER;
  IconInfo: TICONINFO;
  BitmapInfo: BITMAP;
  BadgeBitmap: TByteArray;
  BitmapSize, BoxSize: TSize;
  BoxPos: TPoint;
  TextDrawInfo: TTextDrawInfo;
begin
  if ExtractIconExW(PWideChar(UnicodeString(ParamStr(0))), 0, nil, @Icon, 1) <> 1 then
    raise Exception.Create('ExtractIconExW() failed');

  GetIconInfo(Icon, IconInfo);

  GetObject(IconInfo.hbmColor, SizeOf(BitmapInfo), @BitmapInfo);

  DeleteObject(IconInfo.hbmColor);
  DeleteObject(IconInfo.hbmMask);

  BitmapSize := TSize.Create(BitmapInfo.bmWidth, BitmapInfo.bmHeight);

  DC := CreateCompatibleDC(0);

  BitmapHeader := GetBitmapHeader(BitmapSize);
  Bmp := TCreateDIBSection(@CreateDIBSection)(DC, BitmapHeader, DIB_RGB_COLORS, BitmapStart, 0, 0);

  SelectObject(DC, Bmp);

  DrawIconEx(DC, 0, 0, Icon, BitmapSize.Width, BitmapSize.Height, 0, 0, DI_NORMAL);

  if UnreadCount > 0 then
  begin
    Text := IfThen<string>(UnreadCount > 99, '!!!', UnreadCount.ToString);

    if GetTextDrawInfo(Trunc(BitmapSize.Height * 0.45), Text, TextDrawInfo) then
      try
        BoxSize := TSize.Create(TextDrawInfo.Width + BoxPaddingX * 2, TextDrawInfo.Height + BoxPaddingY * 2);
        BoxPos := TPoint.Create(BitmapSize.Width - BoxSize.Width, BitmapSize.Height - BoxSize.Height);

        FillRect(DC, TRect.Create(BoxPos.X - 1, BoxPos.Y - 1, BitmapSize.Width, BitmapSize.Height), GetStockObject(WHITE_BRUSH));

        BadgeBitmap := DrawBadge(BoxSize, TextDrawInfo, Text);
        AlphaDraw(BitmapStart, @BadgeBitmap[0], BoxPos, BitmapSize, BoxSize);
      finally
        DeleteObject(TextDrawInfo.Font);
      end;
  end;

  IconInfo.fIcon := True;
  IconInfo.xHotspot := 0;
  IconInfo.yHotspot := 0;
  IconInfo.hbmColor := Bmp;
  IconInfo.hbmMask := Bmp;

  Result := CreateIconIndirect(IconInfo);

  DeleteDC(DC);
  DeleteObject(Bmp);
end;

end.
