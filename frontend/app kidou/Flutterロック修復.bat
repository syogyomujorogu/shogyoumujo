@echo off
chcp 65001 >nul
setlocal
set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set "EMULATOR_EXE=%ANDROID_SDK_ROOT%\emulator\emulator.exe"
set "TARGET_AVD=Pixel_9a"
echo ========================================
echo Flutter ファイルロック自動修復ツール
echo ========================================
echo.

echo [1/5] Flutterプロセスを確認中...
powershell -Command "Get-Process | Where-Object {$_.Path -like '*flutter*' -or $_.Path -like '*dart*'} | Select-Object Id, ProcessName | Format-Table -AutoSize"
echo.

echo [2/5] 全てのFlutter/Dartプロセスを終了中...
powershell -Command "Get-Process | Where-Object {$_.Path -like '*flutter*' -or $_.Path -like '*dart*'} | Stop-Process -Force -ErrorAction SilentlyContinue"
echo ✓ プロセスを終了しました
echo.

cd /d "%~dp0.."

echo [3/5] ファイルハンドルの解放を待機中...
timeout /t 2 /nobreak >nul
echo ✓ 待機完了
echo.

echo [4/5] Flutter cacheのクリーンアップ中...
powershell -Command "if (Test-Path 'C:\src\flutter\bin\cache\engine.stamp') { Remove-Item 'C:\src\flutter\bin\cache\engine.stamp' -Force -ErrorAction SilentlyContinue }"
powershell -Command "if (Test-Path 'C:\src\flutter\bin\cache\engine.realm') { Remove-Item 'C:\src\flutter\bin\cache\engine.realm' -Force -ErrorAction SilentlyContinue }"
echo ✓ クリーンアップ完了
echo.

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

:avd_fallback_selected
if not defined TARGET_AVD (
	echo [ERROR] 利用可能な AVD が見つかりません。Android Studio で作成してください。
	pause
	exit /b 1
)
echo 使用AVD: %TARGET_AVD%

echo ADBサーバーを再起動中...
"%ADB%" kill-server >nul 2>&1
"%ADB%" start-server >nul 2>&1

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

echo [5/5] %TARGET_AVD% エミュレータを起動中...
start "" "%EMULATOR_EXE%" -avd %TARGET_AVD% -gpu auto -no-snapshot-load

echo デバイス接続待機中...
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

echo [ERROR] エミュレータ接続に失敗しました。
echo Android Emulator画面が表示されているか確認して再実行してください。
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
echo.

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

echo [ERROR] デバイスIDを取得できませんでした（unauthorized/offline の可能性）。
echo ADBを再接続してから再実行してください。
pause
exit /b 1

:run_with_device
echo 対象デバイス: %DEVICE_ID%
echo Flutterアプリを起動中...
flutter run -d %DEVICE_ID% --no-version-check
goto :end

:end

pause
