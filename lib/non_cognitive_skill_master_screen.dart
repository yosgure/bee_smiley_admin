import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore

class NonCognitiveSkillMasterScreen extends StatefulWidget {
  const NonCognitiveSkillMasterScreen({super.key});

  @override
  State<NonCognitiveSkillMasterScreen> createState() => _NonCognitiveSkillMasterScreenState();
}

class _NonCognitiveSkillMasterScreenState extends State<NonCognitiveSkillMasterScreen> {
  // Firestoreへの参照
  final CollectionReference _skillsRef =
      FirebaseFirestore.instance.collection('non_cognitive_skills');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('非認知能力マスタ'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      
      // リアルタイムデータ取得
      body: StreamBuilder<QuerySnapshot>(
        stream: _skillsRef.snapshots(),
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
              child: Text(
                'データがありません。\n右下の「＋」で追加してください。',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final strengths = List<String>.from(data['strengths'] ?? []);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.psychology, color: Colors.orange),
                  ),
                  title: Text(
                    data['name'] ?? '名称未設定',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${strengths.length}個の項目'),
                  children: [
                    const Divider(height: 1),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: strengths.length,
                      itemBuilder: (context, sIndex) {
                        return ListTile(
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                          title: Text(strengths[sIndex], style: const TextStyle(fontSize: 14)),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            label: const Text('能力ごと削除', style: TextStyle(color: Colors.red)),
                            onPressed: () => _deleteSkill(doc.id, data['name']),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.edit),
                            label: const Text('編集'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                            onPressed: () => _showEditDialog(doc: doc),
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
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _deleteSkill(String docId, String? name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('$name と、紐づく項目をすべて削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              await _skillsRef.doc(docId).delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 編集・新規登録ダイアログ
  void _showEditDialog({DocumentSnapshot? doc}) {
    final isEditing = doc != null;
    final data = isEditing ? (doc.data() as Map<String, dynamic>) : <String, dynamic>{};
    
    final String initialName = data['name'] ?? '';
    final List<String> initialStrengths = data['strengths'] != null
        ? List<String>.from(data['strengths'])
        : ['']; // 新規時は空の入力欄を1つ用意

    final nameCtrl = TextEditingController(text: initialName);
    // 動的なリスト用のコントローラーリストを作成
    final List<TextEditingController> strengthCtrls = initialStrengths
        .map((text) => TextEditingController(text: text))
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(isEditing ? '非認知能力の編集' : '新規追加'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: '能力名 (例: 自立心)',
                            border: OutlineInputBorder(),
                            filled: true, fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('伸びている力 (項目)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('項目を追加'),
                              onPressed: () {
                                setStateDialog(() {
                                  strengthCtrls.add(TextEditingController());
                                });
                              },
                            ),
                          ],
                        ),

                        ...strengthCtrls.asMap().entries.map((entry) {
                          int i = entry.key;
                          TextEditingController ctrl = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: ctrl,
                                    decoration: InputDecoration(
                                      hintText: '例：自分の持ち物の管理ができる',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      border: const OutlineInputBorder(),
                                      filled: true, fillColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (strengthCtrls.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                    onPressed: () {
                                      setStateDialog(() {
                                        strengthCtrls.removeAt(i);
                                      });
                                    },
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
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                ElevatedButton(
                  onPressed: () async {
                    // 空白の項目を除去してリスト化
                    final List<String> newStrengths = strengthCtrls
                        .map((c) => c.text.trim())
                        .where((text) => text.isNotEmpty)
                        .toList();

                    if (nameCtrl.text.isEmpty) return;

                    final saveData = {
                      'name': nameCtrl.text,
                      'strengths': newStrengths,
                    };

                    if (isEditing) {
                      await _skillsRef.doc(doc.id).update(saveData);
                    } else {
                      await _skillsRef.add(saveData);
                    }
                    
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}