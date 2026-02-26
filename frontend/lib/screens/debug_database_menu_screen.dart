// =============================================================================
// debug_database_menu_screen.dart - Supabase データベースデバッグメニュー
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class DebugDatabaseMenuScreen extends StatefulWidget {
  const DebugDatabaseMenuScreen({super.key});

  @override
  State<DebugDatabaseMenuScreen> createState() =>
      _DebugDatabaseMenuScreenState();
}

class _DebugDatabaseMenuScreenState extends State<DebugDatabaseMenuScreen> {
  List<Map<String, dynamic>> _allUsers = [];
  String _selectedEmail = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  /// 全ユーザーを読み込む
  Future<void> _loadAllUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await supabase.from('users').select();
      setState(() => _allUsers = List<Map<String, dynamic>>.from(users));
    } catch (e) {
      _showSnackBar('エラー: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 特定のメールアドレスでユーザーを検索
  Future<void> _searchUserByEmail(String email) async {
    setState(() => _isLoading = true);
    try {
      final result = await supabase
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (result != null) {
        _showSnackBar('✅ ユーザーが見つかりました', Colors.green);
        _showUserDetailDialog(result);
      } else {
        _showSnackBar('❌ ユーザーが見つかりません', Colors.orange);

        // Auth ユーザーを確認
        _checkAuthUser(email);
      }
    } catch (e) {
      _showSnackBar('エラー: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Supabase Auth にユーザーが存在するか確認
  Future<void> _checkAuthUser(String email) async {
    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: 'temp123456',
      );

      if (response.user != null) {
        final userId = response.user!.id;
        _showSnackBar(
          '✅ Auth に存在します (ID: $userId)',
          Colors.blue,
        );

        // users テーブルに追加するか確認
        _showCreateUserDialog(userId, email);
      }
    } catch (e) {
      // エラーの場合は、ユーザーが既に存在する可能性
      if (e.toString().contains('already registered')) {
        _showSnackBar(
          '⚠️ Auth に既に登録済みです',
          Colors.orange,
        );
      } else {
        _showSnackBar('エラー: $e', Colors.red);
      }
    }
  }

  /// ユーザー詳細ダイアログを表示
  void _showUserDetailDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ユーザー詳細'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('ID', user['user_id']),
              _buildDetailRow('Email', user['email']),
              _buildDetailRow('Display Name', user['display_name'] ?? 'N/A'),
              _buildDetailRow('Custom ID', user['custom_user_id'] ?? 'N/A'),
              _buildDetailRow('Karma', (user['karma'] ?? 0).toString()),
              _buildDetailRow('Created', user['created_at'] ?? 'N/A'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// ユーザー作成ダイアログを表示
  void _showCreateUserDialog(String userId, String email) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ユーザーを作成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Auth ID: $userId'),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '表示名',
                hintText: 'テストユーザー1',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _createUser(userId, email, nameController.text);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('作成'),
          ),
        ],
      ),
    );
  }

  /// ユーザーを作成
  Future<void> _createUser(
      String userId, String email, String displayName) async {
    try {
      await supabase.from('users').insert({
        'user_id': userId,
        'email': email,
        'display_name': displayName.isNotEmpty ? displayName : 'テストユーザー',
      });

      _showSnackBar('✅ ユーザーを作成しました', Colors.green);
      _loadAllUsers();
    } catch (e) {
      _showSnackBar('エラー: $e', Colors.red);
    }
  }

  /// 詳細行を構築
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  /// スナックバーを表示
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🗄️ データベースデバッグ'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 検索欄
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue[50],
                  child: Column(
                    children: [
                      TextField(
                        onChanged: (value) =>
                            setState(() => _selectedEmail = value),
                        decoration: InputDecoration(
                          hintText: 'メールアドレスで検索...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _selectedEmail.isNotEmpty
                            ? () => _searchUserByEmail(_selectedEmail)
                            : null,
                        icon: const Icon(Icons.search),
                        label: const Text('検索'),
                      ),
                    ],
                  ),
                ),
                // ユーザー一覧
                Expanded(
                  child: _allUsers.isEmpty
                      ? const Center(
                          child: Text('ユーザーがありません'),
                        )
                      : ListView.builder(
                          itemCount: _allUsers.length,
                          itemBuilder: (context, index) {
                            final user = _allUsers[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    (user['display_name'] ?? 'U')
                                        .toString()
                                        .substring(0, 1),
                                  ),
                                ),
                                title: Text(user['display_name'] ?? 'No Name'),
                                subtitle: Text(user['email'] ?? 'No Email'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.info),
                                  onPressed: () => _showUserDetailDialog(user),
                                ),
                              ),
                            );
                          },
                        ),
                )
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadAllUsers,
        tooltip: 'リロード',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
