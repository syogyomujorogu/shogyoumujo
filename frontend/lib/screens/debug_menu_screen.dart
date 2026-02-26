// =============================================================================
// debug_menu_screen.dart - 開発者専用デバッグメニュー
// =============================================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'debug_account_switcher_screen.dart';

final supabase = Supabase.instance.client;

class DebugMenuScreen extends StatefulWidget {
  const DebugMenuScreen({super.key});

  @override
  State<DebugMenuScreen> createState() => _DebugMenuScreenState();
}

class _DebugMenuScreenState extends State<DebugMenuScreen> {
  final _stepsController = TextEditingController();
  final _weightController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void dispose() {
    _stepsController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  // 指定日の歩数を設定
  Future<void> _setSteps() async {
    final steps = int.tryParse(_stepsController.text);
    if (steps == null) {
      _showMessage('正しい歩数を入力してください');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // 既存のレコードを削除して新規追加
      await supabase
          .from('steps')
          .delete()
          .eq('user_id', userId)
          .eq('date', dateStr);

      await supabase.from('steps').insert({
        'user_id': userId,
        'step_count': steps,
        'date': dateStr,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _showMessage('歩数を $steps 歩に設定しました');
      _stepsController.clear();
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 体重を記録
  Future<void> _setWeight() async {
    final weight = double.tryParse(_weightController.text);
    if (weight == null) {
      _showMessage('正しい体重を入力してください');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      await supabase.from('weight_logs').insert({
        'user_id': userId,
        'weight': weight,
        'note': 'デバッグメニューから入力',
        'created_at': _selectedDate.toUtc().toIso8601String(),
      });

      _showMessage('体重 ${weight}kg を記録しました');
      _weightController.clear();
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 修業開始日を変更（週間まとめテスト用）
  Future<void> _changeTrainingStartDate() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: '修業開始日を選択',
    );

    if (pickedDate == null) return;

    final daysElapsed = DateTime.now().difference(pickedDate).inDays;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 確認'),
        content: Text(
            '修業開始日を ${DateFormat('yyyy年MM月dd日').format(pickedDate)} に変更しますか？\n\n'
            '経過日数: $daysElapsed 日\n'
            '${daysElapsed >= 7 ? '※ 7日以上経過しているため、週間まとめが表示されるはずです' : '※ まだ7日経過していません'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('変更'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      await supabase.from('users').update({
        'training_start_date': pickedDate.toUtc().toIso8601String(),
        'training_started': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      _showMessage('修業開始日を変更しました（経過 $daysElapsed 日）');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 修業期間を強制完了
  Future<void> _completeTraining() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 確認'),
        content: const Text('修業期間を強制完了しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('完了'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      await supabase.from('users').update({
        'training_end_date': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      _showMessage('修業期間を完了しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 全データをリセット（危険）
  Future<void> _resetAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 危険な操作'),
        content: const Text('全てのデータをリセットします。\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('リセット'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // 各テーブルのデータを削除
      await supabase.from('steps').delete().eq('user_id', userId);
      await supabase.from('weight_logs').delete().eq('user_id', userId);
      await supabase.from('meals').delete().eq('user_id', userId);

      // 修業データをリセット
      await supabase.from('users').update({
        'training_started': false,
        'training_start_date': null,
        'training_end_date': null,
        'training_start_weight': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      _showMessage('全データをリセットしました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 複数日分の歩数データを生成
  Future<void> _generateMultipleDaysSteps() async {
    final daysController = TextEditingController(text: '7');
    final stepsController = TextEditingController(text: '8000');

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 複数日分の歩数を生成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: daysController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '日数',
                hintText: '例: 7',
                suffixText: '日',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: stepsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '1日あたりの平均歩数',
                hintText: '例: 8000',
                suffixText: '歩',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              final days = int.tryParse(daysController.text) ?? 7;
              final steps = int.tryParse(stepsController.text) ?? 8000;
              Navigator.pop(context, {'days': days, 'steps': steps});
            },
            child: const Text('生成'),
          ),
        ],
      ),
    );

    if (result == null) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      final days = result['days']!;
      final baseSteps = result['steps']!;

      for (int i = 0; i < days; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final randomVariation = (baseSteps * 0.2).toInt();
        final steps = baseSteps +
            (DateTime.now().millisecond % randomVariation) -
            (randomVariation ~/ 2);

        await supabase
            .from('steps')
            .delete()
            .eq('user_id', userId)
            .eq('date', dateStr);

        await supabase.from('steps').insert({
          'user_id': userId,
          'step_count': steps,
          'date': dateStr,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      _showMessage('$days 日分の歩数データを生成しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ダミーの食事投稿を作成（フレンドからの投稿）
  Future<void> _createDummyMealPost() async {
    final meals = [
      {'name': '精進料理セット', 'calories': 520, 'type': 'lunch'},
      {'name': '玄米と納豆', 'calories': 380, 'type': 'breakfast'},
      {'name': '野菜たっぷり味噌汁定食', 'calories': 450, 'type': 'dinner'},
      {'name': 'サーモンアボカド丼', 'calories': 650, 'type': 'lunch'},
      {'name': 'チキンサラダ', 'calories': 320, 'type': 'lunch'},
      {'name': 'ざるそば', 'calories': 450, 'type': 'lunch'},
      {'name': 'フルーツヨーグルト', 'calories': 220, 'type': 'breakfast'},
      {'name': 'グリルチキンと野菜', 'calories': 580, 'type': 'dinner'},
    ];

    final dummyFriends = ['dummy_friend_1', 'dummy_friend_2', 'dummy_friend_3'];
    final random = Random();
    final meal = meals[random.nextInt(meals.length)];
    final friendId = dummyFriends[random.nextInt(dummyFriends.length)];

    setState(() => _isLoading = true);
    try {
      // ダミーフレンドが存在するか確認
      final friendExists = await supabase
          .from('users')
          .select()
          .eq('user_id', friendId)
          .maybeSingle();

      if (friendExists == null) {
        _showMessage('先にダミーフレンドを追加してください');
        setState(() => _isLoading = false);
        return;
      }

      await supabase.from('meals').insert({
        'user_id': friendId,
        'meal_type': meal['type'],
        'description': '${meal['name']} - 今日も健康的な食事！',
        'photo_url': '',
        'calories': meal['calories'],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      final friendName = friendExists['display_name'] ?? 'フレンド';
      _showMessage('$friendNameの投稿を作成: ${meal['name']}');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 自分の投稿を全削除
  Future<void> _deleteAllMyMeals() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 確認'),
        content: const Text('自分の投稿を全て削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('meals').delete().eq('user_id', userId);
      _showMessage('自分の投稿を全て削除しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 全ての体重記録を削除
  Future<void> _deleteAllWeightLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 確認'),
        content: const Text('体重記録を全て削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('weight_logs').delete().eq('user_id', userId);
      _showMessage('体重記録を全て削除しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 全ての歩数記録を削除
  Future<void> _deleteAllSteps() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 確認'),
        content: const Text('歩数記録を全て削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('steps').delete().eq('user_id', userId);
      _showMessage('歩数記録を全て削除しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 修業状態をリセット
  Future<void> _resetTrainingStatus() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 確認'),
        content: const Text('修業状態をリセットしますか？\n（修業開始前の状態に戻ります）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('リセット'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('users').update({
        'training_started': false,
        'training_start_date': null,
        'training_end_date': null,
        'training_start_weight': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      _showMessage('修業状態をリセットしました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // ガチャチケットを付与
  Future<void> _addGachaTickets() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // 既存のチケット数を取得
      final existing = await supabase
          .from('gacha_tickets')
          .select('ticket_count')
          .eq('user_id', userId)
          .maybeSingle();

      final currentCount = existing?['ticket_count'] ?? 0;

      if (existing != null) {
        // チケットを加算
        await supabase.from('gacha_tickets').update({
          'ticket_count': currentCount + 10,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('user_id', userId);
      } else {
        // 新規作成
        await supabase.from('gacha_tickets').insert({
          'user_id': userId,
          'ticket_count': 10,
        });
      }

      _showMessage('ガチャチケット10枚を付与しました（合計: ${currentCount + 10}枚）');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 初心者実績を達成
  Future<void> _unlockBeginnerAchievements() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // achievementsテーブルから実際に存在する実績を取得（最大3件、カラム名は'id'）
      final achievements =
          await supabase.from('achievements').select('id').limit(3);

      if (achievements.isEmpty) {
        _showMessage('実績データがまだ作成されていません');
        return;
      }

      int unlocked = 0;
      for (final achievement in achievements) {
        final achievementId = achievement['id'];

        // 既に達成済みか確認
        final existing = await supabase
            .from('user_achievements')
            .select()
            .eq('user_id', userId)
            .eq('achievement_id', achievementId)
            .maybeSingle();

        if (existing == null) {
          await supabase.from('user_achievements').insert({
            'user_id': userId,
            'achievement_id': achievementId,
          });
          unlocked++;
        }
      }

      if (unlocked > 0) {
        _showMessage('$unlocked件の実績を達成しました！プロフィールで確認してください');
      } else {
        _showMessage('すべての実績は既に達成済みです');
      }
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 全種類のアイテムを付与
  Future<void> _addAllItems() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // 全アイテムを取得（カラム名は'id'）
      final items = await supabase.from('items').select('id');

      if (items.isEmpty) {
        _showMessage('アイテムデータがまだ作成されていません');
        return;
      }

      int addedItems = 0;
      for (final item in items) {
        final itemId = item['id'];

        // 既存のアイテム数を取得
        final existing = await supabase
            .from('user_items')
            .select('quantity')
            .eq('user_id', userId)
            .eq('item_id', itemId)
            .maybeSingle();

        if (existing != null) {
          // 数量を加算
          await supabase
              .from('user_items')
              .update({
                'quantity': existing['quantity'] + 5,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('user_id', userId)
              .eq('item_id', itemId);
        } else {
          // 新規作成
          await supabase.from('user_items').insert({
            'user_id': userId,
            'item_id': itemId,
            'quantity': 5,
          });
        }
        addedItems++;
      }

      _showMessage('$addedItems種類のアイテムを5個ずつ付与しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // いいね通知を作成
  Future<void> _createLikeNotification() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // テスト用のダミーユーザーID（自分からの通知とする）
      await supabase.from('notifications').insert({
        'recipient_id': userId,
        'sender_id': userId,
        'notification_type': 'like',
        'content': {
          'meal_post_id': 1, // ダミーのmeal_post_id
        },
        'message': 'あなたの食事投稿にいいねしました',
      });

      _showMessage('いいね通知を作成しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // コメント通知を作成
  Future<void> _createCommentNotification() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      await supabase.from('notifications').insert({
        'recipient_id': userId,
        'sender_id': userId,
        'notification_type': 'comment',
        'content': {
          'meal_post_id': 1,
          'comment_text': 'すごいですね！頑張ってください！',
        },
        'message': 'あなたの投稿にコメントしました',
      });

      _showMessage('コメント通知を作成しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // アイテム使用通知を作成
  Future<void> _createItemUsageNotification() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      await supabase.from('notifications').insert({
        'recipient_id': userId,
        'sender_id': userId,
        'notification_type': 'item_usage',
        'content': {
          'meal_post_id': 1,
          'item_name': '増量チケット',
        },
        'message': 'があなたの食事に増量チケットを使いました',
      });

      _showMessage('アイテム使用通知を作成しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 実績達成通知を作成
  Future<void> _createAchievementNotification() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      await supabase.from('notifications').insert({
        'recipient_id': userId,
        'sender_id': null, // システム通知
        'notification_type': 'achievement',
        'content': {
          'achievement_name': '初心者の一歩',
          'badge_name': '駆け出し修行者',
        },
        'message': '実績「初心者の一歩」を達成しました！',
      });

      _showMessage('実績達成通知を作成しました');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ダミーフレンドを作成
  Future<void> _createDummyFriends() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // ダミーユーザーのデータ
      final dummyUsers = [
        {
          'user_id': 'dummy_friend_1',
          'display_name': '修行僧太郎',
          'email': 'taro@example.com',
          'bio': '毎日10km歩いています！',
          'photo_url': null,
        },
        {
          'user_id': 'dummy_friend_2',
          'display_name': '節制花子',
          'email': 'hanako@example.com',
          'bio': '健康的な食生活を心がけています',
          'photo_url': null,
        },
        {
          'user_id': 'dummy_friend_3',
          'display_name': '精進次郎',
          'email': 'jiro@example.com',
          'bio': 'ダイエット頑張ります',
          'photo_url': null,
        },
      ];

      // ダミーユーザーをusersテーブルに追加（既に存在する場合はスキップ）
      for (final dummy in dummyUsers) {
        final userId = dummy['user_id'] as String;
        final existing = await supabase
            .from('users')
            .select()
            .eq('user_id', userId)
            .maybeSingle();

        if (existing == null) {
          await supabase.from('users').insert(dummy);
        }
      }

      // ダミーフレンドとの承認済みフレンド関係を作成
      for (final dummy in dummyUsers) {
        final dummyUserId = dummy['user_id'] as String;

        // 既にフレンド申請が存在するか確認
        final existingRequest = await supabase
            .from('friend_requests')
            .select()
            .eq('requester_id', dummyUserId)
            .eq('target_id', userId)
            .eq('status', 'accepted')
            .maybeSingle();

        if (existingRequest == null) {
          // 承認済みのフレンド申請を作成
          await supabase.from('friend_requests').insert({
            'requester_id': dummyUserId,
            'target_id': userId,
            'status': 'accepted',
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }

      _showMessage('ダミーフレンド3人を追加しました！');
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🛠 開発者デバッグメニュー'),
        backgroundColor: Colors.deepOrange,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 警告メッセージ
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ 開発者専用機能\n本番環境では使用しないでください',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 👤 アカウント管理セクション
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
                    child: Text(
                      '👤 アカウント管理',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                      title: const Text('アカウント切り替えツール'),
                      subtitle: const Text('テストアカウントに簡単に切り替え'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DebugAccountSwitcherScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 日付選択
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('対象日付'),
                      subtitle:
                          Text(DateFormat('yyyy年MM月dd日').format(_selectedDate)),
                      trailing: const Icon(Icons.edit),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() => _selectedDate = date);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 歩数設定
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🚶 歩数を設定',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _stepsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '歩数',
                              hintText: '例: 10000',
                              border: OutlineInputBorder(),
                              suffixText: '歩',
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _setSteps,
                            icon: const Icon(Icons.save),
                            label: const Text('歩数を設定'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 体重設定
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '⚖️ 体重を記録',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _weightController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d{0,3}(\.\d{0,1})?')),
                            ],
                            decoration: const InputDecoration(
                              labelText: '体重',
                              hintText: '例: 70.5',
                              border: OutlineInputBorder(),
                              suffixText: 'kg',
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _setWeight,
                            icon: const Icon(Icons.save),
                            label: const Text('体重を記録'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // データ生成セクション
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
                    child: Text(
                      '📊 データ生成',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.timeline, color: Colors.blue),
                      title: const Text('複数日分の歩数を生成'),
                      subtitle: const Text('指定日数分のランダム歩数データ'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _generateMultipleDaysSteps,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading:
                          const Icon(Icons.restaurant, color: Colors.green),
                      title: const Text('ダミー食事投稿を作成'),
                      subtitle: const Text('テスト用の食事投稿を追加'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _createDummyMealPost,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 修業設定セクション
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
                    child: Text(
                      '🧘 修業設定',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month,
                          color: Colors.orange),
                      title: const Text('修業開始日を変更'),
                      subtitle: const Text('週間まとめのテストに便利'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _changeTrainingStartDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading:
                          const Icon(Icons.check_circle, color: Colors.green),
                      title: const Text('修業期間を強制完了'),
                      subtitle: const Text('現在の日付で修業を完了させます'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _completeTraining,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.refresh, color: Colors.orange),
                      title: const Text('修業状態をリセット'),
                      subtitle: const Text('修業開始前の状態に戻す'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _resetTrainingStatus,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 🎮 ゲーミフィケーション機能テスト
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
                    child: Text(
                      '🎮 ゲーミフィケーション機能',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.confirmation_number,
                          color: Colors.purple),
                      title: const Text('ガチャチケットを付与'),
                      subtitle: const Text('チケット10枚を追加'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _addGachaTickets,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading:
                          const Icon(Icons.emoji_events, color: Colors.amber),
                      title: const Text('初心者実績を達成'),
                      subtitle: const Text('テスト用バッジを付与'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _unlockBeginnerAchievements,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.card_giftcard,
                          color: Colors.deepPurple),
                      title: const Text('全種類のアイテムを付与'),
                      subtitle: const Text('各アイテム×5個'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _addAllItems,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 🔔 通知機能テスト
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
                    child: Text(
                      '🔔 通知機能',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.favorite, color: Colors.red),
                      title: const Text('いいね通知を作成'),
                      subtitle: const Text('テスト通知を送信'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _createLikeNotification,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.comment, color: Colors.blue),
                      title: const Text('コメント通知を作成'),
                      subtitle: const Text('テスト通知を送信'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _createCommentNotification,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading:
                          const Icon(Icons.card_giftcard, color: Colors.purple),
                      title: const Text('アイテム使用通知を作成'),
                      subtitle: const Text('増量チケット使用の通知'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _createItemUsageNotification,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading:
                          const Icon(Icons.emoji_events, color: Colors.amber),
                      title: const Text('実績達成通知を作成'),
                      subtitle: const Text('テスト通知を送信'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _createAchievementNotification,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 👥 フレンド機能テスト
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
                    child: Text(
                      '👥 フレンド機能',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.people, color: Colors.green),
                      title: const Text('ダミーフレンドを追加'),
                      subtitle: const Text('テスト用フレンド3人を追加'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _createDummyFriends,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 個別削除セクション
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
                    child: Text(
                      '🗑️ 個別削除',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ),
                  Card(
                    color: Colors.red.withOpacity(0.05),
                    child: ListTile(
                      leading:
                          const Icon(Icons.restaurant_menu, color: Colors.red),
                      title: const Text('投稿を全削除'),
                      subtitle: const Text('自分の食事投稿のみ'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _deleteAllMyMeals,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.red.withOpacity(0.05),
                    child: ListTile(
                      leading:
                          const Icon(Icons.monitor_weight, color: Colors.red),
                      title: const Text('体重記録を全削除'),
                      subtitle: const Text('全ての体重ログ'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _deleteAllWeightLogs,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.red.withOpacity(0.05),
                    child: ListTile(
                      leading:
                          const Icon(Icons.directions_walk, color: Colors.red),
                      title: const Text('歩数記録を全削除'),
                      subtitle: const Text('全ての歩数データ'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: _deleteAllSteps,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // データリセット（危険）
                  Card(
                    color: Colors.red.withOpacity(0.1),
                    child: ListTile(
                      leading:
                          const Icon(Icons.delete_forever, color: Colors.red),
                      title: const Text(
                        '全データをリセット',
                        style: TextStyle(color: Colors.red),
                      ),
                      subtitle: const Text('⚠️ 取り消せません'),
                      trailing:
                          const Icon(Icons.arrow_forward, color: Colors.red),
                      onTap: _resetAllData,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 情報表示
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ℹ️ 使い方',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text('• 日付を選択してから各機能を使用'),
                        Text('• 歩数は既存データを上書き'),
                        Text('• 体重は新規記録として追加'),
                        Text('• 複数日分の歩数生成で一括テスト'),
                        Text('• ダミー投稿でフィード表示をテスト'),
                        Text('• 個別削除で特定データのみクリア'),
                        Text('• 全リセットは取り消せないので注意'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
