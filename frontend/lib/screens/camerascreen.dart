import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

final supabase = Supabase.instance.client;

class CameraScreen extends StatefulWidget {
  const CameraScreen({Key? key}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isAnalyzing = false;

  Future<void> _takePicture() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (photo != null) {
        setState(() {
          _imageFile = File(photo.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('カメラエラー: $e')),
      );
    }
  }

  Future<void> _analyzeImage() async {
    if (_imageFile == null) return;

    setState(() => _isAnalyzing = true);

    try {
      // 1. 画像をBase64エンコード
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      // 2. OpenAI APIでカロリー推定
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer YOUR_OPENAI_API_KEY', // 自分のキーに変更
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text':
                      'この食事のカロリーを推定してください。以下のJSON形式で返してください:\n{"dishName": "料理名", "calories": カロリー数値, "isHealthy": true/false}'
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                  }
                }
              ],
            }
          ],
          'max_tokens': 300,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('AI API呼び出し失敗: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'];
      final result = jsonDecode(content);

      final calories = result['calories'] as int;
      final dishName = result['dishName'] as String;
      final isHealthy = result['isHealthy'] as bool;

      // 3. Supabase Storage (meals) に写真アップロード
      final userId = supabase.auth.currentUser!.id;
      final mealFileName =
          'meals/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage.from('meals').upload(
            mealFileName,
            _imageFile!,
          );

      final imageUrl =
          supabase.storage.from('meals').getPublicUrl(mealFileName);

      // 4. meals テーブルに記録
      await supabase.from('meals').insert({
        'user_id': userId,
        'image_url': imageUrl,
        'calories': calories,
        'description': dishName,
        'is_healthy': isHealthy,
      });

      // 5. ユーザ状態更新（カロリー & 劣化レベル & 劣化顔生成）
      await _updateUserDegradation(
        userId: userId,
        addCalories: calories,
      );

      // 6. 結果ダイアログ
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('判定結果'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dishName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$calories kcal',
                  style: const TextStyle(
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 8),
                if (!isHealthy)
                  const Text(
                    '⚠️ カロリー注意！',
                    style: TextStyle(color: Colors.red),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分析エラー: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  /// ユーザの current_calories を加算し、
  /// 2000kcal 以上なら劣化レベルを 0〜9 の範囲で上げる。
  /// レベルが 1 以上になったタイミングで、劣化顔を生成して degraded_photo_url に保存。
  Future<void> _updateUserDegradation({
    required String userId,
    required int addCalories,
  }) async {
    final userRow = await supabase
        .from('users')
        .select()
        .eq('user_id', userId)
        .single();

    final currentCalories = (userRow['current_calories'] ?? 0) as int;
    final currentLevel = (userRow['degrade_level'] ?? 0) as int;
    final normalPhotoUrl = userRow['photo_url'] as String?;

    final newCalories = currentCalories + addCalories;

    int newLevel = currentLevel;
    bool isDegraded = userRow['is_degraded'] ?? false;
    String? degradedPhotoUrl = userRow['degraded_photo_url'];

    if (newCalories >= 2000) {
      final over = newCalories - 2000;
      final extraLevel = (over / 250).floor() + 1; // 2000でLv1
      newLevel = extraLevel.clamp(1, 9);
      isDegraded = true;

      // まだ劣化顔がない / あるいは強制的に更新したい場合はここで生成
      if (degradedPhotoUrl == null || degradedPhotoUrl.isEmpty) {
        degradedPhotoUrl = await _generateDegradedAvatar(
          baseFaceUrl: normalPhotoUrl,
        );
      }
    } else {
      // まだ2000未満ならレベル0 & isDegraded=false
      newLevel = 0;
      isDegraded = false;
      degradedPhotoUrl = userRow['degraded_photo_url'];
    }

    await supabase
        .from('users')
        .update({
          'current_calories': newCalories,
          'degrade_level': newLevel,
          'is_degraded': isDegraded,
          'degraded_photo_url': degradedPhotoUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', userId);

    if (isDegraded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 暴食により劣化レベルが $newLevel になりました'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// OpenAI DALL·E 3 で「劣化した顔アイコン」を生成し、
  /// Supabase Storage (avatars) に保存して、その公開URLを返す。
  Future<String?> _generateDegradedAvatar({String? baseFaceUrl}) async {
    try {
      // 1. DALL·E 3 で画像生成（URL返却型）
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/images/generations'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer YOUR_OPENAI_API_KEY', // 自分のキーに変更
        },
        body: jsonEncode({
          'model': 'dall-e-3',
          'prompt':
              'A realistic avatar icon of a person with thinning hair and bad skin, slightly exaggerated but still suitable as a profile picture',
          'n': 1,
          'size': '512x512',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('劣化顔生成API失敗: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final generatedUrl = data['data'][0]['url'] as String;

      // 2. 生成されたURLから画像をダウンロード
      final imgRes = await http.get(Uri.parse(generatedUrl));
      if (imgRes.statusCode != 200) {
        throw Exception('生成画像の取得に失敗: ${imgRes.statusCode}');
      }

      // 3. Supabase Storage (avatars) にアップロード
      final userId = supabase.auth.currentUser!.id;
      final fileName =
          'avatars/$userId/degraded_${DateTime.now().millisecondsSinceEpoch}.png';

      await supabase.storage.from('avatars').uploadBinary(
            fileName,
            imgRes.bodyBytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
            ),
          );

      final publicUrl =
          supabase.storage.from('avatars').getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      debugPrint('劣化顔生成エラー: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('食事を撮影'),
      ),
      body: Center(
        child: _isAnalyzing
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('AI分析中...'),
                ],
              )
            : _imageFile == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.camera_alt,
                        size: 100,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _takePicture,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('写真を撮る'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.file(
                        _imageFile!,
                        height: 300,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _takePicture,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('撮り直す'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _analyzeImage,
                            icon: const Icon(Icons.analytics),
                            label: const Text('分析する'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}
