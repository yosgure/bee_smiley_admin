import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore用パッケージ

class ClassroomMasterScreen extends StatefulWidget {
  const ClassroomMasterScreen({super.key});

  @override
  State<ClassroomMasterScreen> createState() => _ClassroomMasterScreenState();
}

class _ClassroomMasterScreenState extends State<ClassroomMasterScreen> {
  // カラーパレット
  final List<Color> _colors = [
    Colors.blue, Colors.red, Colors.orange, Colors.green, Colors.purple,
    Colors.pink, Colors.brown, Colors.teal, Colors.indigo, Colors.grey,
  ];

  // カテゴリー選択肢
  final List<String> _categories = ['幼児教室', '児童発達支援', 'その他'];

  // Firestoreの「classrooms」コレクションへの参照
  final CollectionReference _classroomsRef =
      FirebaseFirestore.instance.collection('classrooms');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教室設定'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      
      // ★ここが重要：Firestoreのデータをリアルタイムに表示する仕組み
      body: StreamBuilder<QuerySnapshot>(
        stream: _classroomsRef.snapshots(), // データの変更を監視
        builder: (context, snapshot) {
          // 1. ロード中
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // 2. エラー時
          if (snapshot.hasError) {
            return const Center(child: Text('エラーが発生しました'));
          }
          
          final dataList = snapshot.data!.docs;

          // 3. データが空っぽの場合
          if (dataList.isEmpty) {
            return const Center(
              child: Text(
                'データがありません。\n右下の「＋」ボタンで追加してください。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          // 4. データがある場合（リスト表示）
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: dataList.length,
            itemBuilder: (context, index) {
              final doc = dataList[index];
              final data = doc.data() as Map<String, dynamic>;
              
              // データベースの数値から色を復元。なければデフォルト青。
              final colorValue = data['color'] as int? ?? Colors.blue.value;
              final roomColor = Color(colorValue);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: roomColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                    ),
                  ),
                  title: Text(
                    data['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${data['category']} / ☎ ${data['phone']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          _buildInfoRow('カテゴリー', data['category'] ?? ''),
                          _buildInfoRow('住所', data['address'] ?? ''),
                          _buildInfoRow('電話番号', data['phone'] ?? ''),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                label: const Text('削除', style: TextStyle(color: Colors.red)),
                                onPressed: () => _deleteClassroom(doc.id, data['name']),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.edit),
                                label: const Text('編集'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.brown,
                                    foregroundColor: Colors.white),
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
        onPressed: () => _showEditDialog(), // 新規作成
        backgroundColor: Colors.brown,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  // 削除処理 (FirestoreのドキュメントIDを指定して削除)
  void _deleteClassroom(String docId, String? name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('$name を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              // ★Firestoreから削除を実行
              await _classroomsRef.doc(docId).delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 編集・新規追加ダイアログ
  void _showEditDialog({DocumentSnapshot? doc}) {
    final isEditing = doc != null;
    // 編集時はドキュメントの中身、新規時は空っぽ
    final data = isEditing ? (doc.data() as Map<String, dynamic>) : {};

    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final addressCtrl = TextEditingController(text: data['address'] ?? '');
    final phoneCtrl = TextEditingController(text: data['phone'] ?? '');
    
    String selectedCategory = data['category'] ?? _categories[0];
    
    // 色データの復元（int -> Color）
    Color selectedColor = Colors.blue;
    if (data['color'] != null) {
      selectedColor = Color(data['color']);
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(isEditing ? '教室情報の編集' : '新規追加'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTextField(nameCtrl, '教室名 (例: 湘南藤沢教室)'),
                        const SizedBox(height: 16),
                        
                        DropdownButtonFormField<String>(
                          value: _categories.contains(selectedCategory) ? selectedCategory : _categories[0],
                          decoration: const InputDecoration(
                            labelText: 'カテゴリー',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            isDense: true,
                          ),
                          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) {
                            if (val != null) setStateDialog(() => selectedCategory = val);
                          },
                        ),
                        
                        const SizedBox(height: 16),
                        _buildTextField(addressCtrl, '住所', icon: Icons.location_on),
                        const SizedBox(height: 16),
                        _buildTextField(phoneCtrl, '電話番号', icon: Icons.phone, type: TextInputType.phone),
                        
                        const SizedBox(height: 24),
                        
                        const Text('テーマカラー', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _colors.map((color) {
                            final isSelected = color.value == selectedColor.value;
                            return GestureDetector(
                              onTap: () {
                                setStateDialog(() {
                                  selectedColor = color;
                                });
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(color: Colors.black87, width: 3)
                                      : Border.all(color: Colors.grey.shade300),
                                  boxShadow: isSelected
                                      ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))]
                                      : [],
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                                    : null,
                              ),
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
                    // 保存するデータ
                    final saveData = {
                      'name': nameCtrl.text,
                      'category': selectedCategory,
                      'address': addressCtrl.text,
                      'phone': phoneCtrl.text,
                      'color': selectedColor.value, // 色は数値(int)で保存
                    };

                    if (isEditing) {
                      // 更新 (update)
                      await _classroomsRef.doc(doc.id).update(saveData);
                    } else {
                      // 新規作成 (add)
                      await _classroomsRef.add(saveData);
                    }
                    
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {IconData? icon, TextInputType? type}) {
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey, size: 20) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
    );
  }
}