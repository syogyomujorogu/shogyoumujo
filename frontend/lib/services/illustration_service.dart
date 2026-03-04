// =============================================================================
// illustration_service.dart - Gemini を使用したイラスト化サービス
// =============================================================================
// 機能：ユーザー写真をGeminiで穏やかな仏教風イラストに変換
// =============================================================================

import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class IllustrationService {
  final String apiKey;
  late GenerativeModel _model;

  IllustrationService({required this.apiKey}) {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );
  }

  /// ユーザー写真をイラスト化するプロンプトを取得
  String _getIllustrationPrompt() {
    return '''
    この写真の人物の顔を基にして、以下の特徴を持つ穏やかな仏教風イラストを生成してください：
    
    【イラストの特徴】
    - スタイル：日本の仏教美術風の優雅なイラスト
    - 表情：穏やかで慈悲深い
    - 背景：淡いグラデーション（薄紫～薄金色）
    - 色使い：やさしく調和した色合い
    - 質感：デジタルペイント風、柔らかなタッチ
    
    【変換内容】
    元の顔の特徴を尊重しながら、仏教的な穏やかさと優雅さを表現してください。
    顔の輪郭、目、口などの特徴は認識できる程度に保ちつつ、
    全体の雰囲気を穏やかで瞑想的なものに変えてください。
    
    出力：高品質なデジタルイラスト形式（PNG推奨）
    ''';
  }

  /// 仏イラストプロンプトを取得（業100達成時用）
  String _getBuddhaIllustrationPrompt() {
    return '''
    この写真の人物の顔を基にして、以下の特徴を持つ光輝く仏のイラストを生成してください：
    
    【イラストの特徴】
    - スタイル：日本の仏教美術における聖者のイラスト
    - 表情：慈悲と智慧に満ちた穏やかな表情
    - 背景：金色と虹色のオーラ、光輝く円形後光
    - 色使い：金、銀、虹色を基調とした神聖な色合い
    - 光効果：輝く光の粒子、温かみのあるグロー
    - 質感：デジタルペイント風、優雅で荘厳なタッチ
    
    【変換内容】
    元の顔の特徴を尊重しながら、完全な悟りを達成した聖者としての姿を表現してください。
    光と光輝きが全体を包むようなデザインで、観者に平和と希望をもたらす
    力強く優雅な印象を与えてください。
    
    出力：高品質なデジタルイラスト形式（PNG推奨）
    ''';
  }

  /// 写真URLからBase64エンコードされた画像データを取得
  Future<String> _getImageBase64(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        return base64Encode(response.bodyBytes);
      } else {
        throw Exception('Failed to fetch image: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error downloading image: $e');
    }
  }

  /// イラスト化処理（ただしGemini Vision APIは画像生成に対応していないため、
  /// 将来的には Stable Diffusion や DALL-E 3 の導入を検討）
  /// 現在は、ユーザーが既にアップロードしたイラスト化済み画像を使用する仕様に変更
  /// 代わりに、テキスト説明からPrompt Engineeringで最適なプロンプトを生成
  Future<String> generateIllustrationPrompt({
    required String imageUrl,
    bool isBoddha = false,
  }) async {
    try {
      // 画像をBase64で取得
      final imageBase64 = await _getImageBase64(imageUrl);

      // Vision APIを使用して画像を分析し、詳細な説明を取得
      final content = [
        Content.multi([
          TextPart('''
            この写真の人物の顔を詳しく分析してください：
            - 顔の形
            - 目の特徴
            - 鼻の特徴
            - 口の特徴
            - 全体的な雰囲気や印象
            
            これらの特徴を基に、${isBoddha ? _getBuddhaIllustrationPrompt() : _getIllustrationPrompt()}の指示に従ったイラストを説明してください。
            '''),
          DataPart('image/jpeg', base64Decode(imageBase64)),
        ]),
      ];

      final response = await _model.generateContent(content);
      return response.text ?? 'Failed to generate illustration prompt';
    } catch (e) {
      throw Exception('Error generating illustration: $e');
    }
  }

  /// シンプルなイラスト化プロンプトのみを返す（実際の画像生成は別サービスで実行）
  String getSimpleIllustrationPrompt({required bool isBoddha}) {
    return isBoddha ? _getBuddhaIllustrationPrompt() : _getIllustrationPrompt();
  }
}
