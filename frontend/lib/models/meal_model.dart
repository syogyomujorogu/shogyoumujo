// =============================================================================
// meal_model.dart - 食事投稿データモデル
// =============================================================================
// このファイルの役割:
// 1. 食事投稿データの型定義
// 2. Supabaseから取得したMapをモデルに変換
// =============================================================================

class MealModel {
  final String id; // 投稿ID
  final String userId; // 投稿者ユーザーID
  final String? photoUrl; // 食事画像URL
  final String? description; // 投稿説明
  final DateTime createdAt; // 投稿日時

  MealModel({
    required this.id,
    required this.userId,
    this.photoUrl,
    this.description,
    required this.createdAt,
  });

  // Map（Supabaseのレスポンス）からモデルを生成
  factory MealModel.fromMap(Map<String, dynamic> map) {
    return MealModel(
      id: map['id'].toString(),
      userId: map['user_id'] ?? '',
      photoUrl: map['photo_url'] as String?,
      description: map['description'] as String?,
      createdAt:
          DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}
