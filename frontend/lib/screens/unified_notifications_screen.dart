// =============================================================================
// unified_notifications_screen.dart - 統合通知画面
// =============================================================================
// このファイルの役割:
// 1. 全種類の通知を一覧表示（いいね、コメント、フレンド申請、アイテム使用など）
// 2. 通知タイプ別にフィルタリング
// 3. 通知を既読にする
// 4. 通知から該当のコンテンツに移動
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'meal_detail_screen.dart';

final supabase = Supabase.instance.client;

class UnifiedNotificationsScreen extends StatefulWidget {
  const UnifiedNotificationsScreen({super.key});

  @override
  State<UnifiedNotificationsScreen> createState() =>
      _UnifiedNotificationsScreenState();
}

class _UnifiedNotificationsScreenState
    extends State<UnifiedNotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String _filterType = 'all'; // all, like, comment, friend_request, item_usage

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      setState(() => _isLoading = true);

      final userId = supabase.auth.currentUser!.id;

      // フィルタリング条件を先に構築
      PostgrestFilterBuilder query =
          supabase.from('notifications').select('*').eq('recipient_id', userId);

      // タイプフィルタリング
      if (_filterType != 'all') {
        query = query.eq('notification_type', _filterType);
      }

      final notifications = await query.order('created_at', ascending: false);

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
          .from('notifications')
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
          .from('notifications')
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

  Future<void> _handleNotificationTap(Map<String, dynamic> notification) async {
    // 既読にする
    if (!notification['is_read']) {
      await _markAsRead(notification['id']);
    }

    // 通知タイプに応じて適切な画面に遷移
    final type = notification['notification_type'];
    final content = notification['content'] as Map<String, dynamic>?;

    if (!mounted) return;

    switch (type) {
      case 'like':
      case 'comment':
      case 'item_usage':
        // 食事詳細画面に遷移（meal_idが含まれている場合）
        if (content != null && content['meal_id'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  MealDetailScreen(mealId: content['meal_id'].toString()),
            ),
          );
        }
        break;

      case 'friend_request':
      case 'friend_accept':
      case 'achievement':
        // 既読にするだけ（専用画面なし）
        break;

      default:
        break;
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.comment;
      case 'friend_request':
        return Icons.person_add;
      case 'friend_accept':
        return Icons.check_circle;
      case 'item_usage':
        return Icons.card_giftcard;
      case 'achievement':
        return Icons.emoji_events;
      case 'system':
        return Icons.info;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return Colors.blue;
      case 'friend_request':
        return Colors.green;
      case 'friend_accept':
        return Colors.teal;
      case 'item_usage':
        return Colors.purple;
      case 'achievement':
        return Colors.amber;
      case 'system':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡ 通知'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: _markAllAsRead,
            tooltip: '全て既読にする',
          ),
        ],
      ),
      body: Column(
        children: [
          // フィルターチップ
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _buildFilterChip('全て', 'all'),
                _buildFilterChip('❤️ いいね', 'like'),
                _buildFilterChip('💬 コメント', 'comment'),
                _buildFilterChip('👥 フレンド', 'friend_request'),
                _buildFilterChip('🎁 アイテム', 'item_usage'),
                _buildFilterChip('🏆 実績', 'achievement'),
              ],
            ),
          ),
          const Divider(height: 1),

          // 通知リスト
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_off,
                              size: 80,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '通知はありません',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          final isRead = notification['is_read'] as bool;
                          final type =
                              notification['notification_type'] as String;
                          final message = notification['message'] as String;
                          final createdAt =
                              DateTime.parse(notification['created_at']);

                          return Dismissible(
                            key: Key(notification['id']),
                            background: Container(
                              color: Colors.green,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                              ),
                            ),
                            onDismissed: (_) => _markAsRead(notification['id']),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getNotificationColor(type)
                                    .withOpacity(0.2),
                                child: Icon(
                                  _getNotificationIcon(type),
                                  color: _getNotificationColor(type),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                message,
                                style: TextStyle(
                                  fontWeight: isRead
                                      ? FontWeight.normal
                                      : FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                DateFormat('MM/dd HH:mm').format(createdAt),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              ),
                              trailing: !isRead
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
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
                                    )
                                  : null,
                              tileColor:
                                  isRead ? null : Colors.blue.withOpacity(0.05),
                              onTap: () => _handleNotificationTap(notification),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String type) {
    final isSelected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _filterType = type;
          });
          _loadNotifications();
        },
        selectedColor: Colors.deepPurple.withOpacity(0.3),
        checkmarkColor: Colors.deepPurple,
      ),
    );
  }
}
