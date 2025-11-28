import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_manage_screen.dart';
import 'tool_master_screen.dart';
import 'generic_master_screen.dart';
import 'staff_manage_screen.dart';
import 'non_cognitive_skill_master_screen.dart';
import 'sensitive_period_master_screen.dart';
import 'classroom_master_screen.dart';
import 'staff_csv_import_screen.dart';
import 'family_csv_import_screen.dart';
import 'tool_csv_import_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理メニュー'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. ヒトの管理
          _buildSettingsSection(
            context,
            'ヒトの管理',
            [
              _MenuData(
                title: '管理者・スタッフ',
                icon: Icons.badge,
                color: Colors.blue,
                description: '先生や職員の登録・権限設定',
                destination: const StaffManageScreen(),
              ),
              _MenuData(
                title: 'スタッフCSV登録',
                icon: Icons.upload_file,
                color: Colors.green,
                description: 'CSVで一括登録する',
                destination: const StaffCsvImportScreen(),
              ),
              _MenuData(
                title: '保護者・児童',
                icon: Icons.family_restroom,
                color: Colors.blue,
                description: '児童情報と連絡先の管理',
                destination: const StudentManageScreen(),
              ),
              _MenuData(
                title: '保護者CSV登録',
                icon: Icons.upload_file,
                color: Colors.green,
                description: '保護者・児童を一括登録',
                destination: const FamilyCsvImportScreen(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 2. 保育・教育の管理
          _buildSettingsSection(
            context,
            '保育・教育の管理',
            [
              _MenuData(
                title: '教具マスタ',
                icon: Icons.extension,
                color: Colors.orange,
                description: 'アセスメントで使う教具一覧',
                destination: const ToolMasterScreen(),
              ),
              _MenuData(
                title: '教具CSV登録',
                icon: Icons.upload_file,
                color: Colors.green,
                description: '教具を一括登録',
                destination: const ToolCsvImportScreen(),
              ),
              _MenuData(
                title: '非認知能力',
                icon: Icons.psychology,
                color: Colors.orange,
                description: '月間サマリの評価項目',
                destination: const NonCognitiveSkillMasterScreen(),
              ),
              _MenuData(
                title: '敏感期リスト',
                icon: Icons.hourglass_top,
                color: Colors.orange,
                description: '発達段階のキーワード',
                destination: const SensitivePeriodMasterScreen(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 3. 施設の管理
          _buildSettingsSection(
            context,
            '施設の管理',
            [
              _MenuData(
                title: '教室設定',
                icon: Icons.store,
                color: Colors.brown,
                description: '予定で使う部屋・場所',
                destination: const ClassroomMasterScreen(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 4. アカウント
          _buildAccountSection(context),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getStaffInfo(),
      builder: (context, snapshot) {
        final staffData = snapshot.data;
        final name = staffData?['displayName'] ?? '';
        final loginId = staffData?['loginId'] ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 8),
              child: Text(
                'アカウント',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
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
                  // 氏名
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.person, color: Colors.blue, size: 24),
                    ),
                    title: const Text(
                      '氏名',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    subtitle: Text(
                      name.isNotEmpty ? name : '---',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                  const Divider(height: 1, indent: 60),
                  // ID
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.badge, color: Colors.green, size: 24),
                    ),
                    title: const Text(
                      'ID',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    subtitle: Text(
                      loginId.isNotEmpty ? loginId : '---',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                  const Divider(height: 1, indent: 60),
                  // パスワード変更
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.lock, color: Colors.orange, size: 24),
                    ),
                    title: const Text(
                      'パスワード変更',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    onTap: () => _showChangePasswordDialog(context),
                  ),
                  const Divider(height: 1, indent: 60),
                  // ログアウト
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.logout, color: Colors.red, size: 24),
                    ),
                    title: const Text(
                      'ログアウト',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    onTap: () => _logout(context),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _getStaffInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('staffs')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        
        // 名前を取得（nameフィールドまたはlastName+firstName）
        String name = data['name'] ?? '';
        if (name.isEmpty) {
          final lastName = data['lastName'] ?? '';
          final firstName = data['firstName'] ?? '';
          name = '$lastName $firstName'.trim();
        }
        
        return {
          ...data,
          'displayName': name,
        };
      }
    } catch (e) {
      debugPrint('Error getting staff info: $e');
    }
    return null;
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('パスワード変更'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '現在のパスワード',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新しいパスワード',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新しいパスワード（確認）',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final currentPassword = currentPasswordController.text;
                      final newPassword = newPasswordController.text;
                      final confirmPassword = confirmPasswordController.text;

                      if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('すべての項目を入力してください')),
                        );
                        return;
                      }

                      if (newPassword != confirmPassword) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('新しいパスワードが一致しません')),
                        );
                        return;
                      }

                      if (newPassword.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('パスワードは6文字以上で入力してください')),
                        );
                        return;
                      }

                      setState(() => isLoading = true);

                      try {
                        final user = FirebaseAuth.instance.currentUser!;
                        final credential = EmailAuthProvider.credential(
                          email: user.email!,
                          password: currentPassword,
                        );

                        // 再認証
                        await user.reauthenticateWithCredential(credential);
                        // パスワード更新
                        await user.updatePassword(newPassword);

                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('パスワードを変更しました'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } on FirebaseAuthException catch (e) {
                        String message = 'エラーが発生しました';
                        if (e.code == 'wrong-password') {
                          message = '現在のパスワードが正しくありません';
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(message), backgroundColor: Colors.red),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
                        );
                      } finally {
                        setState(() => isLoading = false);
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('変更'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(
      BuildContext context, String header, List<_MenuData> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            header,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;

              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: item.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(item.icon, color: item.color, size: 24),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      item.description,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios,
                        size: 16, color: Colors.grey),
                    onTap: () {
                      if (item.destination != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => item.destination!),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('この画面はまだ実装されていません')),
                        );
                      }
                    },
                  ),
                  if (!isLast) const Divider(height: 1, indent: 60),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _MenuData {
  final String title;
  final IconData icon;
  final Color color;
  final String description;
  final Widget? destination;

  _MenuData({
    required this.title,
    required this.icon,
    required this.color,
    required this.description,
    this.destination,
  });
}