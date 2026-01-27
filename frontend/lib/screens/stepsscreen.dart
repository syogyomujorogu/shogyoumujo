import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class StepsScreen extends StatefulWidget {
  const StepsScreen({Key? key}) : super(key: key);

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  StreamSubscription<StepCount>? _stepSubscription;
  int _todaySteps = 0;
  int _initialStepsOffset = 0; // 今日の開始時点の歩数
  bool _isLoading = true;
  int _degradeLevel = 0;

  static const int stepsPerLevel = 5000; // 5000歩で1レベル回復

  @override
  void initState() {
    super.initState();
    _loadUserStepsAndLevel().then((_) {
      _initPedometer();
    });
  }

  @override
  void dispose() {
    _stepSubscription?.cancel();
    super.dispose();
  }

  /// Supabase から現在のユーザ状態（current_steps, degrade_level）を取得
  Future<void> _loadUserStepsAndLevel() async {
    final userId = supabase.auth.currentUser!.id;

    final userRow = await supabase
        .from('users')
        .select()
        .eq('user_id', userId)
        .single();

    final currentSteps = (userRow['current_steps'] ?? 0) as int;
    final degradeLevel = (userRow['degrade_level'] ?? 0) as int;

    setState(() {
      _todaySteps = currentSteps;
      _degradeLevel = degradeLevel;
      _isLoading = false;
    });
  }

  /// pedometer を初期化して歩数ストリームを購読
  void _initPedometer() {
    _stepSubscription = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepError,
      cancelOnError: false,
    );
  }

  void _onStepCount(StepCount event) {
    // 一部端末では OS 再起動からの総歩数が来るので、オフセットを使って「今日分」だけ扱う簡易実装
    if (_initialStepsOffset == 0) {
      _initialStepsOffset = event.steps;
    }
    final stepsToday = event.steps - _initialStepsOffset;

    if (!mounted) return;

    setState(() {
      _todaySteps = stepsToday;
    });

    _updateStepsOnServer(stepsToday);
  }

  void _onStepError(error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('歩数取得エラー: $error')));
  }

  /// Supabase の users.current_steps と steps_history を更新し、
  /// 必要に応じて劣化レベルを回復させる。
  Future<void> _updateStepsOnServer(int stepsToday) async {
    final userId = supabase.auth.currentUser!.id;

    // まずユーザ状態を取得
    final userRow = await supabase
        .from('users')
        .select()
        .eq('user_id', userId)
        .single();

    final currentLevel = (userRow['degrade_level'] ?? 0) as int;
    final isDegraded = userRow['is_degraded'] ?? false;

    // 5000歩ごとに1レベル回復
    final recoverLevel = (stepsToday / stepsPerLevel).floor();
    int newLevel = currentLevel;

    if (recoverLevel > 0 && currentLevel > 0) {
      newLevel = (currentLevel - recoverLevel).clamp(0, 9);
    }

    final bool newIsDegraded = newLevel > 0 ? true : false;

    // users テーブルの更新
    await supabase
        .from('users')
        .update({
          'current_steps': stepsToday,
          'degrade_level': newLevel,
          'is_degraded': newIsDegraded,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', userId);

    // steps_history にも記録（同じ日付のレコードがあれば上書きでも良い）
    final todayDate = DateTime.now().toIso8601String().substring(0, 10);

    // 既存レコードをチェック
    final existing = await supabase
        .from('steps_history')
        .select()
        .eq('user_id', userId)
        .eq('date', todayDate);

    if (existing.isEmpty) {
      await supabase.from('steps_history').insert({
        'user_id': userId,
        'date': todayDate,
        'steps': stepsToday,
      });
    } else {
      await supabase
          .from('steps_history')
          .update({'steps': stepsToday})
          .eq('user_id', userId)
          .eq('date', todayDate);
    }

    if (!mounted) return;

    setState(() {
      _degradeLevel = newLevel;
    });

    // レベルが下がったときに通知
    if (newLevel < currentLevel && isDegraded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('👏 修行により劣化レベルが $currentLevel → $newLevel に回復しました'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// 進捗バー用：現在のレベルで、次に 1 レベル回復するまでに必要な残り歩数
  int _stepsToNextRecovery() {
    final stepsUsedForRecover = (_todaySteps ~/ stepsPerLevel) * stepsPerLevel;
    final remain = stepsPerLevel - (_todaySteps - stepsUsedForRecover);
    if (_degradeLevel <= 0) {
      return 0;
    }
    return remain.clamp(0, stepsPerLevel);
  }

  double _progressToNextRecovery() {
    if (_degradeLevel <= 0) return 1.0;
    final remain = _stepsToNextRecovery();
    return ((stepsPerLevel - remain) / stepsPerLevel).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final stepsRemain = _stepsToNextRecovery();

    return Scaffold(
      appBar: AppBar(title: const Text('修行（歩数で回復）')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Text(
              '今日の歩数',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '$_todaySteps 歩',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Text('現在の劣化レベル', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'レベル $_degradeLevel / 9',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _degradeLevel > 0 ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            if (_degradeLevel > 0) ...[
              const Text('次の回復までの進捗', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progressToNextRecovery(),
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 12,
              ),
              const SizedBox(height: 8),
              Text(
                'あと $stepsRemain 歩でレベルが 1 つ回復します',
                style: const TextStyle(fontSize: 14),
              ),
            ] else ...[
              const Text(
                '✨ あなたは完全な状態です。修行を続けて徳を積みましょう。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.green),
              ),
            ],
            const Spacer(),
            const Text(
              '※ 5000歩ごとに劣化レベルが1つ回復します',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
