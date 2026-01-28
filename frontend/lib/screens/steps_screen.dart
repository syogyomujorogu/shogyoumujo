// =============================================================================
// steps_screen.dart - 歩数記録・劣化回復画面
// =============================================================================
// このファイルの役割:
// 1. スマートフォンの歩数センサーから歩数を取得
// 2. 歩数をリアルタイムで表示
// 3. 5000歩ごとに劣化レベルを1つ回復
// 4. 歩数データをSupabaseに保存
// 5. 回復進捗バーの表示
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart'; // 歩数計ライブラリ
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// 歩数記録画面のStatefulWidget
class StepsScreen extends StatefulWidget {
  const StepsScreen({Key? key}) : super(key: key);

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

// 歩数記録画面の状態管理クラス
class _StepsScreenState extends State<StepsScreen> {
  StreamSubscription<StepCount>? _stepSubscription; // 歩数ストリームの購読
  int _todaySteps = 0; // 今日の歩数
  int _initialStepsOffset = 0; // 今日の開始時点の歩数（OS再起動からの累計を補正）
  bool _isLoading = true; // ローディング状態
  int _degradeLevel = 0; // 現在の劣化レベル

  static const int stepsPerLevel = 5000; // 5000歩で1レベル回復

  @override
  void initState() {
    super.initState();
    // ユーザーの歩数データとレベルを読み込んでから、歩数計を初期化
    _loadUserStepsAndLevel().then((_) {
      _initPedometer();
    });
  }

  @override
  void dispose() {
    // メモリリークを防ぐため、歩数ストリームの購読を解除
    _stepSubscription?.cancel();
    super.dispose();
  }

  /// Supabase から現在のユーザ状態（current_steps, degrade_level）を取得
  Future<void> _loadUserStepsAndLevel() async {
    final userId = supabase.auth.currentUser!.id;

    // usersテーブルから自分のデータを取得
    final userRow = await supabase
        .from('users')
        .select()
        .eq('user_id', userId)
        .single();

    final currentSteps = (userRow['current_steps'] ?? 0) as int;
    final degradeLevel = (userRow['degrade_level'] ?? 0) as int;

    // 取得したデータを状態に保存
    setState(() {
      _todaySteps = currentSteps;
      _degradeLevel = degradeLevel;
      _isLoading = false;
    });
  }

  /// pedometer を初期化して歩数ストリームを購読
  void _initPedometer() {
    // 歩数センサーからのストリームを購読
    _stepSubscription = Pedometer.stepCountStream.listen(
      _onStepCount, // 歩数が更新されたときの処理
      onError: _onStepError, // エラーが発生したときの処理
      cancelOnError: false, // エラーが発生しても購読を続ける
    );
  }

  // 歩数が更新されたときに呼ばれる関数
  void _onStepCount(StepCount event) {
    // 一部端末では OS 再起動からの総歩数が来るので、オフセットを使って「今日分」だけ扱う簡易実装
    if (_initialStepsOffset == 0) {
      // 初回のみ、現在の歩数をオフセットとして記録
      _initialStepsOffset = event.steps;
    }
    // 今日の歩数 = 現在の歩数 - オフセット
    final stepsToday = event.steps - _initialStepsOffset;

    // 画面がまだ表示されているかチェック
    if (!mounted) return;

    // 歩数を更新
    setState(() {
      _todaySteps = stepsToday;
    });

    // サーバーに歩数を保存
    _updateStepsOnServer(stepsToday);
  }

  // 歩数取得エラーが発生したときに呼ばれる関数
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

    // ========== まずユーザ状態を取得 ==========
    final userRow = await supabase
        .from('users')
        .select()
        .eq('user_id', userId)
        .single();

    final currentLevel = (userRow['degrade_level'] ?? 0) as int;
    final isDegraded = userRow['is_degraded'] ?? false;

    // ========== 劣化レベル回復ロジック ==========
    // 5000歩ごとに1レベル回復
    final recoverLevel = (stepsToday / stepsPerLevel).floor();
    int newLevel = currentLevel;

    if (recoverLevel > 0 && currentLevel > 0) {
      // 現在のレベルから回復レベルを引く（最小0、最大9）
      newLevel = (currentLevel - recoverLevel).clamp(0, 9);
    }

    // レベルが0になったら劣化状態を解除
    final bool newIsDegraded = newLevel > 0 ? true : false;

    // ========== users テーブルの更新 ==========
    await supabase
        .from('users')
        .update({
          'current_steps': stepsToday,
          'degrade_level': newLevel,
          'is_degraded': newIsDegraded,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', userId);

    // ========== steps_history にも記録 ==========
    // 同じ日付のレコードがあれば上書き
    final todayDate = DateTime.now().toIso8601String().substring(0, 10);

    // 既存レコードをチェック
    final existing = await supabase
        .from('steps_history')
        .select()
        .eq('user_id', userId)
        .eq('date', todayDate);

    if (existing.isEmpty) {
      // レコードがない場合は新規作成
      await supabase.from('steps_history').insert({
        'user_id': userId,
        'date': todayDate,
        'steps': stepsToday,
      });
    } else {
      // レコードがある場合は更新
      await supabase
          .from('steps_history')
          .update({'steps': stepsToday})
          .eq('user_id', userId)
          .eq('date', todayDate);
    }

    // 画面がまだ表示されているかチェック
    if (!mounted) return;

    // 劣化レベルを更新
    setState(() {
      _degradeLevel = newLevel;
    });

    // ========== レベルが下がったときに通知 ==========
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
    // これまでに回復に使った歩数
    final stepsUsedForRecover = (_todaySteps ~/ stepsPerLevel) * stepsPerLevel;
    // 次の回復までの残り歩数
    final remain = stepsPerLevel - (_todaySteps - stepsUsedForRecover);
    
    if (_degradeLevel <= 0) {
      return 0; // 既にレベル0なら残り0
    }
    return remain.clamp(0, stepsPerLevel);
  }

  /// 進捗バー用：次の回復までの進捗率（0.0〜1.0）
  double _progressToNextRecovery() {
    if (_degradeLevel <= 0) return 1.0; // 既にレベル0なら100%
    final remain = _stepsToNextRecovery();
    return ((stepsPerLevel - remain) / stepsPerLevel).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // データ読み込み中はローディング表示
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
            // ========== 今日の歩数表示 ==========
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
            
            // ========== 現在の劣化レベル表示 ==========
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
            
            // ========== 回復進捗バー ==========
            if (_degradeLevel > 0) ...[
              // 劣化している場合のみ進捗バーを表示
              const Text('次の回復までの進捗', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progressToNextRecovery(), // 進捗率
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
              // 劣化していない場合のメッセージ
              const Text(
                '✨ あなたは完全な状態です。修行を続けて徳を積みましょう。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.green),
              ),
            ],
            const Spacer(),
            
            // ========== 注意書き ==========
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
