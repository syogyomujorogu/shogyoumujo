// =============================================================================
// profile_screen.dart - プロフィール画面
// =============================================================================
// このファイルの役割:
// 1. ユーザーのプロフィール情報の表示
// 2. プロフィール写真のアップロード
// 3. 慈悲リクエストの確認と承認/拒否
// 4. フレンド追加機能（メールアドレスまたはユーザーIDで検索）
// 5. フレンドリストの表示
// 6. ログアウト機能
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import '../helpers/gemini_helper.dart';
import '../services/stability_ai_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'training_completion_dialog.dart';
import 'debug_menu_screen.dart';
import 'achievements_screen.dart';
import 'unified_notifications_screen.dart';
import 'friend_profile_screen.dart';
import 'reel_settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/icon_degrade_filter.dart';
import '../services/illustration_tier_manager.dart'; // 業テイア画像管理
import 'mercy_request_screen.dart'; // 慈悲リクエスト画面

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// プロフィール画面のStatefulWidget
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

// プロフィール画面の状態管理クラス
class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _userData; // 自分のユーザーデータ
  List<Map<String, dynamic>> _mercyRequests = []; // 慈悲リクエストのリスト
  List<Map<String, dynamic>> _friends = []; // フレンドリスト
  List<Map<String, dynamic>> _myMeals = []; // 自分の食事投稿
  bool _isLoading = true; // ローディング状態
  final _friendSearchController = TextEditingController(); // フレンド検索用のコントローラー
  final ImagePicker _picker = ImagePicker(); // 画像選択用のインスタンス
  late TabController _tabController; // タブコントローラー
  int _debugTapCount = 0; // デバッグメニュー用のタップカウンター
  bool _showDebugMenu = false; // デバッグメニュー表示フラグ
  Map<String, dynamic>? _equippedBadge; // 装備中のバッジ
  int _unreadNotificationsCount = 0; // 未読通知数
  int _currentKarmaTier = 3; // 現在の業テイア (1-5)
  Map<int, String?> _tierImageUrls = {}; // 各テイア画像 URL (1=上仏, 5=他化)
  bool _isRequestingIllustration = false; // 画像生成中フラグ
  String _illustrationRequestStatus = 'idle'; // pending/completed/failed/idle

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    // 画面が表示されたときにすべてのデータを読み込む
    _loadAllData();
  }

  @override
  void dispose() {
    // メモリリークを防ぐため、コントローラーを破棄
    _friendSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // すべてのデータを読み込む関数
  Future<void> _loadAllData() async {
    try {
      print('🔄 プロフィール画面のデータ読み込み開始...');

      await _loadUserData();
      print('✅ ユーザーデータ読み込み成功');

      await _loadMercyRequests();
      print('✅ 慈悲リクエスト読み込み成功');

      await _loadFriends();
      print('✅ フレンドリスト読み込み成功');

      await _loadMyMeals();
      print('✅ 食事投稿読み込み成功');

      await _loadEquippedBadge();
      print('✅ 装備バッジ読み込み成功');

      await _loadUnreadNotificationsCount();
      print('✅ 未読通知数読み込み成功');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('❌ プロフィール画面のデータ読み込みエラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ データの読み込みに失敗: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // ユーザーデータを読み込む関数
  Future<void> _loadUserData() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final response = await supabase
          .from('users')
          .select()
          .eq('user_id', userId)
          .maybeSingle(); // エラーしない取得

      if (response != null) {
        if (mounted) {
          setState(() {
            _userData = response;
            // 業スコアからテイアを計算
            final karma = (response['karma'] ?? 50) as int;
            _currentKarmaTier = IllustrationTierManager.getKarmaTier(karma);

            // 各テイアの画像URLをロード
            _tierImageUrls = {
              1: response['profile_illustration_tier1'] as String?,
              2: response['profile_illustration_tier2'] as String?,
              3: response['profile_illustration_tier3'] as String?,
              4: response['profile_illustration_tier4'] as String?,
              5: response['profile_illustration_tier5'] as String?,
            };

            // リクエストステータスをチェック（アプリ再起動時用）
            if (_tierImageUrls[_currentKarmaTier] == null) {
              _illustrationRequestStatus = 'pending';
            } else {
              _illustrationRequestStatus = 'completed';
            }
          });
        }
      } else {
        print('⚠️ ユーザーレコードが見つかりません');
        if (mounted) {
          setState(() {
            _userData = {
              'user_id': userId,
              'display_name': 'ユーザー',
              'email': supabase.auth.currentUser?.email ?? '',
              'photo_url': null,
              'friends': [],
              'mercy_points': 0,
            };
          });
        }
      }
    } catch (e) {
      print('❌ ユーザーデータ読み込みエラー: $e');
      rethrow;
    }
  }

  /// 業スコアに応じたティア画像URLを取得するヘルパー
  String? _getKarmaTierUrl(Map<String, dynamic>? userData, int karma) {
    if (userData == null) return null;
    String tierKey;
    if (karma <= 20) {
      tierKey = 'profile_illustration_tier1';
    } else if (karma <= 40) {
      tierKey = 'profile_illustration_tier2';
    } else if (karma <= 60) {
      tierKey = 'profile_illustration_tier3';
    } else if (karma <= 80) {
      tierKey = 'profile_illustration_tier4';
    } else {
      tierKey = 'profile_illustration_tier5';
    }
    final tierUrl = userData[tierKey] as String?;
    if (tierUrl != null && tierUrl.isNotEmpty) return tierUrl;
    return userData['photo_url'] as String?;
  }

  // 慈悲リクエストを読み込む関数
  Future<void> _loadMercyRequests() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 自分宛ての保留中のリクエストを取得
      // （ジョイン失敗時は空リストで継続）
      try {
        final response = await supabase
            .from('mercy_requests')
            .select(
                '*, requester:users!requester_id(display_name, email, photo_url, karma, profile_illustration_tier1, profile_illustration_tier2, profile_illustration_tier3, profile_illustration_tier4, profile_illustration_tier5)')
            .eq('receiver_id', userId)
            .eq('status', 'pending')
            .order('created_at', ascending: false);

        if (mounted) {
          setState(() {
            _mercyRequests = List<Map<String, dynamic>>.from(response);
          });
        }
      } catch (selectError) {
        // ジョイン失敗時は users テーブルなしで取得
        final fallbackResponse = await supabase
            .from('mercy_requests')
            .select()
            .eq('receiver_id', userId)
            .eq('status', 'pending')
            .order('created_at', ascending: false);

        if (mounted) {
          setState(() {
            _mercyRequests = List<Map<String, dynamic>>.from(fallbackResponse);
          });
        }
      }
    } catch (e) {
      print('⚠️ 慈悲リクエスト読み込みエラー（スキップ）: $e');
      if (mounted) {
        setState(() {
          _mercyRequests = [];
        });
      }
    }
  }

  // フレンドリストを読み込む関数
  Future<void> _loadFriends() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // friendsテーブルからフレンドIDを取得
      final friendsData = await supabase
          .from('friends')
          .select('friend_id')
          .eq('user_id', userId);

      final friendIds =
          friendsData.map<String>((row) => row['friend_id'] as String).toList();

      if (friendIds.isEmpty) {
        if (mounted) {
          setState(() => _friends = []);
        }
        return;
      }

      // フレンドのユーザー情報を取得
      final response =
          await supabase.from('users').select().inFilter('user_id', friendIds);

      if (mounted) {
        setState(() {
          _friends = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('⚠️ フレンドリスト読み込みエラー（スキップ）: $e');
      if (mounted) {
        setState(() => _friends = []);
      }
    }
  }

  // 自分の食事投稿を読み込む関数
  Future<void> _loadMyMeals() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final response = await supabase
          .from('meals')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _myMeals = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('⚠️ 食事投稿読み込みエラー（スキップ）: $e');
      if (mounted) {
        setState(() => _myMeals = []);
      }
    }
  }

  // 装備中のバッジを読み込む関数
  Future<void> _loadEquippedBadge() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final equippedData = await supabase
          .from('user_equipped_badge')
          .select('*, badges(*)')
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _equippedBadge = equippedData?['badges'];
        });
      }
    } catch (e) {
      print('⚠️ 装備バッジ読み込みエラー（スキップ）: $e');
      if (mounted) {
        setState(() => _equippedBadge = null);
      }
    }
  }

  /// 未読通知数を読み込む関数
  Future<void> _loadUnreadNotificationsCount() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final response = await supabase
          .from('notifications')
          .select()
          .eq('recipient_id', userId)
          .eq('is_read', false)
          .count(CountOption.exact);

      if (mounted) {
        setState(() {
          _unreadNotificationsCount = response.count;
        });
      }
    } catch (e) {
      print('⚠️ 未読通知数読み込みエラー（スキップ）: $e');
      if (mounted) {
        setState(() => _unreadNotificationsCount = 0);
      }
    }
  }

  /// 慈悲リクエストを承認する関数
  Future<void> _approveMercyRequest(
      String requestId, String requesterId) async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // ========== 自分の慈悲ポイントを確認 ==========
      final myData = await supabase
          .from('users')
          .select('mercy_points')
          .eq('user_id', userId)
          .single();
      final myMercy = (myData['mercy_points'] ?? 0) as int;

      if (myMercy <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('慈悲ポイントが不足しています（自分のポイントを1消費します）'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // ========== リクエスターに慈悲ポイントを付与 ==========
      final requesterData = await supabase
          .from('users')
          .select('mercy_points')
          .eq('user_id', requesterId)
          .single();

      final currentPoints = (requesterData['mercy_points'] ?? 0) as int;

      // リクエスターに+1
      await supabase.from('users').update({
        'mercy_points': currentPoints + 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', requesterId);

      // 自分は-1
      await supabase.from('users').update({
        'mercy_points': myMercy - 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      // ========== リクエストのステータスを更新 ==========
      await supabase.from('mercy_requests').update({
        'status': 'approved',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', requestId);

      // リクエストリストを再読み込み
      await _loadMercyRequests();
      // ユーザーデータも再読み込み（ポイントが変わるため）
      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🙏 慈悲を与えました（残り ${myMercy - 1} ポイント）'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  /// 慈悲リクエストを拒否する関数
  Future<void> _rejectMercyRequest(String requestId) async {
    try {
      // リクエストのステータスを「拒否」に更新
      await supabase.from('mercy_requests').update({
        'status': 'rejected',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', requestId);

      // リクエストリストを再読み込み
      await _loadMercyRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('リクエストを拒否しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  /// フレンドを追加する関数（メールアドレスまたはユーザーIDで検索）
  Future<void> _addFriend() async {
    final searchText = _friendSearchController.text.trim();
    if (searchText.isEmpty) return;

    try {
      final userId = supabase.auth.currentUser!.id;
      Map<String, dynamic>? friendResponse;

      // ========== メールアドレスまたはユーザーIDで検索 ==========
      if (searchText.contains('@')) {
        // メールアドレスの場合
        friendResponse = await supabase
            .from('users')
            .select()
            .eq('email', searchText)
            .maybeSingle();
      } else {
        // ユーザーIDの場合
        friendResponse = await supabase
            .from('users')
            .select()
            .eq('custom_user_id', searchText)
            .maybeSingle();
      }

      // ユーザーが見つからない場合
      if (friendResponse == null) {
        throw Exception('ユーザーが見つかりません');
      }

      final friendId = friendResponse['user_id'] as String;
      final friendName = friendResponse['display_name'] ?? 'ユーザー';

      // ========== バリデーション ==========
      // 自分自身は追加できない
      if (friendId == userId) {
        throw Exception('自分自身は追加できません');
      }

      // 既にフレンドか確認
      final isFriendCheck = await supabase
          .from('friends')
          .select()
          .eq('user_id', userId)
          .eq('friend_id', friendId)
          .maybeSingle();

      if (isFriendCheck != null) {
        throw Exception('すでにフレンドです');
      }

      // 既に申請済みか確認
      final existingRequest = await supabase
          .from('friend_requests')
          .select()
          .eq('requester_id', userId)
          .eq('target_id', friendId)
          .maybeSingle();

      if (existingRequest != null) {
        throw Exception('既にフレンド申請を送信済みです');
      }

      // ========== フレンド申請を送信 ==========
      await supabase.from('friend_requests').insert({
        'requester_id': userId,
        'target_id': friendId,
        'status': 'pending',
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 通知を送信
      final currentUserName = _userData?['display_name'] ?? 'ユーザー';
      await supabase.from('notifications').insert({
        'recipient_id': friendId,
        'sender_id': userId,
        'notification_type': 'friend_request',
        'content': {},
        'message': '$currentUserName さんからフレンド申請が届きました',
      });

      // 入力欄をクリア
      _friendSearchController.clear();

      // データを再読み込み
      await _loadUserData();
      await _loadFriends();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$friendName にフレンド申請を送信しました'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // ダイアログを閉じる
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  /// 劣化処理（グレースケール化例）
  Uint8List _degradeImage(Uint8List imageBytes) {
    final original = img.decodeImage(imageBytes);
    if (original == null) return imageBytes;
    final grayscale = img.grayscale(original);
    return Uint8List.fromList(img.encodeJpg(grayscale));
  }

  /// プロフィール写真をアップロードする関数
  Future<void> _uploadProfilePhoto() async {
    try {
      // 月内リクエスト数をチェック
      final userId = supabase.auth.currentUser!.id;
      final allowance =
          await IllustrationTierManager.checkMonthlyRequestAllowance(userId);

      // すでに月内リクエスト済み → 残り日数表示ダイアログ
      if (!allowance['allowed'] && allowance['requestCount']! > 0) {
        final nextAllowedDate =
            DateTime.parse(allowance['nextAllowedDate'] ?? '');
        final now = DateTime.now();
        final daysRemaining = nextAllowedDate.difference(now).inDays + 1;

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('📷 まだ変更できません'),
            content: Text(
              '前回の撮影からまだ日が浅いため、\n'
              'まだ変更することができません。\n\n'
              'あと$daysRemaining日でご利用いただけます。',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                ),
                child: const Text('了解'),
              ),
            ],
          ),
        );
        return; // 撮影を中止
      }

      // 許可されている場合、確認ダイアログを表示
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('📷 証明写真の撮影方法'),
          content: const Text(
            '証明写真を撮るような感じで撮影してください！\n\n'
            '📌 撮影のコツ：\n'
            '• 正面を向いて撮影\n'
            '• 顔全体が映るように\n'
            '• 照明が均一に当たるように\n'
            '• ピントが顔に合うように\n\n'
            '⚠️ 一か月に一回しか変更することができません！\n\n'
            'うまく反映されない場合があります。\n'
            '慎重に行ってください！',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: const Text('撮影開始'),
            ),
          ],
        ),
      );

      if (proceed != true) return; // キャンセル選択

      // 📷 カメラで撮影（ギャラリー選択は削除）
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null) return;

      // ========== ローディングダイアログを表示 ==========
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false, // クリック不可
        builder: (context) => WillPopScope(
          onWillPop: () async => false, // バックボタン無効
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                const Text('📸 アイコン変更中...'),
                const SizedBox(height: 8),
                const Text(
                  'AI がイラストを生成しています。\n少々お待ちください。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );

      // ========== Supabase Storage にアップロード ==========
      final fileName =
          'avatars/$userId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('avatars').upload(
            fileName,
            File(image.path),
          );
      // アップロードした画像の公開URLを取得
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      // ========== 月1回制限の記録を保存（重要！） ==========
      // illustration_requests テーブルに撮影記録を INSERT
      // これにより checkMonthlyRequestAllowance() が正しく月内カウントを行う
      try {
        await supabase.from('illustration_requests').insert({
          'user_id': userId,
          'original_photo_url': publicUrl,
          'tier': 1,
          'prompt': 'Monthly photo capture record',
          'status': 'completed',
          'result_image_url': publicUrl,
        });
        print('✅ 撮影記録を保存しました (月内カウント用)');
      } catch (e) {
        print('⚠️ 撮影記録の保存に失敗: $e');
        // 記録失敗してもユーザー体験は続ける
      }

      // ========== Stability AIでイラスト化 ==========
      try {
        print('🎨 [Profile Screen] Stability AI イラスト化処理開始');

        // ユーザーの現在の業スコアティアを取得
        final currentKarma = _userData?['karma'] ?? 50;
        final currentTier = IllustrationTierManager.getKarmaTier(currentKarma);
        print('📊 業スコア: $currentKarma → Tier: $currentTier');

        // Stability AI APIキーを取得
        final apiKey = dotenv.env['STABILITY_API_KEY'] ?? '';
        if (apiKey.isEmpty) {
          throw Exception('STABILITY_API_KEY is not set in .env');
        }
        print('🔑 Stability AI API キー確認: ✅');

        // Stability AI で画像生成
        print('🤖 Stability AI で画像生成中...');
        final stabilityService = StabilityAIService(apiKey: apiKey);
        final base64Image = await stabilityService.generateIllustration(
          tier: currentTier,
          originalImageUrl: publicUrl,
        );

        if (base64Image != null && base64Image.isNotEmpty) {
          print('✅ Base64 画像取得成功');

          // Base64 画像をバイナリに変換
          final imageBytes = base64Decode(base64Image);
          print('🔄 バイナリ変換完了 (サイズ: ${imageBytes.length} bytes)');

          // Supabase Storage にティア画像をアップロード
          final tierFileName =
              'avatars/$userId/tier${currentTier}_${DateTime.now().millisecondsSinceEpoch}.png';
          print('📤 Storage にアップロード中: $tierFileName');

          await supabase.storage.from('avatars').uploadBinary(
                tierFileName,
                imageBytes,
              );
          print('✅ Storage アップロード完了');

          // アップロードした画像の公開URL
          final tierImageUrl =
              supabase.storage.from('avatars').getPublicUrl(tierFileName);
          print('🔗 公開 URL: $tierImageUrl');

          // users テーブルのティア画像カラムを更新
          final tierColumn = 'profile_illustration_tier$currentTier';
          print('💾 DB 更新中: $tierColumn');

          await supabase.from('users').update({
            tierColumn: tierImageUrl,
          }).eq('user_id', userId);

          print('✅ DB 更新完了');
          print('🎉 Tier$currentTier イラスト生成・保存完了');
        } else {
          print('⚠️ Base64 画像が空です');
        }
      } catch (e) {
        // Stability AI 失敗時は通常画像のみで続ける
        print('⚠️ Stability AI エラー: $e');
        print('🔍 エラー詳細: ${e.toString()}');
      }

      // データを再読み込み
      await _loadUserData();

      // UI反映の遅延を待つ
      await Future.delayed(const Duration(milliseconds: 500));

      // ローディングダイアログを閉じる
      if (mounted) {
        Navigator.pop(context);
      }

      // 画面をリビルド
      if (mounted) {
        setState(() {});

        // 完了ダイアログを表示
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('✅ アイコン変更完了！'),
            content: const Text(
              'プロフィール写真とアイコンを\n'
              'アップロードしました。',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text('完了'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ローディングダイアログが表示されていれば閉じる
        try {
          Navigator.pop(context);
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ エラー: $e')),
        );
      }
    }
  }

  /// 🛠️ デバッグ用：プロフィール写真をアップロード（月1回制限なし、ギャラリー選択可能）
  Future<void> _uploadProfilePhotoDebug() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // ========== カメラ/ギャラリー選択ダイアログ ==========
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('🛠️ デバッグ: 画像を選択'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ImageSource.camera),
              child: const Text('📷 カメラで撮影'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ImageSource.gallery),
              child: const Text('🖼️ ギャラリーから選択'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        ),
      );
      if (source == null) return;

      // 📷 画像を取得
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null) return;

      // ========== ローディングダイアログを表示 ==========
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false, // クリック不可
        builder: (context) => WillPopScope(
          onWillPop: () async => false, // バックボタン無効
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                const Text('🛠️ アイコン変更中（デバッグ）...'),
                const SizedBox(height: 8),
                const Text(
                  'AI がイラストを生成しています。\n少々お待ちください。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );

      // ========== Supabase Storage にアップロード ==========
      final fileName =
          'avatars/$userId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('avatars').upload(
            fileName,
            File(image.path),
          );
      // アップロードした画像の公開URLを取得
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      // ========== 月1回制限の記録を保存（デバッグモードなので毎回可） ==========
      try {
        await supabase.from('illustration_requests').insert({
          'user_id': userId,
          'original_photo_url': publicUrl,
          'tier': 1,
          'prompt': 'Debug photo capture record',
          'status': 'completed',
          'result_image_url': publicUrl,
        });
        print('✅ デバッグ: 撮影記録を保存しました');
      } catch (e) {
        print('⚠️ デバッグ: 撮影記録の保存に失敗: $e');
      }

      // ========== Stability AIでイラスト化 ==========
      try {
        // ユーザーの現在の業スコアティアを取得
        final currentKarma = _userData?['karma'] ?? 50;
        final currentTier = IllustrationTierManager.getKarmaTier(currentKarma);

        // Stability AI APIキーを取得
        final apiKey = dotenv.env['STABILITY_API_KEY'] ?? '';
        if (apiKey.isEmpty) {
          throw Exception('STABILITY_API_KEY is not set in .env');
        }

        // Stability AI で画像生成
        final stabilityService = StabilityAIService(apiKey: apiKey);
        final base64Image = await stabilityService.generateIllustration(
          tier: currentTier,
          originalImageUrl: publicUrl,
        );

        if (base64Image != null && base64Image.isNotEmpty) {
          // Base64 画像をバイナリに変換
          final imageBytes = base64Decode(base64Image);

          // Supabase Storage にティア画像をアップロード
          final tierFileName =
              'avatars/$userId/tier${currentTier}_${DateTime.now().millisecondsSinceEpoch}.png';
          await supabase.storage.from('avatars').uploadBinary(
                tierFileName,
                imageBytes,
              );

          // アップロードした画像の公開URL
          final tierImageUrl =
              supabase.storage.from('avatars').getPublicUrl(tierFileName);

          // users テーブルのティア画像カラムを更新
          final tierColumn = 'profile_illustration_tier$currentTier';
          await supabase.from('users').update({
            tierColumn: tierImageUrl,
          }).eq('user_id', userId);

          print('✅ デバッグ: Tier$currentTier イラスト生成・保存完了');
        } else {
          print('⚠️ デバッグ: Stability AI 画像生成失敗');
        }
      } catch (e) {
        print('⚠️ デバッグ: Stability AI エラー: $e');
      }

      // データを再読み込み
      await _loadUserData();

      // UI反映の遅延を待つ
      await Future.delayed(const Duration(milliseconds: 500));

      // ローディングダイアログを閉じる
      if (mounted) {
        Navigator.pop(context);
      }

      // 画面をリビルド
      if (mounted) {
        setState(() {});

        // 完了ダイアログを表示
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('✅ アイコン変更完了！'),
            content: const Text(
              '🛠️ デバッグモード\n\n'
              'プロフィール写真とアイコンを\n'
              'アップロードしました。',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: const Text('完了'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ローディングダイアログが表示されていれば閉じる
        try {
          Navigator.pop(context);
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🛠️ ❌ デバッグエラー: $e')),
        );
      }
    }
  }

  /// ログアウト処理
  Future<void> _signOut() async {
    await supabase.auth.signOut();
  }

  /// ユーザーアカウントを削除
  Future<void> _deleteUserAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウント削除'),
        content: const Text(
          '本当にアカウントを削除しますか？\n'
          'この操作は取り消せません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔄 アカウントを削除中...'),
              duration: Duration(seconds: 2),
            ),
          );
        }

        final userId = supabase.auth.currentUser!.id;

        // usersテーブルから削除
        await supabase.from('users').delete().eq('user_id', userId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ アカウントを削除しました'),
              backgroundColor: Colors.green,
            ),
          );
          // ログイン画面に戻す
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
      } catch (e) {
        print('❌ アカウント削除エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ 削除エラー: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// ユーザー情報編集ダイアログを表示
  Future<void> _showEditProfileDialog() async {
    final displayNameController = TextEditingController(
      text: _userData?['display_name'] ?? '',
    );
    final userIdController = TextEditingController(
      text: _userData?['custom_user_id'] ?? '',
    );
    final emailController = TextEditingController(
      text: _userData?['email'] ?? '',
    );

    String? errorMessage;
    bool isLoading = false;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('プロフィール編集'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // エラーメッセージ表示
                  if (errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (errorMessage != null) const SizedBox(height: 16),
                  // アカウント名
                  TextField(
                    controller: displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'アカウント名',
                      hintText: 'あなたの名前',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 16),
                  // ユーザーID
                  TextField(
                    controller: userIdController,
                    decoration: const InputDecoration(
                      labelText: 'ユーザーID',
                      hintText: 'username123',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.account_circle),
                      helperText: '他のユーザーが検索するときに使われます',
                    ),
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 16),
                  // メールアドレス
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'メールアドレス',
                      hintText: 'user@example.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    enabled: !isLoading,
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.image),
                label: const Text('プロフィールアイコンを変更'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        Navigator.pop(context);

                        // デバッグモードで ギャラリー選択を許可
                        final prefs = await SharedPreferences.getInstance();
                        final isDebugMode =
                            prefs.getBool('debug_upload_photo_mode') ?? false;

                        if (isDebugMode) {
                          // デバッグモード：ギャラリー選択可能
                          await _uploadProfilePhotoDebug();
                          // フラグをリセット
                          await prefs.setBool('debug_upload_photo_mode', false);
                        } else {
                          // 通常モード：カメラのみ、月1回制限チェック
                          await _uploadProfilePhoto();
                        }
                      },
              ),
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        setState(() {
                          isLoading = true;
                          errorMessage = null;
                        });

                        final result = await _updateUserProfileWithValidation(
                          displayName: displayNameController.text.trim(),
                          userId: userIdController.text.trim(),
                          email: emailController.text.trim(),
                        );

                        if (result['success']) {
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        } else {
                          setState(() {
                            errorMessage = result['error'];
                            isLoading = false;
                          });
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ユーザー情報を更新（バリデーション結果を返す）
  Future<Map<String, dynamic>> _updateUserProfileWithValidation({
    required String displayName,
    required String userId,
    required String email,
  }) async {
    try {
      // バリデーション
      if (displayName.isEmpty) {
        return {
          'success': false,
          'error': 'アカウント名を入力してください',
        };
      }
      if (userId.isEmpty) {
        return {
          'success': false,
          'error': 'ユーザーIDを入力してください',
        };
      }
      if (email.isEmpty) {
        return {
          'success': false,
          'error': 'メールアドレスを入力してください',
        };
      }

      // ユーザーIDの形式チェック（英数字のみ）
      final userIdRegex = RegExp(r'^[a-zA-Z0-9]+$');
      if (!userIdRegex.hasMatch(userId)) {
        return {
          'success': false,
          'error': 'ユーザーIDは英数字のみで入力してください',
        };
      }

      final currentUserId = supabase.auth.currentUser!.id;

      // ========== ユーザーID重複チェック ==========
      if (userId != _userData?['custom_user_id']) {
        final existingUser = await supabase
            .from('users')
            .select('user_id')
            .eq('custom_user_id', userId)
            .maybeSingle();

        if (existingUser != null && existingUser['user_id'] != currentUserId) {
          return {
            'success': false,
            'error': '❌ このユーザーIDは既に使用されています',
          };
        }
      }

      // ========== メールアドレス重複チェック ==========
      if (email != _userData?['email']) {
        final existingEmail = await supabase
            .from('users')
            .select('user_id')
            .eq('email', email)
            .maybeSingle();

        if (existingEmail != null &&
            existingEmail['user_id'] != currentUserId) {
          return {
            'success': false,
            'error': '❌ このメールアドレスは既に使用されています',
          };
        }
      }

      // ========== 実際の更新処理 ==========
      await _updateUserProfile(
        displayName: displayName,
        userId: userId,
        email: email,
      );

      return {
        'success': true,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'エラー: ${e.toString()}',
      };
    }
  }

  /// ユーザー情報を更新
  Future<void> _updateUserProfile({
    required String displayName,
    required String userId,
    required String email,
  }) async {
    try {
      // バリデーション
      if (displayName.isEmpty) {
        throw Exception('アカウント名を入力してください');
      }
      if (userId.isEmpty) {
        throw Exception('ユーザーIDを入力してください');
      }
      if (email.isEmpty) {
        throw Exception('メールアドレスを入力してください');
      }

      final currentUserId = supabase.auth.currentUser!.id;
      print('🔄 プロフィール更新開始');
      print('📝 更新内容:');
      print('  - displayName: $displayName');
      print('  - userId: $userId');
      print('  - email: $email');
      print('  - currentUserId: $currentUserId');

      // ユーザーIDが変更された場合、重複チェック
      if (userId != _userData?['custom_user_id']) {
        print('🔍 ユーザーID変更検出。重複チェック中...');
        final existingUser = await supabase
            .from('users')
            .select('user_id')
            .eq('custom_user_id', userId)
            .maybeSingle();

        if (existingUser != null && existingUser['user_id'] != currentUserId) {
          throw Exception('このユーザーIDは既に使用されています');
        }
        print('✅ ユーザーID重複なし（または自分のID）');
      }

      // ユーザーテーブルを更新（update → insert の安全なフロー）
      print('💾 Supabaseユーザーテーブルを更新（update→insert）中...');

      // userId（custom_user_id）は英数字のみ許可
      final userIdRegex = RegExp(r'^[a-zA-Z0-9]+$');
      if (!userIdRegex.hasMatch(userId)) {
        throw Exception('ユーザーIDは英数字のみで入力してください');
      }

      final data = {
        'display_name': displayName,
        'custom_user_id': userId,
        'email': email,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // まず update を試みる
      final updateResult = await supabase
          .from('users')
          .update(data)
          .eq('user_id', currentUserId)
          .select();
      print('ℹ️ updateResult: $updateResult');

      if (updateResult.isEmpty) {
        // レコードがなければ insert
        final insertData = {
          'user_id': currentUserId,
          ...data,
        };
        try {
          final insertResult =
              await supabase.from('users').insert(insertData).select();
          print('✅ insertResult: $insertResult');
        } catch (e) {
          print('❌ insert でエラー: $e');
          rethrow;
        }
      } else {
        print('✅ update が成功しました');
      }

      // メールアドレスがSupabaseの認証情報と異なる場合、更新
      final currentEmail = supabase.auth.currentUser?.email;
      print('📧 認証メール: $currentEmail → 新メール: $email');

      if (currentEmail != email) {
        try {
          print('🔄 認証メール更新中...');
          await supabase.auth.updateUser(
            UserAttributes(email: email),
          );
          print('✅ 認証メール更新完了');
        } catch (e) {
          print('⚠️ メールアドレスの更新に失敗（ユーザーテーブルのみ更新）: $e');
        }
      }

      // Supabaseから最新データを取得（デフォルト値で上書きされないようにする）
      print('🔄 Supabaseから最新データを取得中...');
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('ユーザーセッションが無効です');
      }

      final response = await supabase
          .from('users')
          .select()
          .eq('user_id', currentUserId)
          .maybeSingle();

      print('📥 Supabase取得結果: $response');

      if (response != null) {
        if (mounted) {
          setState(() {
            _userData = response;
          });
        }
        print('✅ ローカル状態を更新完了');
      } else {
        // データが見つからない場合は、送信したデータをローカルに反映
        print('⚠️ Supabaseからデータが見つかりません。送信したデータをローカルに反映します');
        if (mounted) {
          setState(() {
            _userData?['display_name'] = displayName;
            _userData?['custom_user_id'] = userId;
            _userData?['email'] = email;
          });
        }
      }

      // 更新後のデータを確認
      print('📊 更新後のデータ:');
      print('  - display_name: ${_userData?['display_name']}');
      print('  - custom_user_id: ${_userData?['custom_user_id']}');
      print('  - email: ${_userData?['email']}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ プロフィールを更新しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ プロフィール更新エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Instagram風の統計情報列を作成（投稿数、フレンド数など）
  Widget _buildStatColumn(String value, String label, {VoidCallback? onTap}) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: column,
        ),
      );
    }
    return column;
  }

  // 設定メニューを表示（ログアウト・アカウント削除など）
  void _showSettingsMenu(BuildContext context) {
    final isOnTraining = _userData?['training_started'] == true;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // リール表示設定（法輪の設定）
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.purple),
              title: const Text('リール表示設定'),
              onTap: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                final currentValue =
                    prefs.getBool('reel_keep_aspect_ratio') ?? false;
                showDialog(
                  context: context,
                  builder: (context) => ReelSettingsDialog(
                    initialKeepAspectRatio: currentValue,
                    onChanged: (v) async {
                      await prefs.setBool('reel_keep_aspect_ratio', v);
                      setState(() {}); // 画面をリビルドして他画面反映
                    },
                  ),
                );
              },
            ),
            if (isOnTraining) ...[
              ListTile(
                leading: const Icon(Icons.calendar_today, color: Colors.orange),
                title: const Text('週次まとめの曜日設定'),
                onTap: () {
                  Navigator.pop(context);
                  _showWeeklySummaryDaySettings();
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('プロフィールを編集'),
              onTap: () {
                Navigator.pop(context);
                _showEditProfileDialog();
              },
            ),
            if (_showDebugMenu)
              ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.deepOrange),
                title: const Text('🛠 開発者デバッグメニュー'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DebugMenuScreen(),
                    ),
                  );
                },
              ),
            if (isOnTraining)
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title:
                    const Text('修業を終える', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _endTraining();
                },
              ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.orange),
              title: const Text('ログアウト'),
              onTap: () {
                Navigator.pop(context);
                _signOut();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('アカウント削除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteUserAccount();
              },
            ),
          ],
        ),
      ),
    );
  }

  // 週次まとめの曜日設定ダイアログ
  void _showWeeklySummaryDaySettings() {
    final currentDay = _userData?['weekly_summary_day'] ?? 0;
    int selectedDay = currentDay;

    final dayNames = ['日曜日', '月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('週次まとめの表示曜日'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '毎週、修業の振り返りを表示する曜日を選択してください。',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              DropdownButton<int>(
                isExpanded: true,
                value: selectedDay,
                items: List.generate(
                  7,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text(dayNames[index]),
                  ),
                ),
                onChanged: (value) {
                  setDialogState(() => selectedDay = value!);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateWeeklySummaryDay(selectedDay);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  // 週次まとめの曜日を更新
  Future<void> _updateWeeklySummaryDay(int day) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('users').update({
        'weekly_summary_day': day,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      await _loadUserData();

      final dayNames = ['日曜日', '月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('週次まとめを${dayNames[day]}に表示します'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  // 修業開始ダイアログを表示
  void _showStartTrainingDialog() {
    int selectedSteps = 5000;
    int selectedMonths = 1;
    double? startWeight;
    String? beforePhotoPath;
    String? weightError;
    final weightController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            '🔥 修業を始める',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ダイエットの修業を開始します。\n目標を設定してください。',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 20),
                const Text(
                  '現在の体重（kg）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,3}(\.\d{0,1})?')),
                  ],
                  decoration: InputDecoration(
                    hintText: '例: 70.5',
                    border: const OutlineInputBorder(),
                    suffixText: 'kg',
                    errorText: weightError,
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      startWeight = double.tryParse(value);
                      if (weightError != null) {
                        weightError = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'ビフォー写真（任意）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final XFile? image = await _picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1024,
                      maxHeight: 1024,
                      imageQuality: 85,
                    );
                    if (image != null) {
                      setDialogState(() {
                        beforePhotoPath = image.path;
                      });
                    }
                  },
                  icon: Icon(
                    beforePhotoPath != null
                        ? Icons.check_circle
                        : Icons.add_photo_alternate,
                    color: beforePhotoPath != null ? Colors.green : null,
                  ),
                  label: Text(beforePhotoPath != null ? '写真を選択済み' : '写真を選択'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color:
                          beforePhotoPath != null ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '目標歩数（1日あたり）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButton<int>(
                  isExpanded: true,
                  value: selectedSteps,
                  items: [3000, 5000, 8000, 10000, 15000]
                      .map((steps) => DropdownMenuItem(
                            value: steps,
                            child: Text('$steps 歩'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedSteps = value!);
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  '修業期間',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButton<int>(
                  isExpanded: true,
                  value: selectedMonths,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1ヶ月')),
                    DropdownMenuItem(value: 3, child: Text('3ヶ月')),
                    DropdownMenuItem(value: 6, child: Text('6ヶ月')),
                    DropdownMenuItem(value: 12, child: Text('12ヶ月')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedMonths = value!);
                  },
                ),
                const SizedBox(height: 20),
                // アイコン設定ボタン
                OutlinedButton.icon(
                  icon: const Icon(Icons.image),
                  label: const Text('プロフィールアイコンを設定'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blue),
                    foregroundColor: Colors.blue,
                  ),
                  onPressed: () async {
                    await _uploadProfilePhoto();
                  },
                ),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  '一緒に修行する仲間を追加',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddFriendDialog();
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('フレンドを追加'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange),
                    foregroundColor: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (startWeight == null || startWeight! <= 0) {
                  setDialogState(() {
                    weightError = '体重を入力してください';
                  });
                  return;
                }
                Navigator.pop(context);
                await _startTraining(selectedSteps, selectedMonths,
                    startWeight!, beforePhotoPath);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('修業を始める'),
            ),
          ],
        ),
      ),
    );
  }

  // 修業を開始する
  Future<void> _startTraining(int dailySteps, int months, double startWeight,
      String? beforePhotoPath) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final startDate = DateTime.now().toUtc();
      final endDate = startDate.add(Duration(days: months * 30));

      String? beforePhotoUrl;
      // ビフォー写真をアップロード
      if (beforePhotoPath != null) {
        final fileName =
            'before_photos/$userId/before_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supabase.storage.from('avatars').upload(
              fileName,
              File(beforePhotoPath),
            );
        beforePhotoUrl =
            supabase.storage.from('avatars').getPublicUrl(fileName);
      }

      // 即座にUIを更新
      setState(() {
        if (_userData != null) {
          _userData!['training_started'] = true;
          _userData!['training_start_date'] = startDate.toIso8601String();
          _userData!['training_end_date'] = endDate.toIso8601String();
          _userData!['training_daily_steps_goal'] = dailySteps;
          _userData!['training_months'] = months;
          _userData!['training_start_weight'] = startWeight;
          _userData!['weekly_summary_day'] = 0;
        }
      });

      // バックグラウンドでSupabaseに保存
      final updateData = {
        'training_started': true,
        'training_start_date': startDate.toIso8601String(),
        'training_end_date': endDate.toIso8601String(),
        'training_daily_steps_goal': dailySteps,
        'training_months': months,
        'training_start_weight': startWeight,
        'weekly_summary_day': 0, // デフォルトは日曜日
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (beforePhotoUrl != null) {
        updateData['training_before_photo'] = beforePhotoUrl;
      }
      await supabase.from('users').update(updateData).eq('user_id', userId);

      // 初期体重を記録
      await supabase.from('weight_logs').insert({
        'user_id': userId,
        'weight': startWeight,
        'created_at': startDate.toIso8601String(),
        'note': '修業開始時の体重',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '🔥 修業を開始しました！（$months ヶ月、1日 $dailySteps 歩、開始体重: ${startWeight}kg）'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // エラー時は元に戻す
      await _loadUserData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  // 修業を終える（厳重な確認）
  Future<void> _endTraining() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          '⚠️ 修業を終える',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '本当に修業を終えますか？\n\n'
          'これは非常に重大な決断です。\n'
          '修業を途中で放棄することは、\n'
          'これまでの努力を無駄にすることになります。\n\n'
          '本当に諦めますか？',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('いいえ、続けます'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('はい、終えます'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 2段階目の確認
      if (!mounted) return;
      final finalConfirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text(
            '🛑 最終確認',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            '最後の確認です。\n\n'
            '修業を終えると、すべての進捗がリセットされます。\n'
            '本当によろしいですか？',
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context, false),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('修業を続ける'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                '終える',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (finalConfirmed == true) {
        // 修業完了の祝福ダイアログを表示
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => TrainingCompletionDialog(userData: _userData!),
        );

        try {
          // 即座にUIを更新
          setState(() {
            if (_userData != null) {
              _userData!['training_started'] = false;
              _userData!['training_start_date'] = null;
              _userData!['training_end_date'] = null;
              _userData!['training_daily_steps_goal'] = null;
              _userData!['training_months'] = null;
            }
          });

          // バックグラウンドでSupabaseに保存
          final userId = supabase.auth.currentUser!.id;
          await supabase.from('users').update({
            'training_started': false,
            'training_start_date': null,
            'training_end_date': null,
            'training_daily_steps_goal': null,
            'training_months': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('user_id', userId);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('修業を終了しました。'),
                backgroundColor: Colors.grey,
              ),
            );
          }
        } catch (e) {
          // エラー時は元に戻す
          await _loadUserData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('エラー: $e')),
            );
          }
        }
      }
    }
  }

  // フレンド追加ダイアログを表示
  void _showAddFriendDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フレンドを追加'),
        content: TextField(
          controller: _friendSearchController,
          decoration: const InputDecoration(
            labelText: 'メールアドレスまたはユーザーID',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: _addFriend,
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  // フレンド一覧を表示
  void _showFriendsList() async {
    final userId = supabase.auth.currentUser!.id;

    // フレンドリストを新たに読み込む
    List<Map<String, dynamic>> currentFriends = [];
    List<Map<String, dynamic>> pendingRequests = [];

    try {
      // friendsテーブから直接確認
      final allFriends =
          await supabase.from('friends').select('*').eq('user_id', userId);

      print('📊 friends テーブルのすべてのレコード: $allFriends');
      print('📊 ユーザーID: $userId');
      print('📊 friends テーブルのレコード数: ${allFriends.length}');

      // friendsテーブルからフレンドIDを取得
      final friendsData = await supabase
          .from('friends')
          .select('friend_id')
          .eq('user_id', userId);

      final friendIds =
          friendsData.map<String>((row) => row['friend_id'] as String).toList();

      print('📊 取得したフレンドID一覧: $friendIds');

      if (friendIds.isNotEmpty) {
        // フレンドのユーザー情報を取得
        final response = await supabase
            .from('users')
            .select()
            .inFilter('user_id', friendIds);
        currentFriends = List<Map<String, dynamic>>.from(response);
        print('✅ フレンド情報取得成功: ${currentFriends.length}件');
      } else {
        print('⚠️ フレンドIDが取得できませんでした');
      }
    } catch (e) {
      print('❌ フレンドリスト読み込みエラー: $e');
    }

    // 未承認のフレンド申請を取得
    try {
      final userId = supabase.auth.currentUser!.id;
      final response = await supabase
          .from('friend_requests')
          .select('*')
          .eq('target_id', userId)
          .eq('status', 'pending')
          .order('requested_at', ascending: false);

      pendingRequests = List<Map<String, dynamic>>.from(response);

      // requester_idのユーザー情報を取得
      for (var i = 0; i < pendingRequests.length; i++) {
        final requester = await supabase
            .from('users')
            .select('display_name, photo_url')
            .eq('user_id', pendingRequests[i]['requester_id'])
            .maybeSingle();

        if (requester != null) {
          pendingRequests[i]['requester'] = requester;
        }
      }
    } catch (e) {
      print('❌ フレンド申請読み込みエラー: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          title: const Text('フレンド管理'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                // タブバー
                TabBar(
                  labelColor: Colors.deepPurple,
                  unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(text: 'フレンド (${currentFriends.length})'),
                    Tab(text: '申請待ち (${pendingRequests.length})'),
                  ],
                ),
                // タブコンテンツ
                Expanded(
                  child: TabBarView(
                    children: [
                      // フレンド一覧タブ
                      currentFriends.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('まだフレンドがいません'),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: currentFriends.length,
                              itemBuilder: (context, index) {
                                final friend = currentFriends[index];
                                final friendKarma = friend['karma'] ?? 50;
                                final friendPhotoUrl = _getKarmaTierUrl(friend,
                                    friendKarma is int ? friendKarma : 50);

                                return ListTile(
                                  leading: (friendPhotoUrl != null &&
                                          friendPhotoUrl != '')
                                      ? DegradedIconDisplay(
                                          imageUrl: friendPhotoUrl,
                                          karma: friendKarma is int
                                              ? friendKarma
                                              : 50,
                                          size: 40,
                                          shape: BoxShape.circle,
                                        )
                                      : CircleAvatar(
                                          child: Text(
                                            (friend['display_name'] ?? 'U')[0]
                                                .toUpperCase(),
                                          ),
                                        ),
                                  title: Text(friend['display_name'] ?? 'ユーザー'),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (String value) async {
                                      final userId =
                                          supabase.auth.currentUser!.id;
                                      final friendId = friend['user_id'];

                                      try {
                                        switch (value) {
                                          case 'delete':
                                            // フレンド削除
                                            await supabase
                                                .from('friends')
                                                .delete()
                                                .eq('user_id', userId)
                                                .eq('friend_id', friendId);
                                            await supabase
                                                .from('friends')
                                                .delete()
                                                .eq('user_id', friendId)
                                                .eq('friend_id', userId);

                                            if (mounted) {
                                              Navigator.pop(context);
                                              _loadFriends();
                                              _showFriendsList();
                                            }
                                            break;

                                          case 'block':
                                            // ブロック
                                            await supabase
                                                .from('blocked_users')
                                                .insert({
                                              'user_id': userId,
                                              'blocked_user_id': friendId,
                                            });

                                            // ブロック時は自動的にフレンド削除
                                            await supabase
                                                .from('friends')
                                                .delete()
                                                .eq('user_id', userId)
                                                .eq('friend_id', friendId);
                                            await supabase
                                                .from('friends')
                                                .delete()
                                                .eq('user_id', friendId)
                                                .eq('friend_id', userId);

                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content:
                                                      Text('🚫 ユーザーをブロックしました'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                              Navigator.pop(context);
                                              _loadFriends();
                                              _showFriendsList();
                                            }
                                            break;

                                          case 'mute':
                                            // ミュート
                                            await supabase
                                                .from('muted_users')
                                                .insert({
                                              'user_id': userId,
                                              'muted_user_id': friendId,
                                            });

                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content:
                                                      Text('🔇 ユーザーをミュートしました'),
                                                  backgroundColor:
                                                      Colors.orange,
                                                ),
                                              );
                                              Navigator.pop(context);
                                            }
                                            break;
                                        }
                                      } catch (e) {
                                        print('❌ エラー: $e');
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(content: Text('エラー: $e')),
                                          );
                                        }
                                      }
                                    },
                                    itemBuilder: (BuildContext context) =>
                                        <PopupMenuEntry<String>>[
                                      const PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.person_remove,
                                                color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('削除',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'block',
                                        child: Row(
                                          children: [
                                            Icon(Icons.block,
                                                color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('ブロック',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'mute',
                                        child: Row(
                                          children: [
                                            Icon(Icons.volume_off,
                                                color: Colors.orange),
                                            SizedBox(width: 8),
                                            Text('ミュート',
                                                style: TextStyle(
                                                    color: Colors.orange)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            FriendProfileScreen(
                                          friendId: friend['user_id'],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                      // 申請待ちタブ
                      pendingRequests.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('申請待ちのユーザーはいません'),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: pendingRequests.length,
                              itemBuilder: (context, index) {
                                final request = pendingRequests[index];
                                final requester = request['requester']
                                    as Map<String, dynamic>?;
                                final requesterKarma =
                                    requester?['karma'] ?? 50;
                                final requesterPhotoUrl = _getKarmaTierUrl(
                                    requester,
                                    requesterKarma is int
                                        ? requesterKarma
                                        : 50);

                                return ListTile(
                                  leading: (requesterPhotoUrl != null &&
                                          requesterPhotoUrl != '')
                                      ? DegradedIconDisplay(
                                          imageUrl: requesterPhotoUrl,
                                          karma: requesterKarma is int
                                              ? requesterKarma
                                              : 50,
                                          size: 40,
                                          shape: BoxShape.circle,
                                        )
                                      : CircleAvatar(
                                          child: Text(
                                            (requester?['display_name'] ??
                                                    'U')[0]
                                                .toUpperCase(),
                                          ),
                                        ),
                                  title: Text(
                                      requester?['display_name'] ?? 'ユーザー'),
                                  trailing: SizedBox(
                                    width: 100,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              backgroundColor: Colors.red,
                                            ),
                                            onPressed: () async {
                                              // 拒否処理
                                              try {
                                                await supabase
                                                    .from('friend_requests')
                                                    .update({
                                                  'status': 'rejected',
                                                  'responded_at': DateTime.now()
                                                      .toIso8601String(),
                                                }).eq('id', request['id']);

                                                pendingRequests.removeAt(index);
                                                if (mounted) {
                                                  Navigator.pop(context);
                                                  _showFriendsList();
                                                }
                                              } catch (e) {
                                                print('❌ 拒否エラー: $e');
                                              }
                                            },
                                            child: const Text(
                                              '拒否',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              backgroundColor: Colors.green,
                                            ),
                                            onPressed: () async {
                                              // 承認処理
                                              try {
                                                await supabase
                                                    .from('friend_requests')
                                                    .update({
                                                  'status': 'accepted',
                                                  'responded_at': DateTime.now()
                                                      .toIso8601String(),
                                                }).eq('id', request['id']);

                                                // friendsテーブルに既存レコードがなければinsert
                                                final requesterId =
                                                    request['requester_id'];
                                                final targetId =
                                                    request['target_id'];
                                                // 1. requester→target
                                                final exists1 = await supabase
                                                    .from('friends')
                                                    .select('user_id')
                                                    .eq('user_id', requesterId)
                                                    .eq('friend_id', targetId)
                                                    .maybeSingle();
                                                if (exists1 == null) {
                                                  await supabase
                                                      .from('friends')
                                                      .insert({
                                                    'user_id': requesterId,
                                                    'friend_id': targetId,
                                                  });
                                                }
                                                // 2. target→requester
                                                final exists2 = await supabase
                                                    .from('friends')
                                                    .select('user_id')
                                                    .eq('user_id', targetId)
                                                    .eq('friend_id',
                                                        requesterId)
                                                    .maybeSingle();
                                                if (exists2 == null) {
                                                  await supabase
                                                      .from('friends')
                                                      .insert({
                                                    'user_id': targetId,
                                                    'friend_id': requesterId,
                                                  });
                                                }

                                                // 申請者に通知を送信
                                                await supabase
                                                    .from('notifications')
                                                    .insert({
                                                  'recipient_id': requesterId,
                                                  'sender_id': targetId,
                                                  'notification_type':
                                                      'friend_accept',
                                                  'content': {},
                                                  'message': 'フレンド申請が承認されました',
                                                });

                                                // フレンドリストを再度読み込み
                                                await _loadFriends();

                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          '✅ フレンド申請を承認しました'),
                                                      backgroundColor:
                                                          Colors.green,
                                                    ),
                                                  );
                                                  Navigator.pop(context);
                                                  // 少し遅延してからダイアログを再度開く
                                                  await Future.delayed(
                                                      const Duration(
                                                          milliseconds: 500));
                                                  _showFriendsList();
                                                }
                                              } catch (e) {
                                                print('❌ 承認エラー: $e');
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content:
                                                            Text('エラー: $e')),
                                                  );
                                                }
                                              }
                                            },
                                            child: const Text(
                                              '承認',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    );
  }

  // 慈悲リクエスト一覧ダイアログを表示
  void _showMercyRequestsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('慈悲リクエスト'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _mercyRequests.length,
            itemBuilder: (context, index) {
              final request = _mercyRequests[index];
              final requester = request['requester'] as Map<String, dynamic>?;
              final requesterName = requester?['display_name'] ?? 'ユーザー';
              final requesterKarma = requester?['karma'] ?? 50;
              final requesterPhoto = _getKarmaTierUrl(
                  requester, requesterKarma is int ? requesterKarma : 50);

              return ListTile(
                leading: (requesterPhoto != null && requesterPhoto.isNotEmpty)
                    ? DegradedIconDisplay(
                        imageUrl: requesterPhoto,
                        karma: requesterKarma is int ? requesterKarma : 50,
                        size: 40,
                        shape: BoxShape.circle,
                      )
                    : CircleAvatar(
                        child: const Icon(Icons.person),
                      ),
                title: Text(requesterName),
                subtitle: const Text('慈悲を求めています'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () {
                        _approveMercyRequest(
                          request['id'].toString(),
                          request['requester_id'],
                        );
                        Navigator.pop(context);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () {
                        _rejectMercyRequest(request['id'].toString());
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // データ読み込み中はローディング表示
    if (_isLoading || _userData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 業スコアに応じてアイコンを選択（50未満は劣化状態）
    final karma = _userData?['karma'] ?? 50;
    final isDegraded = (karma is int ? karma : 50) < 50;
    // 業スコアに応じたティア画像を取得
    final photoUrl = _getKarmaTierUrl(_userData, karma is int ? karma : 50) ??
        _userData?['photo_url'];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _userData?['custom_user_id'] ?? 'ユーザー',
          style:
              const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          // 慈悲リクエストボタン（ベルの左）
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.favorite, color: Colors.orange),
                tooltip: '慈悲リクエスト',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MercyRequestScreen(),
                    ),
                  );
                },
              ),
              if (_mercyRequests.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _mercyRequests.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          // 未読通知があれば赤いバッジ付きベルアイコン
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications, color: Colors.black),
                tooltip: '通知',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UnifiedNotificationsScreen(),
                    ),
                  );
                  // 通知画面から戻ったら未読数を再取得
                  _loadUnreadNotificationsCount();
                },
              ),
              if (_unreadNotificationsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      _unreadNotificationsCount > 99
                          ? '99+'
                          : _unreadNotificationsCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.black),
            tooltip: 'フレンドを追加',
            onPressed: () => _showAddFriendDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.black),
            onPressed: () => _showSettingsMenu(context),
          ),
        ],
      ),
      // 下に引っ張って更新する機能
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ========== Instagram風プロフィールヘッダー ==========
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // プロフィール写真と統計情報を横並び
                    Row(
                      children: [
                        // プロフィール写真
                        Stack(
                          children: [
                            GestureDetector(
                              onTap: () {
                                _debugTapCount++;
                                if (_debugTapCount >= 5) {
                                  setState(() {
                                    _showDebugMenu = !_showDebugMenu;
                                    _debugTapCount = 0;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _showDebugMenu
                                            ? '🛠 開発者モードが有効になりました'
                                            : '開発者モードが無効になりました',
                                      ),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                                // タップカウントをリセット（3秒後）
                                Future.delayed(const Duration(seconds: 3), () {
                                  if (mounted) {
                                    setState(() {
                                      _debugTapCount = 0;
                                    });
                                  }
                                });
                              },
                              child: _buildTierImageDisplay(),
                            ),
                            // 装備中のバッジを右上に表示
                            if (_equippedBadge != null)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(
                                      color: _getBadgeBorderColor(
                                          _equippedBadge!['rarity']),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      _equippedBadge!['icon'],
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 24),
                        // 統計情報（投稿数・フレンド数）
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatColumn('${_myMeals.length}', '投稿'),
                              _buildStatColumn(
                                '${_friends.length}',
                                'フレンド',
                                onTap: () => _showFriendsList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 慈悲リクエスト通知（リクエストがある場合のみ表示）
                    if (_mercyRequests.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.favorite,
                                color: Colors.orange[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_mercyRequests.length}件の慈悲リクエストが届いています',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.orange[900],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const MercyRequestScreen(),
                                  ),
                                );
                              },
                              child: const Text('確認',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    if (_mercyRequests.isNotEmpty) const SizedBox(height: 12),
                    // 🎨 業テイア＆イラスト生成セクション
                    _buildIllustrationSection(),
                    const SizedBox(height: 12),
                    // ユーザー名
                    Text(
                      _userData?['display_name'] ?? 'ユーザー',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 修業開始/進行状況ボタン
                    if (_userData?['training_started'] != true)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _showStartTrainingDialog,
                          icon: const Icon(Icons.self_improvement),
                          label: const Text('修業を始める'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              '修業中',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '目標: ${_userData?['training_daily_steps_goal'] ?? 0} 歩/日',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            Text(
                              '期間: ${_userData?['training_months'] ?? 0} ヶ月',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            if (_userData?['training_end_date'] != null)
                              Builder(
                                builder: (context) {
                                  final endDate = DateTime.tryParse(
                                      _userData!['training_end_date']);
                                  if (endDate != null) {
                                    final remaining = endDate
                                        .difference(DateTime.now())
                                        .inDays;
                                    return Text(
                                      '残り: $remaining 日',
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  }
                                  return const SizedBox();
                                },
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    // 実績・バッジボタン
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AchievementsScreen(),
                            ),
                          );
                          // 実績画面から戻ってきたらバッジ情報を再読み込み
                          await _loadEquippedBadge();
                        },
                        icon:
                            const Icon(Icons.emoji_events, color: Colors.amber),
                        label: const Text('実績・バッジ'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          side: const BorderSide(color: Colors.amber),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ========== タブバー（投稿）==========
              TabBar(
                controller: _tabController,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.black,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.grid_on),
                    text: '投稿',
                  ),
                ],
              ),

              // ========== タブビュー（投稿グリッド）==========
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // タブ1: 投稿グリッド
                    _buildMealsGrid(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 投稿詳細を表示（カロリーと健康度スコア）
  void _showMealDetail(Map<String, dynamic> meal) {
    final imageUrl = meal['photo_url'] as String?;
    final calories = meal['calories'] as int? ?? 0;
    final healthScore = meal['health_score'] as int? ?? 0;
    final description = meal['notes'] as String? ?? '';
    final createdAt = meal['created_at'] as String?;
    final date = createdAt != null
        ? DateTime.parse(createdAt).toLocal().toString().substring(0, 10)
        : '';

    // カロリー判定（600を超えたら赤）
    final calorieColor = calories > 600 ? Colors.red : Colors.green;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 食事の画像
              if (imageUrl != null && imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: Image.network(
                    imageUrl,
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 日付
                    if (date.isNotEmpty)
                      Text(
                        date,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 12),

                    // カロリー（大きく表示）
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: calorieColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: calorieColor, width: 2),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'カロリー',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$calories',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: calorieColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'kcal',
                            style: TextStyle(
                              fontSize: 16,
                              color: calorieColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 健康度スコア
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '健康度スコア',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$healthScore',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 説明
                    if (description.isNotEmpty) ...[
                      const Text(
                        '説明',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ボタン群
                    Row(
                      children: [
                        // 削除ボタン
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _deleteMeal(meal);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              '削除',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 閉じるボタン
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              '閉じる',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 投稿を削除する
  Future<void> _deleteMeal(Map<String, dynamic> meal) async {
    final mealId = meal['id'] as String?;
    if (mealId == null) return;

    // 確認ダイアログ
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('投稿を削除'),
        content: const Text('この投稿を削除してもよろしいですか？\n削除後は復元できません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text(
              '削除',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('meals').delete().eq('id', mealId);

      // 画面をリロード
      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 投稿を削除しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 削除失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 投稿グリッドウィジェット
  Widget _buildMealsGrid() {
    if (_myMeals.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'まだ投稿がありません',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 80), // ボトムナビゲーション分の余白
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _myMeals.length,
      itemBuilder: (context, index) {
        final meal = _myMeals[index];
        final imageUrl = meal['photo_url'] as String?;

        return GestureDetector(
          onTap: () {
            // 投稿詳細を表示（カロリーと健康度スコア）
            _showMealDetail(meal);
          },
          child: imageUrl != null && imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.image, color: Colors.grey),
                ),
        );
      },
    );
  }

  // 慈悲リクエスト一覧ウィジェット
  Widget _buildMercyRequestsList() {
    if (_mercyRequests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '慈悲リクエストはありません',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
          left: 8, right: 8, top: 8, bottom: 80), // ボトムナビゲーション分の余白
      itemCount: _mercyRequests.length,
      itemBuilder: (context, index) {
        final request = _mercyRequests[index];
        final requester = request['requester'] as Map<String, dynamic>?;
        final requesterName = requester?['display_name'] ?? 'ユーザー';
        final requesterKarma = requester?['karma'] ?? 50;
        final requesterPhoto = _getKarmaTierUrl(
            requester, requesterKarma is int ? requesterKarma : 50);
        final requesterCustomId = requester?['custom_user_id'] as String?;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: (requesterPhoto != null && requesterPhoto.isNotEmpty)
                ? DegradedIconDisplay(
                    imageUrl: requesterPhoto,
                    karma: requesterKarma is int ? requesterKarma : 50,
                    size: 40,
                    shape: BoxShape.circle,
                  )
                : CircleAvatar(
                    child: const Icon(Icons.person),
                  ),
            title: Text(
              requesterName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              requesterCustomId != null ? '@$requesterCustomId' : '慈悲を求めています',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: () {
                    _approveMercyRequest(
                      request['id'].toString(),
                      request['requester_id'],
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  onPressed: () {
                    _rejectMercyRequest(request['id'].toString());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🎨 業テイア＆イラスト生成セクション
  Widget _buildIllustrationSection() {
    final karma = (_userData?['karma'] ?? 50) as int;
    final currentTierImage = _tierImageUrls[_currentKarmaTier];
    final profilePhoto = _userData?['photo_url'] as String?;

    // プロフィール写真がない場合はセクション非表示
    if (profilePhoto == null || profilePhoto.isEmpty) {
      return const SizedBox.shrink();
    }

    // テイア情報テキスト
    String tierName = '';
    String tierDescription = '';
    switch (_currentKarmaTier) {
      case 1:
        tierName = '悪業(1)';
        tierDescription = 'ハゲ散らかし・ニキビだらけ・デブで太った体';
        break;
      case 2:
        tierName = '不健康(2)';
        tierDescription = '薄毛気味・ニキビ跡・デブ気味';
        break;
      case 3:
        tierName = '通常(3)';
        tierDescription = '穏やかな顔・健康的な肌';
        break;
      case 4:
        tierName = '美化(4)';
        tierDescription = 'つやのある肌・綺麗な髪・輝き';
        break;
      case 5:
        tierName = '究極(5)';
        tierDescription = '光輝く仏';
        break;
    }

    // 次のティアまでの業スコア計算
    int nextTierThreshold = _currentKarmaTier * 20;
    int karmaToNextTier = nextTierThreshold - karma;
    if (karmaToNextTier < 0)
      karmaToNextTier = 20 - (karma - (_currentKarmaTier * 20 - 20));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.purple.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // テイア情報
          Row(
            children: [
              const Icon(Icons.trending_up, color: Colors.purple, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'イラスト: $tierName',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    Text(
                      tierDescription,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ステータス表示
          if (_illustrationRequestStatus == 'pending' &&
              currentTierImage == null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'イラスト生成中...（明朝に完成予定）',
                      style: TextStyle(fontSize: 10, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            )
          else if (_illustrationRequestStatus == 'completed' &&
              currentTierImage != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 12, color: Colors.green),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'イラストが完成しました！',
                      style: TextStyle(fontSize: 10, color: Colors.green),
                    ),
                  ),
                ],
              ),
            )
          else if (_illustrationRequestStatus == 'idle' && profilePhoto != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '業スコア: $karma/100',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Text(
                      '次: あと$karmaToNextTier',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isRequestingIllustration
                        ? null
                        : () => _requestIllustrationGeneration(),
                    icon: _isRequestingIllustration
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image, size: 16),
                    label: Text(
                      _isRequestingIllustration ? '送信中...' : 'イラスト生成をリクエスト',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // 🎨 イラスト生成をリクエスト
  Future<void> _requestIllustrationGeneration() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final profilePhotoUrl = _userData?['photo_url'] as String?;
      if (profilePhotoUrl == null || profilePhotoUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロフィール写真が必要です')),
        );
        return;
      }

      // 🎨 月内のイラスト生成リクエスト数をチェック（月1回制限）
      final allowance =
          await IllustrationTierManager.checkMonthlyRequestAllowance(userId);

      if (!allowance['allowed'] && allowance['requestCount']! > 0) {
        // すでに月内リクエスト済み → エラーダイアログ
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏳ アイコンのイラスト変更は月1回限りです。\nお待ちください。'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      setState(() {
        _isRequestingIllustration = true;
      });

      // すべてのテイアのイラスト生成をリクエスト
      final karma = (_userData?['karma'] ?? 50) as int;
      await IllustrationTierManager.checkAndRequestGeneration(
        userId: userId,
        oldKarma: karma,
        newKarma: karma,
        originalPhotoUrl: profilePhotoUrl,
      );

      if (mounted) {
        setState(() {
          _illustrationRequestStatus = 'pending';
          _isRequestingIllustration = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ イラスト生成をリクエストしました。\n明朝に完成予定です。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ イラスト生成リクエストエラー: $e');
      if (mounted) {
        setState(() {
          _isRequestingIllustration = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  // バッジの縁の色を取得
  Widget _buildTierImageDisplay() {
    // 現在のテイアに対応する画像URLを取得
    final currentTierImageUrl = _tierImageUrls[_currentKarmaTier];
    final photoUrl = _userData?['photo_url'] as String?;

    // テイア画像があればそれを表示、ない場合は元の写真を表示
    if (currentTierImageUrl != null && currentTierImageUrl.isNotEmpty) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _getTierBorderColor(_currentKarmaTier),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: _getTierBorderColor(_currentKarmaTier).withOpacity(0.5),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.network(
            currentTierImageUrl,
            width: 74,
            height: 74,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else if (photoUrl != null && photoUrl.isNotEmpty) {
      // テイア画像待機中 → オリジナル写真表示
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.orange,
            width: 2,
          ),
          image: DecorationImage(
            image: NetworkImage(photoUrl),
            fit: BoxFit.cover,
          ),
        ),
        child: _illustrationRequestStatus == 'pending'
            ? const Opacity(
                opacity: 0.7,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              )
            : null,
      );
    } else {
      // プロフィール写真なし
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[300],
          border: Border.all(
            color: Colors.grey[400]!,
            width: 2,
          ),
        ),
        child: const Icon(Icons.person, size: 40),
      );
    }
  }

  // 🎨 業テイアごとの縁の色を取得
  Color _getTierBorderColor(int tier) {
    switch (tier) {
      case 1:
        return Colors.red.shade700; // 悪業
      case 2:
        return Colors.orange;
      case 3:
        return Colors.grey; // 通常
      case 4:
        return Colors.blue;
      case 5:
        return Colors.amber; // 究極
      default:
        return Colors.grey;
    }
  }

  // バッジの縁の色を取得
  Color _getBadgeBorderColor(String rarity) {
    switch (rarity) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'platinum':
        return const Color(0xFFE5E4E2);
      default:
        return Colors.grey;
    }
  }
}
