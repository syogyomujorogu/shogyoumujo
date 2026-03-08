// =============================================================================
// today_screen.dart - 今日の修業画面（食事投稿+歩数記録 統合）
// =============================================================================
// このファイルの役割:
// 1. 今日の食事投稿と歩数をリアルタイムで統合表示
// 2. ペドメーターで歩数をリアルタイム計測
// 3. 目標達成で慈悲ポイント+1、業スコア+3
// 4. 修業の進捗状況を一目で確認
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'meal_post_sheet.dart';
import 'weekly_summary_dialog.dart';

final supabase = Supabase.instance.client;

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _todayMeals = [];
  int _todaySteps = 0;
  bool _isLoading = true;
  bool _weeklySummaryShown = false; // 重複表示防止フラグ

  // --- 歩数計測 ---
  StreamSubscription<StepCount>? _stepSubscription;
  int _karma = 50;
  int _mercyPoints = 0;
  int _dailyGoal = 5000;
  bool _goalRewardedToday = false;
  int _lastSavedSteps = 0;
  bool _pedometerAvailable = true; // センサー利用可能フラグ

  // SharedPreferences キー
  static const String _keyLastRaw = 'steps_last_raw_pedometer';
  static const String _keyAccumulated = 'steps_accumulated_today';
  static const String _keyDate = 'steps_date';
  static const String _keyGoalRewarded = 'steps_goal_rewarded';

  static const int _karmaRecovery = 3;
  static const int _mercyReward = 1;
  static const int _dbWriteThreshold = 10;

  @override
  void initState() {
    super.initState();
    _initialize();
    _checkAndShowWeeklySummary();
  }

  @override
  void dispose() {
    _stepSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadPersistedSteps();
    await _loadTodayData();
    _initPedometer();
  }

  Future<void> _checkAndShowWeeklySummary() async {
    if (_weeklySummaryShown) return;

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
      final todayDate = DateTime(today.year, today.month, today.day);

      if (today.weekday % 7 == summaryDay) {
        final lastShown = userData['last_summary_shown'];
        bool shouldShow = true;

        if (lastShown != null) {
          final lastShownDate = DateTime.tryParse(lastShown);
          if (lastShownDate != null) {
            final lastShownDay = DateTime(
                lastShownDate.year, lastShownDate.month, lastShownDate.day);
            final daysSince = todayDate.difference(lastShownDay).inDays;
            if (daysSince < 1) shouldShow = false;
          }
        }

        if (shouldShow) {
          _weeklySummaryShown = true;

          try {
            await supabase.from('users').update({
              'last_summary_shown': today.toIso8601String(),
            }).eq('user_id', userId);
          } catch (e) {
            print('⚠️ last_summary_shown更新失敗(カラム未作成?): $e');
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const WeeklySummaryDialog(),
              );
            }
          });
        }
      }
    } catch (e) {
      print('週次まとめチェックエラー: $e');
    }
  }

  // ===================== 歩数計測ロジック =====================

  /// SharedPreferencesから今日の歩数を読み込み、DBとも同期
  Future<void> _loadPersistedSteps() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_keyDate) ?? '';
    final todayDate = DateTime.now().toIso8601String().substring(0, 10);

    if (savedDate == todayDate) {
      _todaySteps = prefs.getInt(_keyAccumulated) ?? 0;
      _goalRewardedToday = prefs.getBool(_keyGoalRewarded) ?? false;
    } else {
      _todaySteps = 0;
      _goalRewardedToday = false;
      await prefs.setString(_keyDate, todayDate);
      await prefs.setInt(_keyAccumulated, 0);
      await prefs.setInt(_keyLastRaw, 0);
      await prefs.setBool(_keyGoalRewarded, false);
    }

    // DBの歩数とも比較して大きい方を採用
    try {
      final userId = supabase.auth.currentUser!.id;
      final stepsRow = await supabase
          .from('steps_history')
          .select()
          .eq('user_id', userId)
          .eq('date', todayDate)
          .maybeSingle();

      if (stepsRow != null) {
        final dbSteps = (stepsRow['steps'] ?? 0) as int;
        if (dbSteps > _todaySteps) {
          _todaySteps = dbSteps;
          await prefs.setInt(_keyAccumulated, dbSteps);
        }
      }
    } catch (e) {
      print('⚠️ DB歩数読み込みエラー: $e');
    }

    _lastSavedSteps = _todaySteps;
  }

  /// ペドメーターを初期化（利用不可ならフォールバック）
  void _initPedometer() {
    try {
      _stepSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepError,
        cancelOnError: false,
      );
    } catch (e) {
      print('⚠️ ペドメーター初期化エラー: $e');
      if (mounted) setState(() => _pedometerAvailable = false);
    }
  }

  /// 歩数イベント受信
  Future<void> _onStepCount(StepCount event) async {
    final prefs = await SharedPreferences.getInstance();
    final todayDate = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString(_keyDate) ?? '';

    if (savedDate != todayDate) {
      _todaySteps = 0;
      _goalRewardedToday = false;
      _lastSavedSteps = 0;
      await prefs.setString(_keyDate, todayDate);
      await prefs.setInt(_keyAccumulated, 0);
      await prefs.setInt(_keyLastRaw, event.steps);
      await prefs.setBool(_keyGoalRewarded, false);
    }

    final lastRaw = prefs.getInt(_keyLastRaw) ?? 0;

    if (lastRaw == 0) {
      await prefs.setInt(_keyLastRaw, event.steps);
    } else {
      int delta = event.steps - lastRaw;
      if (delta < 0) delta = 0;

      if (delta > 0) {
        _todaySteps += delta;
        await prefs.setInt(_keyAccumulated, _todaySteps);
      }
      await prefs.setInt(_keyLastRaw, event.steps);
    }

    if (!mounted) return;
    setState(() {});

    if ((_todaySteps - _lastSavedSteps).abs() >= _dbWriteThreshold) {
      _lastSavedSteps = _todaySteps;
      await _saveStepsToHistory();
    }

    if (!_goalRewardedToday && _todaySteps >= _dailyGoal) {
      await _grantGoalReward();
    }
  }

  void _onStepError(error) {
    print('⚠️ 歩数センサーエラー: $error');
    if (!mounted) return;
    setState(() => _pedometerAvailable = false);
  }

  /// steps_history テーブルに歩数を保存
  Future<void> _saveStepsToHistory() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final todayDate = DateTime.now().toIso8601String().substring(0, 10);

      final existing = await supabase
          .from('steps_history')
          .select()
          .eq('user_id', userId)
          .eq('date', todayDate);

      if (existing.isEmpty) {
        await supabase.from('steps_history').insert({
          'user_id': userId,
          'date': todayDate,
          'steps': _todaySteps,
        });
      } else {
        await supabase
            .from('steps_history')
            .update({'steps': _todaySteps})
            .eq('user_id', userId)
            .eq('date', todayDate);
      }
    } catch (e) {
      print('⚠️ 歩数保存エラー: $e');
    }
  }

  /// 目標達成報酬を付与: 慈悲ポイント+1、業+3
  Future<void> _grantGoalReward() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final userRow = await supabase
          .from('users')
          .select('karma, mercy_points')
          .eq('user_id', userId)
          .single();

      final currentKarma = (userRow['karma'] ?? 50) as int;
      final currentMercy = (userRow['mercy_points'] ?? 0) as int;
      final newKarma = (currentKarma + _karmaRecovery).clamp(0, 100);
      final newMercy = currentMercy + _mercyReward;

      await supabase.from('users').update({
        'karma': newKarma,
        'mercy_points': newMercy,
      }).eq('user_id', userId);

      _goalRewardedToday = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyGoalRewarded, true);

      if (!mounted) return;
      setState(() {
        _karma = newKarma;
        _mercyPoints = newMercy;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '🎉 目標達成！ 慈悲ポイント+$_mercyReward、業スコア $currentKarma → $newKarma (+$_karmaRecovery)'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      print('⚠️ 目標達成報酬エラー: $e');
    }
  }

  double _goalProgress() {
    if (_dailyGoal <= 0) return 1.0;
    return (_todaySteps / _dailyGoal).clamp(0.0, 1.0);
  }

  // ===================== データ読み込み =====================

  Future<void> _loadTodayData() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      final userData = await supabase
          .from('users')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final mealsResponse = await supabase
          .from('meals')
          .select()
          .eq('user_id', userId)
          .gte('created_at', startOfDay.toUtc().toIso8601String())
          .order('created_at', ascending: false);

      // DB歩数とSharedPreferencesの大きい方を維持
      final todayDate = startOfDay.toIso8601String().substring(0, 10);
      final stepsResponse = await supabase
          .from('steps_history')
          .select()
          .eq('user_id', userId)
          .eq('date', todayDate)
          .maybeSingle();

      final dbSteps = stepsResponse?['steps'] ?? 0;
      if (dbSteps > _todaySteps) _todaySteps = dbSteps;

      if (!mounted) return;
      setState(() {
        _userData = userData;
        _todayMeals = List<Map<String, dynamic>>.from(mealsResponse);
        _karma = (userData?['karma'] ?? 50) as int;
        _mercyPoints = (userData?['mercy_points'] ?? 0) as int;
        _dailyGoal = (userData?['training_daily_steps_goal'] ?? 5000) as int;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isTraining = _userData?['training_started'] == true;
    final goalAchieved = _todaySteps >= _dailyGoal;
    final stepsRemaining = (_dailyGoal - _todaySteps).clamp(0, _dailyGoal);

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
              // ========== 歩数リアルタイムカード ==========
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_walk,
                            color: goalAchieved ? Colors.green : Colors.orange,
                            size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          '今日の歩数',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_todaySteps',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: goalAchieved ? Colors.green : Colors.orange,
                      ),
                    ),
                    if (isTraining) ...[
                      Text(
                        '/ $_dailyGoal 歩',
                        style:
                            const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _goalProgress(),
                          minHeight: 12,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            goalAchieved ? Colors.green : Colors.orange,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (goalAchieved)
                        Text(
                          _goalRewardedToday ? '🎉 目標達成！ 報酬獲得済み' : '🎉 目標達成！',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        )
                      else
                        Text(
                          'あと $stepsRemaining 歩',
                          style:
                              const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                    ],
                    if (!_pedometerAvailable) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '⚠️ この端末では歩数センサーが利用できません\nDB記録の歩数を表示しています',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Colors.amber),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ========== ステータス行（業スコア・慈悲ポイント） ==========
              if (isTraining)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text('業スコア',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(
                              '$_karma',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: _karma >= 50 ? Colors.green : Colors.red,
                              ),
                            ),
                            Text('/ 100',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade400)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text('慈悲ポイント',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(
                              '$_mercyPoints',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            Text('送信可能',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade400)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text('食事',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(
                              '${_todayMeals.length}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            Text('回記録',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade400)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              if (isTraining) const SizedBox(height: 8),

              // ========== 目標達成ボーナス説明 ==========
              if (isTraining && !goalAchieved)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '📋 $_dailyGoal 歩達成で 慈悲+$_mercyReward / 業+$_karmaRecovery',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              const SizedBox(height: 20),

              // ========== 食事記録セクション ==========
              const Text(
                '今日の食事',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => MealPostSheet(
                        onPosted: _loadTodayData,
                        mealType: null,
                      ),
                    );
                  },
                  icon: const Icon(Icons.camera_alt, size: 26),
                  label: const Text(
                    '食事を投稿する',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
