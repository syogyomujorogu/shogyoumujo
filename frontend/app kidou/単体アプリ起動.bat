@echo off
chcp 65001 >nul
cd /d "%~dp0.."
setlocal

set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set "EMULATOR_EXE=%ANDROID_SDK_ROOT%\emulator\emulator.exe"
set "TARGET_AVD=Pixel_9a"
set "DEVICE_ID="

if not exist "%ADB%" (
    echo [ERROR] adb が見つかりません: %ADB%
    pause
    exit /b 1
)

if not exist "%EMULATOR_EXE%" (
    echo [ERROR] emulator.exe が見つかりません: %EMULATOR_EXE%
    pause
    exit /b 1
)

for /f "skip=1 tokens=1,2" %%A in ('"%ADB%" devices') do (
    if /I "%%B"=="device" (
        for /f "usebackq delims=" %%N in (`"%ADB%" -s %%A emu avd name 2^>nul`) do (
            for /f "tokens=1" %%X in ("%%N") do (
                if /I "%%X"=="%TARGET_AVD%" (
                    set "DEVICE_ID=%%A"
                    goto :device_found
                )
            )
        )
    )
)

echo [INFO] %TARGET_AVD% が起動していないため起動します...
start "" "%EMULATOR_EXE%" -avd %TARGET_AVD% -gpu auto -no-snapshot-load
"%ADB%" wait-for-device >nul 2>&1

for /f "skip=1 tokens=1,2" %%A in ('"%ADB%" devices') do (
    if /I "%%B"=="device" (
        for /f "usebackq delims=" %%N in (`"%ADB%" -s %%A emu avd name 2^>nul`) do (
            for /f "tokens=1" %%X in ("%%N") do (
                if /I "%%X"=="%TARGET_AVD%" (
                    set "DEVICE_ID=%%A"
                    goto :device_found
                )
            )
        )
    )
)

echo [ERROR] %TARGET_AVD% のデバイスIDを取得できませんでした。
pause
exit /b 1

:device_found
echo 対象デバイス: %DEVICE_ID%
echo Flutterアプリ起動中（エミュレータは起動済み前提）...
echo アプリを起動中...
flutter run -d %DEVICE_ID% --no-version-check

endlocal
