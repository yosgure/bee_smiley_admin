import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class StudentManageScreen extends StatefulWidget {
  const StudentManageScreen({super.key});

  @override
  State<StudentManageScreen> createState() => _StudentManageScreenState();
}

class _StudentManageScreenState extends State<StudentManageScreen> {
  final CollectionReference _familiesRef =
      FirebaseFirestore.instance.collection('families');
  final CollectionReference _classroomsRef =
      FirebaseFirestore.instance.collection('classrooms');

  // Cloud Functions（リージョン指定）
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  List<String> _classroomList = [];

  final List<String> _allCourses = [
    'プリスクール',
    'キッズコース',
    'ベビーコース',
    'その他',
  ];

  final List<String> _genders = ['男', '女', 'その他'];

  static const String _initialPassword = 'pass1234';

  @override
  void initState() {
    super.initState();
    _fetchClassrooms();
  }

  Future<void> _fetchClassrooms() async {
    try {
      final snapshot = await _classroomsRef.get();
      setState(() {
        _classroomList = snapshot.docs
            .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String? ?? '')
            .where((name) => name.isNotEmpty)
            .toList();
      });
    } catch (e) {
      setState(() {
        _classroomList = [
          'ビースマイリー湘南藤沢教室',
          'ビースマイリー湘南台教室',
          'ビースマイリープラス湘南藤沢教室',
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('保護者・児童管理'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: StreamBuilder<QuerySnapshot>(
        stream: _familiesRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('エラーが発生しました'));
          }

          final familyDocs = snapshot.data!.docs;

          if (familyDocs.isEmpty) {
            return const Center(
              child: Text('データがありません。\n右下のマークで追加してください。', style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: familyDocs.length,
            itemBuilder: (context, index) {
              final familyDoc = familyDocs[index];
              final data = familyDoc.data() as Map<String, dynamic>;
              final children = List<Map<String, dynamic>>.from(data['children'] ?? []);

              final parentFullName = '${data['lastName'] ?? ''} ${data['firstName'] ?? ''}';
              final parentKanaName = '${data['lastNameKana'] ?? ''} ${data['firstNameKana'] ?? ''}';
              
              String fullAddress = data['address'] ?? '';
              if (data['postalCode'] != null && data['postalCode'].toString().isNotEmpty) {
                fullAddress = '〒${data['postalCode']} $fullAddress';
              }

              final hasAccount = data['uid'] != null && data['uid'].toString().isNotEmpty;
              final isInitialPassword = data['isInitialPassword'] == true;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: const Icon(Icons.family_restroom, color: Colors.blue),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          parentFullName.trim().isEmpty ? '名称未設定' : parentFullName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (hasAccount)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isInitialPassword ? Colors.orange.shade100 : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isInitialPassword ? '初期PW' : 'アクティブ',
                            style: TextStyle(
                              fontSize: 10,
                              color: isInitialPassword ? Colors.orange.shade800 : Colors.green.shade800,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '未登録',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text('児童数: ${children.length}名 / ID: ${data['loginId'] ?? "未設定"}'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          const Text('【保護者情報】', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          _buildInfoRow('ふりがな', parentKanaName),
                          _buildInfoRow('続柄', data['relation'] ?? ''),
                          _buildInfoRow('電話番号', data['phone'] ?? ''),
                          _buildInfoRow('メール', data['email'] ?? ''),
                          _buildInfoRow('住所', fullAddress),
                          const SizedBox(height: 8),
                          const Text('【緊急連絡先】', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          _buildInfoRow('氏名', data['emergencyName'] ?? ''),
                          _buildInfoRow('続柄', data['emergencyRelation'] ?? ''),
                          _buildInfoRow('電話', data['emergencyPhone'] ?? ''),
                          
                          const SizedBox(height: 12),
                          const Text('【児童詳細】', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          if (children.isEmpty) const Text('登録なし', style: TextStyle(color: Colors.grey)),
                          ...children.map((child) => _buildChildCard(child)).toList(),

                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (hasAccount)
                                TextButton.icon(
                                  icon: const Icon(Icons.lock_reset, color: Colors.orange),
                                  label: const Text('PW初期化', style: TextStyle(color: Colors.orange)),
                                  onPressed: () => _resetPassword(
                                    familyDoc.id, 
                                    data['uid'], 
                                    parentFullName,
                                  ),
                                ),
                              TextButton.icon(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                label: const Text('削除', style: TextStyle(color: Colors.red)),
                                onPressed: () => _deleteFamily(
                                  familyDoc.id, 
                                  data['uid'], 
                                  parentFullName,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.edit),
                                label: const Text('編集'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                onPressed: () => _showEditDialog(familyDoc: familyDoc),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(heroTag: null, 
        onPressed: () => _showEditDialog(),
        backgroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/logo_beesmileymark.png',
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.person_add, color: Colors.blue),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildChildCard(Map<String, dynamic> child) {
    String displayName = child['firstName'] ?? '';
    if (child['firstNameKana'] != null && child['firstNameKana'].isNotEmpty) {
      displayName += ' (${child['firstNameKana']})';
    }

    String classInfo = child['classroom'] ?? '';
    if (child['course'] != null && child['course'].isNotEmpty) {
      classInfo += ' / ${child['course']}';
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$displayName  ${child['gender']}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text('誕生日: ${child['birthDate']}', style: const TextStyle(fontSize: 12)),
          Text('所属: $classInfo', style: const TextStyle(fontSize: 12)),
          if ((child['allergy'] ?? '').isNotEmpty)
            Text('特記事項: ${child['allergy']}', style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
      ),
    );
  }

  /// Cloud Functions経由でパスワードを初期化
  Future<void> _resetPassword(String docId, String? targetUid, String name) async {
    if (targetUid == null || targetUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('アカウントが作成されていません'), backgroundColor: Colors.red),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('パスワード初期化'),
        content: Text('$name さんのパスワードを「$_initialPassword」に初期化しますか？\n\n次回ログイン時にパスワード変更が求められます。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('初期化'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      _showLoadingDialog('パスワードを初期化中...');

      final callable = _functions.httpsCallable('resetParentPassword');
      await callable.call({
        'targetUid': targetUid,
        'familyDocId': docId,
      });

      if (mounted) {
        Navigator.pop(context); // ローディングを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name さんのパスワードを初期化しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // ローディングを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Cloud Functions経由でアカウントを削除
  Future<void> _deleteFamily(String docId, String? targetUid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('$name さんの情報を削除しますか？\n\n※ログインアカウントも削除されます。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      _showLoadingDialog('削除中...');

      final callable = _functions.httpsCallable('deleteParentAccount');
      await callable.call({
        'targetUid': targetUid,
        'familyDocId': docId,
      });

      if (mounted) {
        Navigator.pop(context); // ローディングを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除しました'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // ローディングを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showEditDialog({DocumentSnapshot? familyDoc}) {
    final isEditing = familyDoc != null;
    final data = isEditing ? (familyDoc.data() as Map<String, dynamic>) : <String, dynamic>{};

    final loginIdCtrl = TextEditingController(text: data['loginId'] ?? '');
    final lastNameCtrl = TextEditingController(text: data['lastName'] ?? '');
    final firstNameCtrl = TextEditingController(text: data['firstName'] ?? '');
    final lastNameKanaCtrl = TextEditingController(text: data['lastNameKana'] ?? '');
    final firstNameKanaCtrl = TextEditingController(text: data['firstNameKana'] ?? '');
    
    final relationCtrl = TextEditingController(text: data['relation'] ?? '');
    final phoneCtrl = TextEditingController(text: data['phone'] ?? '');
    final emailCtrl = TextEditingController(text: data['email'] ?? '');
    
    final postalCodeCtrl = TextEditingController(text: data['postalCode'] ?? '');
    final addressCtrl = TextEditingController(text: data['address'] ?? '');
    
    final emNameCtrl = TextEditingController(text: data['emergencyName'] ?? '');
    final emRelCtrl = TextEditingController(text: data['emergencyRelation'] ?? '');
    final emPhoneCtrl = TextEditingController(text: data['emergencyPhone'] ?? '');

    List<Map<String, dynamic>> children = [];
    if (data['children'] != null) {
      children = List<Map<String, dynamic>>.from(data['children']);
    } else {
      children.add({
        'firstName': '',
        'firstNameKana': '',
        'gender': '男',
        'birthDate': '',
        'classroom': _classroomList.isNotEmpty ? _classroomList[0] : '',
        'course': _allCourses[0],
        'allergy': '',
      });
    }

    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(isEditing ? '登録情報の編集' : '新規登録'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 550),
                child: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 新規登録時の説明
                        if (!isEditing)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '初期パスワード: pass1234\n初回ログイン時にパスワード変更が必要です。',
                                    style: TextStyle(fontSize: 12, color: Colors.blue),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        _buildSectionTitle('保護者情報'),
                        _buildTextField(loginIdCtrl, 'ログインID', icon: Icons.vpn_key, enabled: !isEditing),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(lastNameCtrl, '姓', icon: Icons.person)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField(firstNameCtrl, '名')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(lastNameKanaCtrl, 'せい (ふりがな)')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField(firstNameKanaCtrl, 'めい (ふりがな)')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(relationCtrl, '続柄 (父, 母など)'),
                        const SizedBox(height: 8),
                        _buildTextField(phoneCtrl, '電話番号', icon: Icons.phone, type: TextInputType.phone),
                        const SizedBox(height: 8),
                        _buildTextField(emailCtrl, 'メールアドレス', icon: Icons.email, type: TextInputType.emailAddress),
                        const SizedBox(height: 8),
                        
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120, 
                              child: _buildTextField(postalCodeCtrl, '郵便番号', icon: Icons.markunread_mailbox, type: TextInputType.number),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTextField(addressCtrl, '住所', icon: Icons.home),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        _buildSectionTitle('緊急連絡先'),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(emNameCtrl, '氏名')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField(emRelCtrl, '続柄')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(emPhoneCtrl, '電話番号', icon: Icons.phone, type: TextInputType.phone),

                        const SizedBox(height: 24),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildSectionTitle('児童情報'),
                            TextButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('兄弟を追加'),
                              onPressed: () {
                                setStateDialog(() {
                                  children.add({
                                    'firstName': '',
                                    'firstNameKana': '',
                                    'gender': '男',
                                    'birthDate': '',
                                    'classroom': _classroomList.isNotEmpty ? _classroomList[0] : '',
                                    'course': _allCourses[0],
                                    'allergy': '',
                                  });
                                });
                              },
                            ),
                          ],
                        ),
                        
                        ...children.asMap().entries.map((entry) {
                          int i = entry.key;
                          Map<String, dynamic> child = entry.value;
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('児童 ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                    if (children.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                        onPressed: () {
                                          setStateDialog(() {
                                            children.removeAt(i);
                                          });
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: child['firstName'],
                                        decoration: const InputDecoration(labelText: '名前 (名のみ)', isDense: true, border: OutlineInputBorder()),
                                        onChanged: (val) => child['firstName'] = val,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: child['firstNameKana'],
                                        decoration: const InputDecoration(labelText: 'ふりがな', isDense: true, border: OutlineInputBorder()),
                                        onChanged: (val) => child['firstNameKana'] = val,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _genders.contains(child['gender']) ? child['gender'] : _genders[0],
                                        decoration: const InputDecoration(labelText: '性別', isDense: true, border: OutlineInputBorder()),
                                        items: _genders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                                        onChanged: (val) => setStateDialog(() => child['gender'] = val),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          DateTime initialDate = DateTime.now();
                                          if (child['birthDate'] != null && child['birthDate'].isNotEmpty) {
                                            try {
                                              List<String> parts = child['birthDate'].split('/');
                                              if (parts.length == 3) {
                                                initialDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                                              }
                                            } catch (_) {}
                                          }

                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: initialDate,
                                            firstDate: DateTime(2010),
                                            lastDate: DateTime.now(),
                                          );
                                          if (picked != null) {
                                            setStateDialog(() {
                                              child['birthDate'] = '${picked.year}/${picked.month}/${picked.day}';
                                            });
                                          }
                                        },
                                        child: InputDecorator(
                                          decoration: const InputDecoration(labelText: '生年月日', isDense: true, border: OutlineInputBorder()),
                                          child: Text(child['birthDate']?.isEmpty ?? true ? 'YYYY/MM/DD' : child['birthDate']),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                DropdownButtonFormField<String>(
                                  value: _classroomList.contains(child['classroom']) 
                                      ? child['classroom'] 
                                      : (_classroomList.isNotEmpty ? _classroomList[0] : null),
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: '教室', isDense: true, border: OutlineInputBorder()),
                                  items: _classroomList.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
                                  onChanged: (val) => setStateDialog(() => child['classroom'] = val),
                                ),
                                
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: _allCourses.contains(child['course']) ? child['course'] : _allCourses[0],
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'コース', isDense: true, border: OutlineInputBorder()),
                                  items: _allCourses.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
                                  onChanged: (val) => setStateDialog(() => child['course'] = val),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: child['allergy'],
                                  decoration: const InputDecoration(labelText: 'アレルギー・特記事項', isDense: true, border: OutlineInputBorder()),
                                  onChanged: (val) => child['allergy'] = val,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context), 
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    final loginId = loginIdCtrl.text.trim();
                    
                    if (loginId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ログインIDを入力してください'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    setStateDialog(() => isLoading = true);

                    try {
                      if (isEditing) {
                        // 編集の場合はFirestoreのみ更新
                        final saveData = {
                          'lastName': lastNameCtrl.text,
                          'firstName': firstNameCtrl.text,
                          'lastNameKana': lastNameKanaCtrl.text,
                          'firstNameKana': firstNameKanaCtrl.text,
                          'relation': relationCtrl.text,
                          'phone': phoneCtrl.text,
                          'email': emailCtrl.text,
                          'postalCode': postalCodeCtrl.text,
                          'address': addressCtrl.text,
                          'emergencyName': emNameCtrl.text,
                          'emergencyRelation': emRelCtrl.text,
                          'emergencyPhone': emPhoneCtrl.text,
                          'children': children,
                        };
                        await _familiesRef.doc(familyDoc.id).update(saveData);
                      } else {
                        // 新規作成の場合はCloud Functionsを使用
                        final familyData = {
                          'lastName': lastNameCtrl.text,
                          'firstName': firstNameCtrl.text,
                          'lastNameKana': lastNameKanaCtrl.text,
                          'firstNameKana': firstNameKanaCtrl.text,
                          'relation': relationCtrl.text,
                          'phone': phoneCtrl.text,
                          'email': emailCtrl.text,
                          'postalCode': postalCodeCtrl.text,
                          'address': addressCtrl.text,
                          'emergencyName': emNameCtrl.text,
                          'emergencyRelation': emRelCtrl.text,
                          'emergencyPhone': emPhoneCtrl.text,
                          'children': children,
                        };

                        final callable = _functions.httpsCallable('createParentAccount');
                        await callable.call({
                          'loginId': loginId,
                          'familyData': familyData,
                        });
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isEditing ? '更新しました' : '登録しました（初期PW: $_initialPassword）'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } on FirebaseFunctionsException catch (e) {
                      setStateDialog(() => isLoading = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('エラー: ${e.message}'), backgroundColor: Colors.red),
                        );
                      }
                    } catch (e) {
                      setStateDialog(() => isLoading = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  child: isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 4, height: 16, color: Colors.blue, margin: const EdgeInsets.only(right: 8)),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {IconData? icon, TextInputType? type, bool enabled = true}) {
    return TextField(
      controller: controller,
      keyboardType: type,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey, size: 20) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey.shade200,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        isDense: true,
      ),
    );
  }
}