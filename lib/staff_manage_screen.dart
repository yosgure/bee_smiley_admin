import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  
  // ExpansionTileControllerのマップ
  final Map<String, ExpansionTileController> _controllers = {};
  
  // 現在展開中のドキュメントID
  String? _currentExpandedId;

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

  // 五十音の行を判定するヘルパーメソッド
  String _getKanaRow(String? text) {
    if (text == null || text.isEmpty) return '他';
    final char = text.substring(0, 1);

    if (RegExp(r'^[あいうえおアイウエオ]').hasMatch(char)) return 'あ';
    if (RegExp(r'^[かきくけこがぎぐげごカキクケコガギグゲゴ]').hasMatch(char)) return 'か';
    if (RegExp(r'^[さしすせそざじずぜぞサシスセソザジズゼゾ]').hasMatch(char)) return 'さ';
    if (RegExp(r'^[たちつてとだぢづでどタチツテトダヂヅデド]').hasMatch(char)) return 'た';
    if (RegExp(r'^[なにぬねのナニヌネノ]').hasMatch(char)) return 'な';
    if (RegExp(r'^[はひふへほばびぶべぼぱぴぷぺぽハヒフヘホバビブベボパピプペポ]').hasMatch(char)) return 'は';
    if (RegExp(r'^[まみむめもマミムメモ]').hasMatch(char)) return 'ま';
    if (RegExp(r'^[やゆよヤユヨ]').hasMatch(char)) return 'や';
    if (RegExp(r'^[らりるれろラリルレロ]').hasMatch(char)) return 'ら';
    if (RegExp(r'^[わをんワヲン]').hasMatch(char)) return 'わ';
    
    return '他';
  }

  // セクションヘッダーウィジェット
  Widget _buildSectionHeader(String headerText) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$headerText行',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
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

          final docs = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);

          if (docs.isEmpty) {
            return const Center(
              child: Text('スタッフが登録されていません', style: TextStyle(color: Colors.grey)),
            );
          }

          // ふりがな順に並び替え
          docs.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;
            final kanaA = (dataA['furigana'] ?? '').toString();
            final kanaB = (dataB['furigana'] ?? '').toString();
            return kanaA.compareTo(kanaB);
          });

          // リスト表示用のウィジェットリストを作成
          List<Widget> listWidgets = [];
          String currentHeader = '';

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final furigana = data['furigana'] ?? '';
            final header = _getKanaRow(furigana);

            // 行が変わったらヘッダーを挿入
            if (header != currentHeader) {
              currentHeader = header;
              listWidgets.add(_buildSectionHeader(header));
            }

            final List<String> classrooms = List<String>.from(data['classrooms'] ?? []);
            final String? photoUrl = data['photoUrl'];
            
            // コントローラーを取得または作成
            final controller = _controllers.putIfAbsent(
              doc.id, 
              () => ExpansionTileController(),
            );

            listWidgets.add(
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  controller: controller,
                  key: PageStorageKey(doc.id),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  // アコーディオンの排他制御
                  onExpansionChanged: (isOpen) {
                    if (isOpen) {
                      // 他に開いているタイルがあれば閉じる
                      if (_currentExpandedId != null && _currentExpandedId != doc.id) {
                        final prevController = _controllers[_currentExpandedId];
                        if (prevController != null) {
                          try {
                            prevController.collapse();
                          } catch (_) {}
                        }
                      }
                      _currentExpandedId = doc.id;
                    } else {
                      if (_currentExpandedId == doc.id) {
                        _currentExpandedId = null;
                      }
                    }
                  },
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? CachedNetworkImageProvider(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? Text(
                            (data['name'] as String?)?.isNotEmpty == true 
                                ? data['name'].substring(0, 1) 
                                : '?',
                            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                          )
                        : null,
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
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: listWidgets,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, 
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
      barrierDismissible: false,
      builder: (context) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('削除確認'),
              content: Text('$name さんの情報を削除しますか？\n※Authアカウントは別途削除が必要です。'),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.pop(context), 
                  child: const Text('キャンセル')
                ),
                TextButton(
                  onPressed: isDeleting ? null : () async {
                    setStateDialog(() => isDeleting = true);
                    
                    try {
                      await Future.any([
                        _staffsRef.doc(docId).delete(),
                        Future.delayed(const Duration(seconds: 5)).then((_) => throw TimeoutException('Delete timed out')),
                      ]);

                      if (context.mounted) {
                         Navigator.pop(context);
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('情報を削除しました')));
                      }
                    } catch (e) {
                      if (context.mounted) {
                         Navigator.pop(context);
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('削除エラー: $e')));
                      }
                    }
                  },
                  child: isDeleting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('削除', style: TextStyle(color: Colors.red)),
                ),
              ],
            );
          },
        );
      },
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
    String? currentPhotoUrl = data['photoUrl'];

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) {
        Uint8List? newImageBytes;
        bool isUploading = false;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final displayClassrooms = _classroomList.isNotEmpty 
                ? _classroomList 
                : ['ビースマイリー湘南藤沢教室', 'ビースマイリー湘南台教室', 'ビースマイリープラス湘南藤沢教室'];

            final isAllSelected = displayClassrooms.isNotEmpty && selectedClassrooms.length == displayClassrooms.length;

            Future<void> pickImage() async {
              final picker = ImagePicker();
              final picked = await picker.pickImage(source: ImageSource.gallery);
              if (picked != null) {
                final bytes = await picked.readAsBytes();
                setStateDialog(() {
                  newImageBytes = bytes;
                });
              }
            }

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
                        Center(
                          child: GestureDetector(
                            onTap: pickImage,
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: newImageBytes != null
                                      ? MemoryImage(newImageBytes!)
                                      : (currentPhotoUrl != null && currentPhotoUrl!.isNotEmpty
                                          ? CachedNetworkImageProvider(currentPhotoUrl!)
                                          : null) as ImageProvider?,
                                  child: (newImageBytes == null && (currentPhotoUrl == null || currentPhotoUrl!.isEmpty))
                                      ? const Icon(Icons.person, size: 40, color: Colors.grey)
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (!isEditing)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Text(
                              '※新規登録時の初期パスワードは「$_defaultPassword」になります。',
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        _buildTextField(loginIdCtrl, 'ログインID', icon: Icons.vpn_key, enabled: !isEditing),
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
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(context),
                  child: const Text('キャンセル')
                ),
                ElevatedButton(
                  onPressed: isUploading ? null : () async {
                    setStateDialog(() => isUploading = true);
                    
                    try {
                      await Future.any([
                        Future(() async {
                          if (isEditing) {
                            String? uploadedUrl = currentPhotoUrl;
                            if (newImageBytes != null) {
                              final uid = data['uid'] ?? doc!.id;
                              uploadedUrl = await _uploadStaffPhoto(newImageBytes!, uid);
                            }
                            await _staffsRef.doc(doc!.id).update({
                              'name': nameCtrl.text,
                              'furigana': furiganaCtrl.text,
                              'phone': phoneCtrl.text,
                              'email': emailCtrl.text,
                              'role': roleCtrl.text,
                              'classrooms': selectedClassrooms,
                              'photoUrl': uploadedUrl,
                            }).timeout(const Duration(seconds: 5));
                          } else {
                            await _registerNewStaff(
                              loginId: loginIdCtrl.text,
                              name: nameCtrl.text,
                              furigana: furiganaCtrl.text,
                              phone: phoneCtrl.text,
                              email: emailCtrl.text,
                              role: roleCtrl.text,
                              classrooms: selectedClassrooms,
                              imageBytes: newImageBytes,
                            );
                          }
                        }),
                        Future.delayed(const Duration(seconds: 15)).then((_) => throw TimeoutException('処理がタイムアウトしました')),
                      ]);

                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        Navigator.pop(context);
                        
                        String msg = 'エラーが発生しました: $e';
                        if (e.toString().contains('パスワードが変更されています')) {
                          msg = 'IDが既に存在しますが、パスワードが変更されているため復旧できません。';
                        } else if (e.toString().contains('email-already-in-use')) {
                          msg = 'このIDは既に使用されています。';
                        }
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(msg),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    } finally {
                      if (context.mounted) setStateDialog(() => isUploading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  child: isUploading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _uploadStaffPhoto(Uint8List bytes, String uid) async {
    try {
      final fileName = '${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child('staff_photos/$fileName');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg')).timeout(const Duration(seconds: 10));
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveStaffDataToFirestore({
    required String uid,
    required String loginId,
    required String name,
    required String furigana,
    required String phone,
    required String email,
    required String role,
    required List<String> classrooms,
    Uint8List? imageBytes,
  }) async {
    String? photoUrl;
    if (imageBytes != null) {
      photoUrl = await _uploadStaffPhoto(imageBytes, uid);
    }

    await _staffsRef.add({
      'uid': uid,
      'loginId': loginId,
      'name': name,
      'furigana': furigana,
      'phone': phone,
      'email': email,
      'role': role,
      'classrooms': classrooms,
      'photoUrl': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'isInitialPassword': true,
    }).timeout(const Duration(seconds: 5));
  }

  Future<void> _registerNewStaff({
    required String loginId,
    required String name,
    required String furigana,
    required String phone,
    required String email,
    required String role,
    required List<String> classrooms,
    Uint8List? imageBytes,
  }) async {
    final String tempAppName = 'TempStaffRegister_${DateTime.now().millisecondsSinceEpoch}';
    
    FirebaseApp tempApp = await Firebase.initializeApp(
      name: tempAppName, 
      options: Firebase.app().options
    );

    try {
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final authEmail = '$loginId$_fixedDomain';

      try {
        UserCredential userCredential = await tempAuth.createUserWithEmailAndPassword(
          email: authEmail,
          password: _defaultPassword,
        ).timeout(const Duration(seconds: 10));
        
        await _saveStaffDataToFirestore(
          uid: userCredential.user!.uid,
          loginId: loginId,
          name: name,
          furigana: furigana,
          phone: phone,
          email: email,
          role: role,
          classrooms: classrooms,
          imageBytes: imageBytes,
        );

      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          try {
            UserCredential userCredential = await tempAuth.signInWithEmailAndPassword(
              email: authEmail,
              password: _defaultPassword,
            ).timeout(const Duration(seconds: 10));
            
            await _saveStaffDataToFirestore(
              uid: userCredential.user!.uid,
              loginId: loginId,
              name: name,
              furigana: furigana,
              phone: phone,
              email: email,
              role: role,
              classrooms: classrooms,
              imageBytes: imageBytes,
            );
            return;

          } catch (signInError) {
            throw 'パスワードが変更されています。復旧できません。';
          }
        } else {
          rethrow;
        }
      }
    } catch (e) {
      rethrow;
    } finally {
      tempApp.delete(); 
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