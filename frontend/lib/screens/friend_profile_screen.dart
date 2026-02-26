// =============================================================================
// friend_profile_screen.dart - フレンドのプロフィール画面
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class FriendProfileScreen extends StatefulWidget {
  final String friendId;

  const FriendProfileScreen({super.key, required this.friendId});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  Map<String, dynamic>? _friendData;
  List<Map<String, dynamic>> _friendMeals = [];
  Map<String, dynamic>? _equippedBadge;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFriendData();
  }

  Future<void> _loadFriendData() async {
    setState(() => _isLoading = true);
    try {
      // フレンドのユーザーデータを取得
      final userData = await supabase
          .from('users')
          .select()
          .eq('user_id', widget.friendId)
          .maybeSingle();

      // フレンドの食事投稿を取得
      final meals = await supabase
          .from('meals')
          .select()
          .eq('user_id', widget.friendId)
          .order('created_at', ascending: false);

      // フレンドの装備バッジを取得
      final equippedData = await supabase
          .from('user_equipped_badge')
          .select('*, badges(*)')
          .eq('user_id', widget.friendId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _friendData = userData;
          _friendMeals = List<Map<String, dynamic>>.from(meals);
          _equippedBadge = equippedData?['badges'];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('エラー: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_friendData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('プロフィール')),
        body: const Center(child: Text('ユーザーが見つかりません')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_friendData!['display_name'] ?? 'ユーザー'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // プロフィール情報
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // プロフィール画像
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: _friendData!['photo_url'] != null
                            ? NetworkImage(_friendData!['photo_url'])
                            : null,
                        child: _friendData!['photo_url'] == null
                            ? Text(
                                (_friendData!['display_name'] ?? 'U')[0]
                                    .toUpperCase(),
                                style: const TextStyle(fontSize: 32),
                              )
                            : null,
                      ),
                      // 装備バッジ
                      if (_equippedBadge != null)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                color:
                                    _getBorderColor(_equippedBadge!['rarity']),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _equippedBadge!['icon'],
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  // 統計情報
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _friendData!['display_name'] ?? 'ユーザー',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_friendData!['bio'] != null) ...[
                          const SizedBox(height: 8),
                          Text(_friendData!['bio']),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          '投稿: ${_friendMeals.length}件',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            // 投稿一覧
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '投稿',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _friendMeals.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('まだ投稿がありません'),
                          ),
                        )
                      : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                          itemCount: _friendMeals.length,
                          itemBuilder: (context, index) {
                            final meal = _friendMeals[index];
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _getMealTypeIcon(meal['meal_type']),
                                    style: const TextStyle(fontSize: 32),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${meal['calories'] ?? 0}kcal',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBorderColor(String rarity) {
    switch (rarity) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'platinum':
        return const Color(0xFFE5E4E2);
      default:
        return Colors.grey;
    }
  }

  String _getMealTypeIcon(String? mealType) {
    switch (mealType) {
      case 'breakfast':
        return '🌅';
      case 'lunch':
        return '🌞';
      case 'dinner':
        return '🌙';
      default:
        return '🍽️';
    }
  }
}
