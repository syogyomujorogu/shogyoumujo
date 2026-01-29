// =============================================================================
// friend_request_helpers.dart - フレンド申請ヘルパー関数
// =============================================================================
// このファイルの役割:
// 1. フレンド申請の送信
// 2. フレンド申請の承認・拒否
// 3. フレンドリストの取得
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

/// フレンド申請を送信する
///
/// [targetUserId] 申請先のユーザーID
/// [message] 任意のメッセージ
///
/// 成功した場合はtrue、失敗した場合はfalseを返す
Future<bool> sendFriendRequest(String targetUserId, {String? message}) async {
  try {
    final currentUserId = supabase.auth.currentUser!.id;

    // 既に申請済みかチェック
    final existingRequest = await supabase
        .from('friend_requests')
        .select()
        .eq('requester_id', currentUserId)
        .eq('target_id', targetUserId)
        .maybeSingle();

    if (existingRequest != null) {
      final status = existingRequest['status'];
      if (status == 'pending') {
        throw Exception('既にフレンド申請を送信済みです');
      } else if (status == 'accepted') {
        throw Exception('既にフレンドです');
      } else if (status == 'rejected') {
        // 拒否された場合は再申請可能
        await supabase
            .from('friend_requests')
            .delete()
            .eq('id', existingRequest['id']);
      }
    }

    // 既にフレンドかチェック
    final existingFriend = await supabase
        .from('friends')
        .select()
        .eq('user_id', currentUserId)
        .eq('friend_id', targetUserId)
        .maybeSingle();

    if (existingFriend != null) {
      throw Exception('既にフレンドです');
    }

    // フレンド申請を作成
    final request = await supabase
        .from('friend_requests')
        .insert({
          'requester_id': currentUserId,
          'target_id': targetUserId,
          'status': 'pending',
          'message': message,
        })
        .select()
        .single();

    // 通知を送信
    await supabase.from('notifications').insert({
      'recipient_id': targetUserId,
      'sender_id': currentUserId,
      'notification_type': 'friend_request',
      'content': {'request_id': request['id']},
      'message': 'フレンド申請が届いています',
    });

    return true;
  } catch (e) {
    print('フレンド申請エラー: $e');
    rethrow;
  }
}

/// フレンド申請を承認する
///
/// [requestId] フレンド申請のID
///
/// 成功した場合はtrue、失敗した場合はfalseを返す
Future<bool> acceptFriendRequest(String requestId) async {
  try {
    // リクエストを取得
    final request = await supabase
        .from('friend_requests')
        .select()
        .eq('id', requestId)
        .single();

    if (request['status'] != 'pending') {
      throw Exception('この申請は既に処理されています');
    }

    // ステータスを更新
    await supabase.from('friend_requests').update({
      'status': 'accepted',
      'responded_at': DateTime.now().toIso8601String()
    }).eq('id', requestId);

    // friendsテーブルに双方向のレコードを追加
    await supabase.from('friends').insert([
      {
        'user_id': request['requester_id'],
        'friend_id': request['target_id'],
      },
      {
        'user_id': request['target_id'],
        'friend_id': request['requester_id'],
      },
    ]);

    // 申請者に承認通知を送る
    await supabase.from('notifications').insert({
      'recipient_id': request['requester_id'],
      'sender_id': request['target_id'],
      'notification_type': 'friend_accept',
      'content': {},
      'message': 'フレンド申請が承認されました',
    });

    return true;
  } catch (e) {
    print('フレンド承認エラー: $e');
    rethrow;
  }
}

/// フレンド申請を拒否する
///
/// [requestId] フレンド申請のID
///
/// 成功した場合はtrue、失敗した場合はfalseを返す
Future<bool> rejectFriendRequest(String requestId) async {
  try {
    await supabase.from('friend_requests').update({
      'status': 'rejected',
      'responded_at': DateTime.now().toIso8601String()
    }).eq('id', requestId);

    return true;
  } catch (e) {
    print('フレンド拒否エラー: $e');
    rethrow;
  }
}

/// 受信したフレンド申請を取得
///
/// [status] フィルタリングするステータス（省略すると全て）
///
/// フレンド申請のリストを返す
Future<List<Map<String, dynamic>>> getReceivedFriendRequests({
  String? status,
}) async {
  try {
    final currentUserId = supabase.auth.currentUser!.id;

    var query = supabase
        .from('friend_requests')
        .select('*, requester:requester_id(username, avatar_url)')
        .eq('target_id', currentUserId)
        .order('requested_at', ascending: false);

    if (status != null) {
      query = query.eq('status', status);
    }

    final requests = await query;
    return (requests as List).cast<Map<String, dynamic>>();
  } catch (e) {
    print('フレンド申請取得エラー: $e');
    return [];
  }
}

/// 送信したフレンド申請を取得
///
/// [status] フィルタリングするステータス（省略すると全て）
///
/// フレンド申請のリストを返す
Future<List<Map<String, dynamic>>> getSentFriendRequests({
  String? status,
}) async {
  try {
    final currentUserId = supabase.auth.currentUser!.id;

    var query = supabase
        .from('friend_requests')
        .select('*, target:target_id(username, avatar_url)')
        .eq('requester_id', currentUserId)
        .order('requested_at', ascending: false);

    if (status != null) {
      query = query.eq('status', status);
    }

    final requests = await query;
    return (requests as List).cast<Map<String, dynamic>>();
  } catch (e) {
    print('送信済み申請取得エラー: $e');
    return [];
  }
}
