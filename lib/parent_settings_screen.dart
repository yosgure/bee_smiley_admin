import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart';
import 'main.dart' show themeNotifier, setThemeMode;
import 'classroom_utils.dart';
import 'widgets/app_feedback.dart';
import 'notification_service.dart';

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

              const SizedBox(height: 24),

              // アカウント
              _buildSectionTitle('アカウント'),
              const SizedBox(height: 8),
              _buildPasswordChangeCard(),

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
          style: const TextStyle(fontSize: AppTextSize.title, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: AppTextSize.body,
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
                          style: const TextStyle(fontSize: AppTextSize.titleLg, fontWeight: FontWeight.bold),
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
              color: AppColors.aiAccent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('テーマ', style: const TextStyle(fontSize: AppTextSize.bodyLarge)),
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

  Widget _buildPasswordChangeCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colors.borderLight),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: const Icon(Icons.lock_outline, color: AppColors.primary),
        title: const Text('パスワード変更',
            style: TextStyle(fontSize: AppTextSize.bodyLarge)),
        trailing:
            Icon(Icons.chevron_right, color: context.colors.textSecondary),
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => const _PasswordChangeDialog(),
          );
        },
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showLogoutDialog,
        icon: const Icon(Icons.logout, color: AppColors.error),
        label: const Text('ログアウト', style: TextStyle(color: AppColors.error)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppColors.error),
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
              // ログアウト前にFCMトークンをFirestoreから削除（同一端末で別アカウントログイン後も古いアカウントに通知が届くのを防ぐ）
              try {
                await NotificationService().removeToken();
              } catch (_) {}
              await FirebaseAuth.instance.signOut();
              // AuthCheckWrapperが自動でログイン画面に戻すので、何もしなくてOK
            },
            child: const Text('ログアウト', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog();

  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final newPwd = _newController.text;
    final confirm = _confirmController.text;

    if (current.isEmpty || newPwd.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'すべての項目を入力してください');
      return;
    }
    if (newPwd.length < 6) {
      setState(() => _errorMessage = '新しいパスワードは6文字以上で入力してください');
      return;
    }
    if (newPwd != confirm) {
      setState(() => _errorMessage = '新しいパスワード（確認）が一致しません');
      return;
    }
    if (newPwd == current) {
      setState(() => _errorMessage = '現在のパスワードと異なるパスワードを設定してください');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null || user.email!.isEmpty) {
        throw FirebaseAuthException(
            code: 'no-user', message: 'ログイン情報が取得できません');
      }
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: current,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPwd);

      if (!mounted) return;
      Navigator.of(context).pop();
      AppFeedback.success(context, 'パスワードを変更しました');
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          msg = '現在のパスワードが正しくありません';
          break;
        case 'weak-password':
          msg = 'パスワードが弱すぎます';
          break;
        case 'requires-recent-login':
          msg = '再ログインが必要です。一度ログアウトしてから再度お試しください';
          break;
        case 'too-many-requests':
          msg = '試行回数が多すぎます。しばらく待ってから再度お試しください';
          break;
        case 'network-request-failed':
          msg = 'ネットワークに接続できません';
          break;
        default:
          msg = 'エラー: ${e.message ?? e.code}';
      }
      if (mounted) {
        setState(() {
          _errorMessage = msg;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'エラー: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.cardBg,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('パスワード変更',
          style:
              TextStyle(fontSize: AppTextSize.titleSm, fontWeight: FontWeight.bold)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      contentPadding:
          const EdgeInsets.fromLTRB(20, 12, 20, 8),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPasswordField(
                controller: _currentController,
                label: '現在のパスワード',
                obscure: _obscureCurrent,
                onToggle: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              const SizedBox(height: 16),
              _buildPasswordField(
                controller: _newController,
                label: '新しいパスワード',
                helper: '6文字以上',
                obscure: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
              ),
              const SizedBox(height: 16),
              _buildPasswordField(
                controller: _confirmController,
                label: '新しいパスワード（確認）',
                obscure: _obscureConfirm,
                onToggle: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: AppTextSize.body),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text('キャンセル',
              style: TextStyle(color: context.colors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('変更'),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    String? helper,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: !_saving,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
              color: context.colors.textSecondary),
          onPressed: onToggle,
        ),
      ),
    );
  }
}