unit Constants;

interface

uses
  Messages;

const
  WM_SHARED = WM_USER + 100;

  // Launcher window messages
  WM_CHILD_PROCESS_STARTED = WM_SHARED + 1;
  WM_MAINWINDOW_CREATED = WM_SHARED + 2;
  WM_WINDOW_SHOWN = WM_SHARED + 3;
  WM_PATCH_RESOURCES = WM_SHARED + 4;
  WM_CHECK_LINKS = WM_SHARED + 5;

  // WhatsApp window messages
  WM_CHATS_CHANGED = WM_SHARED + 10;
  WM_ACTIVATE_INSTANCE = WM_SHARED + 11;

  // Shared window messages
  WM_EXIT = WM_SHARED + 20;
  WM_NOTIFICATION_ICON = WM_SHARED + 21;

  APPNAME = 'WhatsMissing';
  WHATSMISSING_CLASSNAME: PWideChar = 'WhatsMissing_WndCls';
  WHATSMISSING_EXENAME_32 = 'whatsmissing-i386.exe';
  WHATSMISSING_EXENAME_64 = 'whatsmissing-x86_64.exe';
  WHATSMISSING_LIBRARYNAME_32 = 'whatsmissing-i386.dll';
  WHATSMISSING_LIBRARYNAME_64 = 'whatsmissing-x86_64.dll';
  WHATSAPP_CLASSNAME: PWideChar = 'Chrome_WidgetWin_1';
  WHATSAPP_WINDOWNAME: PWideChar = 'WhatsApp';
  WHATSAPP_APP_MODEL_ID = 'com.squirrel.WhatsApp.WhatsApp';

  WHATSAPP_EXE = 'WhatsApp.exe';
  UPDATE_EXE = 'Update.exe';
  LOGFILE = 'whatsmissing.log';

  MMFNAME_LAUNCHER = 'Local\WM_Launcher';
  MMFNAME_SETTINGS = 'Local\WM_Settings';
  MMFNAME_RESOURCES = 'Local\WM_Resources_%d';
  EVENTNAME_RESOURCES = 'Local\WM_ResourcesEvent_%d';
  EVENTNAME_SETTINGS_CHANGED = 'Local\WM_Settings_Changed';

  SETTINGS_ARG = 'settings';
  INJECT_ARG = 'inject';
  PROCESSHANDLE_ARG = 'processhandle';
  THREADHANDLE_ARG = 'threadhandle';
  PREPARE_UNINSTALL_ARG = 'prepareuninstall';
  UNINSTALL_ARG = 'uninstall';
  UNINSTALL_PARENTHANDLE_ARG = 'parenthandle';

  WNDPROC_PROPNAME: PWideChar = 'WhatsMissing_WndProc';

  UTF8_BOM: array[0..2] of Byte = ($EF, $BB, $BF);

implementation

end.
