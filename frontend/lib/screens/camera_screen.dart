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

  /// ユーザーの業スコア（karma）を不健康な食事に応じて減少させる。
  /// カロリーに応じて業スコアを調整する。
  Future<void> _updateUserDegradation({
    required String userId,
    required int addCalories,
  }) async {
    try {
      // ========== 現在のユーザー状態を取得 ==========
      final userRow = await supabase
          .from('users')
          .select('karma')
          .eq('user_id', userId)
          .single();

      final currentKarma = (userRow['karma'] ?? 50) as int;

      // ========== 業スコア減少ロジック ==========
      // 高カロリーほど業が下がる（500kcalで-1、1000kcalで-2...）
      final karmaDecrease = (addCalories / 500).floor().clamp(0, 10);
      final newKarma = (currentKarma - karmaDecrease).clamp(0, 100);

      // ========== Supabaseのusersテーブルを更新 ==========
      await supabase.from('users').update({
        'karma': newKarma,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      // ========== 業が下がった場合の通知 ==========
      if (newKarma < currentKarma && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ 暴食により業スコアが $currentKarma → $newKarma に低下しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('⚠️ 業スコア更新エラー: $e');
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
