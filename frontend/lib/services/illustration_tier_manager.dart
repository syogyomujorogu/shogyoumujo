// =============================================================================
// illustration_tier_manager.dart - 業スコアティア画像管理クラス
// =============================================================================
// 業スコアの段階変動を監視し、新しいティアの画像生成をリクエスト

import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class IllustrationTierManager {
  /// 業スコアからティア（1-5）を計算
  static int getKarmaTier(int karma) {
    if (karma <= 20) return 1;
    if (karma <= 40) return 2;
    if (karma <= 60) return 3;
    if (karma <= 80) return 4;
    return 5;
  }

  /// 業スコアが段階を超えたかどうかを判定し、画像生成をリクエスト
  static Future<bool> checkAndRequestGeneration({
    required String userId,
    required int oldKarma,
    required int newKarma,
    required String originalPhotoUrl,
  }) async {
    try {
      final oldTier = getKarmaTier(oldKarma);
      final newTier = getKarmaTier(newKarma);

      // 同じティアなら何もしない
      if (oldTier == newTier) {
        return false;
      }

      print('🎨 新しいティアに到達: tier$oldTier → tier$newTier');

      // 生成リクエストをデータベースに登録
      const List<String> prompts = [
        '', // index 0 (unused)
        '悪業を積んだ人物のイラスト。ハゲ散らかし、ニキビだらけの顔。デブで太った体。目は虚ろ。服装はボロボロ。暗い雰囲気。',
        'やや不健康な顔のイラスト。薄毛気味、ニキビ跡が残る。少しデブ気味。表情は沈んでいる。',
        '穏やかな顔のイラスト。健康的な肌。髪は整っている。バランスの良い顔立ち。デジタルペイント風。',
        '光のある美しい顔のイラスト。つやのある肌。綺麗な髪。適度なバランスの顔。輝き。',
        '光輝く仏のイラスト。完璧な美しさ。透き通るような肌。光のオーラに包まれた髪。神聖で荘厳。最高品質。',
      ];

      await supabase.from('illustration_requests').insert({
        'user_id': userId,
        'original_photo_url': originalPhotoUrl,
        'tier': newTier,
        'prompt': prompts[newTier],
        'status': 'pending',
      });

      print('✅ 画像生成リクエスト登録: tier$newTier');
      return true;
    } catch (e) {
      print('❌ リクエスト登録エラー: $e');
      return false;
    }
  }

  /// ユーザーのティア画像URLを取得
  static Future<String?> getTierImageUrl({
    required String userId,
    required int karma,
  }) async {
    try {
      final tier = getKarmaTier(karma);
      final tierColumn = 'profile_illustration_tier$tier';

      final user = await supabase
          .from('users')
          .select(tierColumn)
          .eq('user_id', userId)
          .maybeSingle();

      if (user != null) {
        return user[tierColumn] as String?;
      }
      return null;
    } catch (e) {
      print('❌ ティア画像URL取得エラー: $e');
      return null;
    }
  }

  /// 全ティア画像URLをまとめて取得
  static Future<Map<int, String?>> getAllTierImageUrls({
    required String userId,
  }) async {
    try {
      final user = await supabase
          .from('users')
          .select('profile_illustration_tier1, profile_illustration_tier2, '
              'profile_illustration_tier3, profile_illustration_tier4, '
              'profile_illustration_tier5')
          .eq('user_id', userId)
          .maybeSingle();

      if (user == null) {
        return {};
      }

      return {
        1: user['profile_illustration_tier1'] as String?,
        2: user['profile_illustration_tier2'] as String?,
        3: user['profile_illustration_tier3'] as String?,
        4: user['profile_illustration_tier4'] as String?,
        5: user['profile_illustration_tier5'] as String?,
      };
    } catch (e) {
      print('❌ 全ティア画像取得エラー: $e');
      return {};
    }
  }

  /// ティア画像URLを保存
  static Future<bool> saveTierImageUrl({
    required String userId,
    required int tier,
    required String imageUrl,
  }) async {
    try {
      final tierColumn = 'profile_illustration_tier$tier';

      await supabase.from('users').update({
        tierColumn: imageUrl,
      }).eq('user_id', userId);

      print('✅ ティア$tier画像URL保存: $imageUrl');
      return true;
    } catch (e) {
      print('❌ ティア画像URL保存エラー: $e');
      return false;
    }
  }

  /// 生成リクエストの状態を更新
  static Future<bool> updateRequestStatus({
    required String requestId,
    required String status,
    String? resultImageUrl,
    String? errorMessage,
  }) async {
    try {
      final updateData = {
        'status': status,
        if (resultImageUrl != null) 'result_image_url': resultImageUrl,
        if (errorMessage != null) 'error_message': errorMessage,
        if (status == 'completed')
          'completed_at': DateTime.now().toIso8601String(),
      };

      await supabase
          .from('illustration_requests')
          .update(updateData)
          .eq('id', requestId);

      return true;
    } catch (e) {
      print('❌ リクエスト状態更新エラー: $e');
      return false;
    }
  }

  /// 当月のイラスト生成リクエスト数をカウント（月に1回制限チェック用）
  static Future<int> getMonthlyRequestCount(String userId) async {
    try {
      final now = DateTime.now().toUtc();
      final monthStart = DateTime.utc(now.year, now.month, 1)
          .toIso8601String(); // 月初 00:00:00Z
      final monthEnd =
          DateTime.utc(now.year, now.month + 1, 1).toIso8601String(); // 翌月初

      final response = await supabase
          .from('illustration_requests')
          .select('id')
          .eq('user_id', userId)
          .gte('created_at', monthStart)
          .lt('created_at', monthEnd);

      print('📊 当月のリクエスト数: ${response.length}');
      return response.length;
    } catch (e) {
      print('❌ 月内リクエスト数カウントエラー: $e');
      return 0; // エラー時は0を返す（制限なしと判定）
    }
  }

  /// 月に1回のイラスト生成リクエストが可能かチェック
  static Future<Map<String, dynamic>> checkMonthlyRequestAllowance(
      String userId) async {
    try {
      final count = await getMonthlyRequestCount(userId);
      final isAllowed = count == 0;

      // 次月初日（リセット日）を計算
      final now = DateTime.now().toUtc();
      final nextReset = DateTime.utc(now.year, now.month + 1, 1);

      return {
        'allowed': isAllowed,
        'requestCount': count,
        'nextAllowedDate': isAllowed ? null : nextReset.toIso8601String(),
      };
    } catch (e) {
      print('❌ リクエスト許可判定エラー: $e');
      return {'allowed': false, 'requestCount': 1, 'error': e.toString()};
    }
  }

  /// 🛠️ デバッグ用：月1回制限をリセット（当月のリクエストを削除）
  static Future<bool> resetMonthlyLimitDebug(String userId) async {
    try {
      final now = DateTime.now().toUtc();
      final monthStart = DateTime.utc(now.year, now.month, 1).toIso8601String();
      final monthEnd =
          DateTime.utc(now.year, now.month + 1, 1).toIso8601String();

      // 当月のリクエストをすべて削除
      await supabase
          .from('illustration_requests')
          .delete()
          .eq('user_id', userId)
          .gte('created_at', monthStart)
          .lt('created_at', monthEnd);

      print('🔓 デバッグ: 月1回制限をリセットしました (ユーザーID: $userId)');
      return true;
    } catch (e) {
      print('❌ デバッグリセットエラー: $e');
      return false;
    }
  }
}
