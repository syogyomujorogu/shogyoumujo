@echo off
rem ========================================
rem _find_device.bat - TARGET_AVD のデバイスIDを検出
rem 結果: DEVICE_ID に設定（見つからなければ空）
rem ========================================

set "DEVICE_ID="
for /f "skip=1 tokens=1,2" %%A in ('"%ADB%" devices 2^>nul') do (
    if /I "%%B"=="device" (
        for /f "usebackq delims=" %%N in (`"%ADB%" -s %%A emu avd name 2^>nul`) do (
            for /f "tokens=1" %%X in ("%%N") do (
                if /I "%%X"=="%TARGET_AVD%" (
                    set "DEVICE_ID=%%A"
                    exit /b 0
                )
            )
        )
    )
)
exit /b 1
