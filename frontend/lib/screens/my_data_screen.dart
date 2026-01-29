// =============================================================================
// my_data_screen.dart - 自分のデータ統計画面
// =============================================================================
// このファイルの役割:
// 1. ユーザーの総合統計を表示
// 2. 食事記録、歩数、体重変化などのデータを可視化
// 3. 修業の進捗状況を確認
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// 自分のデータ画面のStatefulWidget
class MyDataScreen extends StatefulWidget {
  const MyDataScreen({Key? key}) : super(key: key);

  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

// 自分のデータ画面の状態管理クラス
class _MyDataScreenState extends State<MyDataScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _meals = [];
  List<Map<String, dynamic>> _steps = [];
  List<Map<String, dynamic>> _weights = [];
  List<Map<String, dynamic>> _weeklySummaries = [];

  // 統計データ
  int _totalMeals = 0;
  int _totalSteps = 0;
  int _avgSteps = 0;
  int _achievedDays = 0;
  double _achievementRate = 0.0;
  double? _weightChange;
  int _consecutiveDays = 0;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // すべてのデータを読み込む
  Future<void> _loadAllData() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // ユーザーデータを取得
      final userResponse =
          await supabase.from('users').select().eq('user_id', userId).single();
      _userData = userResponse;

      // 食事データを取得
      final mealsResponse = await supabase
          .from('meals')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);
      _meals = List<Map<String, dynamic>>.from(mealsResponse);

      // 歩数データを取得
      final stepsResponse = await supabase
          .from('steps')
          .select()
          .eq('user_id', userId)
          .order('date', ascending: true);
      _steps = List<Map<String, dynamic>>.from(stepsResponse);

      // 体重データを取得
      final weightResponse = await supabase
          .from('weight_logs')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);
      _weights = List<Map<String, dynamic>>.from(weightResponse);

      // 週次まとめデータを取得（体重記録から週ごとにグループ化）
      _weeklySummaries = _weights
          .where((w) => w['note']?.toString().contains('週次') ?? false)
          .toList();

      // 統計を計算
      _calculateStats();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('データ読み込みエラー: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 統計を計算
  void _calculateStats() {
    // 総食事記録数
    _totalMeals = _meals.length;

    // 総歩数と平均歩数
    _totalSteps =
        _steps.fold<int>(0, (sum, step) => sum + (step['steps'] as int? ?? 0));
    _avgSteps = _steps.isEmpty ? 0 : (_totalSteps / _steps.length).round();

    // 目標達成率（修業中の場合）
    if (_userData?['training_started'] == true) {
      final dailyGoal = _userData?['training_daily_steps_goal'] ?? 5000;
      _achievedDays = _steps.where((step) {
        final stepCount = step['steps'] as int? ?? 0;
        return stepCount >= dailyGoal;
      }).length;
      _achievementRate =
          _steps.isEmpty ? 0.0 : (_achievedDays / _steps.length) * 100;
    }

    // 体重変化
    if (_weights.length >= 2) {
      final firstWeight = _weights.first['weight'] as double?;
      final lastWeight = _weights.last['weight'] as double?;
      if (firstWeight != null && lastWeight != null) {
        _weightChange = lastWeight - firstWeight;
      }
    }

    // 連続記録日数
    if (_meals.isNotEmpty) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      DateTime checkDate = today;

      while (true) {
        final hasRecord = _meals.any((meal) {
          final mealDate = DateTime.parse(meal['created_at']);
          final mealDay = DateTime(mealDate.year, mealDate.month, mealDate.day);
          return mealDay == checkDate;
        });

        if (hasRecord) {
          _consecutiveDays++;
          checkDate = checkDate.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自分のデータ'),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ヘッダー
                    _buildHeader(),
                    const SizedBox(height: 24),

                    // 基本統計
                    _buildStatCard(
                      '📊 基本統計',
                      Colors.blue,
                      [
                        _buildStatRow('総食事記録数', '$_totalMeals 回'),
                        _buildStatRow('連続記録日数', '$_consecutiveDays 日'),
                        _buildStatRow(
                          '総歩数',
                          '${_totalSteps.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} 歩',
                        ),
                        _buildStatRow(
                          '平均歩数/日',
                          '${_avgSteps.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} 歩',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 修業統計（修業中の場合）
                    if (_userData?['training_started'] == true) ...[
                      _buildStatCard(
                        '🔥 修業統計',
                        Colors.orange,
                        [
                          _buildStatRow('目標達成日数', '$_achievedDays 日'),
                          _buildStatRow(
                            '達成率',
                            '${_achievementRate.toStringAsFixed(1)}%',
                          ),
                          _buildProgressBar(_achievementRate / 100),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 体重記録
                    if (_weights.isNotEmpty) ...[
                      _buildStatCard(
                        '⚖️ 体重記録',
                        Colors.green,
                        [
                          _buildStatRow('総記録回数', '${_weights.length} 回'),
                          if (_weights.length >= 2 && _weightChange != null)
                            _buildStatRow(
                              '体重変化',
                              '${_weightChange! >= 0 ? '+' : ''}${_weightChange!.toStringAsFixed(1)} kg',
                              valueColor: _weightChange! < 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          if (_weights.isNotEmpty)
                            _buildStatRow(
                              '最新体重',
                              '${_weights.last['weight']} kg',
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 週次まとめ履歴
                    if (_weeklySummaries.isNotEmpty) ...[
                      _buildStatCard(
                        '📅 週次まとめ履歴',
                        Colors.purple,
                        [
                          _buildStatRow('記録回数', '${_weeklySummaries.length} 回'),
                          const SizedBox(height: 8),
                          ..._weeklySummaries.reversed.take(5).map((summary) {
                            final date = DateTime.parse(summary['created_at']);
                            final weight = summary['weight'];
                            final note = summary['note'] ?? '';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${date.year}/${date.month}/${date.day}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    Text(
                                      '${weight}kg',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // ヘッダーを構築
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blue, Colors.lightBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics, size: 48, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'あなたの修業記録',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _userData?['training_started'] == true ? '修業中' : '修業前',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 統計カードを構築
  Widget _buildStatCard(String title, Color color, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  // 統計行を構築
  Widget _buildStatRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  // プログレスバーを構築
  Widget _buildProgressBar(double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 24,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                value >= 0.8
                    ? Colors.green
                    : (value >= 0.5 ? Colors.orange : Colors.red),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(value * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
