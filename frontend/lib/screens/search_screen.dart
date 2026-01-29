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
  const SearchScreen({Key? key}) : super(key: key);

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
      final results = await supabase
          .from('users')
          .select()
          .or('custom_user_id.ilike.%$query%,email.ilike.%$query%')
          .limit(10);

      if (mounted) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(results ?? []);
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

  /// フレンド追加
  Future<void> _addFriend(String friendId, String friendName) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      if (friendId == userId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('自分自身は追加できません')),
        );
        return;
      }

      final currentFriends =
          List<String>.from(_currentUserData?['friends'] ?? []);

      if (currentFriends.contains(friendId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('既にフレンドです')),
        );
        return;
      }

      currentFriends.add(friendId);

      await supabase.from('users').update({
        'friends': currentFriends,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      // ローカルデータを更新
      setState(() {
        _currentUserData?['friends'] = currentFriends;
        // 検索結果も更新
        for (var result in _searchResults) {
          if (result['user_id'] == friendId) {
            // UI状態を更新するため、検索結果をリロード
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $friendName をフレンドに追加しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ フレンド追加エラー: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
    }
  }

  /// フレンド削除
  Future<void> _removeFriend(String friendId, String friendName) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final currentFriends =
          List<String>.from(_currentUserData?['friends'] ?? []);

      currentFriends.removeWhere((id) => id == friendId);

      await supabase.from('users').update({
        'friends': currentFriends,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      // ローカルデータを更新
      setState(() {
        _currentUserData?['friends'] = currentFriends;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $friendName をフレンドから削除しました'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ フレンド削除エラー: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
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
                              final isFriend =
                                  (_currentUserData?['friends'] as List?)
                                          ?.contains(userId) ??
                                      false;
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
                                      : ElevatedButton(
                                          onPressed: () {
                                            if (isFriend) {
                                              _removeFriend(userId, userName);
                                            } else {
                                              _addFriend(userId, userName);
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isFriend
                                                ? Colors.red
                                                : Colors.orange,
                                          ),
                                          child: Text(
                                            isFriend ? 'フレンド中' : '追加',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
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
