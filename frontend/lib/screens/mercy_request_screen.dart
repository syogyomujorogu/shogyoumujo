// =============================================================================
// mercy_request_screen.dart - 慈悲リクエスト画面
// =============================================================================
// このファイルの役割:
// 1. 所持している慈悲ポイントの表示
// 2. 慈悲ポイントを使って劣化レベルを回復（1ポイント = 1レベル回復）
// 3. フレンドリストの表示
// 4. フレンドに慈悲ポイントをリクエスト
// 5. 劣化状態の救済システムの中核機能
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// 慈悲リクエスト画面のStatefulWidget
class MercyRequestScreen extends StatefulWidget {
  const MercyRequestScreen({Key? key}) : super(key: key);

  @override
  State<MercyRequestScreen> createState() => _MercyRequestScreenState();
}

// 慈悲リクエスト画面の状態管理クラス
class _MercyRequestScreenState extends State<MercyRequestScreen> {
  List<Map<String, dynamic>> _friends = []; // フレンドリスト
  Map<String, dynamic>? _userData; // 自分のユーザーデータ
  bool _isLoading = true; // ローディング状態

  @override
  void initState() {
    super.initState();
    // 画面が表示されたときにデータを読み込む
    _loadData();
  }

  // 必要なデータを読み込む関数
  Future<void> _loadData() async {
    final userId = supabase.auth.currentUser!.id;

    // ========== 自分のユーザー情報を取得 ==========
    final userResponse = await supabase
        .from('users')
        .select()
        .eq('user_id', userId)
        .single();

    setState(() {
      _userData = userResponse;
    });

    // ========== フレンドリストを取得 ==========
    final friendIds = List<String>.from(_userData?['friends'] ?? []);

    if (friendIds.isNotEmpty) {
      // フレンドのIDリストからユーザー情報を取得
      final friendsResponse = await supabase
          .from('users')
          .select()
          .inFilter('user_id', friendIds);

      setState(() {
        _friends = List<Map<String, dynamic>>.from(friendsResponse);
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// フレンドに慈悲ポイントをリクエストする関数
  Future<void> _requestMercy(String friendId, String friendName) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // ========== mercy_requests テーブルに記録 ==========
      await supabase.from('mercy_requests').insert({
        'requester_id': userId, // リクエストする人
        'receiver_id': friendId, // リクエストを受ける人
        'status': 'pending', // ステータス: 保留中
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$friendName さんに慈悲を求めました'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context); // 画面を閉じる
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('リクエストエラー: $e')),
        );
      }
    }
  }

  /// 慈悲ポイントを使って劣化レベルを回復する関数
  Future<void> _useMercyPoints() async {
    final userId = supabase.auth.currentUser!.id;
    final mercyPoints = (_userData?['mercy_points'] ?? 0) as int;
    final degradeLevel = (_userData?['degrade_level'] ?? 0) as int;

    // ========== バリデーション ==========
    // 慈悲ポイントが足りない場合
    if (mercyPoints <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('慈悲ポイントが不足しています')),
      );
      return;
    }

    // すでに劣化していない場合
    if (degradeLevel <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('すでに完全な状態です')),
      );
      return;
    }

    // ========== 劣化レベルを回復 ==========
    // 1ポイントで1レベル回復
    final newLevel = (degradeLevel - 1).clamp(0, 9);
    final newMercyPoints = mercyPoints - 1;
    final newIsDegraded = newLevel > 0;

    // usersテーブルを更新
    await supabase.from('users').update({
      'degrade_level': newLevel,
      'mercy_points': newMercyPoints,
      'is_degraded': newIsDegraded,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', userId);

    // データを再読み込み
    await _loadData();

    // 成功メッセージを表示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🙏 慈悲により劣化レベルが $degradeLevel → $newLevel に回復しました'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // データ読み込み中はローディング表示
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final mercyPoints = (_userData?['mercy_points'] ?? 0) as int;
    final degradeLevel = (_userData?['degrade_level'] ?? 0) as int;

    return Scaffold(
      appBar: AppBar(
        title: const Text('慈悲を求める'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== 慈悲ポイント表示カード ==========
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // ハートアイコン
                    const Icon(
                      Icons.favorite,
                      size: 60,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '所持している慈悲ポイント',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    // ポイント数を大きく表示
                    Text(
                      '$mercyPoints ポイント',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 現在の劣化レベルを表示
                    Text(
                      '現在の劣化レベル: $degradeLevel / 9',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // ポイント使用ボタン
                    ElevatedButton.icon(
                      onPressed: mercyPoints > 0 && degradeLevel > 0
                          ? _useMercyPoints // ポイントがあってレベルが1以上なら実行
                          : null, // それ以外は無効化
                      icon: const Icon(Icons.healing),
                      label: const Text('1ポイント使って回復する'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '※ 1ポイントで劣化レベルが1つ回復します',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ========== フレンドにリクエストセクション ==========
            const Text(
              'フレンドに慈悲を求める',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'フレンドに慈悲ポイントをリクエストできます',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),

            // フレンドがいない場合のメッセージ
            if (_friends.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: const [
                      Icon(Icons.people_outline, size: 60, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'まだフレンドがいません',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'プロフィール画面からフレンドを追加してください',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              // ========== フレンドリスト ==========
              Column(
                children: _friends.map((friend) {
                  final friendName = friend['display_name'] ?? 'ユーザー';
                  final photoUrl = friend['photo_url'] as String?;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      // プロフィール画像
                      leading: CircleAvatar(
                        backgroundImage: photoUrl != null && photoUrl != ''
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl == ''
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      // フレンド名
                      title: Text(friendName),
                      // メールアドレス
                      subtitle: Text(friend['email'] ?? ''),
                      // リクエストボタン
                      trailing: ElevatedButton.icon(
                        onPressed: () => _requestMercy(
                          friend['user_id'],
                          friendName,
                        ),
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text('リクエスト'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
