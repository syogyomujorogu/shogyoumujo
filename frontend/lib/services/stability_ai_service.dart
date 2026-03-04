// =============================================================================
// stability_ai_service.dart - Stability AI 画像生成サービス
// =============================================================================
// 業スコアティアに応じたイラスト生成

import 'package:http/http.dart' as http;
import 'dart:convert';

class StabilityAIService {
  final String apiKey;
  static const String apiUrl =
      'https://api.stability.ai/v2beta/stable-image/generate/core';

  StabilityAIService({required this.apiKey});

  /// ティア1-5に対応したプロンプト（英語のみサポート）
  final Map<int, String> tierPrompts = {
    1: 'Illustration of a karmic person with severe baldness, acne-covered face, obese body, hollow eyes, tattered clothes, dark atmosphere, digital art',
    2: 'Illustration of a somewhat unhealthy face with thinning hair, acne scars, slightly overweight, depressed expression, digital art style',
    3: 'Illustration of a calm peaceful face with healthy skin, well-groomed hair, well-balanced facial features, serene expression, digital art',
    4: 'Illustration of a beautiful radiant face with luminous glowing skin, shiny healthy hair, well-balanced features, spiritual aura, digital art',
    5: 'Illustration of a radiant enlightened Buddha figure with perfect divine beauty, translucent luminous skin, hair surrounded by sacred light, majestic and serene, highest quality digital art',
  };

  /// Stability AI APIで画像生成（v2beta API使用）
  ///
  /// [tier] 1-5のティア番号
  /// [originalImageUrl] 元画像のURL
  ///
  /// 返却: 生成された画像のBase64データ
  Future<String?> generateIllustration({
    required int tier,
    required String originalImageUrl,
  }) async {
    try {
      print('🎨 [Stability AI] イラスト生成開始 - Tier: $tier');

      if (!tierPrompts.containsKey(tier)) {
        throw Exception('Invalid tier: $tier');
      }

      final prompt = tierPrompts[tier]!;
      print('📝 プロンプト: $prompt');
      print('🔑 API キー確認: ${apiKey.isNotEmpty ? "✅ 設定済み" : "❌ 未設定"}');
      print('🔗 API URL: $apiUrl');

      // Stability AI REST v2beta APIにリクエスト
      print('📤 API リクエスト送信中...');

      final request = http.MultipartRequest('POST', Uri.parse(apiUrl))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..headers['Accept'] = 'application/json'
        ..fields['prompt'] = prompt
        ..fields['output_format'] = 'png';

      final response = await request.send();

      print('📊 レスポンスステータス: ${response.statusCode}');

      final responseBody = await response.stream.bytesToString();
      print('📄 レスポンス本文: $responseBody');

      if (response.statusCode == 200) {
        print('✅ API リクエスト成功');
        final result = jsonDecode(responseBody);

        print('📋 レスポンス構造: ${result.keys.toList()}');

        // レスポンスから画像データを抽出
        if (result['image'] != null && (result['image'] as String).isNotEmpty) {
          final base64Image = result['image'] as String;
          print(
              '🖼️ Base64 画像取得成功 (v2beta image, サイズ: ${base64Image.length} bytes)');
          return base64Image;
        } else if (result['artifacts'] != null &&
            result['artifacts'].isNotEmpty) {
          final base64Image = result['artifacts'][0]['base64'];
          print('🖼️ Base64 画像取得成功 (サイズ: ${base64Image.length} bytes)');
          return base64Image;
        } else {
          print('⚠️ image/artifacts のどちらにも画像がありません: ${result.toString()}');
          throw Exception('No image generated');
        }
      } else if (response.statusCode == 429) {
        print('❌ レート制限: リクエストが多すぎます');
        throw Exception('Rate limit exceeded');
      } else if (response.statusCode == 404) {
        print('❌ エンドポイント不正: ${response.statusCode}');
        throw Exception('API endpoint not found (404)');
      } else {
        print('❌ API エラー: ${response.statusCode}');
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 画像生成エラー: $e');
      print('🔍 エラー詳細: ${e.toString()}');
      return null;
    }
  }

  /// 生成した画像をSupabase Storageにアップロード
  Future<String?> uploadGeneratedImage({
    required String userId,
    required int tier,
    required String base64Image,
  }) async {
    try {
      // このメソッドはプロジェクト内でSupabaseクライアントが
      // 初期化された後に実装してください
      // 形式: profile_illustrations/{user_id}/tier{tier}.png

      print('📤 アップロード予定: tier$tier for user $userId');
      return null; // placeholder
    } catch (e) {
      print('❌ アップロードエラー: $e');
      return null;
    }
  }

  /// 月の生成回数を取得（ダミー実装）
  Future<int> getMonthlyGenerationCount() async {
    // 実装: Supabaseから月ごとの成功リクエスト数をカウント
    return 0;
  }

  /// 月の生成回数が上限に達しているか確認
  Future<bool> isMonthlyLimitExceeded() async {
    const int maxPerMonth = 50;
    final count = await getMonthlyGenerationCount();
    return count >= maxPerMonth;
  }
}
