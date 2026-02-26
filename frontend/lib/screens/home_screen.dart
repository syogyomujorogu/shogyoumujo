// =============================================================================
// home_screen.dart - ホーム画面（メイン画面）
// =============================================================================
// このファイルの役割:
// 1. ユーザーの現在の状態を表示（劣化レベル、カロリー、歩数など）
// 2. 各機能へのナビゲーション（カメラ、歩数記録、慈悲リクエスト）
// 3. 最近の食事履歴の表示
// 4. リアルタイムでのデータ更新（Supabaseのリアルタイム機能）
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'camera_screen.dart';
import 'steps_screen.dart';
import 'mercy_request_screen.dart';
import 'profile_screen.dart';

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// ホーム画面のStatefulWidget
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// ホーム画面の状態管理クラス
class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? userData; // ユーザーデータを格納
  List<Map<String, dynamic>> meals = []; // 食事履歴を格納
  bool isLoading = true; // ローディング状態を管理

  @override
  void initState() {
    super.initState();
    // 画面が表示されたときに実行
    _initializeData(); // すべてのデータを読み込む
    _subscribeToChanges(); // データの変更を監視
  }

  // すべてのデータを読み込む関数（エラーハンドリング付き）
  Future<void> _initializeData() async {
    try {
      print('🔄 データ読み込み開始...');

      // ユーザーデータ読み込み（必須）
      await _loadUserData();
      print('✅ ユーザーデータ読み込み成功');

      // 食事データ読み込み（オプション）
      await _loadMeals();
      print('✅ 食事データ読み込み成功');
    } catch (e) {
      print('❌ データ読み込みエラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ データの読み込みに失敗: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      // 必ず isLoading を false にする
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // ユーザーデータをSupabaseから取得する関数
  Future<void> _loadUserData() async {
    try {
      // 現在ログイン中のユーザーIDを取得
      final userId = supabase.auth.currentUser!.id;
      print('📝 ユーザーID: $userId でデータを取得中...');

      // usersテーブルから自分のデータを取得
      final response = await supabase
          .from('users')
          .select()
          .eq('user_id', userId)
          .maybeSingle(); // 1件または0件を取得（エラーしない）

      if (response == null) {
        // ユーザーレコードが存在しない場合、ダミーデータを作成
        print('⚠️ ユーザーレコードが見つかりません。デフォルトデータを使用します。');
        if (mounted) {
          setState(() {
            userData = {
              'user_id': userId,
              'display_name': 'ユーザー',
              'email': supabase.auth.currentUser?.email ?? '',
              'photo_url': null,
              'degraded_photo_url': null,
              'is_degraded': false,
              'degrade_level': 0,
              'current_calories': 0,
              'current_steps': 0,
            };
          });
        }
      } else {
        // データが取得できた場合
        if (mounted) {
          setState(() {
            userData = response;
          });
        }
      }
    } catch (e) {
      print('❌ ユーザーデータ読み込みエラー: $e');
      rethrow;
    }
  }

  // 最近の食事履歴をSupabaseから取得する関数
  Future<void> _loadMeals() async {
    try {
      // 現在ログイン中のユーザーIDを取得
      final userId = supabase.auth.currentUser!.id;

      // mealsテーブルから自分の食事データを取得
      final response = await supabase
          .from('meals')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(5);

      // 取得したデータを状態に保存し、画面を更新
      if (mounted) {
        setState(() {
          meals = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('⚠️ 食事データ読み込みエラー（スキップ）: $e');
      // 食事データの読み込みに失敗しても、処理を続ける
      if (mounted) {
        setState(() {
          meals = [];
        });
      }
    }
  }

  // Supabaseのリアルタイム機能を使ってデータ変更を監視する関数
  void _subscribeToChanges() {
    // 現在ログイン中のユーザーIDを取得
    final userId = supabase.auth.currentUser!.id;

    // usersテーブルの変更を監視
    supabase
        .channel('user_changes') // チャンネル名
        .onPostgresChanges(
          event: PostgresChangeEvent.all, // すべてのイベント（INSERT, UPDATE, DELETE）
          schema: 'public', // スキーマ名
          table: 'users', // 監視するテーブル
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId, // 自分のデータのみ監視
          ),
          callback: (payload) {
            // データが変更されたらユーザーデータを再読み込み
            _loadUserData();
          },
        )
        .subscribe(); // 監視を開始
  }

  @override
  Widget build(BuildContext context) {
    // データ読み込み中はローディング表示
    if (isLoading || userData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ユーザーデータから各値を取得
    final isDegraded = userData?['is_degraded'] ?? false; // 劣化状態かどうか
    final degradeLevel = (userData?['degrade_level'] ?? 0) as int; // 劣化レベル
    final currentCalories = userData?['current_calories'] ?? 0; // 今日のカロリー
    final currentSteps = userData?['current_steps'] ?? 0; // 今日の歩数

    // 劣化している場合は劣化顔、そうでなければ通常の顔を表示
    final photoURL = isDegraded
        ? (userData?['degraded_photo_url'] ?? userData?['photo_url'])
        : userData?['photo_url'];

    return Scaffold(
      // アプリバー（画面上部のバー）
      appBar: AppBar(
        title: const Text('諸行無常ログ'),
        actions: [
          // プロフィールアイコン（タップでプロフィール画面へ）
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      // 下に引っ張って更新する機能
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadUserData();
          await _loadMeals();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // ========== プロフィールカード ==========
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      // プロフィール画像
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: photoURL != null && photoURL != ''
                            ? NetworkImage(photoURL)
                            : null,
                        child: photoURL == null || photoURL == ''
                            ? const Icon(Icons.person, size: 60)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      // ユーザー名
                      Text(
                        userData?['display_name'] ?? 'ユーザー',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 劣化状態のバッジ
                      if (isDegraded)
                        // 劣化している場合は赤色の警告バッジ
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '⚠️ 劣化レベル: $degradeLevel / 9',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        // 劣化していない場合は緑色の健康バッジ
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '✨ 完全な状態 (レベル 0)',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // カロリーと歩数の表示
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            '今日のカロリー',
                            '$currentCalories kcal',
                            Icons.local_fire_department,
                            Colors.orange,
                          ),
                          _buildStatItem(
                            '今日の歩数',
                            '$currentSteps 歩',
                            Icons.directions_walk,
                            Colors.blue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ========== メインアクションボタン ==========
              // 食事撮影ボタン
              _buildActionButton(
                context,
                '食事を撮影',
                Icons.camera_alt,
                Colors.orange,
                () async {
                  // カメラ画面に遷移
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CameraScreen(),
                    ),
                  );
                  // 戻ってきたらデータを再読み込み
                  await _loadUserData();
                  await _loadMeals();
                },
              ),
              const SizedBox(height: 12),

              // 歩数記録ボタン
              _buildActionButton(
                context,
                '歩数を記録',
                Icons.directions_walk,
                Colors.blue,
                () {
                  // 歩数記録画面に遷移
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StepsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 劣化している場合のみ「慈悲を求める」ボタンを表示
              if (isDegraded)
                _buildActionButton(
                  context,
                  '慈悲を求める',
                  Icons.favorite,
                  Colors.red,
                  () {
                    // 慈悲リクエスト画面に遷移
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MercyRequestScreen(),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),

              // ========== 食事履歴セクション ==========
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '最近の食事',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              _buildMealHistory(), // 食事履歴を表示
            ],
          ),
        ),
      ),
    );
  }

  // 統計情報（カロリー、歩数）を表示するウィジェット
  Widget _buildStatItem(
    String label, // ラベル（例: 今日のカロリー）
    String value, // 値（例: 1500 kcal）
    IconData icon, // アイコン
    Color color, // 色
  ) {
    return Column(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // アクションボタンを作成するウィジェット
  Widget _buildActionButton(
    BuildContext context,
    String label, // ボタンのラベル
    IconData icon, // アイコン
    Color color, // ボタンの色
    VoidCallback onPressed, // タップ時の処理
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 28),
      label: Text(label, style: const TextStyle(fontSize: 18)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // 食事履歴を表示するウィジェット
  Widget _buildMealHistory() {
    // 食事履歴が空の場合
    if (meals.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            'まだ食事の記録がありません',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // 食事履歴をリスト形式で表示
    return Column(
      children: meals.map((meal) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            // 食事の画像
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                meal['image_url'],
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            // 料理名
            title: Text(meal['description'] ?? '食事'),
            // カロリー
            subtitle: Text('${meal['calories']} kcal'),
            // 健康度を示すアイコン
            trailing: Icon(
              meal['is_healthy'] ? Icons.check_circle : Icons.warning,
              color: meal['is_healthy'] ? Colors.green : Colors.red,
            ),
          ),
        );
      }).toList(),
    );
  }
}
