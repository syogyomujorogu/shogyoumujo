import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';

/// デバッグ用アカウント切り替え画面
/// 開発時に複数のテストアカウントを簡単に切り替えるためのツール
class DebugAccountSwitcherScreen extends StatefulWidget {
  const DebugAccountSwitcherScreen({super.key});

  @override
  State<DebugAccountSwitcherScreen> createState() =>
      _DebugAccountSwitcherScreenState();
}

class _DebugAccountSwitcherScreenState
    extends State<DebugAccountSwitcherScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _statusMessage;

  // テストアカウントの定義
  final List<Map<String, String>> _testAccounts = [
    {
      'email': 'test1mujo@gmail.com',
      'password': 'test123456',
      'user_id': 'test_user_1',
      'display_name': 'テストユーザー1',
      'description': '通常ユーザー（既存アカウント想定）',
    },
    {
      'email': 'test2.mujo@gmail.com',
      'password': 'test123456',
      'user_id': 'test_user_2',
      'display_name': 'テストユーザー2',
      'description': 'フレンド申請テスト用',
    },
    {
      'email': 'test3.mujo@gmail.com',
      'password': 'test123456',
      'user_id': 'test_user_3',
      'display_name': 'テストユーザー3',
      'description': '投稿テスト用',
    },
    {
      'email': 'riop0306@icloud.com',
      'password': 'riop1192RIOP',
      'user_id': 'f4cf8afd-9f50-48c3-928f-952ac32290aa',
      'display_name': '管理者',
      'description': 'デバッグ・管理用アカウント（実アカウント）',
    },
  ];

  /// 指定したアカウントに切り替え
  Future<void> _switchToAccount(Map<String, String> account) async {
    setState(() {
      _isLoading = true;
      _statusMessage = '${account['display_name']}に切り替え中...';
    });

    try {
      // 現在のセッションをログアウト
      await supabase.auth.signOut();

      // 新しいアカウントでログイン
      final response = await supabase.auth.signInWithPassword(
        email: account['email']!,
        password: account['password']!,
      );

      if (response.user != null) {
        setState(() {
          _statusMessage = '✅ ${account['display_name']}にログインしました';
        });

        // ログイン成功：認証状態の変化をmain.dartが監視してメイン画面に自動遷移
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          // デバッグメニュー → プロフィール画面 → ボトムナビまで全て遡って戻す
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      String errorMessage = 'エラー: ${e.toString()}';

      // アカウントが存在しない場合、作成を提案
      if (e.toString().contains('Invalid login credentials') ||
          e.toString().contains('User not found')) {
        errorMessage = '⚠️ アカウントが存在しません。「テストアカウント作成」ボタンで作成してください。';
      }

      setState(() {
        _statusMessage = errorMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// すべてのテストアカウントを一括作成
  Future<void> _createAllTestAccounts() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'テストアカウントを作成中...';
    });

    int successCount = 0;
    int skipCount = 0;
    int errorCount = 0;

    for (var account in _testAccounts) {
      try {
        // アカウント作成
        final response = await supabase.auth.signUp(
          email: account['email']!,
          password: account['password']!,
        );

        if (response.user != null) {
          // users テーブルにユーザー情報を追加
          try {
            await supabase.from('users').insert({
              'user_id': account['user_id'],
              'email': account['email'], // emailは必須カラム
              'display_name': account['display_name'],
              'photo_url': 'https://via.placeholder.com/150',
              'karma': 50, // 初期カルマ値
            });

            successCount++;
            print('✅ ${account['display_name']} を作成しました');
          } catch (dbError) {
            if (dbError.toString().contains('duplicate key')) {
              skipCount++;
              print('⚠️ ${account['display_name']} は既に存在します（スキップ）');
            } else {
              errorCount++;
              print('❌ ${account['display_name']} のDB登録エラー: $dbError');
            }
          }

          // 作成後はサインアウト
          await supabase.auth.signOut();
        }
      } catch (authError) {
        if (authError.toString().contains('User already registered')) {
          skipCount++;
          print('⚠️ ${account['display_name']} は既に存在します');
        } else {
          errorCount++;
          print('❌ ${account['display_name']} の作成エラー: $authError');
        }
      }

      // レート制限回避のため少し待機
      await Future.delayed(const Duration(milliseconds: 500));
    }

    setState(() {
      _statusMessage =
          '✅ 完了\n成功: $successCount件\nスキップ: $skipCount件\nエラー: $errorCount件';
      _isLoading = false;
    });
  }

  /// 現在のログイン状態を確認
  Future<void> _checkCurrentUser() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        final userData = await supabase
            .from('users')
            .select()
            .eq('email', user.email!)
            .single();

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('現在のログイン情報'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('表示名: ${userData['display_name']}'),
                  Text('ユーザーID: ${userData['user_id']}'),
                  Text('メール: ${user.email}'),
                  Text('カルマ: ${userData['karma'] ?? 50}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        print('ユーザー情報の取得エラー: $e');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインしていません')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🛠️ デバッグアカウント切り替え'),
        backgroundColor: Colors.orange,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage ?? '処理中...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 警告メッセージ
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⚠️ 開発者向けツール',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.orange,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'このツールは開発・デバッグ専用です。\n本番環境では使用しないでください。',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 現在のユーザー確認ボタン
                  ElevatedButton.icon(
                    onPressed: _checkCurrentUser,
                    icon: const Icon(Icons.person),
                    label: const Text('現在のログイン情報を確認'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // テストアカウント一括作成ボタン
                  ElevatedButton.icon(
                    onPressed: _createAllTestAccounts,
                    icon: const Icon(Icons.add_circle),
                    label: const Text('テストアカウントを一括作成'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ステータスメッセージ
                  if (_statusMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusMessage!,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),

                  // アカウントリスト
                  const Text(
                    'テストアカウント一覧',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._testAccounts.map((account) => _buildAccountCard(account)),
                ],
              ),
            ),
    );
  }

  /// アカウントカードを構築
  Widget _buildAccountCard(Map<String, String> account) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _switchToAccount(account),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // アイコン
              CircleAvatar(
                backgroundColor: Colors.orange.shade100,
                child: Text(
                  account['display_name']![0],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // テキスト情報
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account['display_name']!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      account['user_id']!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      account['description']!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // 切り替えアイコン
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
