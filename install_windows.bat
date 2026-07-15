@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

REM Установочный / упаковочный скрипт Forum для Windows.
REM Примеры:
REM   install_windows.bat
REM   install_windows.bat -Zip
REM   install_windows.bat -PackageOnly
REM   install_windows.bat -SkipBuild -Zip

echo.
echo Forum — установка на Windows
echo.

where flutter >nul 2>&1
if errorlevel 1 (
  echo Flutter не найден в PATH.
  echo Установите Flutter и Visual Studio 2022 ^(Desktop development with C++^).
  echo https://docs.flutter.dev/get-started/install/windows
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_windows.ps1" %*
set ERR=%ERRORLEVEL%
if not %ERR%==0 (
  echo.
  echo Установка завершилась с ошибкой %ERR%.
  pause
  exit /b %ERR%
)

echo.
pause
exit /b 0
