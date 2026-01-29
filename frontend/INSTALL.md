# 諸行無常ログ (Shogyo Mujo Log)

**キャッチコピー：** 食べるのは煩悩、ハゲるのは罰。カロリーという業を、歩数という徳で焼き払え。

修業を通じて心身を鍛え、仲間と共に無常を感じながら健康を追求するアプリです。

## 📱 主な機能

### 🍚 食事記録とAI分析

- 食事の写真を撮影・選択すると、AI（Google Gemini）が自動で料理名とカロリーを推定
- 投稿した食事を仲間と共有
- 仲間の投稿に「無常を感じる」（いいね機能）

### 🏃 修業システム

- 目標歩数と修業期間を設定
- 開始時体重を記録
- 日々の体重と歩数を記録
- 週次サマリーで進捗確認
- 修業完了時に詳細な統計レポート表示

### 👥 フレンド機能

- メールアドレスでフレンド検索
- フレンドリクエストの送受信
- 仲間の食事投稿を閲覧

### 📊 進捗管理

- 体重の推移グラフ
- 歩数の達成率
- カロリー消費の記録

## 🚀 セットアップ方法

### 前提条件

- Flutter SDK 3.10.0以上
- Dart 3.0.0以上
- Android Studio（Android開発の場合）
- Supabaseアカウント
- Google Gemini APIキー

### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd shogyoumujo/frontend
```

### 2. 依存関係のインストール

```bash
flutter pub get
```

### 3. Supabaseの設定

#### 3.1 Supabaseプロジェクト作成

1. [Supabase](https://supabase.com/)でプロジェクトを作成
2. Project Settings → API から以下を取得：
   - Project URL
   - anon/public key

#### 3.2 環境変数の設定

`lib/main.dart` の以下の部分を自分のSupabase情報に変更：

```dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',      // ← ここ
  anonKey: 'YOUR_SUPABASE_KEY',  // ← ここ
);
```

#### 3.3 データベーステーブルの作成

SupabaseのSQL Editorで以下のSQLを実行：

```sql
-- ユーザーテーブル
CREATE TABLE users (
  user_id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  name TEXT,
  profile_image_url TEXT,
  bio TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  training_started BOOLEAN DEFAULT FALSE,
  training_start_date TIMESTAMP WITH TIME ZONE,
  training_end_date TIMESTAMP WITH TIME ZONE,
  training_daily_steps_goal INTEGER,
  training_months INTEGER,
  training_start_weight REAL,
  training_before_photo TEXT,
  weekly_summary_day INTEGER DEFAULT 0
);

-- 体重記録テーブル
CREATE TABLE weight_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  weight REAL NOT NULL,
  note TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 歩数記録テーブル
CREATE TABLE steps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  step_count INTEGER NOT NULL DEFAULT 0,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, date)
);

-- 食事記録テーブル
CREATE TABLE meals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  meal_type TEXT NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  description TEXT,
  photo_url TEXT,
  calories INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 食事へのいいねテーブル
CREATE TABLE meal_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meal_id UUID NOT NULL,
  user_id TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(meal_id, user_id)
);

-- フレンドリクエストテーブル
CREATE TABLE mercy_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id TEXT NOT NULL,
  receiver_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(requester_id, receiver_id)
);

-- インデックス作成
CREATE INDEX idx_weight_logs_user_id ON weight_logs(user_id);
CREATE INDEX idx_weight_logs_created_at ON weight_logs(created_at DESC);
CREATE INDEX idx_steps_user_id ON steps(user_id);
CREATE INDEX idx_steps_date ON steps(date DESC);
CREATE INDEX idx_meals_user_id ON meals(user_id);
CREATE INDEX idx_meals_created_at ON meals(created_at DESC);
CREATE INDEX idx_meal_likes_meal_id ON meal_likes(meal_id);
CREATE INDEX idx_meal_likes_user_id ON meal_likes(user_id);
CREATE INDEX idx_mercy_requests_receiver ON mercy_requests(receiver_id);
CREATE INDEX idx_mercy_requests_status ON mercy_requests(status);
```

#### 3.4 ストレージバケットの作成

1. Supabase Dashboard → Storage → Create Bucket
2. バケット名: `meals`
3. Public accessを有効化

### 4. Google Gemini APIの設定

#### 4.1 APIキーの取得

1. [Google AI Studio](https://aistudio.google.com/app/apikey)でAPIキーを取得

#### 4.2 APIキーの設定

`lib/screens/meal_post_sheet.dart` の以下の部分を変更：

```dart
const apiKey = 'YOUR_GEMINI_API_KEY'; // ← ここに自分のAPIキーを入力
```

### 5. アプリの実行

#### 開発モード

```bash
flutter run
```

#### リリースビルド（APK）

```bash
flutter build apk --release
```

生成されたAPKファイル：
`build/app/outputs/flutter-apk/app-release.apk`

## 📦 APKの配布方法

### Android端末へのインストール

1. `app-release.apk` を端末に転送
2. 端末の設定 → セキュリティ → 「提供元不明のアプリ」を許可
3. APKファイルをタップしてインストール

### 注意事項

- Google Playに公開していないため、各端末で「提供元不明のアプリ」の許可が必要
- 全員が同じSupabaseプロジェクトを使用すること

## 🎮 使い方

### 初回起動

1. アプリを起動
2. 「新規登録」でアカウント作成
3. メールアドレスとパスワードを入力
4. プロフィール設定（任意）

### 修業の開始

1. プロフィール画面の「修業を始める」ボタンをタップ
2. 現在の体重を入力
3. 目標歩数と修業期間を設定
4. 「修業を始める」で開始

### 食事の投稿

1. ホーム画面下部の「＋」ボタンをタップ
2. 写真を選択（自動的にAI分析開始）
3. AI推定結果（料理名・カロリー）を確認
4. 説明を入力（必要に応じて修正）
5. 「投稿する」をタップ

### フレンドの追加

1. プロフィール画面の「フレンドを追加」をタップ
2. 相手のメールアドレスを入力して検索
3. 「フレンドリクエストを送る」をタップ
4. 相手が承認すると、お互いの投稿が見られるように

## 🛠 技術スタック

- **フレームワーク**: Flutter 3.10+
- **言語**: Dart 3.0+
- **バックエンド**: Supabase（PostgreSQL）
- **認証**: Supabase Auth
- **ストレージ**: Supabase Storage
- **AI**: Google Gemini 1.5 Flash
- **パッケージ**:
  - `supabase_flutter`: Supabaseクライアント
  - `image_picker`: 画像選択
  - `pedometer`: 歩数計測
  - `http`: HTTP通信
  - `intl`: 日時フォーマット

## 🔐 セキュリティとプライバシー

- ユーザー認証はSupabaseで管理
- パスワードはハッシュ化されて保存
- 画像はSupabase Storageに保存
- RLS（Row Level Security）は現在無効（開発環境）

**本番環境での推奨事項：**

- RLSポリシーを有効化
- APIキーを環境変数で管理
- HTTPS通信の強制

## 🐛 トラブルシューティング

### ビルドエラーが出る

```bash
flutter clean
flutter pub get
flutter run
```

### 画像が表示されない

- Supabaseのストレージバケット設定を確認
- バケットがPublicになっているか確認

### AI分析が動かない

- Gemini APIキーが正しく設定されているか確認
- インターネット接続を確認
- API使用量の上限を確認

### 歩数が記録されない

- Android: Google Fitの権限を許可
- iOS: ヘルスケアの権限を許可

## 📝 ライセンス

このプロジェクトは教育目的で作成されています。

## 👥 チーム

**チーム名**: 観世音菩薩

## 🙏 謝辞

- [Supabase](https://supabase.com/) - バックエンドサービス
- [Google Gemini](https://ai.google.dev/) - AI画像分析
- [Flutter](https://flutter.dev/) - クロスプラットフォーム開発

---

**諸行無常** - すべては移り変わる。健康も、体重も、修業次第。
