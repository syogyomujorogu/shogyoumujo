// =============================================================================
// icon_degrade_filter.dart - 業スコア連動アイコン劣化/美化フィルター
// =============================================================================
// このファイルの役割:
// 1. 業スコアに応じた10段階フィルターを適用
// 2. 劣化：グレースケール、ぼやけ、ノイズ
// 3. 美化：明るさ、彩度、透明感
// =============================================================================

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// 業スコアに応じた10段階フィルターを適用したアイコン表示ウィジェット
class DegradedIconDisplay extends StatelessWidget {
  final String imageUrl; // 表示するイラスト化済み画像URL
  final String? buddhaImageUrl; // 仏風イラスト画像URL（業100用）
  final int karma; // 現在の業スコア（0-100）
  final double size; // アイコンサイズ
  final BoxShape shape; // アイコン形（circle, rectangle など）

  const DegradedIconDisplay({
    super.key,
    required this.imageUrl,
    this.buddhaImageUrl,
    required this.karma,
    this.size = 80,
    this.shape = BoxShape.circle,
  });

  /// 業スコアから10段階を計算（0-9）
  int _getKarmaStage(int karma) {
    return (karma / 10).floor().clamp(0, 10);
  }

  /// 段階に応じたグレースケール値（0.0 = カラー, 1.0 = 完全グレースケール）
  double _getGrayscale(int stage) {
    // 0-4段階：1.0（完全グレースケール）
    // 5段階：0.0（カラー）
    // 6-9段階：0.0（カラー）
    if (stage <= 4) return 1.0;
    return 0.0;
  }

  /// 段階に応じたぼやけ値
  double _getBlur(int stage) {
    // 0段階：15.0（強いぼやけ）
    // 1段階：12.0
    // 2段階：9.0
    // 3段階：6.0
    // 4段階：3.0
    // 5段階：0.0（加工なし）
    // 6-10段階：0.0
    final blurs = [15.0, 12.0, 9.0, 6.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    return blurs[stage.clamp(0, 10)];
  }

  /// 段階に応じたコントラスト値（0.5 = 低い, 1.0 = 通常, 1.5 = 高い）
  double _getContrast(int stage) {
    final contrasts = [
      0.5, // 0段階：だいぶ低い
      0.6, // 1段階
      0.65, // 2段階
      0.7, // 3段階
      0.85, // 4段階
      1.0, // 5段階：通常
      1.0, // 6段階
      1.05, // 7段階：わずかに高い
      1.1, // 8段階
      1.2, // 9段階
      1.3, // 10段階：高い
    ];
    return contrasts[stage.clamp(0, 10)];
  }

  /// 段階に応じた明るさ値（0.5 = 暗い, 1.0 = 通常, 1.5 = 明るい）
  double _getBrightness(int stage) {
    final brightnesses = [
      0.7, // 0段階：暗い
      0.75, // 1段階
      0.8, // 2段階
      0.85, // 3段階
      0.9, // 4段階
      1.0, // 5段階：通常
      1.0, // 6段階
      1.05, // 7段階：わずかに明るい
      1.1, // 8段階
      1.15, // 9段階
      1.2, // 10段階：明るい
    ];
    return brightnesses[stage.clamp(0, 10)];
  }

  /// 段階に応じた彩度値（0.0 = グレースケール, 1.0 = 通常, 2.0 = 鮮やか）
  double _getSaturation(int stage) {
    final saturations = [
      0.0, // 0段階：グレースケール
      0.0, // 1段階
      0.0, // 2段階
      0.0, // 3段階
      0.0, // 4段階
      1.0, // 5段階：通常
      1.0, // 6段階
      1.05, // 7段階：わずかに鮮やか
      1.1, // 8段階
      1.15, // 9段階
      1.2, // 10段階：鮮やか
    ];
    return saturations[stage.clamp(0, 10)];
  }

  @override
  Widget build(BuildContext context) {
    final stage = _getKarmaStage(karma);

    // 業100の場合は仏イラストを使用
    final displayImageUrl =
        karma >= 100 && buddhaImageUrl != null ? buddhaImageUrl! : imageUrl;

    // フィルター値を計算
    final grayscale = _getGrayscale(stage);
    final blur = _getBlur(stage);
    final contrast = _getContrast(stage);
    final brightness = _getBrightness(stage);
    final saturation = _getSaturation(stage);

    // ベース画像ウィジェット
    Widget imageWidget = Image.network(
      displayImageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[300],
        child: const Icon(Icons.person, color: Colors.grey),
      ),
    );

    // フィルターを段階的に適用
    // 1. ぼやけ
    if (blur > 0) {
      imageWidget = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: imageWidget,
      );
    }

    // 2. 色補正（グレースケール、コントラスト、明るさ、彩度）
    imageWidget = ColorFiltered(
      colorFilter: ColorFilter.matrix(_getColorMatrix(
        grayscale: grayscale,
        contrast: contrast,
        brightness: brightness,
        saturation: saturation,
      )),
      child: imageWidget,
    );

    // 3. 形状設定（円形など）
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: shape,
        border: Border.all(
          color: Colors.grey.shade300,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: shape == BoxShape.circle
            ? BorderRadius.circular(size / 2)
            : BorderRadius.circular(8),
        child: imageWidget,
      ),
    );
  }

  /// カラーマトリックスを生成（グレースケール、コントラスト、明るさ、彩度）
  List<double> _getColorMatrix({
    required double grayscale,
    required double contrast,
    required double brightness,
    required double saturation,
  }) {
    // グレースケール変換マトリックス
    final grayMatrix = [
      0.299 + 0.701 * (1 - grayscale),
      0.587 - 0.587 * (1 - grayscale),
      0.114 - 0.114 * (1 - grayscale),
      0.0,
      0.0,
      0.299 - 0.299 * (1 - grayscale),
      0.587 + 0.413 * (1 - grayscale),
      0.114 - 0.114 * (1 - grayscale),
      0.0,
      0.0,
      0.299 - 0.299 * (1 - grayscale),
      0.587 - 0.587 * (1 - grayscale),
      0.114 + 0.886 * (1 - grayscale),
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
    ];

    // コントラスト・明るさ補正
    final offset = (1.0 - contrast) / 2.0 * 255.0 + (brightness - 1.0) * 255.0;

    return [
      grayMatrix[0] * contrast * saturation,
      grayMatrix[1] * contrast * saturation,
      grayMatrix[2] * contrast * saturation,
      grayMatrix[3],
      offset,
      grayMatrix[5] * contrast * saturation,
      grayMatrix[6] * contrast * saturation,
      grayMatrix[7] * contrast * saturation,
      grayMatrix[8],
      offset,
      grayMatrix[10] * contrast * saturation,
      grayMatrix[11] * contrast * saturation,
      grayMatrix[12] * contrast * saturation,
      grayMatrix[13],
      offset,
      grayMatrix[15],
      grayMatrix[16],
      grayMatrix[17],
      grayMatrix[18],
      grayMatrix[19] + offset,
    ];
  }
}
