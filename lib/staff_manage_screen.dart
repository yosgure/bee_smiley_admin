import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 追加
import 'package:firebase_core/firebase_core.dart'; // 追加

class StaffManageScreen extends StatefulWidget {
  const StaffManageScreen({super.key});

  @override
  State<StaffManageScreen> createState() => _StaffManageScreenState();
}

class _StaffManageScreenState extends State<StaffManageScreen> {
  final CollectionReference _staffsRef =
      FirebaseFirestore.instance.collection('staffs');
  final CollectionReference _classroomsRef =
      FirebaseFirestore.instance.collection('classrooms');

  List<String> _classroomList = [];
  
  // ★共通の初期パスワード
  static const String _defaultPassword = 'bee2025';
  static const String _fixedDomain = '@bee-smiley.com';

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

  String _formatPhoneDisplay(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    if (!phone.startsWith('0') && (phone.length == 9 || phone.length == 10)) {
      return '0$phone';
    }
    return phone;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('スタッフ管理'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      
      body: StreamBuilder<QuerySnapshot>(
        stream: _staffsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('エラーが発生しました'));
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text('スタッフが登録されていません', style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final List<String> classrooms = List<String>.from(data['classrooms'] ?? []);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      (data['name'] as String).isNotEmpty ? data['name'].substring(0, 1) : '?',
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    data['name'] ?? '名称未設定',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${data['role'] ?? ''} / ID: ${data['loginId'] ?? ''}'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          _buildInfoRow('ふりがな', data['furigana'] ?? ''),
                          _buildInfoRow('電話番号', _formatPhoneDisplay(data['phone'])),
                          _buildInfoRow('メール', data['email'] ?? ''),
                          const SizedBox(height: 8),
                          const Text('担当教室:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 4),
                          if (classrooms.isEmpty)
                            const Text('登録なし', style: TextStyle(fontSize: 13))
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: classrooms.map((room) {
                                return Chip(
                                  label: Text(room, style: const TextStyle(fontSize: 11)),
                                  backgroundColor: Colors.blue.shade50,
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                label: const Text('削除', style: TextStyle(color: Colors.red)),
                                onPressed: () => _deleteStaff(doc.id, data['name']),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.edit),
                                label: const Text('編集'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                onPressed: () => _showEditDialog(doc: doc),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        backgroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/logo_beesmileymark.png',
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.add, color: Colors.blue),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  void _deleteStaff(String docId, String? name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('$name さんの情報を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              await _staffsRef.doc(docId).delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog({DocumentSnapshot? doc}) {
    final isEditing = doc != null;
    final data = isEditing ? (doc.data() as Map<String, dynamic>) : {};

    final loginIdCtrl = TextEditingController(text: data['loginId'] ?? '');
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final furiganaCtrl = TextEditingController(text: data['furigana'] ?? '');
    final phoneCtrl = TextEditingController(text: _formatPhoneDisplay(data['phone']));
    final emailCtrl = TextEditingController(text: data['email'] ?? '');
    final roleCtrl = TextEditingController(text: data['role'] ?? '保育士');
    
    List<String> selectedClassrooms = List<String>.from(data['classrooms'] ?? []);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final displayClassrooms = _classroomList.isNotEmpty 
                ? _classroomList 
                : ['ビースマイリー湘南藤沢教室', 'ビースマイリー湘南台教室', 'ビースマイリープラス湘南藤沢教室'];

            final isAllSelected = displayClassrooms.isNotEmpty && selectedClassrooms.length == displayClassrooms.length;

            return AlertDialog(
              title: Text(isEditing ? 'スタッフ編集' : '新規追加'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isEditing)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16.0),
                            child: Text(
                              '※新規登録時の初期パスワードは「$_defaultPassword」になります。',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        _buildTextField(loginIdCtrl, 'ログインID', icon: Icons.vpn_key, enabled: !isEditing), // IDは変更不可推奨
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(nameCtrl, '氏名', icon: Icons.person)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField(furiganaCtrl, 'ふりがな')),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(phoneCtrl, '電話番号', icon: Icons.phone, type: TextInputType.phone),
                        const SizedBox(height: 16),
                        _buildTextField(emailCtrl, 'メールアドレス', icon: Icons.email, type: TextInputType.emailAddress),
                        const SizedBox(height: 16),
                        _buildTextField(roleCtrl, '役職 (例: 園長, 保育士)', icon: Icons.work),
                        
                        const SizedBox(height: 24),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('担当教室 (複数選択可)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            if (displayClassrooms.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  setStateDialog(() {
                                    if (isAllSelected) {
                                      selectedClassrooms.clear();
                                    } else {
                                      selectedClassrooms = List.from(displayClassrooms);
                                    }
                                  });
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(isAllSelected ? '全解除' : '全選択'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        if (displayClassrooms.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text('教室データがありません。', style: TextStyle(color: Colors.red, fontSize: 12)),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: displayClassrooms.map((room) {
                              final isSelected = selectedClassrooms.contains(room);
                              return FilterChip(
                                label: Text(room),
                                selected: isSelected,
                                selectedColor: Colors.blue.shade100,
                                checkmarkColor: Colors.blue,
                                onSelected: (bool selected) {
                                  setStateDialog(() {
                                    if (selected) {
                                      selectedClassrooms.add(room);
                                    } else {
                                      selectedClassrooms.remove(room);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                ElevatedButton(
                  onPressed: () async {
                    // 保存処理
                    try {
                      if (isEditing) {
                        // 編集モード: Firestore更新のみ
                        await _staffsRef.doc(doc.id).update({
                          'name': nameCtrl.text,
                          'furigana': furiganaCtrl.text,
                          'phone': phoneCtrl.text,
                          'email': emailCtrl.text,
                          'role': roleCtrl.text,
                          'classrooms': selectedClassrooms,
                        });
                      } else {
                        // ★新規モード: Authユーザー作成 -> Firestore保存
                        await _registerNewStaff(
                          loginId: loginIdCtrl.text,
                          name: nameCtrl.text,
                          furigana: furiganaCtrl.text,
                          phone: phoneCtrl.text,
                          email: emailCtrl.text,
                          role: roleCtrl.text,
                          classrooms: selectedClassrooms,
                        );
                      }
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('エラー: $e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ★新規スタッフ登録処理（Auth作成含む）
  Future<void> _registerNewStaff({
    required String loginId,
    required String name,
    required String furigana,
    required String phone,
    required String email,
    required String role,
    required List<String> classrooms,
  }) async {
    // 現在の管理者がログアウトしないよう、一時的なアプリを作成
    FirebaseApp tempApp;
    try {
      tempApp = await Firebase.initializeApp(name: 'TempStaffRegister', options: Firebase.app().options);
    } catch (e) {
      tempApp = Firebase.app('TempStaffRegister');
    }

    final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
    final authEmail = '$loginId$_fixedDomain';

    try {
      // 1. Authユーザー作成
      UserCredential userCredential = await tempAuth.createUserWithEmailAndPassword(
        email: authEmail,
        password: _defaultPassword,
      );

      // 2. Firestore保存 (isInitialPassword: true を付与)
      await _staffsRef.add({
        'uid': userCredential.user!.uid,
        'loginId': loginId,
        'name': name,
        'furigana': furigana,
        'phone': phone,
        'email': email,
        'role': role,
        'classrooms': classrooms,
        'createdAt': FieldValue.serverTimestamp(),
        'isInitialPassword': true, // ★ここが重要
      });

      await tempApp.delete();
    } catch (e) {
      await tempApp.delete();
      throw e;
    }
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        isDense: true,
        fillColor: enabled ? null : Colors.grey.shade200,
        filled: !enabled,
      ),
    );
  }
}