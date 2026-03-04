@echo off
chcp 65001 >nul
cd /d "%~dp0.."
setlocal

echo FlutterアプリのAPKビルドを新しいウィンドウで開始します...
start cmd /k "flutter build apk --no-version-check && if exist .\build\app\outputs\flutter-apk\app-release.apk (echo [OK] APKビルド成功: .\build\app\outputs\flutter-apk\app-release.apk) else (echo [ERROR] APKビルド失敗) & pause"
endlocal