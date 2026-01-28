// =============================================================================
// login_screen.dart - ログイン・新規登録画面
// =============================================================================
// このファイルの役割:
// 1. ユーザーのログイン機能
// 2. 新規アカウント登録機能
// 3. Supabaseの認証システムとの連携
// 4. ログイン成功後、自動的にホーム画面に遷移
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// ログイン画面のStatefulWidget（状態を持つウィジェット）
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// ログイン画面の状態管理クラス
class _LoginScreenState extends State<LoginScreen> {
  // 各テキストフィールドのコントローラー（入力値を管理）
  final _emailController = TextEditingController(); // メールアドレス入力
  final _passwordController = TextEditingController(); // パスワード入力
  final _nameController = TextEditingController(); // 表示名入力
  final _userIdController = TextEditingController(); // ユーザーID入力（新規追加）
  
  bool _isLoading = false; // ローディング状態を管理
  bool _isSignUp = false; // 新規登録モードかどうかを管理

  // ログイン処理を実行する関数
  Future<void> _signIn() async {
    // ローディング表示を開始
    setState(() => _isLoading = true);
    
    try {
      // Supabaseの認証APIを使ってログイン
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(), // 入力されたメールアドレス
        password: _passwordController.text.trim(), // 入力されたパスワード
      );

      // ログイン成功メッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログイン成功！')),
        );
      }
    } on AuthException catch (e) {
      // 認証エラーが発生した場合の処理
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ログイン失敗: ${e.message}')),
        );
      }
    } finally {
      // ローディング表示を終了
      setState(() => _isLoading = false);
    }
  }

  // 新規登録処理を実行する関数
  Future<void> _signUp() async {
    // ローディング表示を開始
    setState(() => _isLoading = true);
    
    try {
      // 入力されたユーザーIDの重複チェック
      final existingUser = await supabase
          .from('users')
          .select('user_id')
          .eq('custom_user_id', _userIdController.text.trim())
          .maybeSingle();

      // 既にそのIDが使われている場合はエラー
      if (existingUser != null) {
        throw Exception('このユーザーIDは既に使用されています');
      }

      // Supabaseの認証APIを使って新規アカウントを作成
      final response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // アカウント作成に成功した場合
      if (response.user != null) {
        // usersテーブルに追加情報を保存
        await supabase.from('users').insert({
          'user_id': response.user!.id, // Supabaseが自動生成するUUID
          'custom_user_id': _userIdController.text.trim(), // ユーザーが設定するID
          'display_name': _nameController.text.trim(), // 表示名
          'email': _emailController.text.trim(), // メールアドレス
          'photo_url': 'https://via.placeholder.com/150', // デフォルトのアイコン
          'degraded_photo_url': '', // 劣化顔画像のURL（初期は空）
          'is_degraded': false, // 劣化状態かどうか
          'degrade_level': 0, // 劣化レベル（0〜9）
          'current_calories': 0, // 今日の摂取カロリー
          'current_steps': 0, // 今日の歩数
          'mercy_points': 0, // 慈悲ポイント
          'friends': [], // フレンドリスト（空の配列）
        });

        // 登録成功メッセージを表示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登録成功！メールを確認してください')),
          );
        }
      }
    } on AuthException catch (e) {
      // 認証エラーが発生した場合の処理
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登録失敗: ${e.message}')),
        );
      }
    } catch (e) {
      // その他のエラーが発生した場合の処理
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    } finally {
      // ローディング表示を終了
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // セーフエリア内に表示（ノッチやステータスバーを避ける）
      body: SafeArea(
        // スクロール可能にする
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              // アプリのアイコン
              const Icon(
                Icons.self_improvement,
                size: 100,
                color: Colors.orange,
              ),
              const SizedBox(height: 24),
              // アプリのタイトル
              const Text(
                '諸行無常ログ',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // キャッチコピー
              const Text(
                '「暴食」は煩悩。代償は「苦悩」。',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 48),
              
              // 新規登録モードの場合のみ表示
              if (_isSignUp)
                TextField(
                  controller: _userIdController,
                  decoration: InputDecoration(
                    labelText: 'ユーザーID（英数字、検索用）',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              if (_isSignUp) const SizedBox(height: 16),
              
              // 新規登録モードの場合のみ表示
              if (_isSignUp)
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: '名前',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              if (_isSignUp) const SizedBox(height: 16),
              
              // メールアドレス入力フィールド
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'メールアドレス',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // パスワード入力フィールド（入力内容を隠す）
              TextField(
                controller: _passwordController,
                obscureText: true, // パスワードを隠す
                decoration: InputDecoration(
                  labelText: 'パスワード',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // ローディング中はプログレスインジケータを表示
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      // 新規登録モードかログインモードかで処理を切り替え
                      onPressed: _isSignUp ? _signUp : _signIn,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: Text(_isSignUp ? '新規登録' : 'ログイン'),
                    ),
              const SizedBox(height: 16),
              
              // モード切り替えボタン
              TextButton(
                onPressed: () {
                  // 新規登録モードとログインモードを切り替え
                  setState(() => _isSignUp = !_isSignUp);
                },
                child: Text(
                  _isSignUp ? 'すでにアカウントをお持ちの方' : '新規登録はこちら',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // メモリリークを防ぐため、コントローラーを破棄
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _userIdController.dispose();
    super.dispose();
  }
}
