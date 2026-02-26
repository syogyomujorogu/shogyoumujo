import 'package:flutter/material.dart';
import 'package:shogyo_mujo_log/helpers/gemini_helper.dart';

/// Gemini API テスト画面
class GeminiTestScreen extends StatefulWidget {
  const GeminiTestScreen({super.key});

  @override
  State<GeminiTestScreen> createState() => _GeminiTestScreenState();
}

class _GeminiTestScreenState extends State<GeminiTestScreen> {
  final _gemini = GeminiHelper();
  final _controller = TextEditingController();
  String _response = '';
  bool _loading = false;

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty) return;
    
    setState(() {
      _loading = true;
      _response = '送信中...';
    });

    final result = await _gemini.generateText(_controller.text);
    
    setState(() {
      _loading = false;
      _response = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini API テスト'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '質問を入力',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _sendMessage,
              child: const Text('送信'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _response.isEmpty ? 'ここに回答が表示されます' : _response,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '💡 ヒント:\n'
              '• 無料プラン: 1分間に15リクエストまで\n'
              '• 403エラー: APIキーを確認\n'
              '• 429エラー: 無料枠超過（翌日リセット）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
