// =============================================================================
// meal_post_sheet.dart - 食事投稿用ボトムシート
// =============================================================================
// このファイルの役割:
// 1. 食事画像と説明を入力して投稿
// 2. Supabaseに新しい食事投稿を保存
// 3. 投稿後にコールバックでリストを更新
// =============================================================================

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

final supabase = Supabase.instance.client;

class MealPostSheet extends StatefulWidget {
  final VoidCallback? onPosted; // 投稿完了時のコールバック
  final String? mealType; // 食事タイプ（朝食・昼食・夕食）
  const MealPostSheet({Key? key, this.onPosted, this.mealType})
      : super(key: key);

  @override
  State<MealPostSheet> createState() => _MealPostSheetState();
}

class _MealPostSheetState extends State<MealPostSheet> {
  File? _imageFile;
  final _descController = TextEditingController();
  bool _isPosting = false;
  bool _isAnalyzing = false;
  final ImagePicker _picker = ImagePicker();
  int? _estimatedCalories;
  String? _dishName;
  String _selectedMealType = '朝食'; // デフォルトは朝食

  // 日本語の食事タイプを英語に変換（DB保存用）
  String _convertMealTypeToEnglish(String jpType) {
    switch (jpType) {
      case '朝食':
        return 'breakfast';
      case '昼食':
        return 'lunch';
      case '夕食':
        return 'dinner';
      case '間食':
        return 'snack';
      default:
        return 'snack';
    }
  }

  // 画像を選択してAI分析（圧縮付き）
  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024, // 最大幅1024px
      maxHeight: 1024, // 最大高さ1024px
      imageQuality: 85, // 画質85%（1-100）
    );
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
        _estimatedCalories = null;
        _dishName = null;

        // 時間帯に応じて自動選択（ユーザーが後で変更可能）
        final hour = DateTime.now().hour;
        if (hour >= 6 && hour < 11) {
          _selectedMealType = '朝食';
        } else if (hour >= 11 && hour < 16) {
          _selectedMealType = '昼食';
        } else if (hour >= 16 && hour < 22) {
          _selectedMealType = '夕食';
        } else {
          _selectedMealType = '間食';
        }
      });
      await _analyzeImage();
    }
  }

  // AIで画像を分析してカロリー推定（Google Gemini使用）
  Future<void> _analyzeImage() async {
    if (_imageFile == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Google Gemini APIでカロリー推定
      const apiKey =
          'AIzaSyCxcXu9rO-_vHj-qN4DGw71UoOW4AXsx-Y'; // TODO: 環境変数から読み込む
      final response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      'この食事の料理名とカロリーを推定してください。以下のJSON形式のみで返してください（説明文は不要）:\n{"dishName": "料理名", "calories": カロリー数値}'
                },
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Image,
                  }
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.4,
            'maxOutputTokens': 150,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content =
            data['candidates'][0]['content']['parts'][0]['text'] as String;

        // JSONを抽出（マークダウンコードブロックを除去）
        String jsonString = content;
        if (content.contains('```json')) {
          jsonString = content.split('```json')[1].split('```')[0].trim();
        } else if (content.contains('```')) {
          jsonString = content.split('```')[1].split('```')[0].trim();
        }

        final result = jsonDecode(jsonString);

        setState(() {
          _estimatedCalories = result['calories'] as int;
          _dishName = result['dishName'] as String;
          if (_descController.text.isEmpty && _dishName != null) {
            _descController.text = _dishName!;
          }
        });
      } else {
        throw Exception('API呼び出し失敗: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI分析エラー: $e\n手動でカロリーを入力してください')),
        );
      }
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  // 食事投稿をSupabaseに保存
  Future<void> _postMeal() async {
    if (_imageFile == null || _descController.text.trim().isEmpty) return;
    setState(() => _isPosting = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      // 画像をStorageにアップロード
      final fileName =
          'meals/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('meals').upload(fileName, _imageFile!);
      final photoUrl = supabase.storage.from('meals').getPublicUrl(fileName);
      // 投稿データをDBに保存
      final now = DateTime.now();

      await supabase.from('meals').insert({
        'user_id': userId,
        'photo_url': photoUrl,
        'description': _descController.text.trim(),
        'meal_type': _convertMealTypeToEnglish(_selectedMealType), // 英語に変換して保存
        'calories': _estimatedCalories, // AI推定カロリーを保存
        'created_at': now.toUtc().toIso8601String(),
      });
      if (widget.onPosted != null) widget.onPosted!();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('投稿エラー: $e')),
        );
      }
    } finally {
      setState(() => _isPosting = false);
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text('新しい食事を投稿', style: Theme.of(context).textTheme.titleLarge),
            if (widget.mealType != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.mealType!,
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _isAnalyzing ? null : _pickImage,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _imageFile == null
                      ? Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo,
                                  size: 48, color: Colors.grey[600]),
                              const SizedBox(height: 8),
                              Text(
                                '写真を選択してAI分析',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _imageFile!,
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                  if (_isAnalyzing)
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'AI分析中...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 食事タイプ選択
            if (_imageFile != null) ...[
              const Text(
                '食事タイプ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _selectedMealType,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: '朝食', child: Text('🌅 朝食')),
                    DropdownMenuItem(value: '昼食', child: Text('☀️ 昼食')),
                    DropdownMenuItem(value: '夕食', child: Text('🌙 夕食')),
                    DropdownMenuItem(value: '間食', child: Text('🍪 間食')),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedMealType = value!);
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // AI分析結果表示
            if (_estimatedCalories != null && !_isAnalyzing) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.psychology, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text(
                          'AI推定結果',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '料理名: ${_dishName ?? "不明"}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'カロリー: $_estimatedCalories kcal',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: '説明（例: 今日の精進料理）'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isPosting ? null : _postMeal,
              icon: const Icon(Icons.send),
              label: _isPosting ? const Text('投稿中...') : const Text('投稿する'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
