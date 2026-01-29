// =============================================================================
// weekly_summary_dialog.dart - 週次修業まとめダイアログ
// =============================================================================
// このファイルの役割:
// 1. 1週間の修業成果をまとめて表示
// 2. 食事記録回数、歩数達成率などを可視化
// 3. 修業の振り返りと励まし
// 4. 体重記録機能
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

final supabase = Supabase.instance.client;

class WeeklySummaryDialog extends StatefulWidget {
  const WeeklySummaryDialog({Key? key}) : super(key: key);

  @override
  State<WeeklySummaryDialog> createState() => _WeeklySummaryDialogState();
}

class _WeeklySummaryDialogState extends State<WeeklySummaryDialog> {
  final _weightController = TextEditingController();
  bool _weightSaved = false;

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _getWeeklySummary() async {
    final userId = supabase.auth.currentUser!.id;
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));

    // ユーザーデータ取得
    final userData =
        await supabase.from('users').select().eq('user_id', userId).single();

    // 今週の食事記録取得
    final meals = await supabase
        .from('meals')
        .select()
        .eq('user_id', userId)
        .gte('created_at', weekAgo.toUtc().toIso8601String());

    // 今週の歩数記録取得
    final steps = await supabase
        .from('steps')
        .select()
        .eq('user_id', userId)
        .gte('created_at', weekAgo.toUtc().toIso8601String());

    final dailyGoal = userData['training_daily_steps_goal'] ?? 0;
    final totalSteps = (steps as List).fold<int>(
      0,
      (sum, step) => sum + (step['step_count'] as int? ?? 0),
    );
    final stepsGoalDays = (steps as List).where((step) {
      return (step['step_count'] as int? ?? 0) >= dailyGoal;
    }).length;

    return {
      'mealCount': (meals as List).length,
      'totalSteps': totalSteps,
      'averageSteps':
          steps.isNotEmpty ? (totalSteps / steps.length).round() : 0,
      'goalAchievedDays': stepsGoalDays,
      'dailyGoal': dailyGoal,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getWeeklySummary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertDialog(
            content: SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return AlertDialog(
            title: const Text('エラー'),
            content: const Text('週次まとめの取得に失敗しました'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          );
        }

        final data = snapshot.data!;
        final mealCount = data['mealCount'] as int;
        final totalSteps = data['totalSteps'] as int;
        final averageSteps = data['averageSteps'] as int;
        final goalAchievedDays = data['goalAchievedDays'] as int;
        final dailyGoal = data['dailyGoal'] as int;

        // 評価メッセージ
        String message = '';
        String emoji = '';
        if (goalAchievedDays >= 7) {
          emoji = '🎉';
          message = '完璧です！悟りの境地に達しています！';
        } else if (goalAchievedDays >= 5) {
          emoji = '🔥';
          message = '素晴らしい！継続は力なり！';
        } else if (goalAchievedDays >= 3) {
          emoji = '👍';
          message = '良い調子です！この調子で続けましょう！';
        } else if (goalAchievedDays >= 1) {
          emoji = '💪';
          message = '頑張っています！もう少し努力を！';
        } else {
          emoji = '🌱';
          message = '修業は始まったばかり。焦らず一歩ずつ！';
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 8),
              const Text(
                '今週の修業まとめ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                DateFormat('M月d日').format(
                        DateTime.now().subtract(const Duration(days: 7))) +
                    ' ~ ' +
                    DateFormat('M月d日').format(DateTime.now()),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange.shade100,
                        Colors.deepOrange.shade100
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                _buildStatRow('📸 食事記録', '$mealCount回'),
                const Divider(),
                _buildStatRow(
                    '🚶 合計歩数', '${NumberFormat('#,###').format(totalSteps)}歩'),
                const Divider(),
                _buildStatRow('📊 平均歩数',
                    '${NumberFormat('#,###').format(averageSteps)}歩/日'),
                const Divider(),
                _buildStatRow(
                  '✅ 目標達成日数',
                  '$goalAchievedDays/7日',
                  color: goalAchievedDays >= 5 ? Colors.green : Colors.orange,
                ),
                if (dailyGoal > 0) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: (goalAchievedDays / 7).clamp(0.0, 1.0),
                      minHeight: 20,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        goalAchievedDays >= 5 ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(goalAchievedDays / 7 * 100).toInt()}% 達成',
                    style: TextStyle(
                      color:
                          goalAchievedDays >= 5 ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Divider(thickness: 2),
                const SizedBox(height: 12),
                const Text(
                  '⚖️ 今週の体重を記録',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '体重を入力',
                          border: const OutlineInputBorder(),
                          suffixText: 'kg',
                          enabled: !_weightSaved,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _weightSaved
                          ? null
                          : () async {
                              final weight =
                                  double.tryParse(_weightController.text);
                              if (weight == null || weight <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('正しい体重を入力してください')),
                                );
                                return;
                              }

                              try {
                                final userId = supabase.auth.currentUser!.id;
                                await supabase.from('weight_logs').insert({
                                  'user_id': userId,
                                  'weight': weight,
                                  'created_at':
                                      DateTime.now().toUtc().toIso8601String(),
                                  'note': '週次まとめでの記録',
                                });

                                setState(() => _weightSaved = true);

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('体重を記録しました: ${weight}kg'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('エラー: $e')),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _weightSaved ? Colors.grey : Colors.green,
                      ),
                      child: Text(_weightSaved ? '記録済' : '記録'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔥 来週も頑張りましょう！'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('来週も頑張る！'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
