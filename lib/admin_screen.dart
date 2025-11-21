import 'package:flutter/material.dart';
import 'student_manage_screen.dart';
import 'tool_master_screen.dart';
import 'generic_master_screen.dart'; // 汎用マスタを使う場合に使用
import 'staff_manage_screen.dart';
import 'non_cognitive_skill_master_screen.dart';
import 'sensitive_period_master_screen.dart';
import 'classroom_master_screen.dart';
import 'staff_csv_import_screen.dart';
import 'family_csv_import_screen.dart';
import 'tool_csv_import_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理メニュー'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7), // 背景は薄いグレー（iOS設定風）
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
                color: Colors.green, // ★ここにあったエラーを修正しました
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

          // 下部の余白
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // セクションごとの塊を作るウィジェット
  Widget _buildSettingsSection(
      BuildContext context, String header, List<_MenuData> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ヘッダーテキスト
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
        // リスト本体（白い角丸の箱に入れる）
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
                      // 画面遷移処理
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
                  // 最後以外は区切り線を入れる
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

// メニューデータを保持するクラス
class _MenuData {
  final String title;
  final IconData icon;
  final Color color;
  final String description;
  final Widget? destination; // 遷移先の画面ウィジェット

  _MenuData({
    required this.title,
    required this.icon,
    required this.color,
    required this.description,
    this.destination,
  });
}