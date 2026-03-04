// =============================================================================
// buddhist_meal_feed_screen.dart - 諸行無常ログ（ユーザー別食事記録一覧）
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'meal_post_sheet.dart';
import 'item_usage_dialog.dart';

final supabase = Supabase.instance.client;

class BuddhistMealFeedScreen extends StatefulWidget {
  const BuddhistMealFeedScreen({super.key});

  @override
  State<BuddhistMealFeedScreen> createState() => BuddhistMealFeedScreenState();
}

class BuddhistMealFeedScreenState extends State<BuddhistMealFeedScreen> {
  List<Map<String, dynamic>> _userGroups = [];
  Map<String, dynamic>? _myGroup;
  int _myRank = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadMeals();
  }

  int _calcStreak(List<Map<String, dynamic>> meals) {
    if (meals.isEmpty) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final days = meals
        .map((m) {
          final d = DateTime.tryParse(m['created_at'] ?? '');
          if (d == null) return null;
          return DateTime(d.year, d.month, d.day);
        })
        .whereType<DateTime>()
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (days.isEmpty) return 0;
    if (today.difference(days.first).inDays > 1) return 0;

    int streak = 1;
    for (int i = 1; i < days.length; i++) {
      if (days[i - 1].difference(days[i]).inDays == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  int _calcThisWeek(List<Map<String, dynamic>> meals) {
    final weekAgo = DateTime.now().toUtc().subtract(const Duration(days: 7));
    return meals.where((m) {
      final d = DateTime.tryParse(m['created_at'] ?? '');
      return d != null && d.isAfter(weekAgo);
    }).length;
  }

  String _effortLevel(int thisWeek) {
    if (thisWeek >= 21) return '悟りの境地';
    if (thisWeek >= 14) return '精進中';
    if (thisWeek >= 7) return '継続中';
    return '修行中';
  }

  String _rankMedal(int rank) {
    if (rank == 1) return '🥇';
    if (rank == 2) return '🥈';
    if (rank == 3) return '🥉';
    return '$rank位';
  }

  Future<void> loadMeals() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      final friendsData = await supabase
          .from('friends')
          .select('friend_id')
          .eq('user_id', userId);
      final friendIds =
          friendsData.map<String>((r) => r['friend_id'] as String).toList();
      final ids = [...friendIds, userId];

      final blockedRows = await supabase
          .from('blocked_users')
          .select('blocked_user_id')
          .eq('user_id', userId);
      final mutedRows = await supabase
          .from('muted_users')
          .select('muted_user_id')
          .eq('user_id', userId);
      final blockedIds = blockedRows
          .map<String>((r) => r['blocked_user_id'] as String)
          .toSet();
      final mutedIds =
          mutedRows.map<String>((r) => r['muted_user_id'] as String).toSet();

      final response = await supabase
          .from('meals')
          .select('*')
          .inFilter('user_id', ids)
          .order('created_at', ascending: false);

      final filtered = response.where((m) {
        final uid = m['user_id'] as String?;
        return uid != null &&
            !blockedIds.contains(uid) &&
            !mutedIds.contains(uid);
      }).toList();

      final userInfoMap = <String, Map<String, dynamic>>{};
      for (final uid in ids) {
        if (blockedIds.contains(uid) || mutedIds.contains(uid)) continue;
        final info = await supabase
            .from('users')
            .select('user_id, display_name, custom_user_id, photo_url')
            .eq('user_id', uid)
            .maybeSingle();
        if (info != null) userInfoMap[uid] = info;
      }

      // 全員分の体重記録を取得（先週比計算用）
      final twoWeeksAgo =
          DateTime.now().toUtc().subtract(const Duration(days: 14));
      final allWeightLogs = await supabase
          .from('weight_logs')
          .select('user_id, weight, created_at')
          .inFilter('user_id', ids)
          .gte('created_at', twoWeeksAgo.toIso8601String())
          .order('created_at', ascending: true);

      // ユーザーごとに体重の先週比を計算
      final now2 = DateTime.now().toUtc();
      final oneWeekAgo = now2.subtract(const Duration(days: 7));

      Map<String, double?> weightChangeMap = {};
      Map<String, double?> latestWeightMap = {};

      for (final uid in ids) {
        final logs = allWeightLogs.where((w) => w['user_id'] == uid).toList();
        final lastWeekLogs = logs.where((w) {
          final d = DateTime.tryParse(w['created_at'] ?? '');
          return d != null && d.isBefore(oneWeekAgo);
        }).toList();
        final thisWeekLogs = logs.where((w) {
          final d = DateTime.tryParse(w['created_at'] ?? '');
          return d != null && d.isAfter(oneWeekAgo);
        }).toList();

        if (lastWeekLogs.isNotEmpty && thisWeekLogs.isNotEmpty) {
          final lastW = (lastWeekLogs.last['weight'] as num).toDouble();
          final thisW = (thisWeekLogs.last['weight'] as num).toDouble();
          weightChangeMap[uid] = thisW - lastW;
          latestWeightMap[uid] = thisW;
        } else if (thisWeekLogs.isNotEmpty) {
          latestWeightMap[uid] =
              (thisWeekLogs.last['weight'] as num).toDouble();
          weightChangeMap[uid] = null;
        } else if (lastWeekLogs.isNotEmpty) {
          latestWeightMap[uid] =
              (lastWeekLogs.last['weight'] as num).toDouble();
          weightChangeMap[uid] = null;
        } else {
          latestWeightMap[uid] = null;
          weightChangeMap[uid] = null;
        }
      }

      final groupMap = <String, List<Map<String, dynamic>>>{};
      for (final meal in filtered) {
        final uid = meal['user_id'] as String;
        groupMap.putIfAbsent(uid, () => []).add(meal);
      }

      final groups = groupMap.entries.map((e) {
        final uid = e.key;
        final userMeals = e.value;
        final streak = _calcStreak(userMeals);
        final thisWeek = _calcThisWeek(userMeals);
        return {
          'userId': uid,
          'userInfo': userInfoMap[uid] ?? {},
          'meals': userMeals,
          'streak': streak,
          'thisWeek': thisWeek,
          'totalMeals': userMeals.length,
          'effortLevel': _effortLevel(thisWeek),
          'isMe': uid == userId,
          'weightChange': weightChangeMap[uid],
          'latestWeight': latestWeightMap[uid],
        };
      }).toList();

      // 体重減少量順（マイナスが大きいほど上位）→ 記録なしは末尾
      groups.sort((a, b) {
        final aChange = a['weightChange'] as double?;
        final bChange = b['weightChange'] as double?;
        // 両方記録あり → 減少量が多い（より小さい値）が上位
        if (aChange != null && bChange != null) {
          return aChange.compareTo(bChange); // 小さい値（減少）が上位
        }
        // 片方だけ記録あり → 記録ある方が上位
        if (aChange != null) return -1;
        if (bChange != null) return 1;
        // 両方記録なし → 連続日数順
        final s = (b['streak'] as int).compareTo(a['streak'] as int);
        if (s != 0) return s;
        return (b['totalMeals'] as int).compareTo(a['totalMeals'] as int);
      });

      final myIndex = groups.indexWhere((g) => g['isMe'] == true);

      if (!mounted) return;
      setState(() {
        _userGroups = groups;
        _myGroup = myIndex >= 0 ? groups[myIndex] : null;
        _myRank = myIndex >= 0 ? myIndex + 1 : 0;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ loadMeals エラー: $e');
      if (!mounted) return;
      setState(() {
        _userGroups = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _feelImpermanence(String mealId) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final existing = await supabase
          .from('meal_likes')
          .select()
          .eq('meal_id', mealId)
          .eq('user_id', userId)
          .maybeSingle();
      if (existing != null) {
        await supabase
            .from('meal_likes')
            .delete()
            .eq('meal_id', mealId)
            .eq('user_id', userId);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('無常を取り消しました'), duration: Duration(seconds: 1)));
      } else {
        await supabase
            .from('meal_likes')
            .insert({'meal_id': mealId, 'user_id': userId});
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('🙏 無常を感じました'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_userGroups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('諸行無常ログ')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.self_improvement, size: 80, color: Colors.orange[300]),
              const SizedBox(height: 24),
              const Text('まだ食事の記録がありません',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('食事を投稿するとここに表示されます',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (c) => MealPostSheet(onPosted: loadMeals));
          },
          icon: const Icon(Icons.add),
          label: const Text('食事を記録'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('諸行無常ログ'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: loadMeals)
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: RefreshIndicator(
        onRefresh: loadMeals,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // 自分のカード（常に最上部）
            if (_myGroup != null) ...[
              _buildMyCard(_myGroup!, _myRank),
              const SizedBox(height: 20),
            ],

            // ランキングヘッダー
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                const SizedBox(width: 6),
                const Text('修行ランキング',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('連続投稿日数順',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 10),

            // ランキングリスト
            ..._userGroups.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final group = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildRankCard(group, rank),
              );
            }),

            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (c) => MealPostSheet(onPosted: loadMeals));
        },
        icon: const Icon(Icons.add),
        label: const Text('食事を記録'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
    );
  }

  // ========== 自分のカード（上部固定・大きめ）==========
  Widget _buildMyCard(Map<String, dynamic> group, int rank) {
    final userInfo = group['userInfo'] as Map<String, dynamic>;
    final meals = group['meals'] as List<Map<String, dynamic>>;
    final streak = group['streak'] as int;
    final thisWeek = group['thisWeek'] as int;
    final totalMeals = group['totalMeals'] as int;
    final effortLevel = group['effortLevel'] as String;
    final displayName = userInfo['display_name'] as String? ?? 'あなた';
    final photoUrl = userInfo['photo_url'] as String?;
    final recentMeals = meals.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade300],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.orange.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                    ? NetworkImage(photoUrl)
                    : null,
                backgroundColor: Colors.white30,
                child: photoUrl == null
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Text('あなた',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(effortLevel,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              // 順位バッジ
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                  rank <= 3 ? _rankMedal(rank) : '$rank位',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: rank <= 3 ? 22 : 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statChip('🔥', '$streak日', '連続記録'),
              _statChip('📅', '$thisWeek回', '今週'),
              _statChip('🍽️', '$totalMeals回', '総記録'),
            ],
          ),
          // 体重増減カード
          Builder(builder: (context) {
            final wChange = group['weightChange'] as double?;
            final latest = group['latestWeight'] as double?;
            if (latest == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text('⚖️', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('現在の体重',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 11)),
                        Text('${latest.toStringAsFixed(1)} kg',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (wChange != null) ...[
                      const SizedBox(width: 20),
                      Container(width: 1, height: 32, color: Colors.white30),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('先週比',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          Row(
                            children: [
                              Icon(
                                wChange < 0
                                    ? Icons.trending_down
                                    : wChange > 0
                                        ? Icons.trending_up
                                        : Icons.trending_flat,
                                color: wChange < 0
                                    ? Colors.greenAccent
                                    : wChange > 0
                                        ? Colors.redAccent
                                        : Colors.white70,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${wChange >= 0 ? '+' : ''}${wChange.toStringAsFixed(1)} kg',
                                style: TextStyle(
                                  color: wChange < 0
                                      ? Colors.greenAccent
                                      : wChange > 0
                                          ? Colors.redAccent
                                          : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (recentMeals.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('最近の記録',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  ...recentMeals.take(4).map((meal) {
                    final url = meal['photo_url'] as String?;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: url != null && url.isNotEmpty
                            ? Image.network(url,
                                width: 60, height: 60, fit: BoxFit.cover)
                            : Container(
                                width: 60,
                                height: 60,
                                color: Colors.white24,
                                child: const Icon(Icons.restaurant,
                                    color: Colors.white54)),
                      ),
                    );
                  }),
                  if (meals.length > 4)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 60,
                        height: 60,
                        color: Colors.black26,
                        child: Center(
                            child: Text('+${meals.length - 4}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16))),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ========== ランキングカード ==========
  Widget _buildRankCard(Map<String, dynamic> group, int rank) {
    final userInfo = group['userInfo'] as Map<String, dynamic>;
    final meals = group['meals'] as List<Map<String, dynamic>>;
    final streak = group['streak'] as int;
    final thisWeek = group['thisWeek'] as int;
    final totalMeals = group['totalMeals'] as int;
    final effortLevel = group['effortLevel'] as String;
    final displayName = userInfo['display_name'] as String? ?? '修行者';
    final photoUrl = userInfo['photo_url'] as String?;
    final isMe = group['isMe'] == true;
    final weightChange = group['weightChange'] as double?;
    final latestWeight = group['latestWeight'] as double?;
    final recentMeals = meals.take(4).toList();

    return Container(
      decoration: BoxDecoration(
        color: isMe ? Colors.orange.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isMe ? Colors.orange.shade300 : Colors.grey.shade200,
            width: isMe ? 2 : 1),
        boxShadow: [
          BoxShadow(
              color: isMe
                  ? Colors.orange.withOpacity(0.12)
                  : Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 順位
              SizedBox(
                width: 42,
                child: Center(
                  child: Text(
                    rank <= 3 ? _rankMedal(rank) : '$rank',
                    style: TextStyle(
                        fontSize: rank <= 3 ? 22 : 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // アバター
              CircleAvatar(
                radius: 20,
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                    ? NetworkImage(photoUrl)
                    : null,
                backgroundColor: Colors.grey[200],
                child: photoUrl == null
                    ? const Icon(Icons.person, size: 18)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isMe
                                  ? Colors.orange.shade800
                                  : Colors.black87),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.orange.shade200,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('あなた',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.deepOrange)),
                          ),
                        ],
                      ],
                    ),
                    Text(effortLevel,
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              // 連続日数
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: streak > 0
                      ? Colors.orange.shade100
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department,
                        size: 14,
                        color: streak > 0 ? Colors.orange : Colors.grey),
                    const SizedBox(width: 3),
                    Text('$streak日',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: streak > 0
                                ? Colors.orange.shade800
                                : Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _statLine('📅 今週', '$thisWeek回'),
                    _statLine('🍽️ 総数', '$totalMeals回'),
                    if (latestWeight != null)
                      _weightStatLine(latestWeight, weightChange),
                  ],
                ),
              ),
              // サムネイル
              Row(
                children: [
                  ...recentMeals.map((meal) {
                    final url = meal['photo_url'] as String?;
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: GestureDetector(
                        onLongPress: () => _showMealActions(meal),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: url != null && url.isNotEmpty
                              ? Image.network(url,
                                  width: 44, height: 44, fit: BoxFit.cover)
                              : Container(
                                  width: 44,
                                  height: 44,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.restaurant,
                                      size: 18, color: Colors.grey)),
                        ),
                      ),
                    );
                  }),
                  if (meals.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(6)),
                        child: Center(
                            child: Text('+${meals.length - 4}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54))),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMealActions(Map<String, dynamic> meal) {
    final currentUserId = supabase.auth.currentUser?.id;
    final mealOwnerId = meal['user_id'] as String;
    final isOwnMeal = currentUserId == mealOwnerId;
    final createdAt =
        DateTime.tryParse(meal['created_at'] ?? '') ?? DateTime.now().toUtc();
    final isWithin24h =
        DateTime.now().toUtc().difference(createdAt).inHours < 24;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWithin24h)
              ListTile(
                leading:
                    const Icon(Icons.self_improvement, color: Colors.orange),
                title: const Text('無常を感じる'),
                onTap: () {
                  Navigator.pop(context);
                  _feelImpermanence(meal['id'].toString());
                },
              ),
            ListTile(
              leading: Icon(isOwnMeal ? Icons.favorite : Icons.whatshot,
                  color: isOwnMeal ? Colors.green : Colors.orange),
              title: Text(isOwnMeal ? 'カロリー減アイテムを使う' : 'カロリー増アイテムを使う'),
              onTap: () async {
                Navigator.pop(context);
                final result = await showDialog<bool>(
                  context: context,
                  builder: (context) => ItemUsageDialog(
                    mealId: meal['id'].toString(),
                    mealOwnerId: mealOwnerId,
                    currentCalories: meal['calories'] as int? ?? 0,
                    isOwnMeal: isOwnMeal,
                  ),
                );
                if (result == true) loadMeals();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _statLine(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // 体重増減表示ウィジェット（ランキングカード用）
  Widget _weightStatLine(double latest, double? change) {
    final changeColor = change == null
        ? Colors.grey
        : change < 0
            ? Colors.green
            : change > 0
                ? Colors.red
                : Colors.grey;
    final changeIcon = change == null
        ? Icons.remove
        : change < 0
            ? Icons.trending_down
            : change > 0
                ? Icons.trending_up
                : Icons.trending_flat;
    final changeText = change == null
        ? '先週比なし'
        : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}kg';

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('⚖️ ${latest.toStringAsFixed(1)}kg',
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.bold)),
        Icon(changeIcon, size: 13, color: changeColor),
        Text(changeText,
            style: TextStyle(
                fontSize: 11, color: changeColor, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
