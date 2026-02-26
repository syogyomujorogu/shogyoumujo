@echo off
chcp 65001 >nul
setlocal
set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set "EMULATOR_EXE=%ANDROID_SDK_ROOT%\emulator\emulator.exe"
set "TARGET_AVD=Pixel_9a"
echo ========================================
echo エミュレータ修復スクリプト
echo ========================================
echo.

echo [1/5] %TARGET_AVD% エミュレータで起動を試みます...
echo.

cd /d "%~dp0.."

echo [2/5] ADBサーバーを起動...
"%ADB%" kill-server >nul 2>&1
"%ADB%" start-server >nul 2>&1

echo [3/5] エミュレータを起動中（バックグラウンド）...
start "" "%EMULATOR_EXE%" -avd %TARGET_AVD% -gpu swiftshader_indirect

echo [4/5] デバイス接続待機中...
"%ADB%" wait-for-device >nul 2>&1

set "DEVICE_ID="
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

echo [ERROR] %TARGET_AVD% のデバイスIDを特定できませんでした。
pause
exit /b 1

:device_found
echo ブート完了待機中... (%DEVICE_ID%)
set /a RETRIES=0

:wait_boot
set "BOOT_DONE="
for /f "usebackq delims=" %%B in (`"%ADB%" -s %DEVICE_ID% shell getprop sys.boot_completed 2^>nul`) do set "BOOT_DONE=%%B"
if "%BOOT_DONE%"=="1" goto :boot_ready
set /a RETRIES+=1
if %RETRIES% GEQ 45 goto :boot_timeout
timeout /t 2 /nobreak >nul
goto :wait_boot

:boot_timeout
echo [WARN] ブート完了確認がタイムアウトしました。起動処理を続行します。

:boot_ready
echo ✓ エミュレータ準備完了

echo [5/5] デバイス接続確認...
"%ADB%" devices

echo.
echo ========================================
echo エミュレータが起動しました！
echo ========================================
echo.
echo Flutterアプリを起動しますか？ (Y/N)
choice /c YN /n /m "選択: "

if errorlevel 2 goto :end
if errorlevel 1 goto :run

:run
echo.
echo Flutterアプリを起動中...
flutter run -d %DEVICE_ID% --no-version-check

:end
pause
