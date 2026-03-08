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
import 'package:google_generative_ai/google_generative_ai.dart'; // Gemini SDK
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

final supabase = Supabase.instance.client;

class MealPostSheet extends StatefulWidget {
  final VoidCallback? onPosted; // 投稿完了時のコールバック
  final String? mealType; // 食事タイプ（朝食・昼食・夕食）
  const MealPostSheet({super.key, this.onPosted, this.mealType});

  @override
  State<MealPostSheet> createState() => _MealPostSheetState();
}

class _MealPostSheetState extends State<MealPostSheet> {
  File? _imageFile;
  final _descController = TextEditingController();
  bool _isPosting = false;
  bool _isAnalyzing = false;
  final ImagePicker _picker = ImagePicker();
  int? _estimatedCalories; // AI分析結果
  String? _dishName; // AI分析結果
  String _selectedMealType = '朝食'; // デフォルトは朝食
  double? _latitude;
  double? _longitude;
  String? _resolvedModelName; // 利用できたモデル名
  List<String>? _modelCandidates; // 候補モデル一覧
  String? _locationName;
  bool _isLoadingLocation = false;
  int? _healthScore; // 健康度スコア（0-100、100が最も健康）
  String? _healthRating; // 健康度評価（excellent/good/fair/poor/terrible）

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

  String _normalizeModelName(String name) {
    return name.startsWith('models/') ? name : 'models/$name';
  }

  int _modelScore(String name) {
    var score = 0;
    if (name.contains('vision') ||
        name.contains('image') ||
        name.contains('multimodal')) {
      score += 4;
    }
    if (name.contains('flash')) {
      score += 3;
    }
    if (name.contains('pro')) {
      score += 2;
    }
    if (name.contains('1.5')) {
      score += 2;
    }
    if (name.contains('1.0')) {
      score += 1;
    }
    return score;
  }

  Future<List<String>> _fetchModelCandidates(String apiKey) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('モデル一覧取得に失敗: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final models = (data['models'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();

    final candidates = <String>[];
    for (final model in models) {
      final methods =
          (model['supportedGenerationMethods'] as List<dynamic>? ?? <dynamic>[])
              .map((value) => value.toString())
              .toList();
      if (methods.contains('generateContent')) {
        final name = model['name']?.toString();
        if (name != null && name.isNotEmpty) {
          candidates.add(name);
        }
      }
    }

    candidates.sort((a, b) => _modelScore(b).compareTo(_modelScore(a)));
    print('🤖 取得したモデル数: ${candidates.length}');
    print('🤖 候補モデル(上位5): ${candidates.take(5).join(', ')}');
    return candidates;
  }

  String _extractJsonString(String text) {
    var cleaned = text;
    if (cleaned.contains('```json')) {
      cleaned = cleaned.split('```json')[1].split('```')[0].trim();
    } else if (cleaned.contains('```')) {
      cleaned = cleaned.split('```')[1].split('```')[0].trim();
    }

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      cleaned = cleaned.substring(start, end + 1);
    } else if (start != -1) {
      // "}"が見つからない場合（JSONが途中で切れている）→修復を試みる
      cleaned = _repairTruncatedJson(cleaned.substring(start));
    }
    return cleaned.trim();
  }

  /// 途中で切れたJSONを修復する
  String _repairTruncatedJson(String broken) {
    print('🔧 JSON修復開始: ${broken.length}文字');
    // まず必要なフィールドを抽出してJSONを再構築する
    String? dishName;
    int? calories;
    int? healthScore;
    String? healthRating;
    String? healthComment;

    // 各フィールドを正規表現で安全に抽出
    final dishMatch = RegExp(r'"dishName"\s*:\s*"([^"]*?)"').firstMatch(broken);
    if (dishMatch != null) dishName = dishMatch.group(1);

    final calMatch = RegExp(r'"calories"\s*:\s*(\d+)').firstMatch(broken);
    if (calMatch != null) calories = int.tryParse(calMatch.group(1)!);

    final scoreMatch = RegExp(r'"healthScore"\s*:\s*(\d+)').firstMatch(broken);
    if (scoreMatch != null) healthScore = int.tryParse(scoreMatch.group(1)!);

    final ratingMatch =
        RegExp(r'"healthRating"\s*:\s*"([^"]*?)"').firstMatch(broken);
    if (ratingMatch != null) healthRating = ratingMatch.group(1);

    final commentMatch =
        RegExp(r'"healthComment"\s*:\s*"([^"]*?)"').firstMatch(broken);
    if (commentMatch != null) {
      healthComment = commentMatch.group(1);
    } else {
      // コメントが途中で切れている場合、途中まで取得
      final partialComment =
          RegExp(r'"healthComment"\s*:\s*"([^"]*)').firstMatch(broken);
      if (partialComment != null) {
        healthComment = '${partialComment.group(1)!.trim()}...';
      }
    }

    // 最低限 dishName と calories があれば有効とする
    if (dishName != null && calories != null) {
      final repaired = jsonEncode({
        'dishName': dishName,
        'calories': calories,
        'healthScore': healthScore ?? 50,
        'healthRating': healthRating ?? 'fair',
        'healthComment': healthComment ?? '分析結果が途中で切れたため、詳細不明',
      });
      print('🔧 JSON修復完了: $repaired');
      return repaired;
    }

    // 修復不可能な場合、そのまま返す（後でエラーハンドリングされる）
    print('🔧 JSON修復失敗: 必要なフィールドが見つかりません');
    return broken;
  }

  // カメラで撮影してAI分析（圧縮付き）
  Future<void> _takePhoto() async {
    print('📸 _takePhoto() 開始');
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800, // 最大幅800px
      maxHeight: 800, // 最大高さ800px
      imageQuality: 80, // 画質80%（1-100）
    );
    print('📸 picked結果: ${picked != null ? picked.path : "null"}');
    if (picked != null) {
      final file = File(picked.path);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('画像サイズが大きすぎます（5MB以下推奨）')));
        return;
      }
      setState(() {
        _imageFile = file;
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
      print('📸 AI分析を開始します...');
      await _analyzeImage();
      print('📸 AI分析が完了しました');
    }
  }

  // ギャラリーから画像を選択してAI分析（圧縮付き）
  Future<void> _pickImage() async {
    print('🖼️ _pickImage() 開始');
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800, // 最大幅800px
      maxHeight: 800, // 最大高さ800px
      imageQuality: 80, // 画質80%（1-100）
    );
    print('🖼️ picked結果: ${picked != null ? picked.path : "null"}');
    if (picked != null) {
      final file = File(picked.path);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('画像サイズが大きすぎます（5MB以下推奨）')));
        return;
      }
      setState(() {
        _imageFile = file;
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
      print('🖼️ AI分析を開始します...');
      await _analyzeImage();
      print('🖼️ AI分析が完了しました');
    }
  }

  // AIで画像を分析してカロリー推定（Google Gemini SDK使用）
  Future<void> _analyzeImage() async {
    print('🔍 _analyzeImage() 開始');
    if (_imageFile == null) {
      print('❌ _imageFile が null です');
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final bytes = await _imageFile!.readAsBytes();
      print('📷 画像読み込み完了: ${bytes.length} bytes');
      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      print(
        '🔑 APIキー: ${apiKey.isNotEmpty ? "設定済み(${apiKey.length}文字)" : "未設定"}',
      );

      if (apiKey.isEmpty) {
        throw Exception('APIキーが設定されていません(.envを確認してください)');
      }

      final modelOverride = dotenv.env['GEMINI_MODEL'];
      if (_modelCandidates == null || _modelCandidates!.isEmpty) {
        _modelCandidates = await _fetchModelCandidates(apiKey);
        if (modelOverride != null && modelOverride.trim().isNotEmpty) {
          _modelCandidates!.insert(
            0,
            _normalizeModelName(modelOverride.trim()),
          );
        }
      }
      final candidates = _modelCandidates ?? <String>[];

      final prompt = '''
この食事の画像を分析して、以下の情報をJSON形式で返してください。
JSON以外の文字は一切含めないでください。
healthCommentは30文字以内の短い日本語にしてください。

{"dishName":"料理名","calories":500,"healthScore":50,"healthRating":"fair","healthComment":"短いコメント"}

healthRatingはexcellent/good/fair/poorの4段階です。
''';

      final content = [
        Content.multi([TextPart(prompt), DataPart('image/jpeg', bytes)]),
      ];

      GenerateContentResponse? response;
      Object? lastError;
      for (final modelName in candidates) {
        try {
          final model = GenerativeModel(
            model: modelName,
            apiKey: apiKey,
            generationConfig: GenerationConfig(
              temperature: 0.2,
              maxOutputTokens: 1024,
            ),
          );
          response = await model.generateContent(content);
          if (response.text != null && response.text!.trim().isNotEmpty) {
            _resolvedModelName = modelName;
            break;
          }
        } catch (e) {
          lastError = e;
          continue;
        }
      }

      if (response == null || response.text == null) {
        throw Exception('利用可能なAIモデルが見つかりませんでした: $lastError');
      }

      if (_resolvedModelName != null) {
        print('🤖 使用モデル: $_resolvedModelName');
      }
      print('🤖 AI分析結果(Raw): ${response.text}');

      Map<String, dynamic> result;
      try {
        final jsonString = _extractJsonString(response.text!);
        print('🤖 抽出したJSON: $jsonString');
        result = jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        print('🤖 JSON解析失敗、リトライ中...');
        final retryPrompt = '''
この食事の画像を分析してJSON1行だけ返してください。他の文字は不要です。
healthCommentは20文字以内にしてください。

{"dishName":"料理名","calories":500,"healthScore":50,"healthRating":"fair","healthComment":"短評"}
''';
        final retryContent = [
          Content.multi([TextPart(retryPrompt), DataPart('image/jpeg', bytes)]),
        ];
        final retryModelName = _resolvedModelName ?? candidates.first;
        final retryModel = GenerativeModel(
          model: retryModelName,
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            temperature: 0.0,
            maxOutputTokens: 1024,
          ),
        );
        final retryResponse = await retryModel.generateContent(retryContent);
        if (retryResponse.text == null || retryResponse.text!.trim().isEmpty) {
          throw Exception('AIからの応答が空でした');
        }
        print('🤖 リトライ結果(Raw): ${retryResponse.text}');
        final retryJson = _extractJsonString(retryResponse.text!);
        print('🤖 リトライ抽出JSON: $retryJson');
        result = jsonDecode(retryJson) as Map<String, dynamic>;
      }

      // AI分析結果を使用
      setState(() {
        _estimatedCalories = result['calories'] as int?;
        _dishName = result['dishName'] as String?;
        _healthScore = result['healthScore'] as int?;
        _healthRating = result['healthRating'] as String?;

        print('📊 健康度スコア: $_healthScore');
        print('📊 健康度評価: $_healthRating');

        if (_descController.text.isEmpty && _dishName != null) {
          _descController.text = _dishName!;
        }
      });
    } catch (e) {
      print('AI分析エラー詳細: $e');
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) {
            final manualDishController = TextEditingController();
            final manualCalorieController = TextEditingController();
            final manualHealthScoreController = TextEditingController();
            String? selectedHealthRating;
            return AlertDialog(
              title: const Text('AI分析失敗 - 手動入力'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('AIによる自動分析に失敗しました。手動で入力してください。'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: manualDishController,
                      decoration: const InputDecoration(labelText: '料理名'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: manualCalorieController,
                      decoration: const InputDecoration(
                        labelText: 'カロリー (kcal)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: manualHealthScoreController,
                      decoration: const InputDecoration(
                        labelText: '健康度スコア (0-100)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedHealthRating,
                      items: const [
                        DropdownMenuItem(
                          value: 'excellent',
                          child: Text('excellent (90-100)'),
                        ),
                        DropdownMenuItem(
                          value: 'good',
                          child: Text('good (70-89)'),
                        ),
                        DropdownMenuItem(
                          value: 'fair',
                          child: Text('fair (50-69)'),
                        ),
                        DropdownMenuItem(
                          value: 'poor',
                          child: Text('poor (30-49)'),
                        ),
                        DropdownMenuItem(
                          value: 'terrible',
                          child: Text('terrible (0-29)'),
                        ),
                      ],
                      onChanged: (v) => selectedHealthRating = v,
                      decoration: const InputDecoration(labelText: '健康度評価'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _dishName = manualDishController.text.isNotEmpty
                          ? manualDishController.text
                          : null;
                      _estimatedCalories = int.tryParse(
                        manualCalorieController.text,
                      );
                      _healthScore = int.tryParse(
                        manualHealthScoreController.text,
                      );
                      _healthRating = selectedHealthRating;
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
        if (_dishName == null ||
            _estimatedCalories == null ||
            _healthScore == null ||
            _healthRating == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('手動入力が完了していません')));
        }
      }
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  // 位置情報を取得
  Future<void> _getLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      // 位置情報サービスが有効かチェック
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('位置情報サービスが無効です')));
        }
        return;
      }

      // 権限チェック
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('位置情報の権限が拒否されました')));
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('位置情報の権限が永久に拒否されています。設定から許可してください')),
          );
        }
        return;
      }

      // 現在位置を取得
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationName =
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('📍 位置情報を取得しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('位置情報の取得に失敗: $e')));
      }
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  // ========== カロリー減少アイテムを取得 ==========
  Future<List<Map<String, dynamic>>> _getDecreaseItems() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final items = await supabase
          .from('user_items')
          .select('*, items(*)')
          .eq('user_id', userId)
          .gt('quantity', 0);

      final decreaseItems = (items as List)
          .where((item) => item['items']['effect_type'] == 'calorie_decrease')
          .toList();

      return decreaseItems.cast<Map<String, dynamic>>();
    } catch (e) {
      print('❌ カロリー減少アイテム取得エラー: $e');
      return [];
    }
  }

  // ========== 食事投稿前にアイテムを使用するか確認 ==========
  Future<Map<String, dynamic>?> _showItemSelectionDialog(
      List<Map<String, dynamic>> items) async {
    if (items.isEmpty) {
      return null; // アイテムなし
    }

    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎁 カロリー減少アイテムを使用しますか？'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  title: const Text('アイテムを使用しない'),
                  onTap: () => Navigator.pop(context, null),
                );
              }
              final item = items[index - 1];
              final itemData = item['items'] as Map<String, dynamic>;
              final quantity = item['quantity'] as int? ?? 1;
              final effectValue = itemData['effect_value'] as int? ?? 0;

              return ListTile(
                title: Text('${itemData['name']} (x$quantity)'),
                subtitle:
                    Text('カロリーを${effectValue}%減少 • ${itemData['description']}'),
                onTap: () => Navigator.pop(context, item),
              );
            },
          ),
        ),
      ),
    );
  }

  // 食事投稿をSupabaseに保存
  Future<void> _postMeal() async {
    // バリデーション: 画像
    if (_imageFile == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('写真を選択してください')));
      return;
    }
    // バリデーション: 料理名
    if (_dishName == null || _dishName!.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('料理名を入力してください（AI失敗時は手動入力）')));
      return;
    }
    // バリデーション: カロリー
    if (_estimatedCalories == null || _estimatedCalories! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カロリーを入力してください（AI失敗時は手動入力）')),
      );
      return;
    }
    // バリデーション: 健康度スコア
    if (_healthScore == null || _healthScore! < 0 || _healthScore! > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('健康度スコア(0-100)を入力してください（AI失敗時は手動入力）')),
      );
      return;
    }
    // バリデーション: 健康度評価
    if (_healthRating == null || _healthRating!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('健康度評価を選択してください（AI失敗時は手動入力）')),
      );
      return;
    }

    // ========== アイテム選択ダイアログを表示 ==========
    final decreaseItems = await _getDecreaseItems();
    Map<String, dynamic>? selectedItem;
    if (decreaseItems.isNotEmpty) {
      selectedItem = await _showItemSelectionDialog(decreaseItems);
    }

    int finalCalories = _estimatedCalories!;
    if (selectedItem != null) {
      final itemData = selectedItem['items'] as Map<String, dynamic>;
      final effectValue = itemData['effect_value'] as int? ?? 0;
      finalCalories = (_estimatedCalories! * (100 - effectValue) / 100).round();
    }

    setState(() => _isPosting = true);
    while (true) {
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
          'description': _descController.text.trim().isEmpty
              ? (_dishName ?? '食事を投稿しました')
              : _descController.text.trim(),
          'meal_type': _convertMealTypeToEnglish(
            _selectedMealType,
          ), // 英語に変換して保存
          'calories': finalCalories, // アイテム使用後のカロリー
          'health_score': _healthScore, // 健康度スコア（0-100）
          'health_rating': _healthRating, // 健康度評価
          'latitude': _latitude, // 位置情報（緯度）
          'longitude': _longitude, // 位置情報（経度）
          'location_name': _locationName, // 位置情報（テキスト）
          'created_at': now.toUtc().toIso8601String(),
        });

        // ========== アイテムを消費 ==========
        if (selectedItem != null) {
          final userItemId = selectedItem['id'];
          final quantity = selectedItem['quantity'] as int? ?? 1;
          if (quantity > 1) {
            await supabase
                .from('user_items')
                .update({'quantity': quantity - 1}).eq('id', userItemId);
          } else {
            await supabase.from('user_items').delete().eq('id', userItemId);
          }
        }

        // 実績自動達成判定ロジック
        await _checkAndUnlockAchievements(userId);

        // ユーザーの業（カルマ）値を更新
        int karmaChange = 0;
        if (_healthScore != null) {
          karmaChange = await _updateUserKarma(userId, _healthScore!);
        }

        if (widget.onPosted != null) widget.onPosted!();

        if (mounted) {
          // 先にダイアログを表示してからシートを閉じる
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => _buildResultDialog(karmaChange),
          );

          if (mounted) {
            Navigator.pop(context);
          }
        }
        break; // 成功したらループ終了
      } catch (e) {
        if (mounted) {
          final retry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('投稿エラー'),
              content: Text('食事投稿に失敗しました。\nエラー: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('リトライ'),
                ),
              ],
            ),
          );
          if (retry != true) {
            break;
          }
        } else {
          break;
        }
      } finally {
        setState(() => _isPosting = false);
      }
    }
  }

  // 実績自動達成判定ロジック
  Future<void> _checkAndUnlockAchievements(String userId) async {
    try {
      // 1. 全実績を取得
      final achievements = await supabase.from('achievements').select();
      if (achievements.isEmpty) return;

      // 2. 既に達成済みの実績IDを取得
      final userAchievements = await supabase
          .from('user_achievements')
          .select('achievement_id')
          .eq('user_id', userId);
      final achievedIds =
          userAchievements.map((e) => e['achievement_id']).toSet();

      // 3. 各実績の条件を判定
      for (final achievement in achievements) {
        final achievementId = achievement['id'];
        if (achievedIds.contains(achievementId)) continue; // 既に達成済み

        final conditionType = achievement['condition_type'];
        final conditionValue = achievement['condition_value'];
        bool unlocked = false;

        // 投稿数系
        if (conditionType == 'meal_count') {
          final mealCountRes =
              await supabase.from('meals').select('id').eq('user_id', userId);
          final mealCount = (mealCountRes as List).length;
          if (mealCount >= conditionValue) unlocked = true;
        }
        // 連続投稿日数系
        else if (conditionType == 'meal_streak') {
          // 直近の投稿日を取得し、連続日数を計算
          final meals = await supabase
              .from('meals')
              .select('created_at')
              .eq('user_id', userId)
              .order('created_at', ascending: false);
          final dates = meals
              .map((m) => DateTime.tryParse(m['created_at'] ?? '')?.toUtc())
              .whereType<DateTime>()
              .toList();
          if (dates.isNotEmpty) {
            dates.sort((a, b) => b.compareTo(a));
            int streak = 1;
            for (int i = 1; i < dates.length; i++) {
              final diff = dates[i - 1].difference(dates[i]).inDays;
              if (diff == 1) {
                streak++;
              } else if (diff > 1) {
                break;
              }
            }
            if (streak >= conditionValue) {
              unlocked = true;
              // ★連続投稿ボーナス達成時にガチャチケット1枚付与★
              final ticketRow = await supabase
                  .from('gacha_tickets')
                  .select('ticket_count')
                  .eq('user_id', userId)
                  .maybeSingle();
              final currentTickets = (ticketRow?['ticket_count'] ?? 0) as int;
              if (ticketRow != null) {
                await supabase.from('gacha_tickets').update({
                  'ticket_count': currentTickets + 1,
                }).eq('user_id', userId);
              } else {
                await supabase.from('gacha_tickets').insert({
                  'user_id': userId,
                  'ticket_count': 1,
                });
              }
            }
          }
        }
        // 他の条件タイプもここに追加可能

        if (unlocked) {
          await supabase.from('user_achievements').insert({
            'user_id': userId,
            'achievement_id': achievementId,
          });
        }
      }
    } catch (e) {
      print('実績判定エラー: $e');
    }
  }

  // ユーザーの業（カルマ）値を更新
  Future<int> _updateUserKarma(String userId, int healthScore) async {
    try {
      // 健康度スコアから業の変動を計算
      // 50がデフォルト、健康で上昇、不健康で下降。上限100。維持は難しく、100維持は大変！
      // 90-100: +10 (健康で業アップ)
      // 70-89:  +5  (良好で業アップ)
      // 50-69:   0  (変化なし)
      // 30-49:  -5  (不健康で業ダウン)
      // 0-29:  -10 (大幅不健康で業ダウン)
      int karmaChange = 0;
      if (healthScore >= 90) {
        karmaChange = 10; // 健康な食事で業が上がる
      } else if (healthScore >= 70) {
        karmaChange = 5;
      } else if (healthScore >= 50) {
        karmaChange = 0;
      } else if (healthScore >= 30) {
        karmaChange = -5; // 不健康な食事で業が下がる
      } else {
        karmaChange = -10;
      }

      // 現在の業値を取得
      final response = await supabase
          .from('users')
          .select('karma')
          .eq('custom_user_id', userId)
          .single();

      final currentKarma = response['karma'] as int? ?? 0;
      final newKarma = (currentKarma + karmaChange).clamp(0, 100);

      // 業値を更新
      await supabase
          .from('users')
          .update({'karma': newKarma}).eq('custom_user_id', userId);

      print('💫 業の更新: $currentKarma → $newKarma (変動: $karmaChange)');
      return karmaChange;
    } catch (e) {
      print('⚠️ 業の更新エラー: $e');
      return 0;
    }
  }

  // 健康度スコアに応じたメッセージを返す
  String _getHealthMessage(int score) {
    if (score >= 90) {
      return '✨ 非常に健康的！ アバターの業が減少します';
    } else if (score >= 70) {
      return '😊 健康的です！ アバターが少し回復します';
    } else if (score >= 50) {
      return '😐 普通です アバターに変化はありません';
    } else if (score >= 30) {
      return '😟 やや不健康... アバターが少し劣化します';
    } else {
      return '😱 非常に不健康！ アバターが大きく劣化します';
    }
  }

  // 投稿結果ダイアログを構築
  Widget _buildResultDialog(int karmaChange) {
    // 健康度がnullの場合でもカロリー情報を表示
    if (_healthScore == null) {
      final calories = _estimatedCalories ?? 0; // 分析失敗時は0
      return AlertDialog(
        title: const Text('投稿完了！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 今日の食事表示
            Text(
              '今日の食事：${_dishName ?? '料理名不明'}',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const Divider(height: 24),
            // カロリー表示
            Row(
              children: [
                const Icon(Icons.local_fire_department, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  '$calories kcal',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 食事の評価（700kcal基準）
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    calories <= 700 ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: calories <= 700 ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    calories <= 700 ? Icons.check_circle : Icons.warning,
                    color: calories <= 700 ? Colors.green : Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      calories <= 700 ? '健康的な食事です！' : 'カロリー過多です！煩悩です！',
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        color: calories <= 700
                            ? Colors.green.shade900
                            : Colors.red.shade900,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            _healthScore! >= 70 ? Icons.check_circle : Icons.warning,
            color: _healthScore! >= 70
                ? Colors.green
                : _healthScore! >= 50
                    ? Colors.orange
                    : Colors.red,
            size: 32,
          ),
          const SizedBox(width: 12),
          const Text('投稿完了！'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 料理名
          if (_dishName != null) ...[
            Text(
              _dishName!,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
          // カロリー
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_fire_department, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  '$_estimatedCalories kcal',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 健康度
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _healthScore! >= 70
                  ? Colors.green.withOpacity(0.1)
                  : _healthScore! >= 50
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _healthScore! >= 70
                    ? Colors.green
                    : _healthScore! >= 50
                        ? Colors.orange
                        : Colors.red,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '健康度',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_healthScore',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: _healthScore! >= 70
                        ? Colors.green
                        : _healthScore! >= 50
                            ? Colors.orange
                            : Colors.red,
                  ),
                ),
                Text(
                  '/100',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                Text(
                  _getHealthMessage(_healthScore!),
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 業の変化
          if (karmaChange != 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: karmaChange < 0
                    ? Colors.blue.withOpacity(0.1)
                    : Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    karmaChange < 0 ? Icons.trending_down : Icons.trending_up,
                    color: karmaChange < 0 ? Colors.blue : Colors.purple,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '業 ${karmaChange > 0 ? '+' : ''}$karmaChange',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: karmaChange < 0 ? Colors.blue : Colors.purple,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
            // 画像プレビュー（選択済みの場合のみ表示）
            if (_imageFile != null) ...[
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
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
              const SizedBox(height: 12),
            ],
            // カメラ撮影ボタン（メイン）
            if (_imageFile == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isAnalyzing ? null : _takePhoto,
                    icon: const Icon(Icons.camera_alt, size: 28),
                    label: const Text(
                      'カメラで撮影',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            if (_imageFile == null) const SizedBox(height: 12),
            // 写真選択ボタン（サブ）
            if (_imageFile == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isAnalyzing ? null : _pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('写真を選択', style: TextStyle(fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
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

            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: '説明（例: 今日の精進料理）'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // 位置情報追加ボタン
            if (_imageFile != null) ...[
              OutlinedButton.icon(
                onPressed: _isLoadingLocation ? null : _getLocation,
                icon: _isLoadingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _locationName == null
                            ? Icons.add_location
                            : Icons.check_circle,
                        color:
                            _locationName == null ? Colors.blue : Colors.green,
                      ),
                label: Text(
                  _locationName == null ? '📍 位置情報を追加（任意）' : '✓ 位置情報を取得済み',
                  style: TextStyle(
                    color: _locationName == null ? Colors.blue : Colors.green,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _locationName == null ? Colors.blue : Colors.green,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_locationName != null) ...[
                const SizedBox(height: 8),
                Text(
                  '📍 $_locationName',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
            ],

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
