unit Paths;

interface

uses
  Constants,
  ShlObj,
  SysUtils;

type
  TPaths = class
  private
    class var
    FExeDir: string;
    FExePath: string;
    FTempDir: string;
    FWhatsAppDir: string;
    FWhatsMissingDir: string;
    FSettingsPath: string;
    FWhatsAppExePath: string;
    FPatchedResourceDir: string;
    FDesktopDir: string;
    FStartMenuDir: string;
    FUserPinnedDir: string;
  public
    class procedure Init; static;

    class property ExeDir: string read FExeDir;
    class property ExePath: string read FExePath;
    class property TempDir: string read FTempDir;
    class property WhatsAppDir: string read FWhatsAppDir;
    class property WhatsMissingDir: string read FWhatsMissingDir;
    class property SettingsPath: string read FSettingsPath;
    class property WhatsAppExePath: string read FWhatsAppExePath;
    class property PatchedResourceDir: string read FPatchedResourceDir;
    class property DesktopDir: string read FDesktopDir;
    class property StartMenuDir: string read FStartMenuDir;
    class property UserPinnedDir: string read FUserPinnedDir;
  end;

implementation

uses
  Functions;

class procedure TPaths.Init;
begin
  FExeDir := ExtractFileDir(ParamStr(0));
  FExePath := ParamStr(0);
  FTempDir := TFunctions.GetTempPath;
  FWhatsAppDir := ConcatPaths([TFunctions.GetSpecialFolder(CSIDL_LOCAL_APPDATA), 'WhatsApp']);
  FWhatsMissingDir := ConcatPaths([TFunctions.GetSpecialFolder(CSIDL_LOCAL_APPDATA), APP_NAME]);
  FSettingsPath := ConcatPaths([TFunctions.GetSpecialFolder(CSIDL_APPDATA), APP_NAME, 'wm_settings.json']);
  FWhatsAppExePath := ConcatPaths([TFunctions.GetSpecialFolder(CSIDL_LOCAL_APPDATA), 'WhatsApp', WHATSAPP_EXE]);
  FPatchedResourceDir := ConcatPaths([TFunctions.GetSpecialFolder(CSIDL_APPDATA), APP_NAME, RESOURCES_DIR_NAME]);
  FDesktopDir := TFunctions.GetSpecialFolder(CSIDL_DESKTOP);
  FStartMenuDir := TFunctions.GetSpecialFolder($000B);
  FUserPinnedDir := ConcatPaths([TFunctions.GetSpecialFolder(CSIDL_APPDATA), 'Microsoft\Internet Explorer\Quick Launch']);
end;

end.
