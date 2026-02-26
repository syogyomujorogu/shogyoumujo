// =============================================================================
// search_screen.dart - ユーザー検索画面
// =============================================================================
// このファイルの役割:
// 1. ユーザーをIDまたはメールで検索
// 2. ユーザープロフィール表示
// 3. フレンド追加機能
// 4. フレンド解除機能
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

/// 検索画面のStatefulWidget
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// 検索画面の状態管理クラス
class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isLoading = false;
  Map<String, dynamic>? _currentUserData;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 現在のユーザー情報を読み込む
  Future<void> _loadCurrentUserData() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final userData =
          await supabase.from('users').select().eq('user_id', userId).single();

      if (mounted) {
        setState(() {
          _currentUserData = userData;
        });
      }
    } catch (e) {
      print('❌ 現在のユーザー情報読み込みエラー: $e');
    }
  }

  /// フレンド関係をチェック（friendsテーブルを確認）
  Future<bool> _isFriend(String friendId) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final result = await supabase
          .from('friends')
          .select()
          .eq('user_id', userId)
          .eq('friend_id', friendId)
          .maybeSingle();
      return result != null;
    } catch (e) {
      print('❌ フレンド関係チェックエラー: $e');
      return false;
    }
  }

  /// フレンド申請の状態をチェック
  Future<String?> _checkFriendRequestStatus(String targetId) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 自分 → 相手への申請
      final sentRequest = await supabase
          .from('friend_requests')
          .select()
          .eq('requester_id', userId)
          .eq('target_id', targetId)
          .maybeSingle();

      if (sentRequest != null) {
        return sentRequest['status']; // 'pending' | 'accepted' | 'rejected'
      }

      // 相手 → 自分への申請
      final receivedRequest = await supabase
          .from('friend_requests')
          .select()
          .eq('requester_id', targetId)
          .eq('target_id', userId)
          .maybeSingle();

      if (receivedRequest != null && receivedRequest['status'] == 'pending') {
        return 'received'; // 承認待ち
      }

      return null; // 申請なし
    } catch (e) {
      print('❌ フレンド申請状態チェックエラー: $e');
      return null;
    }
  }

  /// フレンドボタンの状態を取得
  Future<Map<String, dynamic>> _getFriendButtonState(String targetId) async {
    final isFriend = await _isFriend(targetId);
    final requestStatus = await _checkFriendRequestStatus(targetId);

    return {
      'isFriend': isFriend,
      'requestStatus': requestStatus,
    };
  }

  /// ユーザーを検索
  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _isSearching = true;
      });

      // ユーザーIDまたはメールで検索
      // ブロック・ミュートユーザーIDを取得
      final userId = supabase.auth.currentUser!.id;
      final blockedRows = await supabase
          .from('blocked_users')
          .select('blocked_user_id')
          .eq('user_id', userId);
      final mutedRows = await supabase
          .from('muted_users')
          .select('muted_user_id')
          .eq('user_id', userId);
      final blockedIds = blockedRows
          .map<String>((row) => row['blocked_user_id'] as String)
          .toSet();
      final mutedIds = mutedRows
          .map<String>((row) => row['muted_user_id'] as String)
          .toSet();

      final results = await supabase
          .from('users')
          .select()
          .or('custom_user_id.ilike.%$query%,email.ilike.%$query%')
          .limit(10);

      // ブロック・ミュートユーザー除外
      final filteredResults = (results as List).where((user) {
        final uid = user['user_id'] as String?;
        return uid != null &&
            !blockedIds.contains(uid) &&
            !mutedIds.contains(uid);
      }).toList();

      if (mounted) {
        setState(() {
          _searchResults = filteredResults;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ ユーザー検索エラー: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('検索エラー: $e')),
        );
      }
    }
  }

  /// フレンド申請を送信
  Future<void> _sendFriendRequest(String targetId, String targetName) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      if (targetId == userId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('自分自身には申請できません')),
        );
        return;
      }

      // 既にフレンドか確認
      if (await _isFriend(targetId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('既にフレンドです')),
        );
        return;
      }

      // フレンド申請を作成
      await supabase.from('friend_requests').insert({
        'requester_id': userId,
        'target_id': targetId,
        'status': 'pending',
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 通知を送信
      final currentUserName = _currentUserData?['display_name'] ?? 'ユーザー';
      await supabase.from('notifications').insert({
        'recipient_id': targetId,
        'sender_id': userId,
        'notification_type': 'friend_request',
        'content': {},
        'message': '$currentUserName さんからフレンド申請が届きました',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $targetName にフレンド申請を送信しました'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {}); // UIを更新
      }
    } catch (e) {
      print('❌ フレンド申請エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  /// フレンド申請を承認
  Future<void> _acceptFriendRequest(
      String requesterId, String requesterName) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // friend_requestsを取得
      final request = await supabase
          .from('friend_requests')
          .select()
          .eq('requester_id', requesterId)
          .eq('target_id', userId)
          .single();

      // ステータスを更新
      await supabase.from('friend_requests').update({
        'status': 'accepted',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', request['id']);

      // friendsテーブルに双方向レコードを追加
      await supabase.from('friends').insert([
        {'user_id': requesterId, 'friend_id': userId},
        {'user_id': userId, 'friend_id': requesterId},
      ]);

      // 承認通知を送信
      final currentUserName = _currentUserData?['display_name'] ?? 'ユーザー';
      await supabase.from('notifications').insert({
        'recipient_id': requesterId,
        'sender_id': userId,
        'notification_type': 'friend_accept',
        'content': {},
        'message': '$currentUserName さんがフレンド申請を承認しました',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $requesterName のフレンド申請を承認しました'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {}); // UIを更新
      }
    } catch (e) {
      print('❌ フレンド申請承認エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  /// フレンド削除
  Future<void> _removeFriend(String friendId, String friendName) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // friendsテーブルから双方向レコードを削除
      await supabase
          .from('friends')
          .delete()
          .eq('user_id', userId)
          .eq('friend_id', friendId);

      await supabase
          .from('friends')
          .delete()
          .eq('user_id', friendId)
          .eq('friend_id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $friendName をフレンドから削除しました'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {}); // UIを更新
      }
    } catch (e) {
      print('❌ フレンド削除エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ユーザーを検索'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 検索ボックス
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ユーザーIDまたはメールを入力...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _isSearching = false;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (value) {
                setState(() {});
                if (value.isNotEmpty) {
                  _searchUsers(value);
                } else {
                  setState(() {
                    _searchResults = [];
                    _isSearching = false;
                  });
                }
              },
            ),
          ),
          // 検索結果
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : !_isSearching
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search,
                              size: 80,
                              color: Colors.orange.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'ユーザーを検索してフレンドを追加しましょう',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_off,
                                  size: 80,
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'ユーザーが見つかりません',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final user = _searchResults[index];
                              final userId = user['user_id'] as String;
                              final userName = user['display_name'] ?? 'ユーザー';
                              final userCustomId = user['custom_user_id'] ?? '';
                              final userEmail = user['email'] ?? '';
                              final userPhotoUrl = user['photo_url'] as String?;
                              final isCurrentUser =
                                  userId == supabase.auth.currentUser!.id;

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: userPhotoUrl != null &&
                                            userPhotoUrl.isNotEmpty
                                        ? NetworkImage(userPhotoUrl)
                                        : null,
                                    child: userPhotoUrl == null ||
                                            userPhotoUrl.isEmpty
                                        ? const Icon(Icons.person)
                                        : null,
                                  ),
                                  title: Text(userName),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (userCustomId.isNotEmpty)
                                        Text('@$userCustomId'),
                                      if (userEmail.isNotEmpty) Text(userEmail),
                                    ],
                                  ),
                                  trailing: isCurrentUser
                                      ? null
                                      : FutureBuilder<Map<String, dynamic>>(
                                          future: _getFriendButtonState(userId),
                                          builder: (context, snapshot) {
                                            if (!snapshot.hasData) {
                                              return const SizedBox(
                                                width: 80,
                                                child: Center(
                                                  child: SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }

                                            final state = snapshot.data!;
                                            final isFriend =
                                                state['isFriend'] as bool;
                                            final requestStatus =
                                                state['requestStatus']
                                                    as String?;

                                            if (isFriend) {
                                              return ElevatedButton(
                                                onPressed: () => _removeFriend(
                                                    userId, userName),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                ),
                                                child: const Text(
                                                  '解除',
                                                  style: TextStyle(
                                                      color: Colors.white),
                                                ),
                                              );
                                            } else if (requestStatus ==
                                                'pending') {
                                              return const ElevatedButton(
                                                onPressed: null,
                                                child: Text('申請中'),
                                              );
                                            } else if (requestStatus ==
                                                'received') {
                                              return ElevatedButton(
                                                onPressed: () =>
                                                    _acceptFriendRequest(
                                                        userId, userName),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                ),
                                                child: const Text(
                                                  '承認',
                                                  style: TextStyle(
                                                      color: Colors.white),
                                                ),
                                              );
                                            } else {
                                              return ElevatedButton(
                                                onPressed: () =>
                                                    _sendFriendRequest(
                                                        userId, userName),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.orange,
                                                ),
                                                child: const Text(
                                                  '申請',
                                                  style: TextStyle(
                                                      color: Colors.white),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
