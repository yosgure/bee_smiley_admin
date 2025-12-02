import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  bool _isLoading = true;
  bool _isSaving = false;
  
  bool _notifyChat = true;
  bool _notifyAnnouncement = true;
  bool _notifyEvent = true;
  bool _notifyAssessment = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final settings = await _notificationService.getNotificationSettings(user.uid);
    if (mounted) {
      setState(() {
        _notifyChat = settings['chat'] ?? true;
        _notifyAnnouncement = settings['announcement'] ?? true;
        _notifyEvent = settings['event'] ?? true;
        _notifyAssessment = settings['assessment'] ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isSaving = true);
    
    await _notificationService.saveNotificationSettings(user.uid, {
      'chat': _notifyChat,
      'announcement': _notifyAnnouncement,
      'event': _notifyEvent,
      'assessment': _notifyAssessment,
    });

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知設定を保存しました'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        secondary: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知設定'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'プッシュ通知の受信設定',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSwitchTile(
                  icon: Icons.chat_bubble_outline,
                  iconColor: Colors.blue,
                  title: 'チャット',
                  subtitle: '新しいメッセージを受信したとき',
                  value: _notifyChat,
                  onChanged: (v) => setState(() => _notifyChat = v),
                ),
                _buildSwitchTile(
                  icon: Icons.campaign_outlined,
                  iconColor: Colors.orange,
                  title: 'お知らせ',
                  subtitle: '新しいお知らせが投稿されたとき',
                  value: _notifyAnnouncement,
                  onChanged: (v) => setState(() => _notifyAnnouncement = v),
                ),
                _buildSwitchTile(
                  icon: Icons.event_outlined,
                  iconColor: Colors.green,
                  title: 'イベント',
                  subtitle: '新しいイベントが公開されたとき',
                  value: _notifyEvent,
                  onChanged: (v) => setState(() => _notifyEvent = v),
                ),
                _buildSwitchTile(
                  icon: Icons.assessment_outlined,
                  iconColor: Colors.purple,
                  title: 'アセスメント',
                  subtitle: 'アセスメントが公開されたとき',
                  value: _notifyAssessment,
                  onChanged: (v) => setState(() => _notifyAssessment = v),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ),
              ],
            ),
    );
  }
}
