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
    function CreateNotificationIcon: HICON;
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
            if not FMMFLauncher.UseRegularTitleBar then
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
    WM_NCCALCSIZE, WM_NCACTIVATE:
      if FMMFLauncher.UseRegularTitleBar then
        Exit(DefWindowProcW(FHandle, uMsg, wParam, lParam));
    else
      if uMsg = FTaskbarCreatedMsg then
      begin
        HideNotificationIcon;
        ShowOrUpdateNotificationIcon;
        Exit(0);
      end;
  end;

  Result := CallWindowProc(FOriginalWndProc, FHandle, uMsg, wParam, lParam);
end;

function TWindow.MouseHook(Code: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  P: TPoint = (X: 0; Y: 0);
  Rect: TRect = (Left: 0; Top: 0; Right: 0; Bottom: 0);
var
  MHS: PMOUSEHOOKSTRUCT;
begin
  if (wParam = WM_NCLBUTTONDBLCLK) and FHideMaximize then
    Exit(1);

  MHS := PMOUSEHOOKSTRUCT(lParam);

  if FMMFLauncher.UseRegularTitleBar then
  begin
    // With the usual custom drawn title bar it's possible to resize the window at the top which makes no sense with the regular title bar
    GetClientRect(MHS^.hwnd, Rect);

    ClientToScreen(MHS^.hwnd, P);
    Rect.Top := P.Y;
    Rect.Left := P.X;
    Rect.Height := 5;

    if PtInRect(Rect, MHS^.pt) then
      Exit(1);
  end else
  begin
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
  UnreadChatCount: Integer;
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

  FMMFLauncher.Chats.GetUnreadChats(Days, Length(FNotifyData.szTip), FMMFLauncher.ExcludeUnreadMessagesMutedChats, UnreadChatCount, ToolTip);

  FNotifyData.hIcon := CreateNotificationIcon;

  // SendMessage(FHandle, WM_SETICON, ICON_SMALL, FNotifyData.hIcon);

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
  if not FMMFLauncher.UseRegularTitleBar then
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

function TWindow.CreateNotificationIcon: HICON;
var
  DC, Bmp, Icon: HANDLE;
  BitmapStart: Pointer = nil;
  IconInfo: TIconInfo = (fIcon: False; xHotspot: 0; yHotspot: 0; hbmMask: 0; hbmColor: 0);
  BitmapHeader: BITMAPV5HEADER;
  BitmapInfo: BITMAP;
begin
  if ExtractIconExW(PWideChar(UnicodeString(TPaths.ExePath)), 0, nil, @Icon, 1) <> 1 then
    raise Exception.Create('ExtractIconExW() failed');

  GetIconInfo(Icon, IconInfo);

  GetObject(IconInfo.hbmColor, SizeOf(BitmapInfo), @BitmapInfo);

  DeleteObject(IconInfo.hbmColor);
  DeleteObject(IconInfo.hbmMask);

  ZeroMemory(@BitmapHeader, SizeOf(BitmapHeader));
  BitmapHeader.bV5Size := SizeOf(BitmapHeader);
  BitmapHeader.bV5Width := BitmapInfo.bmWidth;
  BitmapHeader.bV5Height := -BitmapInfo.bmHeight;
  BitmapHeader.bV5Planes := 1;
  BitmapHeader.bV5BitCount := 32;
  BitmapHeader.bV5Compression := BI_RGB;

  DC := CreateCompatibleDC(0);
  Bmp := TCreateDIBSection(@CreateDIBSection)(DC, BitmapHeader, DIB_RGB_COLORS, BitmapStart, 0, 0);

  SelectObject(DC, Bmp);
  DrawIconEx(DC, 0, 0, Icon, BitmapInfo.bmWidth, BitmapInfo.bmHeight, 0, 0, DI_NORMAL);

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
