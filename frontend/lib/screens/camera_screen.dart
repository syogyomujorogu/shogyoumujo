// =============================================================================
// camera_screen.dart - 食事撮影・AI分析画面
// =============================================================================
// このファイルの役割:
// 1. カメラで食事の写真を撮影
// 2. OpenAI APIを使って料理とカロリーを推定
// 3. 食事データをSupabaseに保存
// 4. カロリーに応じてユーザーの劣化レベルを更新
// 5. 劣化レベルが上がったらDALL-E 3で劣化顔を生成
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// カメラ画面のStatefulWidget
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

// カメラ画面の状態管理クラス
class _CameraScreenState extends State<CameraScreen> {
  final ImagePicker _picker = ImagePicker(); // 画像選択用のインスタンス
  File? _imageFile; // 撮影した画像を保存
  bool _isAnalyzing = false; // AI分析中かどうかのフラグ

  // カメラで写真を撮影する関数
  Future<void> _takePicture() async {
    try {
      // カメラを起動して写真を撮影
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera, // カメラを使用
        maxWidth: 800, // 最大幅800px
        maxHeight: 800, // 最大高さ800px
        imageQuality: 85, // 画質85%
      );

      // 撮影された場合、ファイルとして保存
      if (photo != null) {
        setState(() {
          _imageFile = File(photo.path);
        });
      }
    } catch (e) {
      // エラーが発生した場合、メッセージを表示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('カメラエラー: $e')),
      );
    }
  }

  // AI分析を実行する関数（ダミーデータ版）
  Future<void> _analyzeImage() async {
    // 画像がない場合は処理を中断
    if (_imageFile == null) return;

    // 分析中フラグをオン
    setState(() => _isAnalyzing = true);

    try {
      // ========== ダミーデータで動作確認 ==========
      // 一時的にAPI呼び出しをスキップしてダミーデータを使用
      await Future.delayed(const Duration(seconds: 1)); // 分析っぽく見せるための待機

      // ダミーデータ
      final calories = 850; // 700kcal超で警告が出る
      final dishName = 'ラーメン（ダミーデータ）';
      final isHealthy = calories <= 700; // 700kcal以下ならtrue

      // ========== STEP 3: Supabase Storageに写真をアップロード ==========
      final userId = supabase.auth.currentUser!.id;
      final mealFileName =
          'meals/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage.from('meals').upload(
            mealFileName,
            _imageFile!,
          );

      // アップロードした画像の公開URLを取得
      final imageUrl =
          supabase.storage.from('meals').getPublicUrl(mealFileName);

      // ========== STEP 4: mealsテーブルに記録を保存 ==========
      await supabase.from('meals').insert({
        'user_id': userId,
        'image_url': imageUrl,
        'calories': calories,
        'description': dishName,
        'is_healthy': isHealthy,
      });

      // ========== STEP 5: ユーザー状態を更新（劣化処理） ==========
      await _updateUserDegradation(
        userId: userId,
        addCalories: calories,
      );

      // ========== STEP 6: 投稿完了メッセージを表示 ==========
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('投稿しました！'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 料理名
                Row(
                  children: [
                    const Icon(Icons.restaurant, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dishName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
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
                // 食事の評価
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        isHealthy ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isHealthy ? Colors.green : Colors.red,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isHealthy ? Icons.check_circle : Icons.warning,
                        color: isHealthy ? Colors.green : Colors.red,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isHealthy ? '健康的な食事です！' : 'カロリー過多です！',
                          style: TextStyle(
                            color: isHealthy
                                ? Colors.green.shade900
                                : Colors.red.shade900,
                            fontSize: 16,
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
                onPressed: () {
                  Navigator.of(context).pop(); // ダイアログを閉じる
                  Navigator.of(context).pop(); // カメラ画面を閉じる
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // エラーが発生した場合
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分析エラー: $e')),
      );
    } finally {
      // 分析中フラグをオフ
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  /// ユーザーの current_calories を加算し、
  /// 2000kcal 以上なら劣化レベルを 0〜9 の範囲で上げる。
  /// レベルが 1 以上になったタイミングで、劣化顔を生成して degraded_photo_url に保存。
  Future<void> _updateUserDegradation({
    required String userId,
    required int addCalories,
  }) async {
    // ========== 現在のユーザー状態を取得 ==========
    final userRow =
        await supabase.from('users').select().eq('user_id', userId).single();

    final currentCalories = (userRow['current_calories'] ?? 0) as int;
    final currentLevel = (userRow['degrade_level'] ?? 0) as int;
    // photo_url は将来の劣化アバター機能で使用予定

    // ========== 新しいカロリー計算 ==========
    final newCalories = currentCalories + addCalories;

    int newLevel = currentLevel;
    bool isDegraded = userRow['is_degraded'] ?? false;
    String? degradedPhotoUrl = userRow['degraded_photo_url'];
    bool skippedAvatarGeneration = false;

    // ========== 劣化判定ロジック ==========
    if (newCalories >= 2000) {
      // 2000kcalを超えた分を計算
      final over = newCalories - 2000;
      // 250kcalごとに1レベル上昇（最大レベル9）
      final extraLevel = (over / 250).floor() + 1; // 2000でLv1
      newLevel = extraLevel.clamp(1, 9);
      isDegraded = true;

      // ========== 劣化顔の生成 ==========
      // Geminiキーのみ運用のため、劣化顔生成は無効化
      if (degradedPhotoUrl == null || degradedPhotoUrl.isEmpty) {
        skippedAvatarGeneration = true;
      }
    } else {
      // まだ2000未満ならレベル0 & isDegraded=false
      newLevel = 0;
      isDegraded = false;
      degradedPhotoUrl = userRow['degraded_photo_url'];
    }

    // ========== Supabaseのusersテーブルを更新 ==========
    await supabase.from('users').update({
      'current_calories': newCalories,
      'degrade_level': newLevel,
      'is_degraded': isDegraded,
      'degraded_photo_url': degradedPhotoUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', userId);

    // ========== 劣化した場合の通知 ==========
    if (isDegraded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 暴食により劣化レベルが $newLevel になりました'),
          backgroundColor: Colors.red,
        ),
      );
      if (skippedAvatarGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ℹ️ 劣化アイコン生成は現在スキップ設定です'),
          ),
        );
      }
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
            // ========== AI分析中の表示 ==========
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('AI分析中...'),
                ],
              )
            : _imageFile == null
                // ========== 写真がまだない場合 ==========
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
                // ========== 写真撮影後の表示 ==========
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 撮影した画像を表示
                      Image.file(
                        _imageFile!,
                        height: 300,
                      ),
                      const SizedBox(height: 24),
                      // 撮り直しボタンと分析ボタン
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
