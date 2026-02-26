@echo off
chcp 65001 >nul
cd /d "%~dp0.."
setlocal

set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set "EMULATOR_EXE=%ANDROID_SDK_ROOT%\emulator\emulator.exe"
set "TARGET_AVD=Pixel_9a"

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

set "AVD_EXISTS="
for /f "usebackq delims=" %%N in (`"%EMULATOR_EXE%" -list-avds`) do (
	if /I "%%N"=="%TARGET_AVD%" set "AVD_EXISTS=1"
)
if not defined AVD_EXISTS (
	echo [ERROR] %TARGET_AVD% が見つかりません。使用可能なAVD:
	"%EMULATOR_EXE%" -list-avds
	pause
	exit /b 1
)
echo 使用AVD: %TARGET_AVD%

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

echo エミュレータ起動中...
echo ※初回は「Process system isn't responding」が出ることがありますが「Wait」を押して待機してください。
start "" "%EMULATOR_EXE%" -avd %TARGET_AVD% -gpu auto

echo デバイス接続待機中...
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
echo エミュレータ準備完了

echo 起動直前にデバイスIDを再確認中...
set "DEVICE_ID="
for /f "skip=1 tokens=1,2" %%A in ('"%ADB%" devices') do (
	if /I "%%B"=="device" (
		for /f "usebackq delims=" %%N in (`"%ADB%" -s %%A emu avd name 2^>nul`) do (
			for /f "tokens=1" %%X in ("%%N") do (
				if /I "%%X"=="%TARGET_AVD%" (
					set "DEVICE_ID=%%A"
					goto :run_with_device
				)
			)
		)
	)
)

echo [ERROR] %TARGET_AVD% のデバイスIDを取得できませんでした。
pause
exit /b 1

:run_with_device
echo 対象デバイス: %DEVICE_ID%
echo Flutterアプリ起動中...
echo アプリを起動中...
flutter run -d %DEVICE_ID% --no-version-check
goto :end

:end
