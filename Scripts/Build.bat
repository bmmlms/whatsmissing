@ECHO OFF

REM Pathes of required tools
SET "FPCBIN=D:\Lazarus\fpc\3.2.2\bin\x86_64-win64"
SET "ZIP=D:\7-Zip\7z.exe"
SET "PLINK=C:\Program Files\PuTTY\plink.exe"

IF NOT EXIST %FPCBIN% GOTO FAILENVIRONMENT

REM Extend PATH
SET "PATH=%PATH%;%FPCBIN%;%FPCBIN%\..\..\..\.."

if exist ..\Build\ (
  rmdir /s /q ..\Build
)

REM Build images
SET "INSTANTFPCOPTIONS=-Fu%FPCBIN%\..\..\..\..\lcl\units\x86_64-win64\win32 -Fu%FPCBIN%\..\..\..\..\lcl\units\x86_64-win64 -Fu%FPCBIN%\..\..\..\..\components\lazutils\lib\x86_64-win64"

instantfpc ProcessImages.pas ..\Resources\Notification\*.png ..\WhatsMissing_Lib\NotificationOverlays.pas

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

cd ..
for %%f in (Build\*.*) do (
  type "%%f" | "%PLINK%" -batch gaia osslsigncode-sign.sh > "%%f-signed"
  IF ERRORLEVEL 1 GOTO FAIL
  move /y "%%f-signed" "%%f"
  IF ERRORLEVEL 1 GOTO FAIL
)

REM Compress setup resources
mkdir Build\SetupResources

instantfpc Scripts\WriteToc.pas Build\WhatsMissing-i386.exe EXE_32 Build\WhatsMissing-x86_64.exe EXE_64 Build\WhatsMissing-i386.dll LIB_32 Build\WhatsMissing-x86_64.dll LIB_64 > Build\SetupResources\Toc.bin
IF ERRORLEVEL 1 GOTO FAIL

type Build\WhatsMissing-i386.exe Build\WhatsMissing-x86_64.exe Build\WhatsMissing-i386.dll Build\WhatsMissing-x86_64.dll > Build\SetupResources\Files.bin
IF ERRORLEVEL 1 GOTO FAIL

type Build\SetupResources\Toc.bin Build\SetupResources\Files.bin > Build\SetupResources\Output.bin
IF ERRORLEVEL 1 GOTO FAIL

REM Build setup
cd WhatsMissing_Setup
lazbuild --build-all --cpu=i386 --os=Win32 --build-mode=Release WhatsMissing_Setup.lpi
IF ERRORLEVEL 1 GOTO FAIL

cd ..\Build

type WhatsMissing_Setup.exe | "%PLINK%" -batch gaia osslsigncode-sign.sh > WhatsMissing_Setup-signed.exe
IF ERRORLEVEL 1 GOTO FAIL
move /y WhatsMissing_Setup-signed.exe WhatsMissing_Setup.exe
IF ERRORLEVEL 1 GOTO FAIL

"%ZIP%" a dummy -tzip -mx=9 -so WhatsMissing_Setup.exe > WhatsMissing_Setup.zip
IF ERRORLEVEL 1 GOTO FAIL
cd ..

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
