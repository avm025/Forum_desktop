#Requires -Version 5.1
<#
.SYNOPSIS
  Сборка и установка Forum (forum_app) на Windows.

.DESCRIPTION
  Запускайте этот скрипт на компьютере с Windows (сборка macOS → Windows не поддерживается).

.PARAMETER Zip
  Создать dist\forum_app-windows.zip для передачи на другой ПК.

.PARAMETER PackageOnly
  Только упаковать в ZIP, не устанавливать локально.

.PARAMETER SkipBuild
  Не собирать (использовать уже собранный Release).

.PARAMETER Open
  Запустить после установки.

.PARAMETER Dest
  Каталог установки (по умолчанию: %LOCALAPPDATA%\Programs\Forum).

.EXAMPLE
  .\install_windows.ps1
  .\install_windows.ps1 -Zip
  .\install_windows.ps1 -PackageOnly
  .\install_windows.ps1 -SkipBuild -Zip
#>
[CmdletBinding()]
param(
    [switch]$Zip,
    [switch]$PackageOnly,
    [switch]$SkipBuild,
    [switch]$Open,
    [string]$Dest = "",
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$AppName = "forum_app"
$DisplayName = "Forum"
$ExeName = "forum_app.exe"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $ScriptDir "build\windows\x64\runner\Release"
$BuildExe = Join-Path $BuildDir $ExeName
$DistDir = Join-Path $ScriptDir "dist"

if ([string]::IsNullOrWhiteSpace($Dest)) {
    $Dest = Join-Path $env:LOCALAPPDATA "Programs\Forum"
}

function Write-Log([string]$Message) {
    Write-Host "→ $Message"
}

function Write-Err([string]$Message) {
    Write-Host "✗ $Message" -ForegroundColor Red
    exit 1
}

function Show-Usage {
    @"
Установка / упаковка Forum для Windows

  .\install_windows.ps1 [параметры]

Параметры:
  -Zip           Создать dist\forum_app-windows.zip
  -PackageOnly   Только упаковать (не устанавливать)
  -SkipBuild     Не собирать (использовать существующий Release)
  -Open          Запустить после установки
  -Dest PATH     Каталог установки (по умолчанию: %LOCALAPPDATA%\Programs\Forum)
  -Help          Эта справка

Требования (на Windows):
  • Flutter SDK в PATH
  • Visual Studio 2022 с «Desktop development with C++»
  • Windows 10/11 x64

На другом ПК после скачивания zip:
  1. Распаковать архив
  2. Запустить install_on_this_pc.bat
     или скопировать содержимое в нужную папку и запустить forum_app.exe
"@
}

if ($Help) {
    Show-Usage
    exit 0
}

if ($env:OS -ne "Windows_NT") {
    Write-Err "Этот скрипт нужно запускать на Windows (не на macOS/Linux)."
}

if ($PackageOnly) {
    $Zip = $true
    $InstallLocal = $false
} else {
    $InstallLocal = $true
}

# --- Сборка ---
if (-not $SkipBuild) {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Write-Err "Flutter не найден в PATH. Установите: https://docs.flutter.dev/get-started/install/windows"
    }

    Write-Log "Зависимости Flutter…"
    Push-Location $ScriptDir
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { Write-Err "flutter pub get завершился с ошибкой" }

        Write-Log "Сборка release для Windows (может занять несколько минут)…"
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { Write-Err "Сборка Windows не удалась" }
    } finally {
        Pop-Location
    }
} else {
    Write-Log "Пропуск сборки (-SkipBuild)"
}

if (-not (Test-Path $BuildExe)) {
    Write-Err "Не найден $BuildExe. Запустите без -SkipBuild на Windows."
}

# --- Локальная установка ---
if ($InstallLocal) {
    Write-Log "Установка в $Dest …"
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null

    # Полная копия Release-папки (exe + dll + data)
    Get-ChildItem -Path $Dest -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path $BuildDir "*") -Destination $Dest -Recurse -Force

    $InstalledExe = Join-Path $Dest $ExeName
    Write-Log "Готово: $InstalledExe"

    # Ярлык в меню Пуск
    try {
        $StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
        New-Item -ItemType Directory -Force -Path $StartMenu | Out-Null
        $ShortcutPath = Join-Path $StartMenu "$DisplayName.lnk"
        $Wsh = New-Object -ComObject WScript.Shell
        $Shortcut = $Wsh.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = $InstalledExe
        $Shortcut.WorkingDirectory = $Dest
        $Shortcut.Description = $DisplayName
        $Shortcut.Save()
        Write-Log "Ярлык: $ShortcutPath"
    } catch {
        Write-Log "Ярлык в меню Пуск не создан: $_"
    }

    if ($Open) {
        Write-Log "Запуск…"
        Start-Process -FilePath $InstalledExe -WorkingDirectory $Dest
    }
}

# --- Упаковка ZIP ---
if ($Zip) {
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    $ZipPath = Join-Path $DistDir "$AppName-windows.zip"
    $Staging = Join-Path $DistDir "windows-staging"

    Write-Log "Создание ZIP для передачи…"
    if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

    New-Item -ItemType Directory -Force -Path $Staging | Out-Null
    Copy-Item -Path (Join-Path $BuildDir "*") -Destination $Staging -Recurse -Force

    # Скрипт установки на чужом ПК
    $HelperBat = Join-Path $Staging "install_on_this_pc.bat"
    @"
@echo off
chcp 65001 >nul
setlocal
set "SRC=%~dp0"
set "DEST=%LOCALAPPDATA%\Programs\Forum"
echo → Установка Forum в %DEST% ...
if not exist "%DEST%" mkdir "%DEST%"
xcopy /E /I /Y /Q "%SRC%*" "%DEST%\" >nul
if errorlevel 1 (
  echo Не удалось скопировать файлы.
  pause
  exit /b 1
)
rem Не копируем сами скрипты установки как обязательные, exe уже в DEST
echo → Создание ярлыка...
powershell -NoProfile -Command ^
  "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('%APPDATA%\Microsoft\Windows\Start Menu\Programs\Forum.lnk');" ^
  "$s.TargetPath='%DEST%\$ExeName'; $s.WorkingDirectory='%DEST%'; $s.Save()"
echo → Запуск...
start "" "%DEST%\$ExeName"
echo Готово.
pause
"@ | Set-Content -Path $HelperBat -Encoding ASCII

    $Readme = Join-Path $Staging "КАК_УСТАНОВИТЬ.txt"
    @"
Установка Forum на этот компьютер (Windows)
===========================================

Способ 1:
  Дважды щёлкните install_on_this_pc.bat

Способ 2:
  Скопируйте все файлы из этой папки в любое место
  и запустите forum_app.exe

Требования: Windows 10/11 x64.

Примечание для разработчика:
  Сборку .exe нужно делать на Windows-машине:
    flutter build windows --release
    .\install_windows.ps1 -SkipBuild -Zip
"@ | Set-Content -Path $Readme -Encoding UTF8

    Compress-Archive -Path (Join-Path $Staging "*") -DestinationPath $ZipPath -Force
    Remove-Item $Staging -Recurse -Force
    Write-Log "ZIP: $ZipPath"
    Write-Log "Передайте этот файл на другой Windows-ПК."
}

Write-Log "Готово."
