import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Gemini APIヘルパークラス
class GeminiHelper {
  late final GenerativeModel _model;

  /// 初期化
  GeminiHelper() {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY が .env に設定されていません');
    }

    // モデルを初期化（無料プランで使える gemini-1.5-flash）
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );
  }

  /// テキスト生成（シンプルな質問）
  Future<String> generateText(String prompt) async {
    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? 'レスポンスが空です';
    } catch (e) {
      if (e.toString().contains('403')) {
        return 'エラー: 403 Forbidden - APIキーまたは権限を確認してください\n'
            '1. https://aistudio.google.com/ で発行したキーか確認\n'
            '2. Generative Language API が有効か確認\n'
            '3. VPN接続を解除して試してください';
      } else if (e.toString().contains('429')) {
        return 'エラー: 無料枠の上限に達しました。明日再試行してください。';
      }
      return 'エラー: $e';
    }
  }

  /// チャット形式で会話
  Future<String> chat(String message, {List<Content>? history}) async {
    try {
      final chat = _model.startChat(history: history ?? []);
      final response = await chat.sendMessage(Content.text(message));
      return response.text ?? 'レスポンスが空です';
    } catch (e) {
      if (e.toString().contains('403')) {
        return 'エラー: 403 - APIキーの権限を確認してください';
      } else if (e.toString().contains('429')) {
        return 'エラー: 無料枠の上限に達しました';
      }
      return 'エラー: $e';
    }
  }

  /// 画像とテキストから生成（マルチモーダル）
  Future<String> generateFromImageAndText({
    required List<int> imageBytes,
    required String prompt,
  }) async {
    try {
      // List<int> を Uint8List に変換（DataPart が Uint8List を要求するため）
      final uint8Bytes =
          imageBytes is Uint8List ? imageBytes : Uint8List.fromList(imageBytes);
      final response = await _model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', uint8Bytes),
        ])
      ]);
      return response.text ?? 'レスポンスが空です';
    } catch (e) {
      return 'エラー: $e';
    }
  }
}
