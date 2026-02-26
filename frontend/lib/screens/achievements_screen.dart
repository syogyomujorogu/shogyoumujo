// =============================================================================
// achievements_screen.dart - 実績・バッジ画面
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _achievements = [];
  List<Map<String, dynamic>> _badges = [];
  Map<String, dynamic>? _equippedBadge;
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // 全実績とバッジを取得
      final achievementsData = await supabase
          .from('achievements')
          .select('*, badges(*)')
          .order('condition_value');

      // ユーザーの達成済み実績を取得
      final userAchievements = await supabase
          .from('user_achievements')
          .select('achievement_id')
          .eq('user_id', userId);

      final achievedIds =
          userAchievements.map((e) => e['achievement_id']).toSet();

      // 実績データに達成フラグを追加
      _achievements = achievementsData.map((ach) {
        return {
          ...ach,
          'is_achieved': achievedIds.contains(ach['id']),
        };
      }).toList();

      // 達成済みバッジのリストを作成
      _badges = _achievements
          .where((ach) => ach['is_achieved'] == true)
          .map((ach) => ach['badges'] as Map<String, dynamic>)
          .toList();

      // 装備中のバッジを取得
      final equippedData = await supabase
          .from('user_equipped_badge')
          .select('*, badges(*)')
          .eq('user_id', userId)
          .maybeSingle();

      _equippedBadge = equippedData?['badges'];
    } catch (e) {
      _showMessage('データの読み込みに失敗しました: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _equipBadge(Map<String, dynamic> badge) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 既存の装備を削除してから新しいバッジを装備
      await supabase.from('user_equipped_badge').delete().eq('user_id', userId);

      await supabase.from('user_equipped_badge').insert({
        'user_id': userId,
        'badge_id': badge['id'],
      });

      setState(() => _equippedBadge = badge);
      _showMessage('${badge['name']} を装備しました！');
    } catch (e) {
      _showMessage('装備に失敗しました: $e');
    }
  }

  Future<void> _unequipBadge() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('user_equipped_badge').delete().eq('user_id', userId);
      setState(() => _equippedBadge = null);
      _showMessage('バッジを外しました');
    } catch (e) {
      _showMessage('エラー: $e');
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
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

  String _getRarityText(String rarity) {
    switch (rarity) {
      case 'bronze':
        return 'ブロンズ';
      case 'silver':
        return 'シルバー';
      case 'gold':
        return 'ゴールド';
      case 'platinum':
        return 'プラチナ';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏆 実績・バッジ'),
        backgroundColor: Colors.amber,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.emoji_events), text: '実績一覧'),
            Tab(icon: Icon(Icons.military_tech), text: 'バッジコレクション'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAchievementsTab(),
                _buildBadgesTab(),
              ],
            ),
    );
  }

  // 実績一覧タブ
  Widget _buildAchievementsTab() {
    final achievedCount =
        _achievements.where((a) => a['is_achieved'] == true).length;
    final totalCount = _achievements.length;

    return Column(
      children: [
        // 進捗表示
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.amber.withOpacity(0.1),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '達成状況',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '$achievedCount / $totalCount',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.amber[700],
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: totalCount > 0 ? achievedCount / totalCount : 0,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.amber[700]!),
                minHeight: 8,
              ),
            ],
          ),
        ),
        // 実績リスト
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _achievements.length,
            itemBuilder: (context, index) {
              final achievement = _achievements[index];
              final badge = achievement['badges'] as Map<String, dynamic>;
              final isAchieved = achievement['is_achieved'] == true;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                color: isAchieved
                    ? Colors.amber.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.05),
                child: ListTile(
                  leading: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isAchieved
                            ? _getBorderColor(badge['rarity'])
                            : Colors.grey,
                        width: 3,
                      ),
                      color: isAchieved ? Colors.white : Colors.grey[300],
                    ),
                    child: Center(
                      child: Text(
                        badge['icon'],
                        style: TextStyle(
                          fontSize: 28,
                          color: isAchieved ? null : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    achievement['name'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isAchieved ? null : Colors.grey,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        achievement['description'],
                        style: TextStyle(
                          color: isAchieved ? null : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getRarityText(badge['rarity']),
                        style: TextStyle(
                          fontSize: 12,
                          color: _getBorderColor(badge['rarity']),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  trailing: isAchieved
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.lock, color: Colors.grey),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // バッジコレクションタブ
  Widget _buildBadgesTab() {
    return Column(
      children: [
        // 装備中バッジ表示
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.amber.withOpacity(0.1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '装備中のバッジ',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Center(
                child: _equippedBadge != null
                    ? Column(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    _getBorderColor(_equippedBadge!['rarity']),
                                width: 4,
                              ),
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      _getBorderColor(_equippedBadge!['rarity'])
                                          .withOpacity(0.3),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _equippedBadge!['icon'],
                                style: const TextStyle(fontSize: 50),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _equippedBadge!['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _unequipBadge,
                            icon: const Icon(Icons.close),
                            label: const Text('外す'),
                          ),
                        ],
                      )
                    : const Text('バッジを装備していません'),
              ),
            ],
          ),
        ),
        // 所持バッジ一覧
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '所持バッジ (${_badges.length}個)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: _badges.isEmpty
              ? const Center(
                  child: Text('まだバッジを獲得していません\n実績を達成してバッジを集めよう！'),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _badges.length,
                  itemBuilder: (context, index) {
                    final badge = _badges[index];
                    final isEquipped = _equippedBadge?['id'] == badge['id'];

                    return GestureDetector(
                      onTap: () => _equipBadge(badge),
                      child: Card(
                        elevation: isEquipped ? 8 : 2,
                        color:
                            isEquipped ? Colors.amber.withOpacity(0.2) : null,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _getBorderColor(badge['rarity']),
                                  width: 3,
                                ),
                                color: Colors.white,
                              ),
                              child: Center(
                                child: Text(
                                  badge['icon'],
                                  style: const TextStyle(fontSize: 35),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                badge['name'],
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isEquipped)
                              const Text(
                                '装備中',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
