// =============================================================================
// comment_sheet.dart - コメント表示・投稿シート
// =============================================================================
// このファイルの役割:
// 1. 食事投稿のコメント一覧を表示
// 2. コメント投稿機能
// 3. リアルタイムコメント更新
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

final supabase = Supabase.instance.client;

/// コメントシートを表示
void showCommentSheet(
  BuildContext context,
  String mealId,
  String mealCreatorId,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => CommentSheet(
      mealId: mealId,
      mealCreatorId: mealCreatorId,
    ),
  );
}

/// コメントシートのStatefulWidget
class CommentSheet extends StatefulWidget {
  final String mealId;
  final String mealCreatorId;

  const CommentSheet({
    Key? key,
    required this.mealId,
    required this.mealCreatorId,
  }) : super(key: key);

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

/// コメントシートの状態管理クラス
class _CommentSheetState extends State<CommentSheet> {
  final _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// コメント一覧を読み込む
  Future<void> _loadComments() async {
    try {
      final comments = await supabase
          .from('meal_comments')
          .select(
            '*, user:users!user_id(display_name, custom_user_id, photo_url)',
          )
          .eq('meal_id', widget.mealId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _comments = List<Map<String, dynamic>>.from(comments ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ コメント読み込みエラー: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// コメントを投稿
  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    try {
      setState(() => _isPosting = true);

      final userId = supabase.auth.currentUser!.id;

      // コメントを投稿
      await supabase.from('meal_comments').insert({
        'meal_id': widget.mealId,
        'user_id': userId,
        'comment_text': text,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 入力欄をクリア
      _commentController.clear();

      // コメント一覧を再読み込み
      await _loadComments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💬 コメントを投稿しました'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ コメント投稿エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // ハンドル
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // ヘッダー
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'コメント',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 0),
              // コメント一覧
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.comment_outlined,
                                  size: 48,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'コメントはまだありません',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _comments.length,
                            itemBuilder: (context, index) {
                              final comment = _comments[index];
                              final user =
                                  comment['user'] as Map<String, dynamic>?;
                              final userName = user?['display_name'] ?? 'ユーザー';
                              final userCustomId =
                                  user?['custom_user_id'] ?? '';
                              final userPhotoUrl =
                                  user?['photo_url'] as String?;
                              final content =
                                  comment['comment_text'] as String?;
                              final createdAt =
                                  comment['created_at'] as String?;

                              // 投稿日時をフォーマット
                              String formattedTime = '';
                              if (createdAt != null) {
                                try {
                                  final dateTime = DateTime.parse(createdAt);
                                  formattedTime = DateFormat('HH:mm')
                                      .format(dateTime.toLocal());
                                } catch (e) {
                                  formattedTime = '';
                                }
                              }

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ユーザー画像
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundImage: userPhotoUrl != null &&
                                              userPhotoUrl.isNotEmpty
                                          ? NetworkImage(userPhotoUrl)
                                          : null,
                                      child: userPhotoUrl == null ||
                                              userPhotoUrl.isEmpty
                                          ? const Icon(Icons.person, size: 20)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    // コメント内容
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // ユーザー名
                                          Row(
                                            children: [
                                              Text(
                                                userName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '@$userCustomId',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                formattedTime,
                                                style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          // コメント本文
                                          Text(
                                            content ?? '',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              const Divider(height: 0),
              // コメント入力欄
              Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        decoration: InputDecoration(
                          hintText: 'コメントを入力...',
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: Colors.grey[300]!,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          enabled: !_isPosting,
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 送信ボタン
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                      ),
                      child: IconButton(
                        icon: _isPosting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.send),
                        color: Colors.white,
                        onPressed: _isPosting ? null : _postComment,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
