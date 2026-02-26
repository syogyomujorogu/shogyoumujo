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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/login_screen.dart';
import 'screens/main_home_screen.dart';

// アプリケーション起動時に最初に実行される関数
Future<void> main() async {
  // Flutterの初期化を確実に行う（非同期処理を使う前に必要）
  WidgetsFlutterBinding.ensureInitialized();

  // 環境変数ファイルを読み込む
  await dotenv.load(fileName: ".env");

  // Supabase（バックエンドサービス）の初期化
  // 環境変数から設定を読み込む（セキュリティ向上）
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // アプリを起動
  runApp(const ShogyoMujoApp());
}

// アプリケーション全体のルートウィジェット
class ShogyoMujoApp extends StatelessWidget {
  const ShogyoMujoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Supabaseクライアントのインスタンスを取得
    // final supabase = Supabase.instance.client; // 未使用のためコメントアウト

    return MaterialApp(
      // デバッグバナーを非表示にする
      debugShowCheckedModeBanner: false,
      // アプリのタイトル
      title: '諸行無常ログ',
      // アプリ全体のテーマカラー（オレンジ系）
      theme: ThemeData(primarySwatch: Colors.orange),

      // 認証状態の監視と画面の切り替え
      home: _AuthGate(),
    );
  }
}

/// 認証状態を監視し、タイムアウト付きで画面を切り替えるウィジェット
class _AuthGate extends StatefulWidget {
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    // 5秒経っても認証イベントが来なければタイムアウト
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _timedOut = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // タイムアウトまたはデータ到着
        if (snapshot.hasData) {
          final session = snapshot.data!.session;
          if (session == null) {
            return const LoginScreen();
          } else {
            return const MainHomeScreen();
          }
        }

        // タイムアウト → 既存セッションを直接チェック
        if (_timedOut) {
          final session = supabase.auth.currentSession;
          if (session != null) {
            return const MainHomeScreen();
          }
          return const LoginScreen();
        }

        // ロード中
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
