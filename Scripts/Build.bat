@ECHO OFF

REM Path to fpc binaries
SET "FPCBIN=D:\Lazarus\fpc\3.2.0\bin\x86_64-win64"

IF NOT EXIST %FPCBIN% GOTO FAILENVIRONMENT

REM Extend PATH
SET "PATH=%PATH%;%FPCBIN%;%FPCBIN%\..\..\..\.."

REM Build images
SET "INSTANTFPCOPTIONS=-Fu%FPCBIN%\..\..\..\..\lcl\units\x86_64-win64\win32 -Fu%FPCBIN%\..\..\..\..\lcl\units\x86_64-win64 -Fu%FPCBIN%\..\..\..\..\components\lazutils\lib\x86_64-win64"

mkdir ..\Build\Resources
instantfpc ..\Scripts\ProcessImages.pas ..\Resources\Notification\*.png ..\Build\Resources\NotificationOverlays.pas

REM Build exes
cd ..\WhatsMissing
lazbuild --build-all --cpu=i386 --os=Win32 --build-mode=Release WhatsMissing.lpi
IF ERRORLEVEL 1 GOTO FAIL
lazbuild --build-all --cpu=x86_64 --os=Win64 --build-mode=Release WhatsMissing.lpi
IF ERRORLEVEL 1 GOTO FAIL

REM Build dlls
cd ..\WhatsMissing_Lib
lazbuild --build-all --cpu=i386 --os=Win32 --build-mode=Release WhatsMissing_Lib.lpi
IF ERRORLEVEL 1 GOTO FAIL
lazbuild --build-all --cpu=x86_64 --os=Win64 --build-mode=Release WhatsMissing_Lib.lpi
IF ERRORLEVEL 1 GOTO FAIL


REM Compress setup resources
cd ..
instantfpc Scripts\Compress.pas Build\WhatsMissing-i386.exe Build\Resources\WhatsMissing-i386.exe.z
instantfpc Scripts\Compress.pas Build\WhatsMissing-x86_64.exe Build\Resources\WhatsMissing-x86_64.exe.z
instantfpc Scripts\Compress.pas Build\WhatsMissing-i386.dll Build\Resources\WhatsMissing-i386.dll.z
instantfpc Scripts\Compress.pas Build\WhatsMissing-x86_64.dll Build\Resources\WhatsMissing-x86_64.dll.z

REM Build setup
cd WhatsMissing_Setup
lazbuild --build-all --cpu=i386 --os=Win32 --build-mode=Release WhatsMissing_Setup.lpi
IF ERRORLEVEL 1 GOTO FAIL

ECHO.
ECHO Build finished
ECHO.
GOTO END

:FAILENVIRONMENT
  ECHO.
  ECHO FPCBIN does not exist, please adjust variable
  ECHO.
  PAUSE
  GOTO END

:FAIL
  ECHO.
  ECHO Build failed
  ECHO.
  PAUSE

:END
