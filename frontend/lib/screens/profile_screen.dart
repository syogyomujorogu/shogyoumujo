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
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'training_completion_dialog.dart';
import 'debug_menu_screen.dart';
import 'achievements_screen.dart';
import 'unified_notifications_screen.dart';
import 'friend_profile_screen.dart';
import 'reel_settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

  // 慈悲リクエストを読み込む関数
  Future<void> _loadMercyRequests() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 自分宛ての保留中のリクエストを取得
      final response = await supabase
          .from('mercy_requests')
          .select('*, requester:users!requester_id(display_name, email)')
          .eq('receiver_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _mercyRequests = List<Map<String, dynamic>>.from(response);
        });
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
      // ========== リクエスターに慈悲ポイントを付与 ==========
      final requesterData = await supabase
          .from('users')
          .select('mercy_points')
          .eq('user_id', requesterId)
          .single();

      final currentPoints = (requesterData['mercy_points'] ?? 0) as int;

      // ポイントを1増やす
      await supabase.from('users').update({
        'mercy_points': currentPoints + 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', requesterId);

      // ========== リクエストのステータスを更新 ==========
      await supabase.from('mercy_requests').update({
        'status': 'approved',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', requestId);

      // リクエストリストを再読み込み
      await _loadMercyRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🙏 慈悲を与えました'),
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
      // 選択肢ダイアログ（カメラ or ギャラリー）
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('プロフィール写真を選択'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ImageSource.camera),
              child: const Text('カメラで撮影'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ImageSource.gallery),
              child: const Text('ギャラリーから選択'),
            ),
          ],
        ),
      );
      if (source == null) return;

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null) return;

      // ========== Supabase Storage にアップロード ==========
      final userId = supabase.auth.currentUser!.id;
      final fileName =
          'avatars/$userId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('avatars').upload(
            fileName,
            File(image.path),
          );
      // アップロードした画像の公開URLを取得
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      // ========== Gemini APIでイラスト化 ==========
      try {
        final imageBytes = await File(image.path).readAsBytes();
        final gemini = GeminiHelper();
        final prompt = '証明写真風の自撮り画像を、アイコン用の優しいイラストに変換してください。';
        final illustrationText = await gemini.generateFromImageAndText(
          imageBytes: imageBytes,
          prompt: prompt,
        );
        // Gemini APIレスポンスがbase64画像の場合
        if (illustrationText.startsWith('data:image')) {
          final base64Data = illustrationText.split(',').last;
          final illustrationBytes =
              Uint8List.fromList(base64Decode(base64Data));
          // 劣化処理（グレースケール化例）
          final degradedBytes = _degradeImage(illustrationBytes);
          // 劣化画像を保存
          final degradedFileName =
              'avatars/$userId/degraded_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final degradedFile = File('${image.path}_degraded.jpg');
          await degradedFile.writeAsBytes(degradedBytes);
          await supabase.storage.from('avatars').upload(
                degradedFileName,
                degradedFile,
              );
          final degradedUrl =
              supabase.storage.from('avatars').getPublicUrl(degradedFileName);
          // usersテーブルにdegraded_photo_urlを保存
          await supabase.from('users').update({
            'photo_url': publicUrl,
            'degraded_photo_url': degradedUrl,
            'is_degraded': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('user_id', userId);
        } else {
          // イラスト画像生成失敗時は通常画像のみ保存
          await supabase.from('users').update({
            'photo_url': publicUrl,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('user_id', userId);
        }
      } catch (e) {
        // Gemini API失敗時は通常画像のみ保存
        await supabase.from('users').update({
          'photo_url': publicUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('user_id', userId);
      }

      // データを再読み込み
      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('プロフィール写真を更新しました'),
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
                        await _uploadProfilePhoto();
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
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: friend['photo_url'] != null
                                        ? NetworkImage(friend['photo_url'])
                                        : null,
                                    child: friend['photo_url'] == null
                                        ? Text(
                                            (friend['display_name'] ?? 'U')[0]
                                                .toUpperCase(),
                                          )
                                        : null,
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

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: requester?['photo_url'] !=
                                            null
                                        ? NetworkImage(requester!['photo_url'])
                                        : null,
                                    child: requester?['photo_url'] == null
                                        ? Text(
                                            (requester?['display_name'] ??
                                                    'U')[0]
                                                .toUpperCase(),
                                          )
                                        : null,
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
              final requesterPhoto = requester?['photo_url'] as String?;

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage:
                      requesterPhoto != null && requesterPhoto.isNotEmpty
                          ? NetworkImage(requesterPhoto)
                          : null,
                  child:
                      requesterPhoto == null ? const Icon(Icons.person) : null,
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

    // 劣化している場合は劣化顔を表示
    final isDegraded = _userData?['is_degraded'] ?? false;
    final photoUrl = isDegraded
        ? (_userData?['degraded_photo_url'] ?? _userData?['photo_url'])
        : _userData?['photo_url'];

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
                              onLongPress: _uploadProfilePhoto,
                              child: CircleAvatar(
                                radius: 40,
                                backgroundImage:
                                    photoUrl != null && photoUrl != ''
                                        ? NetworkImage(photoUrl)
                                        : null,
                                child: photoUrl == null || photoUrl == ''
                                    ? const Icon(Icons.person, size: 40)
                                    : null,
                              ),
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
                              onPressed: _showMercyRequestsDialog,
                              child: const Text('確認',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    if (_mercyRequests.isNotEmpty) const SizedBox(height: 12),
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

              // ========== タブバー（投稿 / 慈悲リクエスト）==========
              TabBar(
                controller: _tabController,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.black,
                tabs: [
                  const Tab(
                    icon: Icon(Icons.grid_on),
                    text: '投稿',
                  ),
                  Tab(
                    icon: const Icon(Icons.favorite),
                    text: '慈悲リクエスト (${_mercyRequests.length})',
                  ),
                ],
              ),

              // ========== タブビュー（投稿グリッド / 慈悲リクエスト一覧）==========
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // タブ1: 投稿グリッド
                    _buildMealsGrid(),
                    // タブ2: 慈悲リクエスト一覧
                    _buildMercyRequestsList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
      padding: EdgeInsets.zero,
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
            // 投稿詳細を表示（オプション）
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
      padding: const EdgeInsets.all(8),
      itemCount: _mercyRequests.length,
      itemBuilder: (context, index) {
        final request = _mercyRequests[index];
        final requester = request['requester'] as Map<String, dynamic>?;
        final requesterName = requester?['display_name'] ?? 'ユーザー';
        final requesterPhoto = requester?['photo_url'] as String?;
        final requesterCustomId = requester?['custom_user_id'] as String?;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage:
                  requesterPhoto != null && requesterPhoto.isNotEmpty
                      ? NetworkImage(requesterPhoto)
                      : null,
              child: requesterPhoto == null ? const Icon(Icons.person) : null,
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
