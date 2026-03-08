@echo off
rem ========================================
rem _common.bat - 共通設定＆ユーティリティ
rem 他のbatから call で読み込んで使う
rem ========================================

rem --- 環境変数 ---
set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set "EMULATOR_EXE=%ANDROID_SDK_ROOT%\emulator\emulator.exe"
set "TARGET_AVD=Pixel_9a"
set "DEVICE_ID="

rem --- 作業ディレクトリをfrontendルートへ ---
cd /d "%~dp0.."
exit /b 0
