import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StaffCsvImportScreen extends StatefulWidget {
  const StaffCsvImportScreen({super.key});

  @override
  State<StaffCsvImportScreen> createState() => _StaffCsvImportScreenState();
}

class _StaffCsvImportScreenState extends State<StaffCsvImportScreen> {
  List<List<dynamic>> _csvData = [];
  bool _isLoading = false;
  String _statusMessage = '';
  
  static const String _fixedDomain = '@bee-smiley.com';

  Future<void> _pickCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null) {
        final bytes = result.files.first.bytes!;
        final csvString = utf8.decode(bytes);
        
        setState(() {
          _csvData = const CsvToListConverter(shouldParseNumbers: false).convert(csvString);
          _statusMessage = '${_csvData.length - 1} 件のデータを読み込みました。\n「登録開始」を押してください。';
        });
      }
    } catch (e) {
      setState(() => _statusMessage = 'エラー: CSVを読み込めませんでした。\n$e');
    }
  }

  String _formatPhone(dynamic value) {
    if (value == null) return '';
    String s = value.toString().trim();
    if (s.isEmpty) return '';
    if (s.contains('-')) return s;
    if (!s.startsWith('0') && (s.length == 9 || s.length == 10)) {
      return '0$s';
    }
    return s;
  }

  Future<void> _registerAll() async {
    if (_csvData.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '登録処理中... アプリを閉じないでください。';
    });

    int successCount = 0;
    int errorCount = 0;
    List<String> errorLogs = [];

    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(
        name: 'TemporaryRegisterApp',
        options: Firebase.app().options,
      );
    } catch (e) {
      tempApp = Firebase.app('TemporaryRegisterApp');
    }

    final tempAuth = FirebaseAuth.instanceFor(app: tempApp!);
    final firestore = FirebaseFirestore.instance;

    for (int i = 1; i < _csvData.length; i++) {
      final row = _csvData[i];
      if (row.length < 4) {
        errorCount++;
        continue;
      }

      final String name = row[0].toString().trim();
      final String furigana = row.length > 1 ? row[1].toString().trim() : '';
      final String loginId = row[2].toString().trim();
      final String password = row[3].toString().trim();
      
      final String phone = row.length > 4 ? _formatPhone(row[4]) : '';
      
      final String contactEmail = row.length > 5 ? row[5].toString().trim() : '';
      final String role = row.length > 6 ? row[6].toString().trim() : 'スタッフ';
      
      final String rawClassrooms = row.length > 7 ? row[7].toString() : '';
      final List<String> classrooms = rawClassrooms
          .replaceAll('、', '/')
          .split('/')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final String authEmail = '$loginId$_fixedDomain';

      try {
        UserCredential userCredential = await tempAuth.createUserWithEmailAndPassword(
          email: authEmail,
          password: password,
        );

        await firestore.collection('staffs').add({
          'uid': userCredential.user!.uid,
          'loginId': loginId,
          'name': name,
          'furigana': furigana,
          'phone': phone,
          'email': contactEmail,
          'role': role,
          'classrooms': classrooms,
          'createdAt': FieldValue.serverTimestamp(),
          'isInitialPassword': true, // ★ここを追加
        });

        successCount++;
      } catch (e) {
        errorCount++;
        errorLogs.add('$name ($loginId): $e');
      }
    }

    await tempApp.delete();

    setState(() {
      _isLoading = false;
      _statusMessage = '完了！\n成功: $successCount 件\n失敗: $errorCount 件\n\n${errorLogs.join('\n')}';
      if (successCount > 0) _csvData = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('スタッフCSV一括登録')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('【CSVファイルのルール】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 12),
                  Text('・文字コード: UTF-8'),
                  Text('・1行目: ヘッダー (無視されます)'),
                  Text('・列の順番: A:氏名, B:ふりがな, C:ID, D:PW, E:電話, F:メール, G:役職, H:教室'),
                  SizedBox(height: 12),
                  Text('【パスワードについて】', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('D列のパスワードが初期設定されます。「次回ログイン時に変更」フラグが自動でONになります。'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _pickCsv,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('CSVを選択'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  ),
                ),
                const SizedBox(width: 16),
                if (_csvData.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _registerAll,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('登録開始'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            
            if (_isLoading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            
            Expanded(
              child: SingleChildScrollView(
                child: Text(_statusMessage, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}