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
import 'package:fl_chart/fl_chart.dart';
import 'reel_settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// 自分のデータ画面のStatefulWidget
class MyDataScreen extends StatefulWidget {
  const MyDataScreen({super.key});

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

      // 歩数データを取得（steps_historyに統一）
      final stepsResponse = await supabase
          .from('steps_history')
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
  /// 業（karma）の値に応じて色を計算（赤→紫→金色）
  Color _getKarmaColor(int karma) {
    // 0: 赤色, 50: 紫色, 100: 金色へのグラデーション
    if (karma < 50) {
      // 0-50: 赤から紫へ（#FF4444 → #9C27B0）
      return Color.lerp(
        const Color(0xFFFF4444), // 赤
        const Color(0xFF9C27B0), // 紫
        (karma / 50.0).clamp(0.0, 1.0),
      )!;
    } else {
      // 50-100: 紫から金色へ（#9C27B0 → #FFD700）
      return Color.lerp(
        const Color(0xFF9C27B0), // 紫
        const Color(0xFFFFD700), // 金色
        ((karma - 50) / 50.0).clamp(0.0, 1.0),
      )!;
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

                    // ========== 業（Karma）スコア表示 ==========
                    _buildStatCard(
                      '業（カルマ）スコア',
                      _getKarmaColor(_userData?['karma'] ?? 0), // 動的色
                      [
                        Text(
                          '${_userData?['karma'] ?? 0} / 100',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: ((_userData?['karma'] ?? 0) / 100)
                                .clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                _getKarmaColor(_userData?['karma'] ?? 0)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ========== 食事記録 ==========
                    _buildStatCard(
                      '食事記録',
                      Colors.orange,
                      [
                        Text(
                          '$_totalMeals回',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '連続：$_consecutiveDays日',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ========== 歩数統計 ==========
                    _buildStatCard(
                      '歩数統計',
                      Colors.blue,
                      [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '総歩数',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  '$_totalSteps歩',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '平均',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  '$_avgSteps歩',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_userData?['training_started'] == true) ...[
                          const SizedBox(height: 12),
                          Text(
                            '目標達成: $_achievedDays日 (${_achievementRate.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ========== 体重変化 ==========
                    if (_weights.isNotEmpty)
                      _buildStatCard(
                        '体重',
                        Colors.green,
                        [
                          if (_weights.last['weight'] != null)
                            Text(
                              '${_toDouble(_weights.last['weight'])?.toStringAsFixed(1) ?? '未計測'} kg',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          if (_weightChange != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    _weightChange! < 0
                                        ? Icons.trending_down
                                        : Icons.trending_up,
                                    color: _weightChange! < 0
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_weightChange! >= 0 ? '+' : ''}${_weightChange!.toStringAsFixed(1)} kg',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _weightChange! < 0
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  // 統計を計算
  /// int または double を double に安全に変換するヘルパーメソッド
  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

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
      final firstWeightRaw = _weights.first['weight'];
      final lastWeightRaw = _weights.last['weight'];
      final firstWeight = _toDouble(firstWeightRaw);
      final lastWeight = _toDouble(lastWeightRaw);
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

  // ヘッダーを構築
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics, size: 48, color: Colors.blue.shade600),
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
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _userData?['training_started'] == true ? '修業中' : '修業前',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
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
