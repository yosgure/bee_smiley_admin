import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart';
import 'main.dart' show themeNotifier, setThemeMode;
import 'classroom_utils.dart';

class ParentSettingsScreen extends StatefulWidget {
  final Map<String, dynamic>? familyData;
  final List<Map<String, dynamic>> children;
  final int selectedChildIndex;
  final Function(int) onChildChanged;
  final VoidCallback onFamilyUpdated;

  const ParentSettingsScreen({
    super.key,
    required this.familyData,
    required this.children,
    required this.selectedChildIndex,
    required this.onChildChanged,
    required this.onFamilyUpdated,
  });

  @override
  State<ParentSettingsScreen> createState() => _ParentSettingsScreenState();
}

class _ParentSettingsScreenState extends State<ParentSettingsScreen> {

  // 現在選択中の子ども
  Map<String, dynamic>? get _currentChild {
    if (widget.children.isEmpty) return null;
    return widget.children[widget.selectedChildIndex];
  }

  // 子どもの表示名
  String get _currentChildName {
    if (_currentChild == null || widget.familyData == null) return '';
    final lastName = widget.familyData!['lastName'] ?? '';
    final firstName = _currentChild!['firstName'] ?? '';
    return '$lastName $firstName';
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader('設定'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 子どもの情報セクション
              _buildSectionTitle('お子さま情報'),
              const SizedBox(height: 8),
              _buildChildCard(),
              
              const SizedBox(height: 24),

              // テーマ設定
              _buildSectionTitle('表示設定'),
              const SizedBox(height: 8),
              _buildThemeCard(),

              const SizedBox(height: 32),

              // ログアウト
              _buildLogoutButton(),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String title) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border(bottom: BorderSide(color: context.colors.borderLight)),
      ),
      child: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: context.colors.textSecondary,
      ),
    );
  }

  Widget _buildChildCard() {
    if (widget.children.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const Text('お子さまの情報がありません'),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 複数の子どもがいる場合は選択UI
            if (widget.children.length > 1) ...[
              ...widget.children.asMap().entries.map((entry) {
                final index = entry.key;
                final child = entry.value;
                final lastName = widget.familyData?['lastName'] ?? '';
                final firstName = child['firstName'] ?? '';
                final isSelected = index == widget.selectedChildIndex;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isSelected 
                        ? AppColors.primary.withOpacity(0.1) 
                        : context.colors.chipBg,
                    backgroundImage: child['photoUrl'] != null 
                        ? NetworkImage(child['photoUrl']) 
                        : null,
                    child: child['photoUrl'] == null
                        ? Icon(Icons.person, color: isSelected ? AppColors.primary : Colors.grey)
                        : null,
                  ),
                  title: Text(
                    '$lastName $firstName',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(classroomsDisplayText(child)),
                  trailing: isSelected 
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : null,
                  onTap: () => widget.onChildChanged(index),
                );
              }),
            ] else ...[
              // 1人の場合はシンプル表示
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    backgroundImage: _currentChild?['photoUrl'] != null 
                        ? NetworkImage(_currentChild!['photoUrl']) 
                        : null,
                    child: _currentChild?['photoUrl'] == null
                        ? const Icon(Icons.person, size: 30, color: AppColors.primary)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentChildName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentChild != null ? classroomsDisplayText(_currentChild!) : '',
                          style: TextStyle(color: context.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThemeCard() {
    final currentMode = themeNotifier.value;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              context.isDark ? Icons.dark_mode : Icons.light_mode,
              color: Colors.deepPurple,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('テーマ', style: const TextStyle(fontSize: 15)),
            ),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16)),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_brightness, size: 16)),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16)),
              ],
              selected: {currentMode},
              onSelectionChanged: (selected) {
                setThemeMode(selected.first);
                setState(() {});
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showLogoutDialog,
        icon: const Icon(Icons.logout, color: Colors.red),
        label: const Text('ログアウト', style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseAuth.instance.signOut();
              // AuthCheckWrapperが自動でログイン画面に戻すので、何もしなくてOK
            },
            child: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}