// =============================================================================
// item_notifications_screen.dart - アイテム使用通知画面
// =============================================================================
// このファイルの役割:
// 1. 増量チケットが使われた通知を一覧表示
// 2. 通知を既読にする
// 3. 通知から該当の食事に移動
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

final supabase = Supabase.instance.client;

class ItemNotificationsScreen extends StatefulWidget {
  const ItemNotificationsScreen({Key? key}) : super(key: key);

  @override
  State<ItemNotificationsScreen> createState() =>
      _ItemNotificationsScreenState();
}

class _ItemNotificationsScreenState extends State<ItemNotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final notifications =
          await supabase.from('item_usage_notifications').select('''
            *,
            sender:sender_id(username, avatar_url),
            item:items(name, rarity)
          ''').eq('recipient_id', userId).order('created_at', ascending: false);

      setState(() {
        _notifications = (notifications as List).cast<Map<String, dynamic>>();
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

  Future<void> _markAsRead(String notificationId) async {
    try {
      await supabase
          .from('item_usage_notifications')
          .update({'is_read': true}).eq('id', notificationId);

      await _loadNotifications();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase
          .from('item_usage_notifications')
          .update({'is_read': true})
          .eq('recipient_id', userId)
          .eq('is_read', false);

      await _loadNotifications();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 全ての通知を既読にしました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        _notifications.where((n) => n['is_read'] == false).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡ アイテム使用通知'),
        backgroundColor: Colors.deepPurple,
        actions: [
          if (unreadCount > 0)
            TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all, color: Colors.white),
              label: const Text(
                '全て既読',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.notifications_off,
                          size: 100, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        '通知はありません',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      final sender =
                          notification['sender'] as Map<String, dynamic>?;
                      final item =
                          notification['item'] as Map<String, dynamic>?;
                      final effectPercentage =
                          notification['effect_percentage'] as int;
                      final isRead = notification['is_read'] as bool;
                      final createdAt =
                          DateTime.parse(notification['created_at']);

                      final senderName = sender?['username'] ?? '削除されたユーザー';
                      final itemName = item?['name'] ?? '不明なアイテム';
                      final rarity = item?['rarity'] ?? 'N';

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

                      return Dismissible(
                        key: Key(notification['id']),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.green,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.done, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          _markAsRead(notification['id']);
                        },
                        child: Container(
                          color: isRead
                              ? Colors.transparent
                              : Colors.orange.withOpacity(0.1),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: rarityColor.withOpacity(0.2),
                              child: Icon(Icons.whatshot, color: rarityColor),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  '$senderName さん',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                if (!isRead)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'NEW',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  '⚡ $effectPercentage%増量チケット「$itemName」を使用しました！',
                                  style: TextStyle(
                                    color: rarityColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('yyyy/MM/dd HH:mm')
                                      .format(createdAt.toLocal()),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                            trailing: !isRead
                                ? IconButton(
                                    icon: const Icon(Icons.done),
                                    onPressed: () =>
                                        _markAsRead(notification['id']),
                                    tooltip: '既読にする',
                                  )
                                : null,
                            onTap: () {
                              if (!isRead) {
                                _markAsRead(notification['id']);
                              }
                              // ここで該当の食事詳細に移動する処理を追加可能
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
