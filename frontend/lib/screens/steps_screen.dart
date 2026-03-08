// =============================================================================
// steps_screen.dart - 歩数記録画面
// =============================================================================
// このファイルの役割:
// 1. スマートフォンの歩数センサーから歩数を取得
// 2. 歩数をリアルタイムで表示
// 3. 1日の目標歩数を達成したら → 慈悲ポイント+1、業スコア少し回復(+3)
// 4. 歩数データをSupabase steps_historyに保存
// 5. SharedPreferencesで歩数オフセットを永続化
// 6. アプリ非表示中の歩数もセンサー差分で自動キャッチアップ
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final supabase = Supabase.instance.client;

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  StreamSubscription<StepCount>? _stepSubscription;
  int _todaySteps = 0;
  bool _isLoading = true;
  int _karma = 50; // 業スコア (0-100)
  int _mercyPoints = 0; // 慈悲ポイント
  int _dailyGoal = 5000; // 1日の目標歩数
  bool _goalRewardedToday = false; // 今日の目標達成報酬を既に付与したか
  int _lastSavedSteps = 0; // DB書き込みスロットル用

  // SharedPreferences キー
  static const String _keyLastRaw = 'steps_last_raw_pedometer';
  static const String _keyAccumulated = 'steps_accumulated_today';
  static const String _keyDate = 'steps_date';
  static const String _keyGoalRewarded = 'steps_goal_rewarded';

  static const int _karmaRecovery = 3; // 目標達成時の業回復量
  static const int _mercyReward = 1; // 目標達成時の慈悲ポイント
  static const int _dbWriteThreshold = 10; // N歩ごとにDB書き込み

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _stepSubscription?.cancel();
    super.dispose();
  }

  /// 初期化: SharedPreferences → DB → ペドメーター の順で起動
  Future<void> _initialize() async {
    await _loadPersistedSteps();
    await _loadUserData();
    _initPedometer();
    if (mounted) setState(() => _isLoading = false);
  }

  /// SharedPreferencesから今日の歩数を読み込み、DBとも同期
  Future<void> _loadPersistedSteps() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_keyDate) ?? '';
    final todayDate = DateTime.now().toIso8601String().substring(0, 10);

    if (savedDate == todayDate) {
      _todaySteps = prefs.getInt(_keyAccumulated) ?? 0;
      _goalRewardedToday = prefs.getBool(_keyGoalRewarded) ?? false;
    } else {
      // 日付が変わった: リセット
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

  /// Supabase から karma, mercy_points, training_daily_steps_goal を取得
  Future<void> _loadUserData() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final userRow = await supabase
          .from('users')
          .select('karma, mercy_points, training_daily_steps_goal')
          .eq('user_id', userId)
          .single();
      _karma = (userRow['karma'] ?? 50) as int;
      _mercyPoints = (userRow['mercy_points'] ?? 0) as int;
      _dailyGoal = (userRow['training_daily_steps_goal'] ?? 5000) as int;
    } catch (e) {
      print('⚠️ ユーザーデータ読み込みエラー: $e');
    }
  }

  /// ペドメーターを初期化
  void _initPedometer() {
    _stepSubscription = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepError,
      cancelOnError: false,
    );
  }

  /// 歩数イベント受信
  Future<void> _onStepCount(StepCount event) async {
    final prefs = await SharedPreferences.getInstance();
    final todayDate = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString(_keyDate) ?? '';

    // 日付が変わった場合はリセット
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
      // 初回: 基準点を設定
      await prefs.setInt(_keyLastRaw, event.steps);
    } else {
      int delta = event.steps - lastRaw;
      if (delta < 0) delta = 0; // デバイス再起動等

      if (delta > 0) {
        _todaySteps += delta;
        await prefs.setInt(_keyAccumulated, _todaySteps);
      }
      await prefs.setInt(_keyLastRaw, event.steps);
    }

    if (!mounted) return;
    setState(() {});

    // DB書き込みスロットル
    if ((_todaySteps - _lastSavedSteps).abs() >= _dbWriteThreshold) {
      _lastSavedSteps = _todaySteps;
      await _saveStepsToHistory();
    }

    // 目標達成チェック
    if (!_goalRewardedToday && _todaySteps >= _dailyGoal) {
      await _grantGoalReward();
    }
  }

  void _onStepError(error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('歩数取得エラー: $error')),
    );
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

      // 最新のkarmaとmercy_pointsを取得
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

      // フラグを永続化
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

  /// 目標までの進捗率 (0.0〜1.0)
  double _goalProgress() {
    if (_dailyGoal <= 0) return 1.0;
    return (_todaySteps / _dailyGoal).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final stepsRemaining = (_dailyGoal - _todaySteps).clamp(0, _dailyGoal);
    final goalAchieved = _todaySteps >= _dailyGoal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('歩数記録'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 8),

            // ========== 今日の歩数 ==========
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
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
                  const Text(
                    '今日の歩数',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_todaySteps',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                      color: goalAchieved ? Colors.green : Colors.orange,
                    ),
                  ),
                  Text(
                    '/ $_dailyGoal 歩',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  // 目標進捗バー
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _goalProgress(),
                      minHeight: 14,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        goalAchieved ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (goalAchieved)
                    Text(
                      _goalRewardedToday ? '🎉 目標達成！ 報酬獲得済み' : '🎉 目標達成！',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    )
                  else
                    Text(
                      'あと $stepsRemaining 歩で目標達成',
                      style: const TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ========== ステータスカード ==========
            Row(
              children: [
                // 業スコア
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text('業スコア',
                            style: TextStyle(fontSize: 13, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          '$_karma',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: _karma >= 50 ? Colors.green : Colors.red,
                          ),
                        ),
                        Text('/ 100',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade400)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 慈悲ポイント
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text('慈悲ポイント',
                            style: TextStyle(fontSize: 13, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          '$_mercyPoints',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        Text('送信可能',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade400)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),

            // ========== 報酬説明 ==========
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    '📋 目標達成ボーナス',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1日 $_dailyGoal 歩を達成すると：\n'
                    '・慈悲ポイント +$_mercyReward\n'
                    '・業スコア +$_karmaRecovery',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '※ アプリを閉じていた間の歩数も自動で反映されます',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
