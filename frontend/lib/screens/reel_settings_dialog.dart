import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReelSettingsDialog extends StatefulWidget {
  final bool initialKeepAspectRatio;
  final ValueChanged<bool> onChanged;
  const ReelSettingsDialog({
    super.key,
    required this.initialKeepAspectRatio,
    required this.onChanged,
  });

  @override
  State<ReelSettingsDialog> createState() => _ReelSettingsDialogState();
}

class _ReelSettingsDialogState extends State<ReelSettingsDialog> {
  late bool _keepAspectRatio;

  @override
  void initState() {
    super.initState();
    _keepAspectRatio = widget.initialKeepAspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('リール表示設定'),
      content: Row(
        children: [
          const Expanded(child: Text('縦横比を維持して表示する')),
          Switch(
            value: _keepAspectRatio,
            onChanged: (v) {
              setState(() => _keepAspectRatio = v);
              widget.onChanged(v);
            },
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
}
