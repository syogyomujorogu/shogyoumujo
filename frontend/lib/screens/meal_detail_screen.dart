// =============================================================================
// meal_detail_screen.dart - 食事詳細画面
// =============================================================================
// このファイルの役割:
// 1. meal_id を受け取り、該当の食事投稿詳細を表示
// 2. 投稿画像・説明・投稿者情報・カロリー・健康度などを表示
// 3. コメントや「無常」などのアクションも将来的に追加可能
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class MealDetailScreen extends StatefulWidget {
  final String mealId;
  const MealDetailScreen({super.key, required this.mealId});

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  Map<String, dynamic>? _meal;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMeal();
  }

  Future<void> _loadMeal() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('meals')
          .select(
              '*, user:users!user_id(display_name, photo_url, custom_user_id)')
          .eq('id', widget.mealId)
          .maybeSingle();
      setState(() {
        _meal = response;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _meal = null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_meal == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('食事詳細')),
        body: const Center(child: Text('食事データが見つかりませんでした')),
      );
    }
    final user = _meal!['user'] ?? {};
    final photoUrl = _meal!['photo_url'] as String?;
    final description = _meal!['description'] as String?;
    final displayName = user['display_name'] ?? '無名の修行者';
    final userPhoto = user['photo_url'] as String?;
    final calories = _meal!['calories']?.toString() ?? '-';
    final healthScore = _meal!['health_score']?.toString() ?? '-';
    final createdAt = _meal!['created_at'] ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('食事詳細')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photoUrl != null && photoUrl.isNotEmpty)
              Image.network(photoUrl, fit: BoxFit.cover, height: 220),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundImage:
                            userPhoto != null && userPhoto.isNotEmpty
                                ? NetworkImage(userPhoto)
                                : null,
                        child:
                            userPhoto == null ? const Icon(Icons.person) : null,
                      ),
                      const SizedBox(width: 8),
                      Text(displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      Text(createdAt.toString().substring(0, 16),
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (description != null && description.isNotEmpty)
                    Text(description, style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department,
                          color: Colors.red),
                      const SizedBox(width: 4),
                      Text('カロリー: $calories kcal'),
                      const SizedBox(width: 16),
                      const Icon(Icons.health_and_safety, color: Colors.green),
                      const SizedBox(width: 4),
                      Text('健康度: $healthScore'),
                    ],
                  ),
                  // 今後: コメント欄やアクションボタン追加予定
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
