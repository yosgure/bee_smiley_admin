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
        const SnackBar(content: Text('通知設定を保存しました'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知設定'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 説明
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '受け取りたい通知の種類を選択してください',
                          style: TextStyle(color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 通知設定リスト
                _buildSectionTitle('通知の種類'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildNotificationTile(
                        icon: Icons.chat_bubble_outline,
                        color: Colors.blue,
                        title: 'チャット',
                        subtitle: '新しいメッセージを受信したとき',
                        value: _notifyChat,
                        onChanged: (val) => setState(() => _notifyChat = val),
                      ),
                      const Divider(height: 1, indent: 60),
                      _buildNotificationTile(
                        icon: Icons.campaign_outlined,
                        color: Colors.orange,
                        title: 'お知らせ',
                        subtitle: '新しいお知らせが投稿されたとき',
                        value: _notifyAnnouncement,
                        onChanged: (val) => setState(() => _notifyAnnouncement = val),
                      ),
                      const Divider(height: 1, indent: 60),
                      _buildNotificationTile(
                        icon: Icons.event_outlined,
                        color: Colors.green,
                        title: 'イベント',
                        subtitle: 'イベントの更新や新規登録があったとき',
                        value: _notifyEvent,
                        onChanged: (val) => setState(() => _notifyEvent = val),
                      ),
                      const Divider(height: 1, indent: 60),
                      _buildNotificationTile(
                        icon: Icons.assessment_outlined,
                        color: Colors.purple,
                        title: 'アセスメント',
                        subtitle: 'アセスメントが公開されたとき',
                        value: _notifyAssessment,
                        onChanged: (val) => setState(() => _notifyAssessment = val),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // 注意事項
                Text(
                  '※ 端末の設定でアプリの通知がオフになっている場合は、通知を受け取れません。',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildNotificationTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.blue,
      ),
    );
  }
}