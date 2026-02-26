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
  final List<Widget> _screens = const [
    ReelFeedScreen(), // タブ0: 通常リール
    BuddhistMealFeedScreen(), // タブ1: 諸行無常ログ
    TodayScreen(), // タブ2: 今日（食事+ウォーキング統合）
    MyDataScreen(), // タブ3: 自分のデータ
    GachaScreen(), // タブ4: ガチャガチャ
    ProfileScreen(), // タブ5: プロフィール
  ];

  // タブ選択時の処理
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    _checkLoginBonus();
  }

  Future<void> _checkLoginBonus() async {
    if (_loginBonusChecked) return;
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // 今日の日付（UTC, yyyy-MM-dd）
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final result = await supabase
        .from('login_bonus_history')
        .select()
        .eq('user_id', userId)
        .gte('received_at', today)
        .maybeSingle();

    if (result == null) {
      // まだ今日のボーナスを受け取っていない場合、付与
      await supabase.from('login_bonus_history').insert({
        'user_id': userId,
        'received_at': DateTime.now().toUtc().toIso8601String(),
      });
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
      if (mounted) {
        _showLoginBonusDialog();
      }
    }
    _loginBonusChecked = true;
  }

  void _showLoginBonusDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎁 ログインボーナス'),
        content: const Text('本日のログインボーナスを獲得しました！\n慈悲ポイント +1'),
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
