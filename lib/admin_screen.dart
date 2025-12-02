import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
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
import 'csv_export_screen.dart';
import 'notification_settings_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

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
                title: '保護者・児童',
                icon: Icons.family_restroom,
                color: Colors.blue,
                description: '児童情報と連絡先の管理',
                destination: const StudentManageScreen(),
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

          // 4. CSV管理
          _buildCsvSection(context),

          const SizedBox(height: 24),

          // 5. アカウント
          _buildAccountSection(context),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // CSV管理セクション
  Widget _buildCsvSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            'CSV管理',
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
              // インポート（登録）
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
                subtitle: const Text(
                  'CSVファイルから一括登録',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () => _showCsvImportMenu(context),
              ),
              const Divider(height: 1, indent: 60),
              // エクスポート（出力）
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
                subtitle: const Text(
                  'データをCSVファイルに出力',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () => _showCsvExportMenu(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // CSVインポートメニュー
  void _showCsvImportMenu(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    
    if (isWide) {
      // PC版: ダイアログ
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
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const StaffCsvImportScreen(),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.family_restroom, color: Colors.blue),
                  title: const Text('保護者・児童'),
                  subtitle: const Text('保護者と児童を一括登録'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const FamilyCsvImportScreen(),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.extension, color: Colors.orange),
                  title: const Text('教具'),
                  subtitle: const Text('教具マスタを一括登録'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const ToolCsvImportScreen(),
                    ));
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
      // スマホ版: ボトムシート
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
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
                    color: Colors.grey.shade300,
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
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const StaffCsvImportScreen(),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.family_restroom, color: Colors.blue),
                  title: const Text('保護者・児童'),
                  subtitle: const Text('保護者と児童を一括登録'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const FamilyCsvImportScreen(),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.extension, color: Colors.orange),
                  title: const Text('教具'),
                  subtitle: const Text('教具マスタを一括登録'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const ToolCsvImportScreen(),
                    ));
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

  // CSVエクスポートメニュー
  void _showCsvExportMenu(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    
    if (isWide) {
      // PC版: ダイアログ
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
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const StaffCsvExportScreen(),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.family_restroom, color: Colors.blue),
                  title: const Text('保護者・児童'),
                  subtitle: const Text('保護者・児童一覧をCSV出力'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const FamilyCsvExportScreen(),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.extension, color: Colors.orange),
                  title: const Text('教具'),
                  subtitle: const Text('教具マスタをCSV出力'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const ToolCsvExportScreen(),
                    ));
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
      // スマホ版: ボトムシート
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
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
                    color: Colors.grey.shade300,
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
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const StaffCsvExportScreen(),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.family_restroom, color: Colors.blue),
                  title: const Text('保護者・児童'),
                  subtitle: const Text('保護者・児童一覧をCSV出力'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const FamilyCsvExportScreen(),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.extension, color: Colors.orange),
                  title: const Text('教具'),
                  subtitle: const Text('教具マスタをCSV出力'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const ToolCsvExportScreen(),
                    ));
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
              // プロフィール写真 + 氏名
              ListTile(
                leading: GestureDetector(
                  onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Icon(Icons.person, size: 24, color: Colors.grey.shade400)
                            : null,
                      ),
                      if (_isUploadingPhoto)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
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
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Icons.camera_alt, size: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                title: const Text(
                  '氏名',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                subtitle: Text(
                  name.isNotEmpty ? name : '---',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
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
                  'ログインID',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                subtitle: Text(
                  loginId.isNotEmpty ? loginId : '---',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ),
              const Divider(height: 1, indent: 60),
              // 通知設定
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
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen(),
                  ));
                },
              ),
              const Divider(height: 1, indent: 60),
              // 通知設定
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
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotificationSettingsScreen()),
                  );
                },
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
          'docId': snap.docs.first.id,
          'displayName': name,
        };
      }
    } catch (e) {
      debugPrint('Error getting staff info: $e');
    }
    return null;
  }

  // プロフィール写真用の圧縮（小さめ：長辺300px、目標100KB）
  Future<Uint8List> _compressProfileImage(Uint8List bytes) async {
    final original = img.decodeImage(bytes);
    if (original == null) return bytes;

    const int targetSize = 100 * 1024; // 100KB
    const int maxDimension = 300; // 長辺300px
    
    // リサイズ
    img.Image resized;
    if (original.width > original.height) {
      resized = original.width > maxDimension 
          ? img.copyResize(original, width: maxDimension)
          : original;
    } else {
      resized = original.height > maxDimension 
          ? img.copyResize(original, height: maxDimension)
          : original;
    }

    // 品質を下げながら圧縮
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

      // Firestoreを更新
      await FirebaseFirestore.instance.collection('staffs').doc(docId).update({
        'photoUrl': photoUrl,
      });

      // 状態を更新
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