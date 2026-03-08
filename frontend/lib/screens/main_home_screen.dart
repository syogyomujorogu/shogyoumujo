// =============================================================================
// main_home_screen.dart - メインホーム画面（ボトムナビゲーション対応）
// =============================================================================
// このファイルの役割:
// 1. ボトムナビゲーションの管理
// 2. タブ切り替え（リール、検索、プロフィール）
// 3. 各タブの画面を表示
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'reel_feed_screen.dart'; // 通常のリールフィード画面
import 'today_screen.dart'; // 今日の修業画面（食事+ウォーキング統合）
import 'profile_screen.dart'; // プロフィール画面
import 'buddhist_meal_feed_screen.dart'; // 仏教的な食事投稿リール画面（新規追加）
import 'my_data_screen.dart'; // 自分のデータ画面（新規追加）
import 'gacha_screen.dart'; // ガチャガチャ画面（新規追加）
import '../services/illustration_tier_manager.dart'; // 業スコアティア画像管理
import 'package:shared_preferences/shared_preferences.dart'; // デバッグモード設定

// メインホーム画面のStatefulWidget
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

// メインホーム画面の状態管理クラス
class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0; // 現在のタブインデックス

  bool _loginBonusChecked = false;

  // 各タブの画面ウィジェット
  // 0: 通常リール, 1: 諸行無常ログ, 2: 今日, 3: 自分のデータ, 4: ガチャガチャ, 5: プロフィール
  final GlobalKey<ReelFeedScreenState> _reelFeedKey =
      GlobalKey<ReelFeedScreenState>();
  final GlobalKey<BuddhistMealFeedScreenState> _buddhistMealFeedKey =
      GlobalKey<BuddhistMealFeedScreenState>();
  late final List<Widget> _screens = [
    ReelFeedScreen(key: _reelFeedKey), // タブ0: 通常リール
    BuddhistMealFeedScreen(key: _buddhistMealFeedKey), // タブ1: 諸行無常ログ
    const TodayScreen(), // タブ2: 今日（食事+ウォーキング統合）
    const MyDataScreen(), // タブ3: 自分のデータ
    const GachaScreen(), // タブ4: ガチャガチャ
    const ProfileScreen(), // タブ5: プロフィール
  ];

  // タブ選択時の処理
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        _reelFeedKey.currentState?.refreshMeals();
      }
      if (index == 1) {
        _buddhistMealFeedKey.currentState?.loadMeals();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _checkLoginBonus();
    _checkDailyStepGoal(); // 毎日歩数目標をチェック
    _checkKarmaTierChange(); // 業スコアティア変更をチェック
  }

  Future<void> _checkLoginBonus() async {
    if (_loginBonusChecked) return;
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      print('❌ ログインボーナス: ユーザーIDが取得できない');
      return;
    }

    try {
      // 今日の日付（DATE型用: yyyy-MM-dd）
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      print('📅 ログインボーナスをチェック: ユーザーID=$userId, 日付=$today');

      final result = await supabase
          .from('login_bonus_history')
          .select()
          .eq('user_id', userId)
          .eq('login_date', today)
          .maybeSingle();

      if (result == null) {
        print('✅ 今日のボーナスはまだ未受取、配布開始...');

        // ログインボーナスを記録
        await supabase.from('login_bonus_history').insert({
          'user_id': userId,
          'login_date': today,
          'ticket_awarded': true,
        });
        print('✅ login_bonus_history に記録完了');

        // mercy_pointsを+1
        final userRow = await supabase
            .from('users')
            .select('mercy_points')
            .eq('user_id', userId)
            .maybeSingle();
        final currentPoints = (userRow?['mercy_points'] ?? 0) as int;
        await supabase.from('users').update({
          'mercy_points': currentPoints + 1,
        }).eq('user_id', userId);
        print('✅ 慈悲ポイント: $currentPoints → ${currentPoints + 1}');

        // ガチャチケットも1枚付与
        final ticketRow = await supabase
            .from('gacha_tickets')
            .select('ticket_count')
            .eq('user_id', userId)
            .maybeSingle();
        final currentTickets = (ticketRow?['ticket_count'] ?? 0) as int;
        if (ticketRow != null) {
          await supabase.from('gacha_tickets').update({
            'ticket_count': currentTickets + 1,
          }).eq('user_id', userId);
        } else {
          await supabase.from('gacha_tickets').insert({
            'user_id': userId,
            'ticket_count': 1,
          });
        }
        print('✅ ガチャチケット: $currentTickets → ${currentTickets + 1}');

        // 📉 毎日ログイン時に業を-2点自動減衰（維持は難しい！）
        final karmaRow = await supabase
            .from('users')
            .select('karma')
            .eq('user_id', userId)
            .maybeSingle();
        final currentKarma = (karmaRow?['karma'] ?? 50) as int;
        final newKarma = (currentKarma - 2).clamp(0, 100);
        if (newKarma != currentKarma) {
          await supabase.from('users').update({
            'karma': newKarma,
          }).eq('user_id', userId);
          print('📉 業の自動減衰: $currentKarma → $newKarma (-2)');
        }

        if (mounted) {
          _showLoginBonusDialog();
        }
      } else {
        print('⏭️ 今日のボーナスは既に受取済み');
      }
    } catch (e) {
      print('❌ ログインボーナス処理エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ログインボーナスエラー: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      _loginBonusChecked = true;
    }
  }

  // 📊 毎日の歩数目標達成をチェック（業の変動）
  Future<void> _checkDailyStepGoal() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      print('❌ 歩数目標チェック: ユーザーIDが取得できない');
      return;
    }

    try {
      // ユーザーの修業情報を取得
      final userRow = await supabase
          .from('users')
          .select(
              'training_started, training_daily_steps_goal, last_step_goal_check')
          .eq('user_id', userId)
          .maybeSingle();

      if (userRow == null) return;

      // 修業開始済みかチェック
      final isTraining = userRow['training_started'] == true;
      if (!isTraining) {
        print('⏭️ 歩数目標チェック: 修業未開始');
        return;
      }

      // 既にチェック済みの日付を取得
      final lastCheckStr = userRow['last_step_goal_check'] as String?;
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);

      if (lastCheckStr == today) {
        print('⏭️ 歩数目標チェック: 本日既にチェック済み');
        return;
      }

      // 昨日の日付（歩数目標チェック対象）
      final yesterday = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);

      // 昨日のsteps_historyから歩数を取得
      final stepsResult = await supabase
          .from('steps_history')
          .select('steps')
          .eq('user_id', userId)
          .eq('date', yesterday)
          .maybeSingle();

      final yesterdaySteps = (stepsResult?['steps'] ?? 0) as int;
      final dailyGoal = (userRow['training_daily_steps_goal'] ?? 5000) as int;

      print('📊 歩数目標チェック: 昨日=$yesterdaySteps, 目標=$dailyGoal');

      // 業を更新（達成 +5 or 未達成 -3）
      final karmaRow = await supabase
          .from('users')
          .select('karma')
          .eq('user_id', userId)
          .maybeSingle();

      final currentKarma = (karmaRow?['karma'] ?? 50) as int;
      int karmaChange = yesterdaySteps >= dailyGoal ? 5 : -3;
      final newKarma = (currentKarma + karmaChange).clamp(0, 100);

      await supabase.from('users').update({
        'karma': newKarma,
        'last_step_goal_check': today,
      }).eq('user_id', userId);

      print(
          '📊 歩数目標チェック完了: 業 $currentKarma → $newKarma (${karmaChange > 0 ? "+$karmaChange" : "$karmaChange"})');

      // 📸 業ティア変更をチェック＆イラスト生成をリクエスト
      await _checkAndRequestIllustration(userId, currentKarma, newKarma);
    } catch (e) {
      print('❌ 歩数目標チェックエラー: $e');
    }
  }

  // 🎨 業ティアが変更されたかチェック＆イラスト生成をリクエスト
  Future<void> _checkAndRequestIllustration(
      String userId, int oldKarma, int newKarma) async {
    try {
      // イラスト生成機能が有効か確認（デバッグモード用）
      final prefs = await SharedPreferences.getInstance();
      final isEnabled =
          prefs.getBool('illustration_generation_enabled') ?? true;
      if (!isEnabled) {
        print('⏭️ イラスト生成: 機能が無効化されています');
        return;
      }

      final supabase = Supabase.instance.client;

      // ユーザーのプロフィール写真を取得
      final userRow = await supabase
          .from('users')
          .select('photo_url')
          .eq('user_id', userId)
          .maybeSingle();

      final profilePhotoUrl = userRow?['photo_url'] as String?;

      // プロフィール写真がない場合はスキップ
      if (profilePhotoUrl == null || profilePhotoUrl.isEmpty) {
        print('⏭️ イラスト生成: ユーザーがプロフィール写真を設定していません');
        return;
      }

      // 業ティア変更チェック＆リクエスト
      final oldTier = IllustrationTierManager.getKarmaTier(oldKarma);
      final newTier = IllustrationTierManager.getKarmaTier(newKarma);

      if (oldTier != newTier) {
        print('🎨 イラスト生成: 業ティア変更 $oldTier → $newTier');
        await IllustrationTierManager.checkAndRequestGeneration(
          userId: userId,
          oldKarma: oldKarma,
          newKarma: newKarma,
          originalPhotoUrl: profilePhotoUrl,
        );
      } else {
        print('⏭️ イラスト生成: 業ティアに変更なし');
      }
    } catch (e) {
      print('❌ イラスト生成リクエストエラー: $e');
    }
  }

  // 📊 初期化時の業ティア確認（アプリ再起動時用）
  Future<void> _checkKarmaTierChange() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final userRow = await supabase
          .from('users')
          .select('karma, photo_url')
          .eq('user_id', userId)
          .maybeSingle();

      if (userRow == null) return;

      final karma = (userRow['karma'] ?? 50) as int;
      final profilePhotoUrl = userRow['photo_url'] as String?;

      // ティア画像があるか別クエリで確認（カラムが存在しない場合に備える）
      String? tier1ImageUrl;
      try {
        final tierRow = await supabase
            .from('users')
            .select('profile_illustration_tier1')
            .eq('user_id', userId)
            .maybeSingle();
        tier1ImageUrl = tierRow?['profile_illustration_tier1'] as String?;
      } catch (e) {
        print('⚠️ イラストティアカラムが未作成: $e');
        // カラムが存在しない場合はスキップ
        return;
      }

      // ティア1の画像がまだ生成されていない場合、生成をリクエスト
      if (profilePhotoUrl != null &&
          profilePhotoUrl.isNotEmpty &&
          tier1ImageUrl == null) {
        print('🎨 初期化イラスト生成: ティア1 イラストを生成します');
        await IllustrationTierManager.checkAndRequestGeneration(
          userId: userId,
          oldKarma: 50,
          newKarma: karma,
          originalPhotoUrl: profilePhotoUrl,
        );
      }
    } catch (e) {
      print('❌ 初期化イラストチェックエラー: $e');
    }
  }

  void _showLoginBonusDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎁 ログインボーナス'),
        content: const Text('本日のログインボーナスを獲得しました！\n慈悲ポイント +1\nガチャチケット +1'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      // ボトムナビゲーションバーに仏教的な食事投稿リールタブを追加
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '法輪',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.self_improvement),
            label: '諸行無常',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.today),
            label: '今日の行',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: '功徳',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.casino),
            label: 'ガチャ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '我',
          ),
        ],
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
