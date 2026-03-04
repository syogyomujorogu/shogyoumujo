// =============================================================================
// karma_avatar_manager.dart - 業スコア連動アバター管理サービス
// =============================================================================
// 機能：
// 1. イラスト化されたアバターをGeminiプロンプトで生成
// 2. 仏イラストを業100に達成したときに生成
// 3. Supabaseに保存、キャッシュ管理
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/illustration_service.dart';

final supabase = Supabase.instance.client;

class KarmaAvatarManager {
  final String geminiApiKey;
  late IllustrationService _illustrationService;

  KarmaAvatarManager({required this.geminiApiKey}) {
    _illustrationService = IllustrationService(apiKey: geminiApiKey);
  }

  /// ユーザーが初めてプロフィール写真をアップロードしたときに呼び出す
  /// イラスト化プロンプトを生成し、ユーザーに提示
  Future<String?> generateIllustrationPrompt({
    required String userId,
    required String photoUrl,
  }) async {
    try {
      // ユーザーのイラストがすでに存在するかチェック
      final existing = await supabase
          .from('users')
          .select('profile_illustration_url')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null && existing['profile_illustration_url'] != null) {
        return existing['profile_illustration_url'];
      }

      // Geminiで詳細なイラスト化プロンプトを生成
      final prompt = await _illustrationService.generateIllustrationPrompt(
        imageUrl: photoUrl,
        isBoddha: false,
      );

      // プロンプトを保存（後で手動でイラストを生成するために使用）
      print('📝 イラスト化プロンプト\n$prompt');

      // ここからユーザーは実際のイラスト生成API（Stable Diffusion, DALL-Eなど）
      // を使用して画像を生成し、URLをアップロードする必要がある
      // または、デフォルトのプレースホルダーを返す

      return null; // プロンプトのみ返す
    } catch (e) {
      print('❌ イラスト化プロンプト生成エラー: $e');
      return null;
    }
  }

  /// 業100に到達したときに仏イラストプロンプトを生成
  Future<String?> generateBuddhaIllustrationPrompt({
    required String userId,
    required String profileIllustrationUrl,
  }) async {
    try {
      // すでに仏イラストが存在するかチェック
      final existing = await supabase
          .from('users')
          .select('profile_buddha_illustration_url')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null &&
          existing['profile_buddha_illustration_url'] != null) {
        return existing['profile_buddha_illustration_url'];
      }

      // Geminiで詳細な仏イラスト化プロンプトを生成
      final prompt = await _illustrationService.generateIllustrationPrompt(
        imageUrl: profileIllustrationUrl,
        isBoddha: true,
      );

      print('📝 仏イラスト化プロンプト\n$prompt');

      // ここからユーザーは実際のイラスト生成API（Stable Diffusion, DALL-Eなど）
      // を使用して画像を生成し、URLをアップロードする必要がある

      return null; // プロンプトのみ返す
    } catch (e) {
      print('❌ 仏イラスト化プロンプト生成エラー: $e');
      return null;
    }
  }

  /// ユーザーが手動でアップロードしたイラストURLを保存
  Future<bool> saveIllustrationUrl({
    required String userId,
    required String illustrationUrl,
  }) async {
    try {
      await supabase.from('users').update({
        'profile_illustration_url': illustrationUrl,
        'illustration_created': true,
      }).eq('user_id', userId);

      return true;
    } catch (e) {
      print('❌ イラスト保存エラー: $e');
      return false;
    }
  }

  /// 日本の仏イラストをユーザーが手動でアップロード
  Future<bool> saveBuddhaIllustrationUrl({
    required String userId,
    required String buddhaiIllustrationUrl,
  }) async {
    try {
      await supabase.from('users').update({
        'profile_buddha_illustration_url': buddhaiIllustrationUrl,
        'buddha_illustration_created': true,
      }).eq('user_id', userId);

      return true;
    } catch (e) {
      print('❌ 仏イラスト保存エラー: $e');
      return false;
    }
  }

  /// シンプルなイラスト化プロンプトを取得（カスタマイズ用）
  String getSimpleIllustrationPrompt({required bool isBoddha}) {
    return _illustrationService.getSimpleIllustrationPrompt(isBoddha: isBoddha);
  }
}
