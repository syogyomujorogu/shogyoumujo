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
```
