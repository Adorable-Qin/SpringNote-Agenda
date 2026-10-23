@echo off
setlocal
for %%I in ("%~dp0..\..") do set "SPRINGNOTE_ROOT=%%~fI"
set "SPRINGNOTE_TYPORA_LAB_DIR=%SPRINGNOTE_ROOT%\.toolchains\typora-lab\web"
set "APPDATA=%SPRINGNOTE_ROOT%\.toolchains\typora-lab\profile\Roaming"
set "LOCALAPPDATA=%SPRINGNOTE_ROOT%\.toolchains\typora-lab\profile\Local"
if not exist "%SPRINGNOTE_TYPORA_LAB_DIR%\index.html" (
  echo Run node tools/typora-lab/prepare.mjs first.
  pause
  exit /b 1
)
if not exist "%SPRINGNOTE_ROOT%\.toolchains\typora-lab\app\SpringNote.exe" (
  echo The local test application has not been built.
  pause
  exit /b 1
)
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
start "" "%SPRINGNOTE_ROOT%\.toolchains\typora-lab\app\SpringNote.exe"
