@echo off
rem ========================================
rem _start_emulator.bat - エミュレータ起動＆接続待機
rem 前提: _common.bat, _check_tools.bat 呼出済み
rem 結果: DEVICE_ID に設定
rem オプション: GPU_MODE (未設定なら auto)
rem ========================================

if not defined GPU_MODE set "GPU_MODE=auto"

rem --- AVD存在チェック ---
set "_AVD_EXISTS="
for /f "usebackq delims=" %%N in (`"%EMULATOR_EXE%" -list-avds`) do (
    if /I "%%N"=="%TARGET_AVD%" set "_AVD_EXISTS=1"
)
if not defined _AVD_EXISTS (
    echo [ERROR] AVD '%TARGET_AVD%' が見つかりません。利用可能なAVD:
    "%EMULATOR_EXE%" -list-avds
    exit /b 1
)

rem --- 既に起動中か確認 ---
call "%~dp0_find_device.bat"
if defined DEVICE_ID (
    echo [INFO] %TARGET_AVD% は既に起動中です (%DEVICE_ID%)
    exit /b 0
)

rem --- 起動 ---
echo %TARGET_AVD% エミュレータを起動中 (GPU: %GPU_MODE%)...
echo ※初回は「Process system isn't responding」が出ることがあります。「Wait」を押して待機してください。
start "" "%EMULATOR_EXE%" -avd %TARGET_AVD% -gpu %GPU_MODE%
"%ADB%" wait-for-device >nul 2>&1

rem --- デバイスID取得 ---
call "%~dp0_find_device.bat"
if not defined DEVICE_ID (
    echo [ERROR] エミュレータ接続に失敗しました。
    exit /b 1
)

rem --- ブート待機 ---
call "%~dp0_wait_boot.bat"
exit /b 0
