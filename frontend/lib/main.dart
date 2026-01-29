// =============================================================================
// main.dart - アプリケーションのエントリーポイント
// =============================================================================
// このファイルの役割:
// 1. Flutterアプリの起動処理
// 2. Supabaseの初期化（データベース接続の設定）
// 3. 認証状態に応じた画面の切り替え（ログイン画面 or ホーム画面）
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/main_home_screen.dart';

// アプリケーション起動時に最初に実行される関数
Future<void> main() async {
  // Flutterの初期化を確実に行う（非同期処理を使う前に必要）
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase（バックエンドサービス）の初期化
  // url: Supabaseプロジェクトの固有URL
  // anonKey: 匿名アクセス用の公開キー（フロントエンドで使用可能）
  await Supabase.initialize(
    url: 'https://dbrbufzvahscmipqinpq.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRicmJ1Znp2YWhzY21pcHFpbnBxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk0NjEzNjgsImV4cCI6MjA4NTAzNzM2OH0.yZ6HU-0FKD2SeX-uWP-ogdsociSWl2Yv0OSwQ-K5UvY',
  );

  // アプリを起動
  runApp(const ShogyoMujoApp());
}

// アプリケーション全体のルートウィジェット
class ShogyoMujoApp extends StatelessWidget {
  const ShogyoMujoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Supabaseクライアントのインスタンスを取得
    final supabase = Supabase.instance.client;

    return MaterialApp(
      // デバッグバナーを非表示にする
      debugShowCheckedModeBanner: false,
      // アプリのタイトル
      title: '諸行無常ログ',
      // アプリ全体のテーマカラー（オレンジ系）
      theme: ThemeData(primarySwatch: Colors.orange),

      // 認証状態の監視と画面の切り替え
      home: StreamBuilder<AuthState>(
        // Supabaseの認証状態の変化を監視するストリーム
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          // データがまだ読み込まれていない場合はローディング表示
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // 現在のセッション（ログイン状態）を取得
          final session = snapshot.data!.session;

          // セッションがnull = ログインしていない → ログイン画面を表示
          if (session == null) {
            return const LoginScreen();
          } else {
            // セッションがある = ログイン済み → メインホーム画面（ボトムナビ対応）を表示
            return const MainHomeScreen();
          }
        },
      ),
    );
  }
}
