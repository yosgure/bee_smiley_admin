import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyCsvImportScreen extends StatefulWidget {
  const FamilyCsvImportScreen({super.key});

  @override
  State<FamilyCsvImportScreen> createState() => _FamilyCsvImportScreenState();
}

class _FamilyCsvImportScreenState extends State<FamilyCsvImportScreen> {
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
        
        // CSV読み込み設定: 数値も文字列として読み込むように試みますが、
        // ライブラリの挙動によってはintになるため、後述の_formatPhoneで補正します。
        setState(() {
          _csvData = const CsvToListConverter(shouldParseNumbers: false).convert(csvString);
          _statusMessage = '${_csvData.length - 1} 件のデータを読み込みました。';
        });
      }
    } catch (e) {
      setState(() => _statusMessage = 'エラー: CSVを読み込めませんでした。\n$e');
    }
  }

  // 電話番号の0落ちを補正する関数
  String _formatPhone(dynamic value) {
    if (value == null) return '';
    String s = value.toString().trim();
    if (s.isEmpty) return '';
    
    // ハイフンがあればそのまま（文字列として正しく扱われている）
    if (s.contains('-')) return s;

    // 10桁または11桁未満で、先頭が0でない場合は0を付与
    // (例: 9012345678 -> 09012345678, 466123456 -> 0466123456)
    if (!s.startsWith('0')) {
      return '0$s';
    }
    return s;
  }

  Future<void> _registerAll() async {
    if (_csvData.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '登録処理中...';
    });

    int successCount = 0;
    int errorCount = 0;
    List<String> errorLogs = [];

    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(name: 'TempFamilyApp', options: Firebase.app().options);
    } catch (e) {
      tempApp = Firebase.app('TempFamilyApp');
    }

    final tempAuth = FirebaseAuth.instanceFor(app: tempApp!);
    final firestore = FirebaseFirestore.instance;

    // 1行目はヘッダーとしてスキップ
    for (int i = 1; i < _csvData.length; i++) {
      final row = _csvData[i];
      // 児童情報開始位置(14)までデータがあるかチェック
      if (row.length < 14) continue;

      try {
        // --- 保護者・基本情報 ---
        final lastName = row[0].toString().trim();
        final firstName = row[1].toString().trim();
        final lastNameKana = row[2].toString().trim();
        final firstNameKana = row[3].toString().trim();
        
        final loginId = row[4].toString().trim();
        final password = row[5].toString().trim();
        
        final relation = row[6].toString().trim();
        
        // ★電話番号の補正
        final phone = _formatPhone(row[7]);
        
        final email = row[8].toString().trim();
        final postalCode = row[9].toString().trim();
        final address = row[10].toString().trim();
        
        final emName = row[11].toString().trim();
        final emRelation = row[12].toString().trim();
        // ★緊急電話の補正
        final emPhone = _formatPhone(row[13]);

        if (loginId.isEmpty || password.isEmpty) {
          throw Exception('IDまたはパスワードが空です');
        }

        // --- 児童情報のパース (14列目以降を7列セットで読み込む) ---
        // 順序: 名前, ふりがな, 性別, 誕生日, 教室(New), クラス, アレルギー
        List<Map<String, dynamic>> children = [];
        
        int colIndex = 14;
        // 7項目セットなので、残り列数をチェック
        while (colIndex + 6 < row.length) { 
          final childName = row[colIndex].toString().trim();
          
          if (childName.isEmpty) {
            colIndex += 7; // 7列進める
            continue;
          }

          final childKana = row[colIndex + 1].toString().trim();
          final gender = row[colIndex + 2].toString().trim();
          String birthDate = row[colIndex + 3].toString().trim();
          // ★教室（例：ビースマイリー湘南藤沢教室）
          final classroom = row[colIndex + 4].toString().trim();
          // ★クラス/コース（例：プリスクール、キッズコース）
          final course = row[colIndex + 5].toString().trim();
          final allergy = row[colIndex + 6].toString().trim();

          // 日付補正
          birthDate = birthDate.replaceAll('-', '/').replaceAll('年', '/').replaceAll('月', '/').replaceAll('日', '');

          children.add({
            'firstName': childName,
            'firstNameKana': childKana,
            'gender': gender,
            'birthDate': birthDate,
            'classroom': classroom, // 教室名
            'course': course,       // コース名
            'allergy': allergy,
            'photoUrl': '',
          });

          colIndex += 7; // 次の児童へ
        }

        final authEmail = '$loginId$_fixedDomain';

        UserCredential userCredential = await tempAuth.createUserWithEmailAndPassword(
          email: authEmail,
          password: password,
        );

        await firestore.collection('families').add({
          'uid': userCredential.user!.uid,
          'loginId': loginId,
          'lastName': lastName,
          'firstName': firstName,
          'lastNameKana': lastNameKana,
          'firstNameKana': firstNameKana,
          'relation': relation,
          'phone': phone,
          'email': email,
          'postalCode': postalCode,
          'address': address,
          'emergencyName': emName,
          'emergencyRelation': emRelation,
          'emergencyPhone': emPhone,
          'children': children,
          'createdAt': FieldValue.serverTimestamp(),
          'isInitialPassword': true, 
        });

        successCount++;
      } catch (e) {
        errorCount++;
        final idLog = row.length > 4 ? row[4] : 'Unknown';
        errorLogs.add('行${i + 1} (ID: $idLog): $e');
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
      appBar: AppBar(
        title: const Text('保護者CSV一括登録'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('【CSVフォーマット】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('列の順序（14列目まで）:'),
                  const Text('1.姓, 2.名, 3.姓かな, 4.名かな, 5.ID, 6.PW, 7.続柄, 8.電話, 9.Email, 10.郵便番号, 11.住所, 12.緊急名, 13.緊急続柄, 14.緊急電話'),
                  
                  const Divider(height: 24),

                  const Text('【児童情報の書き方】', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  const Text('15列目から「7つの項目」を1セットとして、横に追加してください。'),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCell('児童1\n名前'),
                        _buildCell('児童1\nふりがな'),
                        _buildCell('児童1\n性別'),
                        _buildCell('児童1\n誕生日'),
                        _buildCell('児童1\n教室(New)'), // 追加
                        _buildCell('児童1\nクラス'),
                        _buildCell('児童1\nアレルギー'),
                        const Icon(Icons.arrow_right_alt),
                        _buildCell('児童2\n名前'),
                        _buildCell('...'),
                      ],
                    ),
                  ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                if (_csvData.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _registerAll,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('登録実行'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isLoading) 
              const Column(
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Firebaseに登録中...画面を閉じないでください'),
                ],
              ),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_statusMessage.isEmpty ? '待機中' : _statusMessage),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(String text) {
    return Container(
      margin: const EdgeInsets.only(right: 2),
      padding: const EdgeInsets.all(8),
      color: Colors.blue.shade50,
      child: Text(text, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
    );
  }
}