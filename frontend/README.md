ここはフロントエンドです
※lib以外は触れないでください！！！！！！１

# 📱 諸行無常ログ - Frontend (Mobile App)

このディレクトリは、「諸行無常ログ」のフロントエンド（スマホアプリ本体）のソースコードです。
Flutter を使用して開発されており、iOS と Android の両方に対応しています。

## 🔧 技術スタック (Tech Stack)

- **フレームワーク**: Flutter 3.16+
- **言語**: Dart 3.0+
- **バックエンド連携**: Supabase Flutter SDK
- **主要パッケージ**:
  - `image_picker`: カメラ撮影
  - `pedometer`: 歩数計測
  - `flutter_local_notifications`: 催促通知
  - `http`: API通信

## 🚀 役割 (What this app does)

ユーザーが直接操作する画面と、スマホのセンサー機能を提供します。

1.  **食事の撮影 & 投稿**
    - カメラを起動し、撮影した画像をバックエンド（またはSupabase）へ送信します。
2.  **歩数の計測 (修行)**
    - バックグラウンドで歩数をカウントし、アバターの回復判定に使います。
3.  **アバター表示**
    - 現在の「業（カルマ）」の状態に合わせて、アイコン（正常/劣化）を切り替えて表示します。
4.  **通知の受信**
    - 朝・昼・夜の投稿期限が迫ると、ローカル通知で催促します。

## 🛠 開発環境の構築 (Flutter SDK)

公式サイトのダウンロードリンクが機能していない（404エラー等）場合に備え、GitHubから直接SDKを取得する方法を推奨しています。

### 1. Flutter SDKの取得

ターミナルまたはコマンドプロンプトを開き、SDKをインストールしたいディレクトリ（例: `C:\src` や `~/development`）で以下を実行してください。

```bash
git clone [https://github.com/flutter/flutter.git](https://github.com/flutter/flutter.git) -b stable
2. パスの設定
クローンしたフォルダ内にある bin フォルダへのパスを通します。

Windows: 1. 「システム環境変数の編集」 > 「環境変数」を開く 2. ユーザー変数の Path に [クローンした場所]\flutter\bin を追記

Mac: 1. ~/.zshrc（または ~/.bash_profile）に以下を追記 export PATH="$PATH:[クローンした場所]/flutter/bin" 2. source ~/.zshrc を実行

3. 導入確認
以下のコマンドを実行し、Flutterが正しく認識されているか確認してください。

Bash
flutter doctor
※ Android Toolchain や Xcode の項目に [✗] が出ている場合は、画面の指示に従ってセットアップを行ってください。

4. エディタの設定
VS Code: 拡張機能「Flutter」をインストール

Android Studio: Pluginから「Flutter」をインストール

## 🛠 開発者機能 (Developer Features)

### デバッグメニュー（隠し機能）

開発・テスト用のデバッグメニューにアクセスする方法：

1. アプリを起動し、プロフィール画面に移動
2. **プロフィール写真を5回連続でタップ**
3. 「🛠 開発者モードが有効になりました」と表示される
4. 右上のメニューボタンから「🛠 開発者デバッグメニュー」が選択可能になる

#### デバッグメニューの機能

- **📅 日付選択**: テストしたい日付を指定
- **🚶 歩数設定**: 指定日の歩数を自由に変更（既存データ上書き）
- **⚖️ 体重記録**: 任意の体重データを追加
- **✅ 修業強制完了**: 修業期間を即座に完了させる
- **🗑️ 全データリセット**: 歩数、体重、食事、修業データを一括削除（⚠️取り消し不可）

> **注意**: プロフィール写真の変更は**長押し**で行います。

> **セキュリティ**: 5回タップ後3秒以内にタップしないとカウントがリセットされるため、一般ユーザーが偶然有効化する可能性は低いです。

## ⚠️ トラブルシューティング (Troubleshooting)

### エラー: "Unable to determine engine version" または "engine.stamp/engine.realm file locked"

**症状**: `flutter run` 実行時に以下のエラーが発生する
```

別のプロセスで使用されているため、プロセスはファイル 'C:\src\flutter\bin\cache\engine.stamp' にアクセスできません
Error: Unable to determine engine version...

````

**原因**: 複数のdart.exeプロセスが同時にFlutterエンジンファイルへアクセスしようとしてファイルロックが発生

**解決方法**:

#### 方法1: バージョンチェックをスキップして起動（推奨）
```powershell
cd C:\Users\n1250282\Desktop\mujo\shogyoumujo\frontend
flutter run --no-version-check
````

#### 方法2: 自動修復スクリプトを使用

プロジェクトルートの `fix_flutter_lock.bat` を実行：

```powershell
.\fix_flutter_lock.bat
```

#### 方法3: 手動でプロセスを終了

1. PowerShellで実行：

```powershell
Get-Process | Where-Object {$_.Path -like "*flutter*" -or $_.Path -like "*dart*"} | Stop-Process -Force
```

2. その後、通常通り `flutter run --no-version-check` を実行

**予防策**:

- VS Codeで複数のターミナルを開いている場合は、不要なターミナルを閉じる
- `flutter run` を複数同時に実行しない
- エラーが出たら `Ctrl+C` で確実に終了してから再実行

### 🛡️ エラーを防ぐための正しい終了方法

#### アプリ実行中の終了手順

1. **ホットリロード中の場合**:
   - ターミナルで `q` キーを押して終了
   - または `Ctrl+C` を押してプロセスを停止

2. **VS Codeのデバッグ実行の場合**:
   - デバッグツールバーの停止ボタン（赤い■）をクリック
   - または `Shift+F5` で停止

3. **ターミナルを閉じる前に**:
   - 必ず `q` または `Ctrl+C` でFlutterプロセスを終了してから閉じる
   - ターミナルを×ボタンで強制終了すると、dartプロセスがバックグラウンドに残る可能性あり

#### VS Code終了時の注意

- **推奨**: VS Codeを閉じる前に、全てのターミナルで実行中のプロセスを停止
- ターミナルを開いたまま VS Code を閉じると、dartプロセスが残留する場合がある

#### 定期的なクリーンアップ

週に1回程度、以下のコマンドで残留プロセスをクリーンアップすることを推奨：

```powershell
# 残留しているFlutter/Dartプロセスを確認
Get-Process | Where-Object {$_.Path -like "*flutter*" -or $_.Path -like "*dart*"}

# 全て終了（作業中でないことを確認してから実行）
Get-Process | Where-Object {$_.Path -like "*flutter*" -or $_.Path -like "*dart*"} | Stop-Process -Force
```

#### ベストプラクティス

✅ **推奨される起動方法**:

```powershell
cd C:\Users\n1250282\Desktop\mujo\shogyoumujo\frontend
flutter run --no-version-check
```

✅ **推奨される終了方法**:

1. ターミナルで `q` を押す
2. プロセスが完全に終了するのを待つ（数秒）
3. ターミナルを閉じる

❌ **避けるべき操作**:

- ターミナルを×ボタンで強制終了
- `flutter run` 実行中にVS Codeを強制終了
- 複数のターミナルで同時に `flutter run` を実行

```

```
