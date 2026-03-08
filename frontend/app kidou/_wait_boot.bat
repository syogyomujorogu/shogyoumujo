@echo off
rem ========================================
rem _wait_boot.bat - エミュレータのブート完了を待機
rem 前提: DEVICE_ID が設定済み
rem ========================================

echo ブート完了待機中... (%DEVICE_ID%)
set /a _RETRIES=0

:_wait_loop
set "_BOOT_DONE="
for /f "usebackq delims=" %%B in (`"%ADB%" -s %DEVICE_ID% shell getprop sys.boot_completed 2^>nul`) do set "_BOOT_DONE=%%B"
if "%_BOOT_DONE%"=="1" (
    echo [OK] エミュレータ準備完了
    exit /b 0
)
set /a _RETRIES+=1
if %_RETRIES% GEQ 45 (
    echo [WARN] ブート完了確認がタイムアウトしました。続行します。
    exit /b 0
)
timeout /t 2 /nobreak >nul
goto :_wait_loop
