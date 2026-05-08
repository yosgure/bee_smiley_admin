import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'services/chat_prefs.dart';
import 'widgets/app_feedback.dart';

class ChatSettingsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ChatSettingsScreen({super.key, this.onBack});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  bool _loading = true;
  bool _sendOnEnter = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await ChatPrefs.getSendOnEnter();
    if (!mounted) return;
    setState(() {
      _sendOnEnter = v;
      _loading = false;
    });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _sendOnEnter = v);
    await ChatPrefs.setSendOnEnter(v);
    if (mounted) AppFeedback.success(context, '保存しました');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('チャット設定'),
        centerTitle: true,
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '送信キー',
                  style: TextStyle(
                    fontSize: AppTextSize.titleSm,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: SwitchListTile(
                    title: const Text('Enter キーで送信'),
                    subtitle: Text(
                      _sendOnEnter
                          ? 'Enter で送信 / Shift + Enter で改行'
                          : 'Shift + Enter で送信 / Enter で改行',
                      style: const TextStyle(fontSize: AppTextSize.small),
                    ),
                    value: _sendOnEnter,
                    onChanged: _toggle,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '※ 設定はこの端末のみに保存されます。',
                  style: TextStyle(
                    fontSize: AppTextSize.small,
                    color: context.colors.textTertiary,
                  ),
                ),
              ],
            ),
    );
  }
}
