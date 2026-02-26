// =============================================================================
// buddhist_meal_feed_screen.dart - 諸行無常ログ（仏教的食事投稿リール）画面
// =============================================================================
// このファイルの役割:
// 1. 友達や自分の食事投稿を仏教的なテーマでリール形式（縦スワイプ）で表示
// 2. 投稿画像・説明・投稿者情報を表示
// 3. 「無常を感じる」ボタン（いいね的）やコメント機能
// 4. Supabaseから食事投稿データを取得
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'meal_post_sheet.dart'; // 食事投稿用ボトムシート
import 'item_usage_dialog.dart'; // アイテム使用ダイアログ

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// 諸行無常ログ（仏教的食事投稿リール）画面のStatefulWidget
class BuddhistMealFeedScreen extends StatefulWidget {
  const BuddhistMealFeedScreen({super.key});

  @override
  State<BuddhistMealFeedScreen> createState() => _BuddhistMealFeedScreenState();
}

// 画面の状態管理クラス
class _BuddhistMealFeedScreenState extends State<BuddhistMealFeedScreen> {
  late PageController _pageController; // リール用ページコントローラー
  List<Map<String, dynamic>> _meals = []; // 食事投稿リスト
  bool _isLoading = true; // ローディング状態

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadMeals();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // 各ユーザーのダイエット統計情報を計算
  Map<String, dynamic> _calculateDietStats(
      String userId, List<Map<String, dynamic>> allMeals) {
    final userMeals = allMeals.where((m) => m['user_id'] == userId).toList();

    // 今週の投稿数
    final now = DateTime.now().toUtc();
    final weekAgo = now.subtract(const Duration(days: 7));
    final thisWeekMeals = userMeals.where((m) {
      final createdAt = DateTime.tryParse(m['created_at'] ?? '') ?? now;
      return createdAt.isAfter(weekAgo);
    }).length;

    // 連続投稿日数（ストリーク）を計算
    int streak = 0;
    DateTime? lastPostDate;
    final sortedMeals = List<Map<String, dynamic>>.from(userMeals)
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? now;
        final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? now;
        return bDate.compareTo(aDate);
      });

    for (final meal in sortedMeals) {
      final mealDate = DateTime.tryParse(meal['created_at'] ?? '');
      if (mealDate == null) continue;

      final mealDay = DateTime(mealDate.year, mealDate.month, mealDate.day);
      if (lastPostDate == null) {
        lastPostDate = mealDay;
        streak = 1;
      } else {
        final diff = lastPostDate.difference(mealDay).inDays;
        if (diff == 1) {
          streak++;
          lastPostDate = mealDay;
        } else if (diff > 1) {
          break;
        }
      }
    }

    // 頑張りレベルを判定
    String effortLevel = '修行中';
    if (thisWeekMeals >= 21) {
      effortLevel = '悟りの境地';
    } else if (thisWeekMeals >= 14) {
      effortLevel = '精進中';
    } else if (thisWeekMeals >= 7) {
      effortLevel = '継続中';
    }

    return {
      'thisWeekMeals': thisWeekMeals,
      'streak': streak,
      'effortLevel': effortLevel,
      'totalMeals': userMeals.length,
    };
  }

  // Supabaseから友達＋自分の食事投稿を取得（24時間以内のみ）
  Future<void> _loadMeals() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // friendsテーブルからフレンドIDを取得
      final friendsData = await supabase
          .from('friends')
          .select('friend_id')
          .eq('user_id', userId);
      final friendIds =
          friendsData.map<String>((row) => row['friend_id'] as String).toList();
      final ids = [...friendIds, userId];

      // ブロック・ミュートユーザーIDを取得
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

      // 友達＋自分の食事投稿を新しい順で取得
      final response = await supabase
          .from('meals')
          .select(
              '*, user:users!user_id(display_name, custom_user_id, photo_url)')
          .inFilter('user_id', ids)
          .order('created_at', ascending: false);

      // 24時間以内＆ブロック・ミュート除外
      final now = DateTime.now().toUtc();
      final filtered = response.where((meal) {
        final createdAt = DateTime.tryParse(meal['created_at'] ?? '') ?? now;
        final uid = meal['user_id'] as String?;
        return now.difference(createdAt).inHours < 24 &&
            uid != null &&
            !blockedIds.contains(uid) &&
            !mutedIds.contains(uid);
      }).toList();

      // 各投稿にダイエット統計情報を追加
      final mealsWithStats = filtered.map((meal) {
        final stats = _calculateDietStats(meal['user_id'], response);
        return {...meal, 'dietStats': stats};
      }).toList();

      if (!mounted) return;
      setState(() {
        _meals = mealsWithStats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _meals = [];
        _isLoading = false;
      });
    }
  }

  // 無常を感じる（いいね機能）- 24時間以内の投稿のみ有効
  Future<void> _feelImpermanence(String mealId) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 既にいいねしているかチェック
      final existing = await supabase
          .from('meal_likes')
          .select()
          .eq('meal_id', mealId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        // 既にいいねしている場合は削除（取り消し）
        await supabase
            .from('meal_likes')
            .delete()
            .eq('meal_id', mealId)
            .eq('user_id', userId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('無常を取り消しました'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        // いいねを追加
        await supabase.from('meal_likes').insert({
          'meal_id': mealId,
          'user_id': userId,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🙏 無常を感じました'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ローディング中はインジケーター
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // 投稿がない場合
    if (_meals.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('諸行無常ログ')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.self_improvement,
                    size: 80, color: Colors.orange[300]),
                const SizedBox(height: 24),
                const Text(
                  'まだ食事の記録がありません',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  '食事を投稿すると、ここに統計情報が表示されます：',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📊 表示される統計情報',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 12),
                      Text('🔥 連続記録日数（ストリーク）\n   毎日連続で投稿している日数'),
                      SizedBox(height: 8),
                      Text('📅 今週の投稿数\n   過去7日間の食事記録回数'),
                      SizedBox(height: 8),
                      Text('🍽️ 総記録数\n   これまでの総投稿数'),
                      SizedBox(height: 8),
                      Text('⭐ 修行レベル\n   投稿数に応じて自動判定\n   (修行中→継続中→精進中→悟りの境地)'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // リール形式で食事投稿を縦スワイプ表示
    // 食事投稿リール画面本体
    return Scaffold(
      appBar: AppBar(title: const Text('諸行無常ログ')),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _meals.length,
        itemBuilder: (context, index) {
          final meal = _meals[index];
          final user = meal['user'] ?? {};
          final photoUrl = meal['photo_url'] as String?;
          final description = meal['description'] as String?;
          final displayName = user['display_name'] ?? '無名の修行者';
          final userPhoto = user['photo_url'] as String?;
          final dietStats = meal['dietStats'] as Map<String, dynamic>? ?? {};

          return Stack(
            fit: StackFit.expand,
            children: [
              // 投稿画像
              if (photoUrl != null && photoUrl.isNotEmpty)
                Image.network(photoUrl, fit: BoxFit.cover)
              else
                Container(color: Colors.grey[300]),
              // ダイエット統計情報カード（上部）
              Positioned(
                top: 60,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$displayName の修行状況',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            '${dietStats['streak'] ?? 0}日',
                            '連続記録',
                            Icons.local_fire_department,
                          ),
                          _buildStatItem(
                            '${dietStats['thisWeekMeals'] ?? 0}回',
                            '今週の投稿',
                            Icons.calendar_today,
                          ),
                          _buildStatItem(
                            '${dietStats['totalMeals'] ?? 0}食',
                            '総記録数',
                            Icons.restaurant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '修行レベル: ${dietStats['effortLevel'] ?? '修行中'}',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 投稿情報のオーバーレイ
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundImage:
                                userPhoto != null && userPhoto.isNotEmpty
                                    ? NetworkImage(userPhoto)
                                    : null,
                            child: userPhoto == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(displayName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (description != null && description.isNotEmpty)
                        Text(description,
                            style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 12),
                      // 24時間以内の投稿のみ慈悲（無常）ボタンを有効化
                      Row(
                        children: [
                          Builder(
                            builder: (context) {
                              final createdAt =
                                  DateTime.tryParse(meal['created_at'] ?? '') ??
                                      DateTime.now().toUtc();
                              final isWithin24h = DateTime.now()
                                      .toUtc()
                                      .difference(createdAt)
                                      .inHours <
                                  24;
                              return ElevatedButton.icon(
                                onPressed: isWithin24h
                                    ? () =>
                                        _feelImpermanence(meal['id'].toString())
                                    : null, // 24時間超は無効
                                icon: const Icon(Icons.self_improvement),
                                label: Text(isWithin24h ? '無常を感じる' : '期限切れ'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isWithin24h
                                      ? Colors.orange[700]
                                      : Colors.grey,
                                  foregroundColor: Colors.white,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          // アイテム使用ボタン
                          Builder(
                            builder: (context) {
                              final currentUserId =
                                  supabase.auth.currentUser?.id;
                              final mealOwnerId = meal['user_id'] as String;
                              final isOwnMeal = currentUserId == mealOwnerId;

                              return ElevatedButton.icon(
                                onPressed: () async {
                                  final result = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => ItemUsageDialog(
                                      mealId: meal['id'].toString(),
                                      mealOwnerId: mealOwnerId,
                                      currentCalories: meal['calories'] as int,
                                      isOwnMeal: isOwnMeal,
                                    ),
                                  );
                                  // アイテム使用後にリストを再読み込み
                                  if (result == true) {
                                    _loadMeals();
                                  }
                                },
                                icon: Icon(isOwnMeal
                                    ? Icons.favorite
                                    : Icons.whatshot),
                                label: Text(isOwnMeal ? 'カロリー減' : 'カロリー増'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isOwnMeal
                                      ? Colors.green[700]
                                      : Colors.orange[700],
                                  foregroundColor: Colors.white,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      // 画面右下に食事投稿用のFABを追加
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // 食事投稿ボトムシートを表示し、投稿後にリストを再取得
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) => MealPostSheet(onPosted: _loadMeals),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('食事を記録'),
        tooltip: '新しい食事を投稿',
      ),
    );
  }

  // 統計情報の各項目ウィジェット
  Widget _buildStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.orange, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
