// =============================================================================
// item_usage_dialog.dart - アイテム使用ダイアログ
// =============================================================================
// このファイルの役割:
// 1. 所持アイテム一覧を表示
// 2. アイテムを選択して食事に使用
// 3. カロリー変更処理と通知送信
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ItemUsageDialog extends StatefulWidget {
  final String mealId;
  final String mealOwnerId;
  final int currentCalories;
  final bool isOwnMeal; // true: 自分の食事, false: 友達の食事

  const ItemUsageDialog({
    super.key,
    required this.mealId,
    required this.mealOwnerId,
    required this.currentCalories,
    required this.isOwnMeal,
  });

  @override
  State<ItemUsageDialog> createState() => _ItemUsageDialogState();
}

class _ItemUsageDialogState extends State<ItemUsageDialog> {
  List<Map<String, dynamic>> _availableItems = [];
  bool _isLoading = true;
  bool _alreadyUsed = false;

  @override
  void initState() {
    super.initState();
    _checkAndLoadItems();
  }

  Future<void> _checkAndLoadItems() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 既にこの食事にこのユーザーがアイテムを使用しているかチェック
      final usageCheck = await supabase
          .from('item_usage_history')
          .select()
          .eq('meal_id', widget.mealId)
          .eq('user_id', userId)
          .maybeSingle();

      if (usageCheck != null) {
        setState(() {
          _alreadyUsed = true;
          _isLoading = false;
        });
        return;
      }

      // 所持アイテムを取得
      final userItems = await supabase
          .from('user_items')
          .select('*, items(*)')
          .eq('user_id', userId)
          .gt('quantity', 0);

      // 自分の食事なら減少系のみ、友達の食事なら増加系のみフィルタ
      final filtered = (userItems as List).where((item) {
        final effectType = item['items']['effect_type'] as String;
        if (widget.isOwnMeal) {
          return effectType == 'calorie_decrease';
        } else {
          return effectType == 'calorie_increase';
        }
      }).toList();

      setState(() {
        _availableItems = filtered.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _useItem(Map<String, dynamic> userItem) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final item = userItem['items'] as Map<String, dynamic>;
      final effectValue = item['effect_value'] as int;
      final itemId = item['id'] as String;

      // カロリー計算
      final modifiedCalories = widget.isOwnMeal
          ? (widget.currentCalories * (100 - effectValue) / 100).round()
          : (widget.currentCalories * (100 + effectValue) / 100).round();

      // アイテム使用履歴に記録
      await supabase.from('item_usage_history').insert({
        'user_id': userId,
        'item_id': itemId,
        'meal_id': widget.mealId,
        'meal_owner_id': widget.mealOwnerId,
        'original_calories': widget.currentCalories,
        'modified_calories': modifiedCalories,
      });

      // アイテム数量を減らす
      final newQuantity = (userItem['quantity'] as int) - 1;
      if (newQuantity > 0) {
        await supabase
            .from('user_items')
            .update({'quantity': newQuantity}).eq('id', userItem['id']);
      } else {
        await supabase.from('user_items').delete().eq('id', userItem['id']);
      }

      // 食事のカロリーを更新
      await supabase
          .from('meals')
          .update({'calories': modifiedCalories}).eq('id', widget.mealId);

      // ========== 業スコアの更新（実際のカロリー変動量ベース） ==========
      // 変動カロリー 500kcal につき業±1（camera_screen.dartと同じ基準）
      // 例: 800kcal × 30%増 = +240kcal → 業-0, 800kcal × 100%増 = +800kcal → 業-1
      // 例: 800kcal × 30%減 = -240kcal → 業+0, 800kcal × 100%減 = -800kcal → 業+1
      int karmaChange = 0;
      try {
        final calorieDiff = (modifiedCalories - widget.currentCalories).abs();
        final karmaAmount = (calorieDiff / 500).floor().clamp(0, 10);
        final targetUserId = widget.isOwnMeal ? userId : widget.mealOwnerId;
        final targetUser = await supabase
            .from('users')
            .select('karma')
            .eq('user_id', targetUserId)
            .single();
        final currentKarma = (targetUser['karma'] ?? 50) as int;

        if (karmaAmount > 0) {
          if (widget.isOwnMeal) {
            // 慈悲系: カロリー減った分だけ業回復
            karmaChange = karmaAmount;
          } else {
            // 業系: カロリー増えた分だけ相手の業低下
            karmaChange = -karmaAmount;
          }
          final newKarma = (currentKarma + karmaChange).clamp(0, 100);
          await supabase.from('users').update({
            'karma': newKarma,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('user_id', targetUserId);
        }
      } catch (e) {
        print('⚠️ アイテム使用時の業スコア更新エラー: $e');
      }

      // 他人の食事にアイテムを使用した場合は通知を作成
      if (!widget.isOwnMeal) {
        // 送信者の表示名を取得
        String senderName = '誰か';
        try {
          final senderData = await supabase
              .from('users')
              .select('display_name')
              .eq('user_id', userId)
              .maybeSingle();
          senderName = senderData?['display_name'] ?? '誰か';
        } catch (_) {}

        final itemName = item['name'] as String? ?? 'アイテム';
        final karmaInfo =
            karmaChange < 0 ? '\n😈 業値が${karmaChange.abs()}低下しました…' : '';

        // 統合通知テーブルに追加（ベルアイコンに反映される）
        try {
          await supabase.from('notifications').insert({
            'recipient_id': widget.mealOwnerId,
            'sender_id': userId,
            'notification_type': 'item_usage',
            'content': {
              'meal_id': widget.mealId,
              'item_id': itemId,
              'effect_percentage': effectValue,
              'karma_change': karmaChange,
            },
            'message':
                '⚡ ${senderName}さんが「$itemName」をあなたの食事に使用！カロリーが${effectValue}%増量されました！$karmaInfo',
          });
        } catch (e) {
          print('⚠️ 統合通知作成エラー（スキップ）: $e');
        }

        // 旧テーブルにも互換性のため残す（失敗しても無視）
        try {
          await supabase.from('item_usage_notifications').insert({
            'recipient_id': widget.mealOwnerId,
            'sender_id': userId,
            'item_id': itemId,
            'meal_id': widget.mealId,
            'effect_percentage': effectValue,
          });
        } catch (_) {}
      }

      if (mounted) {
        Navigator.pop(context, true); // 成功を返す
        final karmaMsg = karmaChange > 0
            ? '（業+$karmaChange）'
            : karmaChange < 0
                ? '（相手の業$karmaChange）'
                : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isOwnMeal
                  ? '✅ カロリーを$effectValue%減少させました！$karmaMsg'
                  : '⚡ $effectValue%増量チケットを使用しました！$karmaMsg',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ エラー: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.isOwnMeal ? Icons.favorite : Icons.whatshot,
            color: widget.isOwnMeal ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Text(widget.isOwnMeal ? 'カロリー減少アイテム' : 'カロリー増量アイテム'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _alreadyUsed
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'この食事には既にアイテムが\n使用されています',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  )
                : _availableItems.isEmpty
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.isOwnMeal
                                ? '使用可能な減少アイテムがありません\nガチャで入手できます'
                                : '使用可能な増量アイテムがありません\nガチャで入手できます',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _availableItems.length,
                        itemBuilder: (context, index) {
                          final userItem = _availableItems[index];
                          final item =
                              userItem['items'] as Map<String, dynamic>;
                          final quantity = userItem['quantity'] as int;
                          final effectValue = item['effect_value'] as int;
                          final name = item['name'] as String;
                          final description = item['description'] as String;
                          final rarity = item['rarity'] as String;

                          // レアリティに応じた色
                          Color rarityColor;
                          switch (rarity) {
                            case 'SSR':
                              rarityColor = Colors.purple;
                              break;
                            case 'SR':
                              rarityColor = Colors.blue;
                              break;
                            default:
                              rarityColor = Colors.grey;
                          }

                          // 適用後のカロリーを計算
                          final newCalories = widget.isOwnMeal
                              ? (widget.currentCalories *
                                      (100 - effectValue) /
                                      100)
                                  .round()
                              : (widget.currentCalories *
                                      (100 + effectValue) /
                                      100)
                                  .round();

                          return Card(
                            color: rarityColor.withOpacity(0.1),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: rarityColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  rarity,
                                  style: TextStyle(
                                    color: rarityColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                '$name (x$quantity)',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(description),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${widget.currentCalories} kcal → $newCalories kcal',
                                    style: TextStyle(
                                      color: widget.isOwnMeal
                                          ? Colors.green
                                          : Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward),
                              onTap: () => _useItem(userItem),
                            ),
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
    );
  }
}
