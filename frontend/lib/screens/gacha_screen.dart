// =============================================================================
// gacha_screen.dart - ガチャガチャ画面
// =============================================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class GachaScreen extends StatefulWidget {
  const GachaScreen({Key? key}) : super(key: key);

  @override
  State<GachaScreen> createState() => _GachaScreenState();
}

class _GachaScreenState extends State<GachaScreen>
    with TickerProviderStateMixin {
  int _ticketCount = 0;
  List<Map<String, dynamic>> _userItems = [];
  bool _isLoading = true;
  bool _isPulling = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // チケット枚数を取得
      final ticketData = await supabase
          .from('gacha_tickets')
          .select('ticket_count')
          .eq('user_id', userId)
          .maybeSingle();

      _ticketCount = ticketData?['ticket_count'] ?? 0;

      // 所持アイテムを取得
      final itemsData = await supabase
          .from('user_items')
          .select('*, items(*)')
          .eq('user_id', userId)
          .order('obtained_at', ascending: false);

      _userItems = List<Map<String, dynamic>>.from(itemsData);

      // 同じアイテムをまとめる（item_idごとにグループ化してquantityを合計）
      final Map<String, Map<String, dynamic>> groupedItems = {};
      for (final userItem in _userItems) {
        final itemId = userItem['item_id'] as String;
        final quantity = userItem['quantity'] as int? ?? 1;

        if (groupedItems.containsKey(itemId)) {
          groupedItems[itemId]!['quantity'] =
              (groupedItems[itemId]!['quantity'] as int) + quantity;
        } else {
          groupedItems[itemId] = {
            ...userItem,
            'quantity': quantity,
          };
        }
      }

      _userItems = groupedItems.values.toList();
    } catch (e) {
      _showMessage('データの読み込みに失敗: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pullGacha() async {
    if (_ticketCount <= 0) {
      _showMessage('チケットが足りません');
      return;
    }

    setState(() => _isPulling = true);

    try {
      final userId = supabase.auth.currentUser!.id;

      // アイテムマスターデータを取得
      final items = await supabase.from('items').select();

      // 排出率に基づいてランダム選択
      final selectedItem = _selectRandomItem(items);

      // チケット消費
      await supabase.from('gacha_tickets').upsert({
        'user_id': userId,
        'ticket_count': _ticketCount - 1,
      });

      // アイテム追加
      await supabase.from('user_items').insert({
        'user_id': userId,
        'item_id': selectedItem['id'],
      });

      // ガチャ履歴追加
      await supabase.from('gacha_history').insert({
        'user_id': userId,
        'item_id': selectedItem['id'],
        'rarity': selectedItem['rarity'],
      });

      // アニメーション開始
      await Future.delayed(const Duration(milliseconds: 500));
      _animationController.forward(from: 0.0);

      // 結果表示
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _buildResultDialog(selectedItem),
      );

      // データ再読み込み
      await _loadData();
    } catch (e) {
      _showMessage('エラー: $e');
    } finally {
      setState(() => _isPulling = false);
    }
  }

  Map<String, dynamic> _selectRandomItem(List<dynamic> items) {
    final random = Random();
    final roll = random.nextDouble() * 100; // 0-100の乱数

    double cumulative = 0.0;
    for (final item in items) {
      cumulative += (item['drop_rate'] as num).toDouble();
      if (roll <= cumulative) {
        return item as Map<String, dynamic>;
      }
    }

    // フォールバック（通常は到達しない）
    return items.first as Map<String, dynamic>;
  }

  Widget _buildResultDialog(Map<String, dynamic> item) {
    Color rarityColor;
    String rarityText;

    switch (item['rarity']) {
      case 'N':
        rarityColor = Colors.grey;
        rarityText = 'ノーマル';
        break;
      case 'SR':
        rarityColor = Colors.blue;
        rarityText = 'スーパーレア';
        break;
      case 'SSR':
        rarityColor = Colors.amber;
        rarityText = 'スーパースーパーレア';
        break;
      default:
        rarityColor = Colors.grey;
        rarityText = '';
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                rarityColor.withOpacity(0.3),
                rarityColor.withOpacity(0.1),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rarityText,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: rarityColor,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: rarityColor, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: rarityColor.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _getItemIcon(item),
                    style: const TextStyle(fontSize: 60),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                item['name'],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                item['description'],
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: rarityColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Color _getRarityColor(String rarity) {
    switch (rarity) {
      case 'N':
        return Colors.grey;
      case 'SR':
        return Colors.blue;
      case 'SSR':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _useItem(
    String userItemId,
    String itemId,
    String effectType,
    int effectValue,
  ) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // アイテムを削除（1個減らす）
      await supabase.from('user_items').delete().eq('id', userItemId).limit(1);

      // エフェクトを適用
      if (effectType == 'calorie_decrease') {
        // カロリー減少（善いアイテム）
        _showMessage('✨ カロリーが${effectValue}減少しました！');
      } else if (effectType == 'calorie_increase') {
        // カロリー増加（悪いアイテム）
        _showMessage('💀 カロリーが${effectValue}増加しました...');
      }

      // 通知を作成
      await supabase.from('notifications').insert({
        'recipient_id': userId,
        'sender_id': userId,
        'notification_type': 'item_usage',
        'message': 'アイテムを使用しました',
        'content': {
          'item_id': itemId,
          'effect_type': effectType,
          'effect_value': effectValue,
        },
      });

      // データ再読み込み
      await _loadData();
    } catch (e) {
      _showMessage('アイテム使用エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎰 ガチャガチャ'),
        backgroundColor: Colors.purple,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // チケット表示
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple[700]!, Colors.purple[400]!],
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '所持チケット',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '🎫',
                              style: TextStyle(fontSize: 40),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$_ticketCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '枚',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ガチャボタン
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.purple[300]!,
                                Colors.purple[600]!,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withOpacity(0.5),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isPulling ? null : _pullGacha,
                              customBorder: const CircleBorder(),
                              child: Center(
                                child: _isPulling
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                      )
                                    : const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '🎰',
                                            style: TextStyle(fontSize: 60),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'ガチャを回す',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'チケット1枚消費',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 排出率表示
                  _buildDropRateInfo(),

                  const SizedBox(height: 16),

                  // 所持アイテム
                  _buildItemInventory(),
                ],
              ),
            ),
    );
  }

  Widget _buildDropRateInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 排出率',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildRateRow('SSR', '3%', Colors.amber),
          _buildRateRow('SR', '27%', Colors.blue),
          _buildRateRow('N', '70%', Colors.grey),
        ],
      ),
    );
  }

  Widget _buildRateRow(String rarity, String rate, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              rarity,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(rate),
        ],
      ),
    );
  }

  Widget _buildItemInventory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '🎒 所持アイテム (${_userItems.length}個)',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _userItems.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('まだアイテムを持っていません'),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _userItems.length,
                itemBuilder: (context, index) {
                  final userItem = _userItems[index];
                  final item = userItem['items'] as Map<String, dynamic>;
                  final quantity = userItem['quantity'] as int? ?? 1;
                  final effectType = item['effect_type'] as String;
                  final effectValue = item['effect_value'] as int? ?? 0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              _getRarityColor(item['rarity']).withOpacity(0.2),
                          border: Border.all(
                            color: _getRarityColor(item['rarity']),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _getItemIcon(item),
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['name'],
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (quantity > 1)
                            Text(
                              '×$quantity',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['description']),
                          const SizedBox(height: 4),
                          ElevatedButton(
                            onPressed: () => _useItem(
                              userItem['user_item_id'] ?? userItem['id'],
                              item['id'],
                              effectType,
                              effectValue,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            child: const Text(
                              '使用する',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getRarityColor(item['rarity']),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item['rarity'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
        const SizedBox(height: 24),
      ],
    );
  }
}
