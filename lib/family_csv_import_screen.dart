import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class FamilyCsvImportScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const FamilyCsvImportScreen({super.key, this.onBack});

  @override
  State<FamilyCsvImportScreen> createState() => _FamilyCsvImportScreenState();
}

class _FamilyCsvImportScreenState extends State<FamilyCsvImportScreen> {
  List<List<dynamic>> _csvData = [];
  bool _isLoading = false;
  String _statusMessage = '';
  
  // インポートモード
  int _importMode = 0; // 0: 新規登録（従来形式）, 1: 新規登録（エクスポート形式）, 2: 更新
  
  static const String _fixedDomain = '@bee-smiley.com';
  // 初期パスワードはCloud Functions (Secret Manager) で管理

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
    
    if (s.contains('-')) return s;

    if (!s.startsWith('0')) {
      return '0$s';
    }
    return s;
  }

  // ============================================
  // 新規登録モード（従来のフォーマット）
  // ============================================
  Future<void> _registerNewAll() async {
    if (_csvData.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '登録処理中...';
    });

    int successCount = 0;
    int errorCount = 0;
    List<String> errorLogs = [];

    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

    for (int i = 1; i < _csvData.length; i++) {
      final row = _csvData[i];
      if (row.length < 14) continue;

      try {
        final lastName = row[0].toString().trim();
        final firstName = row[1].toString().trim();
        final lastNameKana = row[2].toString().trim();
        final firstNameKana = row[3].toString().trim();

        final loginId = row[4].toString().trim();

        final relation = row[6].toString().trim();
        final phone = _formatPhone(row[7]);
        final email = row[8].toString().trim();
        final postalCode = row[9].toString().trim();
        final address = row[10].toString().trim();

        final emName = row[11].toString().trim();
        final emRelation = row[12].toString().trim();
        final emPhone = _formatPhone(row[13]);

        if (loginId.isEmpty) {
          throw Exception('ログインIDが空です');
        }

        List<Map<String, dynamic>> children = [];

        int colIndex = 14;
        while (colIndex + 6 < row.length) {
          final childName = row[colIndex].toString().trim();

          if (childName.isEmpty) {
            colIndex += 7;
            continue;
          }

          final childKana = row[colIndex + 1].toString().trim();
          final gender = row[colIndex + 2].toString().trim();
          String birthDate = row[colIndex + 3].toString().trim();
          final classroom = row[colIndex + 4].toString().trim();
          final course = row[colIndex + 5].toString().trim();
          final allergy = row[colIndex + 6].toString().trim();

          birthDate = birthDate.replaceAll('-', '/').replaceAll('年', '/').replaceAll('月', '/').replaceAll('日', '');

          children.add({
            'firstName': childName,
            'firstNameKana': childKana,
            'gender': gender,
            'birthDate': birthDate,
            'classroom': classroom,
            'course': course,
            'allergy': allergy,
            'photoUrl': '',
          });

          colIndex += 7;
        }

        // Cloud Functions経由でアカウント作成（パスワードはSecret Managerで管理）
        final result = await functions.httpsCallable('createParentAccount').call({
          'loginId': loginId,
          'familyData': {
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
          },
        });

        if (result.data['success'] == true) {
          successCount++;
        } else {
          throw Exception(result.data['message'] ?? '不明なエラー');
        }
      } catch (e) {
        errorCount++;
        final idLog = row.length > 4 ? row[4] : 'Unknown';
        errorLogs.add('行${i + 1} (ID: $idLog): $e');
      }
    }

    setState(() {
      _isLoading = false;
      _statusMessage = '完了！\n成功: $successCount 件\n失敗: $errorCount 件\n\n${errorLogs.join('\n')}';
      if (successCount > 0) _csvData = [];
    });
  }

  // ============================================
  // 新規登録モード（エクスポート形式 - パスワード自動設定）
  // ============================================
  Future<void> _registerFromExportCsv() async {
    if (_csvData.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '登録処理中...';
    });

    int successCount = 0;
    int errorCount = 0;
    List<String> errorLogs = [];

    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

    // エクスポート形式のCSV列順序:
    // 0: ログインID, 1: 保護者姓, 2: 保護者名, 3: 保護者姓カナ, 4: 保護者名カナ,
    // 5: 続柄, 6: 電話番号, 7: メールアドレス, 8: 郵便番号, 9: 住所,
    // 10: 緊急連絡先氏名, 11: 緊急連絡先続柄, 12: 緊急連絡先電話, 13: アカウント状態,
    // 14: 児童名, 15: 児童カナ, 16: 性別, 17: 生年月日, 18: 教室, 19: コース, 20: アレルギー

    // 同じログインIDの行をグループ化（複数児童対応）
    Map<String, List<List<dynamic>>> groupedByLoginId = {};

    for (int i = 1; i < _csvData.length; i++) {
      final row = _csvData[i];
      if (row.isEmpty) continue;

      final loginId = row[0].toString().trim();
      if (loginId.isEmpty) continue;

      groupedByLoginId.putIfAbsent(loginId, () => []);
      groupedByLoginId[loginId]!.add(row);
    }

    // ログインIDごとに処理
    for (var entry in groupedByLoginId.entries) {
      final loginId = entry.key;
      final rows = entry.value;

      try {
        final firstRow = rows.first;

        // 保護者情報を取得（最初の行から）
        final lastName = firstRow[1].toString().trim();
        final firstName = firstRow[2].toString().trim();
        final lastNameKana = firstRow[3].toString().trim();
        final firstNameKana = firstRow[4].toString().trim();
        final relation = firstRow[5].toString().trim();
        final phone = _formatPhone(firstRow[6]);
        final email = firstRow[7].toString().trim();
        final postalCode = firstRow[8].toString().trim();
        final address = firstRow[9].toString().trim();
        final emName = firstRow[10].toString().trim();
        final emRelation = firstRow[11].toString().trim();
        final emPhone = _formatPhone(firstRow[12]);

        // 全行から児童情報を収集
        List<Map<String, dynamic>> children = [];
        for (var row in rows) {
          if (row.length < 15) continue;

          final childName = row[14].toString().trim();
          if (childName.isEmpty) continue;

          String birthDate = row.length > 17 ? row[17].toString().trim() : '';
          birthDate = birthDate.replaceAll('-', '/').replaceAll('年', '/').replaceAll('月', '/').replaceAll('日', '');

          children.add({
            'firstName': childName,
            'firstNameKana': row.length > 15 ? row[15].toString().trim() : '',
            'gender': row.length > 16 ? row[16].toString().trim() : '',
            'birthDate': birthDate,
            'classroom': row.length > 18 ? row[18].toString().trim() : '',
            'course': row.length > 19 ? row[19].toString().trim() : '',
            'allergy': row.length > 20 ? row[20].toString().trim() : '',
            'photoUrl': '',
          });
        }

        // Cloud Functions経由でアカウント作成（パスワードはSecret Managerで管理）
        final result = await functions.httpsCallable('createParentAccount').call({
          'loginId': loginId,
          'familyData': {
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
          },
        });

        if (result.data['success'] == true) {
          successCount++;
        } else {
          throw Exception(result.data['message'] ?? '不明なエラー');
        }

      } catch (e) {
        errorCount++;
        errorLogs.add('ID: $loginId - $e');
      }
    }

    setState(() {
      _isLoading = false;
      _statusMessage = '完了！\n成功: $successCount 件\n失敗: $errorCount 件\n\n${errorLogs.join('\n')}';
      if (successCount > 0) _csvData = [];
    });
  }

  // ============================================
  // 更新モード（エクスポート形式）
  // ============================================
  Future<void> _updateFromExportCsv() async {
    if (_csvData.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '更新処理中...';
    });

    int updateCount = 0;
    int skipCount = 0;
    int errorCount = 0;
    List<String> logs = [];

    final firestore = FirebaseFirestore.instance;

    // エクスポート形式のCSV列順序:
    // 0: ログインID, 1: 保護者姓, 2: 保護者名, 3: 保護者姓カナ, 4: 保護者名カナ,
    // 5: 続柄, 6: 電話番号, 7: メールアドレス, 8: 郵便番号, 9: 住所,
    // 10: 緊急連絡先氏名, 11: 緊急連絡先続柄, 12: 緊急連絡先電話, 13: アカウント状態,
    // 14: 児童名, 15: 児童カナ, 16: 性別, 17: 生年月日, 18: 教室, 19: コース, 20: アレルギー

    // 同じログインIDの行をグループ化（複数児童対応）
    Map<String, List<List<dynamic>>> groupedByLoginId = {};
    
    for (int i = 1; i < _csvData.length; i++) {
      final row = _csvData[i];
      if (row.isEmpty) continue;
      
      final loginId = row[0].toString().trim();
      if (loginId.isEmpty) continue;
      
      groupedByLoginId.putIfAbsent(loginId, () => []);
      groupedByLoginId[loginId]!.add(row);
    }

    // ログインIDごとに処理
    for (var entry in groupedByLoginId.entries) {
      final loginId = entry.key;
      final rows = entry.value;
      
      try {
        // 既存のドキュメントを検索
        final querySnapshot = await firestore
            .collection('families')
            .where('loginId', isEqualTo: loginId)
            .limit(1)
            .get();

        if (querySnapshot.docs.isEmpty) {
          skipCount++;
          logs.add('スキップ (ID: $loginId): 既存データが見つかりません');
          continue;
        }

        final docId = querySnapshot.docs.first.id;
        final firstRow = rows.first;

        // 保護者情報を取得（最初の行から）
        final lastName = firstRow[1].toString().trim();
        final firstName = firstRow[2].toString().trim();
        final lastNameKana = firstRow[3].toString().trim();
        final firstNameKana = firstRow[4].toString().trim();
        final relation = firstRow[5].toString().trim();
        final phone = _formatPhone(firstRow[6]);
        final email = firstRow[7].toString().trim();
        final postalCode = firstRow[8].toString().trim();
        final address = firstRow[9].toString().trim();
        final emName = firstRow[10].toString().trim();
        final emRelation = firstRow[11].toString().trim();
        final emPhone = _formatPhone(firstRow[12]);

        // 全行から児童情報を収集
        List<Map<String, dynamic>> children = [];
        for (var row in rows) {
          if (row.length < 15) continue;
          
          final childName = row[14].toString().trim();
          if (childName.isEmpty) continue;

          String birthDate = row.length > 17 ? row[17].toString().trim() : '';
          birthDate = birthDate.replaceAll('-', '/').replaceAll('年', '/').replaceAll('月', '/').replaceAll('日', '');

          children.add({
            'firstName': childName,
            'firstNameKana': row.length > 15 ? row[15].toString().trim() : '',
            'gender': row.length > 16 ? row[16].toString().trim() : '',
            'birthDate': birthDate,
            'classroom': row.length > 18 ? row[18].toString().trim() : '',
            'course': row.length > 19 ? row[19].toString().trim() : '',
            'allergy': row.length > 20 ? row[20].toString().trim() : '',
            'photoUrl': '',
          });
        }

        // ドキュメントを更新
        await firestore.collection('families').doc(docId).update({
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
          'updatedAt': FieldValue.serverTimestamp(),
        });

        updateCount++;
        logs.add('更新成功 (ID: $loginId): 児童${children.length}名');

      } catch (e) {
        errorCount++;
        logs.add('エラー (ID: $loginId): $e');
      }
    }

    setState(() {
      _isLoading = false;
      _statusMessage = '完了！\n更新: $updateCount 件\nスキップ: $skipCount 件\nエラー: $errorCount 件\n\n${logs.join('\n')}';
      if (updateCount > 0) _csvData = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
appBar: AppBar(
  title: const Text('保護者CSV一括登録・更新'),
  centerTitle: true,
  backgroundColor: Colors.white,
  elevation: 0,
  leading: IconButton(
    icon: const Icon(Icons.arrow_back, color: Colors.black87),
    onPressed: () {
      if (widget.onBack != null) {
        widget.onBack!();
      } else {
        Navigator.pop(context);
      }
    },
  ),
),

      backgroundColor: const Color(0xFFF2F2F7),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // モード選択
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
                  const Text('インポートモード', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildModeCard(
                          0,
                          Icons.person_add,
                          '新規（従来形式）',
                          'ID+PW列を含むCSV',
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildModeCard(
                          1,
                          Icons.upload_file,
                          '新規（エクスポート形式）',
                          'PW自動設定\n(初期PW)',
                          AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildModeCard(
                          2,
                          Icons.sync,
                          '更新',
                          '既存データを\n上書き',
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),

            // フォーマット説明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _importMode == 0 
                  ? _buildNewFormatHelp() 
                  : _importMode == 1
                      ? _buildExportNewFormatHelp()
                      : _buildUpdateFormatHelp(),
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
                    onPressed: _isLoading 
                        ? null 
                        : (_importMode == 0 
                            ? _registerNewAll 
                            : _importMode == 1 
                                ? _registerFromExportCsv 
                                : _updateFromExportCsv),
                    icon: Icon(_importMode == 2 ? Icons.sync : Icons.cloud_upload),
                    label: Text(_importMode == 2 ? '更新実行' : '新規登録実行'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _importMode == 0 
                          ? Colors.blue 
                          : _importMode == 1 
                              ? AppColors.accent 
                              : Colors.green,
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
                  Text('処理中...画面を閉じないでください'),
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

  Widget _buildModeCard(int mode, IconData icon, String title, String subtitle, Color color) {
    final isSelected = _importMode == mode;
    return InkWell(
      onTap: () => setState(() => _importMode = mode),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: isSelected ? color : Colors.grey),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? color : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewFormatHelp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('【新規登録CSVフォーマット（従来形式）】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
        const SizedBox(height: 8),
        const Text('列の順序（14列目まで）:', style: TextStyle(fontSize: 12)),
        const Text('1.姓, 2.名, 3.姓かな, 4.名かな, 5.ID, 6.PW, 7.続柄, 8.電話, 9.Email, 10.郵便番号, 11.住所, 12.緊急名, 13.緊急続柄, 14.緊急電話', 
          style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 12),
        const Text('児童情報（15列目以降、7項目×児童数）:', style: TextStyle(fontSize: 12)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildCell('名前'),
              _buildCell('ふりがな'),
              _buildCell('性別'),
              _buildCell('誕生日'),
              _buildCell('教室'),
              _buildCell('コース'),
              _buildCell('アレルギー'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExportNewFormatHelp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('【新規登録（エクスポート形式）】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.accent)),
        const SizedBox(height: 8),
        const Text('エクスポート機能で出力したCSVをそのまま使用できます。', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('✓ パスワードは初期パスワードに自動設定', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              Text('✓ 同じIDの複数行は1家族として統合', style: TextStyle(fontSize: 11)),
              Text('✓ 「アカウント状態」列は無視される', style: TextStyle(fontSize: 11)),
              Text('✓ 全員「初期PW」状態で登録', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('※ 既存のログインIDがある場合はエラーになります', style: TextStyle(fontSize: 11, color: Colors.red)),
      ],
    );
  }

  Widget _buildUpdateFormatHelp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('【更新用CSVフォーマット（エクスポート形式）】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
        const SizedBox(height: 8),
        const Text('エクスポート機能で出力したCSVをそのまま使用できます。', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('✓ ログインIDで既存データを照合', style: TextStyle(fontSize: 11)),
              Text('✓ 同じIDの複数行は1家族として統合', style: TextStyle(fontSize: 11)),
              Text('✓ 存在しないIDはスキップ', style: TextStyle(fontSize: 11)),
              Text('✓ アカウント状態列は無視（変更不可）', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('列順序:', style: TextStyle(fontSize: 12)),
        const Text('ログインID, 保護者姓, 保護者名, 姓カナ, 名カナ, 続柄, 電話, メール, 郵便番号, 住所, 緊急名, 緊急続柄, 緊急電話, アカウント状態, 児童名, 児童カナ, 性別, 生年月日, 教室, コース, アレルギー', 
          style: TextStyle(fontSize: 10, color: Colors.grey)),
      ],
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