import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Web用の条件付きインポート
import 'csv_export_web.dart' if (dart.library.io) 'csv_export_stub.dart' as web_helper;

// ==========================================
// CSVエクスポート共通クラス
// ==========================================
class CsvExporter {
  
  // CSVダウンロード処理（プラットフォーム対応）
  static Future<void> downloadCsv(BuildContext context, String csvContent, String fileName) async {
    // BOM付きUTF-8でExcelで文字化けしないように
    final bytes = utf8.encode('\uFEFF$csvContent');
    
    if (kIsWeb) {
      // Webの場合
      web_helper.downloadCsvWeb(bytes, fileName);
    } else {
      // iOS/Androidの場合はファイルを共有
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      
      await Share.shareXFiles(
        [XFile(file.path)],
        text: fileName,
      );
    }
  }

  // 値をCSV用にエスケープ
  static String escapeCsvValue(dynamic value) {
    if (value == null) return '';
    String str = value.toString();
    // カンマ、改行、ダブルクォートを含む場合はクォートで囲む
    if (str.contains(',') || str.contains('\n') || str.contains('"')) {
      str = '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }
}

// ==========================================
// スタッフCSVエクスポート
// ==========================================
class StaffCsvExportScreen extends StatefulWidget {
  const StaffCsvExportScreen({super.key});

  @override
  State<StaffCsvExportScreen> createState() => _StaffCsvExportScreenState();
}

class _StaffCsvExportScreenState extends State<StaffCsvExportScreen> {
  bool _isLoading = false;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchCount();
  }

  Future<void> _fetchCount() async {
    final snap = await FirebaseFirestore.instance.collection('staffs').get();
    setState(() => _totalCount = snap.docs.length);
  }

  Future<void> _exportCsv() async {
    setState(() => _isLoading = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('staffs')
          .orderBy('name')
          .get();

      // ヘッダー行
      final headers = [
        'ログインID',
        '名前',
        'フリガナ',
        'メールアドレス',
        '役職',
        '担当教室',
        '権限',
        '登録日',
      ];

      final rows = <List<String>>[headers];

      for (var doc in snap.docs) {
        final d = doc.data();
        final classrooms = (d['classrooms'] as List?)?.join('、') ?? '';
        final createdAt = d['createdAt'] != null
            ? DateFormat('yyyy/MM/dd').format((d['createdAt'] as Timestamp).toDate())
            : '';

        rows.add([
          CsvExporter.escapeCsvValue(d['loginId']),
          CsvExporter.escapeCsvValue(d['name']),
          CsvExporter.escapeCsvValue(d['furigana']),
          CsvExporter.escapeCsvValue(d['email']),
          CsvExporter.escapeCsvValue(d['position']),
          CsvExporter.escapeCsvValue(classrooms),
          CsvExporter.escapeCsvValue(d['role']),
          CsvExporter.escapeCsvValue(createdAt),
        ]);
      }

      final csvContent = rows.map((row) => row.join(',')).join('\n');
      final fileName = 'スタッフ一覧_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      
      await CsvExporter.downloadCsv(context, csvContent, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${snap.docs.length}件のスタッフデータをエクスポートしました'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('スタッフCSVエクスポート'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.badge, size: 64, color: Colors.blue.shade300),
                      const SizedBox(height: 16),
                      const Text(
                        'スタッフデータをエクスポート',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '登録されている $_totalCount 件のスタッフ情報を\nCSVファイルとしてダウンロードします',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '出力項目: ログインID、名前、フリガナ、\nメールアドレス、役職、担当教室、権限、登録日',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading || _totalCount == 0 ? null : _exportCsv,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download),
                          label: Text(_isLoading ? 'エクスポート中...' : 'CSVをダウンロード'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 保護者・児童CSVエクスポート
// ==========================================
class FamilyCsvExportScreen extends StatefulWidget {
  const FamilyCsvExportScreen({super.key});

  @override
  State<FamilyCsvExportScreen> createState() => _FamilyCsvExportScreenState();
}

class _FamilyCsvExportScreenState extends State<FamilyCsvExportScreen> {
  bool _isLoading = false;
  int _familyCount = 0;
  int _childCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchCount();
  }

  Future<void> _fetchCount() async {
    final snap = await FirebaseFirestore.instance.collection('families').get();
    int children = 0;
    for (var doc in snap.docs) {
      final data = doc.data();
      final childList = data['children'] as List?;
      children += childList?.length ?? 0;
    }
    setState(() {
      _familyCount = snap.docs.length;
      _childCount = children;
    });
  }

  Future<void> _exportCsv() async {
    setState(() => _isLoading = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('families')
          .orderBy('lastNameKana')
          .get();

      // ヘッダー行
      final headers = [
        '保護者姓',
        '保護者名',
        '保護者姓カナ',
        '保護者名カナ',
        'メールアドレス',
        '電話番号',
        '児童名',
        '児童カナ',
        '生年月日',
        '性別',
        '教室',
      ];

      final rows = <List<String>>[headers];

      for (var doc in snap.docs) {
        final d = doc.data();
        final children = List<Map<String, dynamic>>.from(d['children'] ?? []);

        if (children.isEmpty) {
          // 児童がいない場合は保護者情報のみ
          rows.add([
            CsvExporter.escapeCsvValue(d['lastName']),
            CsvExporter.escapeCsvValue(d['firstName']),
            CsvExporter.escapeCsvValue(d['lastNameKana']),
            CsvExporter.escapeCsvValue(d['firstNameKana']),
            CsvExporter.escapeCsvValue(d['email']),
            CsvExporter.escapeCsvValue(d['phone']),
            '', '', '', '', '',
          ]);
        } else {
          // 児童ごとに1行
          for (var child in children) {
            final birthDate = child['birthDate'] != null
                ? DateFormat('yyyy/MM/dd').format((child['birthDate'] as Timestamp).toDate())
                : '';

            rows.add([
              CsvExporter.escapeCsvValue(d['lastName']),
              CsvExporter.escapeCsvValue(d['firstName']),
              CsvExporter.escapeCsvValue(d['lastNameKana']),
              CsvExporter.escapeCsvValue(d['firstNameKana']),
              CsvExporter.escapeCsvValue(d['email']),
              CsvExporter.escapeCsvValue(d['phone']),
              CsvExporter.escapeCsvValue(child['name']),
              CsvExporter.escapeCsvValue(child['nameKana']),
              CsvExporter.escapeCsvValue(birthDate),
              CsvExporter.escapeCsvValue(child['gender']),
              CsvExporter.escapeCsvValue(child['classroom']),
            ]);
          }
        }
      }

      final csvContent = rows.map((row) => row.join(',')).join('\n');
      final fileName = '保護者児童一覧_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      
      await CsvExporter.downloadCsv(context, csvContent, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_familyCount世帯・$_childCount名の児童データをエクスポートしました'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('保護者・児童CSVエクスポート'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.family_restroom, size: 64, color: Colors.blue.shade300),
                      const SizedBox(height: 16),
                      const Text(
                        '保護者・児童データをエクスポート',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_familyCount 世帯・$_childCount 名の児童情報を\nCSVファイルとしてダウンロードします',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '出力項目: 保護者姓名、カナ、メール、電話、\n児童名、カナ、生年月日、性別、教室',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading || _familyCount == 0 ? null : _exportCsv,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download),
                          label: Text(_isLoading ? 'エクスポート中...' : 'CSVをダウンロード'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 教具CSVエクスポート
// ==========================================
class ToolCsvExportScreen extends StatefulWidget {
  const ToolCsvExportScreen({super.key});

  @override
  State<ToolCsvExportScreen> createState() => _ToolCsvExportScreenState();
}

class _ToolCsvExportScreenState extends State<ToolCsvExportScreen> {
  bool _isLoading = false;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchCount();
  }

  Future<void> _fetchCount() async {
    final snap = await FirebaseFirestore.instance.collection('tools').get();
    setState(() => _totalCount = snap.docs.length);
  }

  Future<void> _exportCsv() async {
    setState(() => _isLoading = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('tools')
          .orderBy('category')
          .get();

      // ヘッダー行
      final headers = [
        '教具名',
        'カテゴリ',
        '説明',
        '対象年齢（下限）',
        '対象年齢（上限）',
      ];

      final rows = <List<String>>[headers];

      for (var doc in snap.docs) {
        final d = doc.data();

        rows.add([
          CsvExporter.escapeCsvValue(d['name']),
          CsvExporter.escapeCsvValue(d['category']),
          CsvExporter.escapeCsvValue(d['description']),
          CsvExporter.escapeCsvValue(d['ageMin']),
          CsvExporter.escapeCsvValue(d['ageMax']),
        ]);
      }

      final csvContent = rows.map((row) => row.join(',')).join('\n');
      final fileName = '教具マスタ_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      
      await CsvExporter.downloadCsv(context, csvContent, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${snap.docs.length}件の教具データをエクスポートしました'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教具CSVエクスポート'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.extension, size: 64, color: Colors.orange.shade300),
                      const SizedBox(height: 16),
                      const Text(
                        '教具マスタをエクスポート',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '登録されている $_totalCount 件の教具情報を\nCSVファイルとしてダウンロードします',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '出力項目: 教具名、カテゴリ、説明、対象年齢',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading || _totalCount == 0 ? null : _exportCsv,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download),
                          label: Text(_isLoading ? 'エクスポート中...' : 'CSVをダウンロード'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}