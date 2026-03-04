// =============================================================================
// reel_feed_screen.dart - リールフィード画面（BeReal/Instagram風）
// =============================================================================
// このファイルの役割:
// 1. 友達が投稿した食事写真をリール形式で表示
// 2. 縦スワイプで写真を切り替え
// 3. 慈悲ボタン、いいねボタンなどのアクション実装
// 4. リアルタイムでのデータ更新
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'comment_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'reel_settings_dialog.dart';
import '../widgets/icon_degrade_filter.dart';

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// リールフィード画面のStatefulWidget
class ReelFeedScreen extends StatefulWidget {
  const ReelFeedScreen({super.key});

  @override
  State<ReelFeedScreen> createState() => ReelFeedScreenState();
}

// リールフィード画面の状態管理クラス
class ReelFeedScreenState extends State<ReelFeedScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  bool _keepAspectRatio = false;
  late PageController _pageController;
  List<Map<String, dynamic>> _meals = []; // 食事投稿のリスト
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    _loadReelSettings();
    super.initState();
    print('🟢 ReelFeedScreen: initState呼び出し');
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _loadMeals();
    _subscribeToMealUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // アプリが再開された時、データを再読み込み
      _loadMeals();
    }
  }

  /// 食事投稿のリアルタイム更新を購読（v2以降は未対応のため一時的に無効化）
  void _subscribeToMealUpdates() {
    // Supabase v2.x では .on メソッドが廃止されたため、リアルタイム購読は未実装
    // 必要なら公式ドキュメントの新APIで実装してください
  }

  Future<void> _loadReelSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _keepAspectRatio = prefs.getBool('reel_keep_aspect_ratio') ?? false;
    });
  }

  Future<void> _setKeepAspectRatio(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reel_keep_aspect_ratio', value);
    setState(() {
      _keepAspectRatio = value;
    });
  }

  Future<void> refreshMeals() async {
    await _loadMeals();
  }

  /// フレンドの食事投稿を読み込む
  Future<void> _loadMeals() async {
    print('========================================');
    print('🔍 リール画面: データ読み込み開始');
    print('========================================');
    try {
      final userId = supabase.auth.currentUser!.id;
      print('🔍 現在のユーザーID: $userId');

      // friendsテーブルからフレンドIDを取得
      final friendsData = await supabase
          .from('friends')
          .select('friend_id')
          .eq('user_id', userId);
      final friendIds =
          friendsData.map<String>((row) => row['friend_id'] as String).toList();

      // ブロック・ミュートユーザーIDを取得
      final blockedRows = await supabase
          .from('blocked_users')
          .select('blocked_user_id')
          .eq('user_id', userId);
      final mutedRows = await supabase
          .from('muted_users')
          .select('muted_user_id')
          .eq('user_id', userId);
      final blockedIds = blockedRows
          .map<String>((row) => row['blocked_user_id'] as String)
          .toSet();
      final mutedIds = mutedRows
          .map<String>((row) => row['muted_user_id'] as String)
          .toSet();

      final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 24));

      // フレンドの食事投稿を取得（mealテーブルから）
      final meals = await supabase
          .from('meals')
          .select()
          .inFilter('user_id', friendIds)
          .gte('created_at', cutoff.toIso8601String())
          .order('created_at', ascending: false);

      // ブロック・ミュート除外
      final filteredMeals = meals.where((meal) {
        final uid = meal['user_id'] as String?;
        return uid != null &&
            !blockedIds.contains(uid) &&
            !mutedIds.contains(uid);
      }).toList();

      // ユーザー情報を取得
      if (filteredMeals.isNotEmpty) {
        final userIds =
            filteredMeals.map((m) => m['user_id'] as String).toSet().toList();
        List<dynamic> users;
        try {
          users = await supabase
              .from('users')
              .select(
                  'user_id, display_name, custom_user_id, photo_url, profile_illustration_url, karma, profile_buddha_illustration_url')
              .inFilter('user_id', userIds);
        } catch (e) {
          final message = e.toString();
          if (message.contains('code: 42703') ||
              message.contains('does not exist')) {
            users = await supabase
                .from('users')
                .select(
                    'user_id, display_name, custom_user_id, photo_url, karma')
                .inFilter('user_id', userIds);
          } else {
            rethrow;
          }
        }

        // ユーザー情報をマップに変換
        final userMap = {for (var u in users) u['user_id']: u};

        // 食事データにユーザー情報を結合
        for (var meal in filteredMeals) {
          meal['user'] = userMap[meal['user_id']];
        }
      }

      if (mounted) {
        setState(() {
          _meals = List<Map<String, dynamic>>.from(filteredMeals);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('========================================');
      print('❌ 食事投稿読み込みエラー: $e');
      print('========================================');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 慈悲ボタンをタップ（リールでは直接ポイント付与）
  Future<void> _addMercy(String userId) async {
    try {
      // 慈悲を与えたことを通知（mercy_pointsカラムは存在しないため通知のみ）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🙏 慈悲を与えました'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ 慈悲追加エラー: $e');
    }
  }

  /// いいねボタンをタップ
  Future<void> _toggleLike(String mealId) async {
    try {
      final currentUserId = supabase.auth.currentUser!.id;

      // 既存のいいねをチェック
      final existing = await supabase
          .from('meal_likes')
          .select('id')
          .eq('meal_id', mealId)
          .eq('user_id', currentUserId)
          .maybeSingle();

      if (existing != null) {
        // いいねが存在する場合は削除
        await supabase
            .from('meal_likes')
            .delete()
            .eq('meal_id', mealId)
            .eq('user_id', currentUserId);

        print('👍 いいねを削除しました');
      } else {
        // いいねが存在しない場合は追加
        await supabase.from('meal_likes').insert({
          'meal_id': mealId,
          'user_id': currentUserId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });

        print('👍 いいねを追加しました');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('👍 いいね！'),
              backgroundColor: Colors.pink,
              duration: Duration(milliseconds: 500),
            ),
          );
        }
      }

      // データをリロード（状態を更新）
      await _loadMeals();
    } catch (e) {
      print('❌ いいね操作エラー: $e');
    }
  }

  /// アイテム使用ダイアログを表示
  Future<void> _showItemDialog(String mealId) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 所持アイテムを取得してグループ化
      final userItems = await supabase
          .from('user_items')
          .select('*, items(*)')
          .eq('user_id', userId);

      if (!mounted) return;

      if (userItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('使用できるアイテムがありません')),
        );
        return;
      }

      // 同じアイテムをまとめる
      final Map<String, Map<String, dynamic>> groupedItems = {};
      for (final userItem in userItems) {
        final item = userItem['items'] as Map<String, dynamic>;
        final itemId = item['id'] as String;

        if (groupedItems.containsKey(itemId)) {
          groupedItems[itemId]!['count'] =
              (groupedItems[itemId]!['count'] as int) + 1;
          groupedItems[itemId]!['userItemIds'].add(userItem['id']);
        } else {
          groupedItems[itemId] = {
            'item': item,
            'count': 1,
            'userItemIds': [userItem['id']],
          };
        }
      }

      // アイテム選択ダイアログを表示
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('アイテムを使用'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: groupedItems.length,
              itemBuilder: (context, index) {
                final entry = groupedItems.values.elementAt(index);
                final item = entry['item'] as Map<String, dynamic>;
                final count = entry['count'] as int;
                final userItemIds = entry['userItemIds'] as List;

                return ListTile(
                  leading: Text(
                    _getItemIcon(item),
                    style: const TextStyle(fontSize: 32),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(item['name'])),
                      Text(
                        '×$count',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(item['description']),
                  onTap: () {
                    Navigator.pop(context);
                    _useItem(userItemIds.first, item);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ アイテム一覧取得エラー: $e');
    }
  }

  String _getItemIcon(Map<String, dynamic> item) {
    if (item['effect_type'] == 'calorie_decrease') {
      switch (item['rarity']) {
        case 'N':
          return '😇';
        case 'SR':
          return '🙏';
        case 'SSR':
          return '✨';
      }
    } else {
      switch (item['rarity']) {
        case 'N':
          return '😈';
        case 'SR':
          return '👹';
        case 'SSR':
          return '💀';
      }
    }
    return '🎁';
  }

  /// アイテムを使用
  Future<void> _useItem(String userItemId, Map<String, dynamic> item) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final effectType = item['effect_type'] as String;
      final effectValue = item['effect_value'] as int? ?? 0;

      // アイテムを削除
      await supabase.from('user_items').delete().eq('id', userItemId);

      // 通知を作成
      await supabase.from('notifications').insert({
        'recipient_id': userId,
        'sender_id': userId,
        'notification_type': 'item_usage',
        'message': 'アイテムを使用しました',
        'content': {
          'item_id': item['id'],
          'effect_type': effectType,
          'effect_value': effectValue,
        },
      });

      if (mounted) {
        if (effectType == 'calorie_decrease') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✨ ${item['name']}を使用しました！'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('💀 ${item['name']}を使用しました...'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ アイテム使用エラー: $e');
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin requires this

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_meals.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('リール'),
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.no_meals,
                size: 80,
                color: Colors.orange.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              const Text(
                'フレンドの投稿がまだありません',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('リール'),
        // 設定アイコンは削除。設定は「我の欄（三本線）」からのみ開けるようにする。
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _meals.length,
        itemBuilder: (context, index) {
          final meal = _meals[index];
          final user = meal['user'] as Map<String, dynamic>?;
          final userName = user?['display_name'] ?? 'ユーザー';
          final userCustomId = user?['custom_user_id'] ?? '';
          final userPhotoUrl = user?['profile_illustration_url'] ??
              user?['photo_url'] as String?;
          final userKarma = user?['karma'] ?? 50;
          final userBuddhaUrl =
              user?['profile_buddha_illustration_url'] as String?;
          final mealPhotoUrl = meal['photo_url'] as String?;
          final mealDescription = meal['description'] as String?;
          final calories = meal['calories'] as int? ?? 0;

          return _ReelItem(
            mealId: meal['id'] as String,
            userId: meal['user_id'] as String,
            userName: userName,
            userCustomId: userCustomId,
            userPhotoUrl: userPhotoUrl,
            userKarma: userKarma,
            userBuddhaUrl: userBuddhaUrl,
            mealPhotoUrl: mealPhotoUrl,
            mealDescription: mealDescription,
            calories: calories,
            onMercyTap: () => _addMercy(meal['user_id'] as String),
            onLikeTap: () => _toggleLike(meal['id'] as String),
            onItemTap: () => _showItemDialog(meal['id'] as String),
            onCommentTap: (context) => showCommentSheet(
              context,
              meal['id'] as String,
              meal['user_id'] as String,
            ),
            keepAspectRatio: _keepAspectRatio,
          );
        },
      ),
    );
  }
}

/// 個別のリールアイテム
class _ReelItem extends StatefulWidget {
  final bool keepAspectRatio;
  final String mealId;
  final String userId;
  final String userName;
  final String userCustomId;
  final String? userPhotoUrl;
  final int userKarma;
  final String? userBuddhaUrl;
  final String? mealPhotoUrl;
  final String? mealDescription;
  final int calories;
  final VoidCallback onMercyTap;
  final VoidCallback onLikeTap;
  final VoidCallback onItemTap;
  final Function(BuildContext)? onCommentTap;

  const _ReelItem({
    required this.mealId,
    required this.userId,
    required this.userName,
    required this.userCustomId,
    this.userPhotoUrl,
    required this.userKarma,
    this.userBuddhaUrl,
    this.mealPhotoUrl,
    this.mealDescription,
    required this.calories,
    required this.onMercyTap,
    required this.onLikeTap,
    required this.onItemTap,
    this.onCommentTap,
    this.keepAspectRatio = false,
  });

  @override
  State<_ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<_ReelItem>
    with SingleTickerProviderStateMixin {
  bool _isLiked = false;
  late AnimationController _likeAnimationController;
  late Animation<double> _likeScaleAnimation;

  @override
  void initState() {
    super.initState();
    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _likeScaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _likeAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    _checkLikeStatus();
  }

  @override
  void dispose() {
    _likeAnimationController.dispose();
    super.dispose();
  }

  /// いいね状態をDBから確認
  Future<void> _checkLikeStatus() async {
    try {
      final currentUserId = supabase.auth.currentUser!.id;

      final like = await supabase
          .from('meal_likes')
          .select('id')
          .eq('meal_id', widget.mealId)
          .eq('user_id', currentUserId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isLiked = like != null;
        });
      }
    } catch (e) {
      print('❌ いいね状態確認エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景画像
        if (widget.mealPhotoUrl != null && widget.mealPhotoUrl!.isNotEmpty)
          Image.network(
            widget.mealPhotoUrl!,
            fit: widget.keepAspectRatio ? BoxFit.contain : BoxFit.cover,
          )
        else
          Container(
            color: Colors.grey[300],
            child: const Icon(Icons.image, size: 80, color: Colors.grey),
          ),

        // グラデーション（下部を暗くしてテキストを見やすく）
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.9),
                  Colors.black.withOpacity(0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ユーザー情報（左下）
        Positioned(
          bottom: 100,
          left: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ユーザー名とID
              Row(
                children: [
                  // ユーザー画像
                  (widget.userPhotoUrl != null &&
                          widget.userPhotoUrl!.isNotEmpty)
                      ? DegradedIconDisplay(
                          imageUrl: widget.userPhotoUrl!,
                          buddhaImageUrl: widget.userBuddhaUrl,
                          karma: widget.userKarma,
                          size: 48,
                          shape: BoxShape.circle,
                        )
                      : CircleAvatar(
                          radius: 24,
                          child: const Icon(Icons.person),
                        ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '@${widget.userCustomId}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // カロリー表示（一番目立つように大きく）
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: widget.calories > 600
                      ? Colors.red.withOpacity(0.9)
                      : Colors.green.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: (widget.calories > 600 ? Colors.red : Colors.green)
                          .withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.calories > 600
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.calories}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'kcal',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 説明文
              if (widget.mealDescription != null &&
                  widget.mealDescription!.isNotEmpty)
                SizedBox(
                  width: MediaQuery.of(context).size.width - 32,
                  child: Text(
                    widget.mealDescription!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // アクションボタン（右側）
        Positioned(
          bottom: 100,
          right: 16,
          child: Column(
            children: [
              // 慈悲ボタン
              GestureDetector(
                onTap: widget.onMercyTap,
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.orange.withOpacity(0.8),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '慈悲',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // いいねボタン
              GestureDetector(
                onTap: () async {
                  // すぐに状態を更新してUIをレスポンシブにする
                  setState(() {
                    _isLiked = !_isLiked;
                  });

                  // アニメーションを再生
                  _likeAnimationController.forward().then((_) {
                    _likeAnimationController.reverse();
                  });

                  // バックエンドに送信
                  widget.onLikeTap();

                  // 念のため状態を再確認（エラーがあった場合に戻す）
                  await Future.delayed(const Duration(milliseconds: 100));
                  await _checkLikeStatus();
                },
                child: ScaleTransition(
                  scale: _likeScaleAnimation,
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isLiked
                              ? Colors.pink
                              : Colors.white.withOpacity(0.7),
                          boxShadow: _isLiked
                              ? [
                                  BoxShadow(
                                    color: Colors.pink.withOpacity(0.6),
                                    blurRadius: 15,
                                    spreadRadius: 3,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          _isLiked ? Icons.favorite : Icons.favorite_border,
                          color: _isLiked ? Colors.white : Colors.grey,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'いいね',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // コメントボタン
              GestureDetector(
                onTap: () => widget.onCommentTap?.call(context),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.withOpacity(0.7),
                      ),
                      child: const Icon(
                        Icons.comment_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'コメント',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // アイテム使用ボタン
              GestureDetector(
                onTap: widget.onItemTap,
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.purple.withOpacity(0.7),
                      ),
                      child: const Icon(
                        Icons.card_giftcard,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'アイテム',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
