// =============================================================================
// training_completion_dialog.dart - 修業完了祝福ダイアログ
// =============================================================================
// このファイルの役割:
// 1. 修業完了を盛大に祝福
// 2. 全期間の統計データをグラフで表示
// 3. ビフォーアフターの比較
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

final supabase = Supabase.instance.client;

class TrainingCompletionDialog extends StatelessWidget {
  final Map<String, dynamic> userData;

  const TrainingCompletionDialog({
    Key? key,
    required this.userData,
  }) : super(key: key);

  Future<Map<String, dynamic>> _getCompletionStats() async {
    final userId = supabase.auth.currentUser!.id;
    final startDate = DateTime.tryParse(userData['training_start_date'] ?? '');
    final now = DateTime.now();

    if (startDate == null) {
      return {};
    }

    // 全期間の食事記録取得
    final meals = await supabase
        .from('meals')
        .select()
        .eq('user_id', userId)
        .gte('created_at', startDate.toUtc().toIso8601String());

    // 全期間の歩数記録取得
    final steps = await supabase
        .from('steps')
        .select()
        .eq('user_id', userId)
        .gte('created_at', startDate.toUtc().toIso8601String());

    // 体重記録取得
    final weightLogs = await supabase
        .from('weight_logs')
        .select()
        .eq('user_id', userId)
        .gte('created_at', startDate.toUtc().toIso8601String())
        .order('created_at', ascending: true);

    final dailyGoal = userData['training_daily_steps_goal'] ?? 0;
    final totalSteps = (steps as List).fold<int>(
      0,
      (sum, step) => sum + (step['step_count'] as int? ?? 0),
    );
    final goalAchievedDays = (steps as List).where((step) {
      return (step['step_count'] as int? ?? 0) >= dailyGoal;
    }).length;

    final totalDays = now.difference(startDate).inDays + 1;
    final startWeight = userData['training_start_weight'] as double? ?? 0.0;
    final currentWeight = (weightLogs as List).isNotEmpty
        ? (weightLogs.last['weight'] as num?)?.toDouble() ?? startWeight
        : startWeight;
    final weightLoss = startWeight - currentWeight;

    return {
      'totalDays': totalDays,
      'mealCount': (meals as List).length,
      'totalSteps': totalSteps,
      'averageSteps': steps.isNotEmpty ? (totalSteps / totalDays).round() : 0,
      'goalAchievedDays': goalAchievedDays,
      'achievementRate':
          totalDays > 0 ? (goalAchievedDays / totalDays * 100).toInt() : 0,
      'startWeight': startWeight,
      'currentWeight': currentWeight,
      'weightLoss': weightLoss,
      'weightLogs': weightLogs,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getCompletionStats(),
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
            content: const Text('統計データの取得に失敗しました'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          );
        }

        final stats = snapshot.data!;
        final totalDays = stats['totalDays'] as int;
        final mealCount = stats['mealCount'] as int;
        final totalSteps = stats['totalSteps'] as int;
        final averageSteps = stats['averageSteps'] as int;
        final goalAchievedDays = stats['goalAchievedDays'] as int;
        final achievementRate = stats['achievementRate'] as int;
        final startWeight = stats['startWeight'] as double;
        final currentWeight = stats['currentWeight'] as double;
        final weightLoss = stats['weightLoss'] as double;
        // beforePhoto機能は一時的に無効化
        // final beforePhoto = userData['training_before_photo'] as String?;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 祝福メッセージ
                  const Text(
                    '🎉',
                    style: TextStyle(fontSize: 80),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '修業完了おめでとうございます！',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$totalDays日間の修業を完走しました',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 体重変化
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.shade50,
                          Colors.green.shade100,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '⚖️ 体重変化',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text('開始時'),
                                Text(
                                  '${startWeight}kg',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_forward, size: 32),
                            Column(
                              children: [
                                const Text('現在'),
                                Text(
                                  '${currentWeight}kg',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (weightLoss > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '-${weightLoss.toStringAsFixed(1)}kg 達成！',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else
                          const Text(
                            '体重維持に成功！',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ビフォーアフター写真（一時的に無効化）
                  // if (beforePhoto != null) ...[
                  //   const Text(
                  //     '📸 ビフォー写真',
                  //     style: TextStyle(
                  //       fontSize: 16,
                  //       fontWeight: FontWeight.bold,
                  //     ),
                  //   ),
                  //   const SizedBox(height: 12),
                  //   ClipRRect(
                  //     borderRadius: BorderRadius.circular(12),
                  //     child: Image.network(
                  //       beforePhoto,
                  //       height: 200,
                  //       fit: BoxFit.cover,
                  //     ),
                  //   ),
                  //   const SizedBox(height: 24),
                  // ],

                  // 統計データ
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '📊 修業の記録',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildStatRow('📸 総食事記録', '$mealCount回'),
                        const Divider(),
                        _buildStatRow('🚶 総歩数',
                            '${NumberFormat('#,###').format(totalSteps)}歩'),
                        const Divider(),
                        _buildStatRow('📊 平均歩数',
                            '${NumberFormat('#,###').format(averageSteps)}歩/日'),
                        const Divider(),
                        _buildStatRow(
                            '✅ 目標達成日数', '$goalAchievedDays/$totalDays日'),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: (achievementRate / 100).clamp(0.0, 1.0),
                            minHeight: 24,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              achievementRate >= 70
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '達成率: $achievementRate%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: achievementRate >= 70
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 閉じるボタン
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                    ),
                    child: const Text(
                      '素晴らしい修業でした！',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
