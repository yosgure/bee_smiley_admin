import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:cloud_functions/cloud_functions.dart';
import 'attendance_screen.dart';

// 各画面のインポート
import 'student_manage_screen.dart';
import 'tool_master_screen.dart';
import 'generic_master_screen.dart';
import 'staff_manage_screen.dart';
import 'non_cognitive_skill_master_screen.dart';
import 'classroom_master_screen.dart';
import 'staff_csv_import_screen.dart';
import 'family_csv_import_screen.dart';
import 'tool_csv_import_screen.dart';
import 'csv_export_screen.dart';
import 'notification_settings_screen.dart';
import 'ai_command_manage_screen.dart';
import 'hug_mapping_screen.dart';
import 'app_theme.dart';
import 'main.dart' show themeNotifier, setThemeMode;

class AdminScreen extends StatefulWidget {
  // Web版で画面を差し替えるためのコールバック
  final void Function(Widget screen)? onOpenWebScreen;
  final VoidCallback? onCloseWebScreen;

  const AdminScreen({
    super.key,
    this.onOpenWebScreen,
     this.onCloseWebScreen,
  });

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _staffData;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadStaffInfo();
  }

  Future<void> _loadStaffInfo() async {
    final data = await _getStaffInfo();
    if (mounted) {
      setState(() => _staffData = data);
    }
  }

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

void _navigateTo(BuildContext context, Widget screen) {
  final isWide = MediaQuery.of(context).size.width >= AppBreakpoints.tablet;
  
  if (isWide && widget.onOpenWebScreen != null) {
    // Web版: onBackを注入した画面を渡す
    Widget screenWithBack;
    
    if (screen is StaffManageScreen) {
      screenWithBack = StaffManageScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is StudentManageScreen) {
      screenWithBack = StudentManageScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is ToolMasterScreen) {
      screenWithBack = ToolMasterScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is NonCognitiveSkillMasterScreen) {
      screenWithBack = NonCognitiveSkillMasterScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is ClassroomMasterScreen) {
      screenWithBack = ClassroomMasterScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is NotificationSettingsScreen) {
      screenWithBack = NotificationSettingsScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is StaffCsvImportScreen) {
      screenWithBack = StaffCsvImportScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is FamilyCsvImportScreen) {
      screenWithBack = FamilyCsvImportScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is ToolCsvImportScreen) {
      screenWithBack = ToolCsvImportScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is StaffCsvExportScreen) {
      screenWithBack = StaffCsvExportScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is FamilyCsvExportScreen) {
      screenWithBack = FamilyCsvExportScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is ToolCsvExportScreen) {
      screenWithBack = ToolCsvExportScreen(onBack: widget.onCloseWebScreen);
    } else if (screen is AiCommandManageScreen) {
      screenWithBack = AiCommandManageScreen(onBack: widget.onCloseWebScreen);
    } else {
      screenWithBack = screen;
    }
    
    widget.onOpenWebScreen!(screenWithBack);
  } else {
    // Mobile: 通常遷移
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

  // 入退室管理用 - 常に全画面遷移
  void _navigateFullScreen(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理メニュー'),
        centerTitle: true,
        backgroundColor: context.colors.cardBg,
        elevation: 0,
      ),
      backgroundColor: context.colors.scaffoldBgAlt,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // マイグレーションボタン（一時的）
          Card(
            color: Colors.orange.shade800,
            child: ListTile(
              leading: const Icon(Icons.update, color: Colors.white),
              title: const Text('教室データ移行', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('classroom → classrooms 配列に変換', style: TextStyle(color: Colors.white70, fontSize: 12)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('データ移行を実行しますか？'),
                    content: const Text('全familiesのclassroomフィールドをclassrooms配列に変換します。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('実行')),
                    ],
                  ),
                );
                if (confirm != true) return;
                try {
                  final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast1')
                      .httpsCallable('migrateClassroomToClassrooms')
                      .call();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('移行完了: ${result.data}')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 16),
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
                title: '保護者・児童',
                icon: Icons.family_restroom,
                color: Colors.blue,
                description: '児童情報と連絡先の管理',
                destination: const StudentManageScreen(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSettingsSection(
            context,
            '保育・教育の管理',
            [
              _MenuData(
                title: '教具マスタ',
                icon: Icons.extension,
                color: AppColors.accent,
                description: 'アセスメントで使う教具一覧',
                destination: const ToolMasterScreen(),
              ),
              _MenuData(
                title: '非認知能力',
                icon: Icons.psychology,
                color: AppColors.accent,
                description: '月間サマリの評価項目',
                destination: const NonCognitiveSkillMasterScreen(),
              ),
              _MenuData(
                title: 'AI相談コマンド',
                icon: Icons.auto_awesome,
                color: context.colors.aiAccent,
                description: '/コマンドの追加・編集',
                destination: const AiCommandManageScreen(),
              ),
              _MenuData(
                title: 'hug連携設定',
                icon: Icons.sync_alt,
                color: const Color(0xFF0891B2),
                description: '児童・スタッフのhug IDマッピング',
                destination: const HugMappingScreen(),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
SizedBox(height: 8),
Container(
  decoration: BoxDecoration(
    color: context.colors.cardBg,
    borderRadius: BorderRadius.circular(10),
    boxShadow: [
      BoxShadow(
        color: context.colors.shadow,
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ],
  ),
  child: ListTile(
    leading: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.how_to_reg, color: Colors.green, size: 24),
    ),
    title: const Text(
      '入退室管理',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
    subtitle: Text(
      'タブレット用の入退室画面',
      style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
    ),
    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: context.colors.iconMuted),
    onTap: () {
      _navigateFullScreen(context, const AttendanceClassroomSelectScreen());
    },
  ),
),
          const SizedBox(height: 24),
          _buildCsvSection(context),
          const SizedBox(height: 24),
          _buildThemeSection(context),
          const SizedBox(height: 24),
          _buildAccountSection(context),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCsvSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            'CSV管理',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: context.colors.shadow,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.upload_file, color: Colors.teal, size: 24),
                ),
                title: const Text(
                  'インポート（登録）',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'CSVファイルから一括登録',
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: context.colors.iconMuted),
                onTap: () => _showCsvImportMenu(context),
              ),
              const Divider(height: 1, indent: 60),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.download, color: Colors.indigo, size: 24),
                ),
                title: const Text(
                  'エクスポート（出力）',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'データをCSVファイルに出力',
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: context.colors.iconMuted),
                onTap: () => _showCsvExportMenu(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showCsvImportMenu(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= AppBreakpoints.tablet;

    if (isWide) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CSVインポート'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.badge, color: Colors.blue),
                  title: const Text('スタッフ'),
                  subtitle: const Text('先生・職員を一括登録'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const StaffCsvImportScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.family_restroom, color: Colors.blue),
                  title: const Text('保護者・児童'),
                  subtitle: const Text('保護者と児童を一括登録'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const FamilyCsvImportScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.extension, color: AppColors.accent),
                  title: const Text('教具'),
                  subtitle: const Text('教具マスタを一括登録'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const ToolCsvImportScreen());
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: context.colors.dialogBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.colors.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'CSVインポート',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.badge, color: Colors.blue),
                  title: const Text('スタッフ'),
                  subtitle: const Text('先生・職員を一括登録'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const StaffCsvImportScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.family_restroom, color: Colors.blue),
                  title: const Text('保護者・児童'),
                  subtitle: const Text('保護者と児童を一括登録'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const FamilyCsvImportScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.extension, color: AppColors.accent),
                  title: const Text('教具'),
                  subtitle: const Text('教具マスタを一括登録'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const ToolCsvImportScreen());
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _showCsvExportMenu(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= AppBreakpoints.tablet;

    if (isWide) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CSVエクスポート'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.badge, color: Colors.blue),
                  title: const Text('スタッフ'),
                  subtitle: const Text('スタッフ一覧をCSV出力'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const StaffCsvExportScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.family_restroom, color: Colors.blue),
                  title: const Text('保護者・児童'),
                  subtitle: const Text('保護者・児童一覧をCSV出力'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const FamilyCsvExportScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.extension, color: AppColors.accent),
                  title: const Text('教具'),
                  subtitle: const Text('教具マスタをCSV出力'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const ToolCsvExportScreen());
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: context.colors.dialogBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.colors.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'CSVエクスポート',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.badge, color: Colors.blue),
                  title: const Text('スタッフ'),
                  subtitle: const Text('スタッフ一覧をCSV出力'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const StaffCsvExportScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.family_restroom, color: Colors.blue),
                  title: const Text('保護者・児童'),
                  subtitle: const Text('保護者・児童一覧をCSV出力'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const FamilyCsvExportScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.extension, color: AppColors.accent),
                  title: const Text('教具'),
                  subtitle: const Text('教具マスタをCSV出力'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(context, const ToolCsvExportScreen());
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildThemeSection(BuildContext context) {
    final currentMode = themeNotifier.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            '表示設定',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: context.colors.shadow,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                context.isDark ? Icons.dark_mode : Icons.light_mode,
                color: Colors.deepPurple,
                size: 24,
              ),
            ),
            title: const Text(
              'テーマ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              currentMode == ThemeMode.system
                  ? 'システム設定に連動'
                  : currentMode == ThemeMode.dark
                      ? 'ダーク'
                      : 'ライト',
              style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
            ),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 18)),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_brightness, size: 18)),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 18)),
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
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    final name = _staffData?['displayName'] ?? '';
    final loginId = _staffData?['loginId'] ?? '';
    final photoUrl = _staffData?['photoUrl'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            'アカウント',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: context.colors.shadow,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            children: [
              ListTile(
                leading: GestureDetector(
                  onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: context.colors.borderLight,
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Icon(Icons.person, size: 24, color: context.colors.iconMuted)
                            : null,
                      ),
                      if (_isUploadingPhoto)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: context.colors.cardBg, strokeWidth: 2),
                              ),
                            ),
                          ),
                        )
                      else
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: context.colors.cardBg, width: 1.5),
                            ),
                            child: const Icon(Icons.camera_alt, size: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                title: Text(
                  '氏名',
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                ),
                subtitle: Text(
                  name.isNotEmpty ? name : '---',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
                ),
                trailing: photoUrl != null && photoUrl.isNotEmpty
                    ? TextButton(
                        onPressed: _isUploadingPhoto ? null : _deletePhoto,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(50, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('削除', style: TextStyle(color: Colors.red, fontSize: 12)),
                      )
                    : null,
              ),
              const Divider(height: 1, indent: 60),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.badge, color: Colors.green, size: 24),
                ),
                title: Text(
                  'ログインID',
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                ),
                subtitle: Text(
                  loginId.isNotEmpty ? loginId : '---',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
                ),
              ),
              const Divider(height: 1, indent: 60),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.notifications_outlined, color: Colors.blue, size: 24),
                ),
                title: const Text(
                  '通知設定',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: context.colors.iconMuted),
                onTap: () {
                  _navigateTo(context, const NotificationSettingsScreen());
                },
              ),
              const Divider(height: 1, indent: 60),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.lock, color: AppColors.accent, size: 24),
                ),
                title: const Text(
                  'パスワード変更',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: context.colors.iconMuted),
                onTap: () => _showChangePasswordDialog(context),
              ),
              const Divider(height: 1, indent: 60),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                ),
                onTap: () => _logout(context),
              ),
            ],
          ),
        ),
      ],
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
        String name = data['name'] ?? '';
        if (name.isEmpty) {
          final lastName = data['lastName'] ?? '';
          final firstName = data['firstName'] ?? '';
          name = '$lastName $firstName'.trim();
        }
        return {
          ...data,
          'docId': snap.docs.first.id,
          'displayName': name,
        };
      }
    } catch (e) {
      debugPrint('Error getting staff info: $e');
    }
    return null;
  }

  Future<Uint8List> _compressProfileImage(Uint8List bytes) async {
    final original = img.decodeImage(bytes);
    if (original == null) return bytes;
    const int targetSize = 100 * 1024;
    const int maxDimension = 300;
    img.Image resized;
    if (original.width > original.height) {
      resized = original.width > maxDimension ? img.copyResize(original, width: maxDimension) : original;
    } else {
      resized = original.height > maxDimension ? img.copyResize(original, height: maxDimension) : original;
    }
    for (int quality = 85; quality >= 40; quality -= 10) {
      final compressed = img.encodeJpg(resized, quality: quality);
      if (compressed.length <= targetSize) {
        return Uint8List.fromList(compressed);
      }
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 40));
  }

  Future<void> _pickAndUploadPhoto() async {
    final docId = _staffData?['docId'];
    if (docId == null) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _isUploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final compressed = await _compressProfileImage(bytes);
      final user = FirebaseAuth.instance.currentUser;
      final fileName = '${user!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child('staff_photos/$fileName');
      await ref.putData(compressed, SettableMetadata(contentType: 'image/jpeg'));
      final photoUrl = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('staffs').doc(docId).update({
        'photoUrl': photoUrl,
      });
      await _loadStaffInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロフィール写真を更新しました'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _deletePhoto() async {
    final docId = _staffData?['docId'];
    if (docId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写真を削除'),
        content: const Text('プロフィール写真を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isUploadingPhoto = true);
    try {
      await FirebaseFirestore.instance.collection('staffs').doc(docId).update({
        'photoUrl': FieldValue.delete(),
      });
      await _loadStaffInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('写真を削除しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
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
                decoration: InputDecoration(
                  labelText: '現在のパスワード',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '新しいパスワード',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
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
                        await user.reauthenticateWithCredential(credential);
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

  Widget _buildSettingsSection(BuildContext context, String header, List<_MenuData> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            header,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: context.colors.shadow,
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      item.description,
                      style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: context.colors.iconMuted),
                    onTap: () {
                      if (item.destination == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('この画面はまだ実装されていません')),
                        );
                        return;
                      }
                      _navigateTo(context, item.destination!);
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