@echo off
rem ========================================
rem _check_tools.bat - ADB/エミュレータの存在確認
rem 戻り値: ERRORLEVEL 0=OK, 1=NG
rem ========================================

if not exist "%ADB%" (
    echo [ERROR] adb が見つかりません: %ADB%
    exit /b 1
)
if not exist "%EMULATOR_EXE%" (
    echo [ERROR] emulator.exe が見つかりません: %EMULATOR_EXE%
    exit /b 1
)
exit /b 0
