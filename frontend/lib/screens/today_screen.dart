// =============================================================================
// today_screen.dart - 今日の修業画面（食事投稿+ウォーキング統合）
// =============================================================================
// このファイルの役割:
// 1. 今日の食事投稿と歩数を統合して表示
// 2. 修業の進捗状況を一目で確認
// 3. 食事の投稿とウォーキング記録を簡単に追加
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'meal_post_sheet.dart';
import 'weekly_summary_dialog.dart';

final supabase = Supabase.instance.client;

class TodayScreen extends StatefulWidget {
  const TodayScreen({Key? key}) : super(key: key);

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _todayMeals = [];
  int _todaySteps = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTodayData();
    _checkAndShowWeeklySummary();
  }

  Future<void> _checkAndShowWeeklySummary() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final userData = await supabase
          .from('users')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (userData == null || userData['training_started'] != true) return;

      final summaryDay = userData['weekly_summary_day'] ?? 0;
      final today = DateTime.now();

      // 今日が設定された曜日かチェック（必ず表示）
      if (today.weekday % 7 == summaryDay) {
        // 最後に表示した日付をチェック
        final lastShown = userData['last_summary_shown'];
        bool shouldShow = true;

        if (lastShown != null) {
          final lastShownDate = DateTime.tryParse(lastShown);
          if (lastShownDate != null) {
            final daysSince = today.difference(lastShownDate).inDays;
            if (daysSince < 7) shouldShow = false; // 1週間以内なら表示しない
          }
        }

        if (shouldShow) {
          // まとめを必ず表示（barrierDismissibleをfalseに）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false, // 閉じるボタン以外で閉じられないように
                builder: (context) => const WeeklySummaryDialog(),
              );

              // 表示日時を記録
              supabase.from('users').update({
                'last_summary_shown': today.toUtc().toIso8601String(),
              }).eq('user_id', userId);
            }
          });
        }
      }
    } catch (e) {
      print('週次まとめチェックエラー: $e');
    }
  }

  Future<void> _loadTodayData() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // ユーザーデータ取得
      final userData = await supabase
          .from('users')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      // 今日の食事取得
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final mealsResponse = await supabase
          .from('meals')
          .select()
          .eq('user_id', userId)
          .gte('created_at', startOfDay.toUtc().toIso8601String())
          .order('created_at', ascending: false);

      // 今日の歩数取得
      final stepsResponse = await supabase
          .from('steps')
          .select()
          .eq('user_id', userId)
          .gte('created_at', startOfDay.toUtc().toIso8601String())
          .maybeSingle();

      setState(() {
        _userData = userData;
        _todayMeals = List<Map<String, dynamic>>.from(mealsResponse ?? []);
        _todaySteps = stepsResponse?['step_count'] ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isTraining = _userData?['training_started'] == true;
    final dailyGoal = _userData?['training_daily_steps_goal'] ?? 0;
    final stepsProgress =
        dailyGoal > 0 ? (_todaySteps / dailyGoal).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('今日の修業'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadTodayData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 修業状況カード
              if (isTraining)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange, Colors.deepOrange],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '🔥 今日の修業進捗',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 歩数進捗
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '歩数',
                                style: TextStyle(color: Colors.white70),
                              ),
                              Text(
                                '$_todaySteps / $dailyGoal 歩',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: stepsProgress,
                              minHeight: 12,
                              backgroundColor: Colors.white.withOpacity(0.3),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 食事回数
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.restaurant,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '今日の食事: ${_todayMeals.length}回',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (isTraining) const SizedBox(height: 24),

              // 食事記録セクション
              const Text(
                '📸 今日の食事',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // 大きな投稿ボタン
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // 時間制限チェック
                    final now = DateTime.now();
                    final hour = now.hour;

                    String? mealType;
                    if (hour >= 6 && hour < 11) {
                      mealType = '朝食（任意）';
                    } else if (hour >= 11 && hour < 16) {
                      mealType = '昼食';
                    } else if (hour >= 16 && hour < 22) {
                      mealType = '夕食';
                    } else {
                      // 時間外の場合は警告
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ 食事の投稿時間外です（6時〜22時）'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => MealPostSheet(
                        onPosted: _loadTodayData,
                        mealType: mealType,
                      ),
                    );
                  },
                  icon: const Icon(Icons.camera_alt, size: 28),
                  label: const Text(
                    '食事を投稿する',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _todayMeals.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          children: [
                            Icon(Icons.restaurant_menu,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              'まだ食事を記録していません',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _todayMeals.length,
                      itemBuilder: (context, index) {
                        final meal = _todayMeals[index];
                        final photoUrl = meal['photo_url'] as String?;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: photoUrl != null && photoUrl.isNotEmpty
                              ? Image.network(photoUrl, fit: BoxFit.cover)
                              : Container(
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.image,
                                      color: Colors.grey),
                                ),
                        );
                      },
                    ),

              const SizedBox(height: 24),

              // ウォーキングセクション
              const Text(
                '🚶 今日の歩数',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      '$_todaySteps',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const Text(
                      '歩',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    if (isTraining && dailyGoal > 0) ...[
                      const SizedBox(height: 16),
                      Text(
                        dailyGoal - _todaySteps > 0
                            ? 'あと ${dailyGoal - _todaySteps} 歩で目標達成！'
                            : '🎉 目標達成！',
                        style: TextStyle(
                          color: dailyGoal - _todaySteps > 0
                              ? Colors.grey
                              : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
