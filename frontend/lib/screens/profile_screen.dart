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
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabaseクライアントのグローバルインスタンス
final supabase = Supabase.instance.client;

// プロフィール画面のStatefulWidget
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

// プロフィール画面の状態管理クラス
class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData; // 自分のユーザーデータ
  List<Map<String, dynamic>> _mercyRequests = []; // 慈悲リクエストのリスト
  List<Map<String, dynamic>> _friends = []; // フレンドリスト
  bool _isLoading = true; // ローディング状態
  final _friendSearchController = TextEditingController(); // フレンド検索用のコントローラー
  final ImagePicker _picker = ImagePicker(); // 画像選択用のインスタンス

  @override
  void initState() {
    super.initState();
    // 画面が表示されたときにすべてのデータを読み込む
    _loadAllData();
  }

  @override
  void dispose() {
    // メモリリークを防ぐため、コントローラーを破棄
    _friendSearchController.dispose();
    super.dispose();
  }

  // すべてのデータを読み込む関数
  Future<void> _loadAllData() async {
    await _loadUserData();
    await _loadMercyRequests();
    await _loadFriends();
    setState(() => _isLoading = false);
  }

  // ユーザーデータを読み込む関数
  Future<void> _loadUserData() async {
    final userId = supabase.auth.currentUser!.id;

    final response = await supabase
        .from('users')
        .select()
        .eq('user_id', userId)
        .single();

    setState(() {
      _userData = response;
    });
  }

  // 慈悲リクエストを読み込む関数
  Future<void> _loadMercyRequests() async {
    final userId = supabase.auth.currentUser!.id;

    // 自分宛ての保留中のリクエストを取得
    final response = await supabase
        .from('mercy_requests')
        .select('*, requester:users!requester_id(display_name, email)')
        .eq('receiver_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    setState(() {
      _mercyRequests = List<Map<String, dynamic>>.from(response);
    });
  }

  // フレンドリストを読み込む関数
  Future<void> _loadFriends() async {
    final friendIds = List<String>.from(_userData?['friends'] ?? []);

    if (friendIds.isEmpty) {
      setState(() => _friends = []);
      return;
    }

    final response = await supabase
        .from('users')
        .select()
        .inFilter('user_id', friendIds);

    setState(() {
      _friends = List<Map<String, dynamic>>.from(response);
    });
  }

  /// 慈悲リクエストを承認する関数
  Future<void> _approveMercyRequest(String requestId, String requesterId) async {
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

      // ========== バリデーション ==========
      // 自分自身は追加できない
      if (friendId == userId) {
        throw Exception('自分自身は追加できません');
      }

      // 現在のフレンドリストを取得
      final currentFriends = List<String>.from(_userData?['friends'] ?? []);

      // すでにフレンドの場合
      if (currentFriends.contains(friendId)) {
        throw Exception('すでにフレンドです');
      }

      // ========== フレンドリストに追加 ==========
      currentFriends.add(friendId);

      await supabase.from('users').update({
        'friends': currentFriends,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

      // 入力欄をクリア
      _friendSearchController.clear();
      
      // データを再読み込み
      await _loadUserData();
      await _loadFriends();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${friendResponse['display_name']} をフレンドに追加しました'),
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

  /// プロフィール写真をアップロードする関数
  Future<void> _uploadProfilePhoto() async {
    try {
      // ギャラリーから画像を選択
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      // ========== Supabase Storage にアップロード ==========
      final userId = supabase.auth.currentUser!.id;
      final fileName = 'avatars/$userId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage.from('avatars').upload(
            fileName,
            File(image.path),
          );

      // アップロードした画像の公開URLを取得
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      // ========== usersテーブルを更新 ==========
      await supabase.from('users').update({
        'photo_url': publicUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);

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
      // アプリバー
      appBar: AppBar(
        title: const Text('プロフィール'),
        actions: [
          // ログアウトボタン
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      // 下に引っ張って更新する機能
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ========== プロフィール情報カード ==========
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      // プロフィール画像（編集ボタン付き）
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundImage: photoUrl != null && photoUrl != ''
                                ? NetworkImage(photoUrl)
                                : null,
                            child: photoUrl == null || photoUrl == ''
                                ? const Icon(Icons.person, size: 60)
                                : null,
                          ),
                          // 画像編集ボタン
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              backgroundColor: Colors.orange,
                              radius: 20,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.camera_alt,
                                  size: 20,
                                  color: Colors.white,
                                ),
                                onPressed: _uploadProfilePhoto,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // ユーザー名
                      Text(
                        _userData?['display_name'] ?? 'ユーザー',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ユーザーID
                      if (_userData?['custom_user_id'] != null)
                        Text(
                          '@${_userData?['custom_user_id']}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.blue,
                          ),
                        ),
                      const SizedBox(height: 4),
                      // メールアドレス
                      Text(
                        _userData?['email'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ========== 慈悲リクエストセクション ==========
              const Text(
                '慈悲リクエスト',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (_mercyRequests.isEmpty)
                // リクエストがない場合
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      '新しいリクエストはありません',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                // リクエストがある場合
                Column(
                  children: _mercyRequests.map((request) {
                    final requester = request['requester'] as Map<String, dynamic>?;
                    final requesterName = requester?['display_name'] ?? 'ユーザー';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(
                          Icons.favorite,
                          color: Colors.red,
                          size: 40,
                        ),
                        title: Text('$requesterName さんから'),
                        subtitle: const Text('慈悲を求めています'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 承認ボタン
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: () => _approveMercyRequest(
                                request['id'].toString(),
                                request['requester_id'],
                              ),
                            ),
                            // 拒否ボタン
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _rejectMercyRequest(
                                request['id'].toString(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 24),

              // ========== フレンドセクション ==========
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'フレンド',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // フレンド追加ボタン
                  ElevatedButton.icon(
                    onPressed: () {
                      // フレンド追加ダイアログを表示
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('フレンドを追加'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: _friendSearchController,
                                decoration: const InputDecoration(
                                  labelText: 'ユーザーIDまたはメールアドレス',
                                  border: OutlineInputBorder(),
                                  hintText: '@user_id または email@example.com',
                                ),
                                keyboardType: TextInputType.text,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '※ユーザーIDは @ から始まります',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
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
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('追加'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_friends.isEmpty)
                // フレンドがいない場合
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      'まだフレンドがいません',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                // フレンドリスト
                Column(
                  children: _friends.map((friend) {
                    final friendPhotoUrl = friend['photo_url'] as String?;
                    final friendCustomId = friend['custom_user_id'] as String?;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: friendPhotoUrl != null &&
                                  friendPhotoUrl != ''
                              ? NetworkImage(friendPhotoUrl)
                              : null,
                          child: friendPhotoUrl == null || friendPhotoUrl == ''
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(friend['display_name'] ?? 'ユーザー'),
                        subtitle: Text(
                          friendCustomId != null 
                              ? '@$friendCustomId' 
                              : (friend['email'] ?? '')
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
