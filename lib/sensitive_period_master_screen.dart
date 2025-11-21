import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore

class SensitivePeriodMasterScreen extends StatefulWidget {
  const SensitivePeriodMasterScreen({super.key});

  @override
  State<SensitivePeriodMasterScreen> createState() => _SensitivePeriodMasterScreenState();
}

class _SensitivePeriodMasterScreenState extends State<SensitivePeriodMasterScreen> {
  // Firestoreへの参照
  final CollectionReference _periodsRef =
      FirebaseFirestore.instance.collection('sensitive_periods');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('敏感期リスト'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      
      // リアルタイムデータ取得
      body: StreamBuilder<QuerySnapshot>(
        stream: _periodsRef.snapshots(),
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
              final behaviors = List<String>.from(data['behaviors'] ?? []);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.hourglass_top, color: Colors.purple),
                  ),
                  title: Text(
                    data['name'] ?? '名称未設定',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '目安: ${data['startAge']}歳 〜 ${data['endAge']}歳頃',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          // 意味
                          _buildLabel('この時期の意味'),
                          Text(data['meaning'] ?? '', style: const TextStyle(height: 1.4)),
                          const SizedBox(height: 12),
                          
                          // よくある姿
                          _buildLabel('よくある姿（行動例）'),
                          if (behaviors.isEmpty) const Text('登録なし', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ...behaviors.map((b) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.check, size: 16, color: Colors.purple),
                                const SizedBox(width: 8),
                                Expanded(child: Text(b, style: const TextStyle(fontSize: 13))),
                              ],
                            ),
                          )).toList(),
                          const SizedBox(height: 12),

                          // アドバイス
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.purple.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.lightbulb, size: 16, color: Colors.purple.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      '親へのアドバイス',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700, fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(data['advice'] ?? '', style: const TextStyle(fontSize: 13, height: 1.4)),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          // 編集・削除ボタン
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                label: const Text('削除', style: TextStyle(color: Colors.red)),
                                onPressed: () => _deletePeriod(doc.id, data['name']),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.edit),
                                label: const Text('編集'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
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
        backgroundColor: Colors.purple,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12),
      ),
    );
  }

  void _deletePeriod(String docId, String? name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('$name を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              await _periodsRef.doc(docId).delete();
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
    
    // データの準備
    final String initialName = data['name'] ?? '';
    final String initialStartAge = (data['startAge'] ?? 0.0).toString();
    final String initialEndAge = (data['endAge'] ?? 3.0).toString();
    final String initialMeaning = data['meaning'] ?? '';
    final String initialAdvice = data['advice'] ?? '';
    
    final List<String> initialBehaviors = data['behaviors'] != null
        ? List<String>.from(data['behaviors'])
        : ['']; // 新規時は空欄1つ

    // コントローラー
    final nameCtrl = TextEditingController(text: initialName);
    final startAgeCtrl = TextEditingController(text: initialStartAge);
    final endAgeCtrl = TextEditingController(text: initialEndAge);
    final meaningCtrl = TextEditingController(text: initialMeaning);
    final adviceCtrl = TextEditingController(text: initialAdvice);
    
    // 動的リスト用のコントローラー
    final List<TextEditingController> behaviorCtrls = initialBehaviors
        .map((text) => TextEditingController(text: text))
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(isEditing ? '敏感期の編集' : '新規追加'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 名前
                        _buildTextField(nameCtrl, '敏感期名 (例: 秩序の敏感期)', icon: Icons.hourglass_top),
                        const SizedBox(height: 12),
                        
                        // 年齢範囲
                        const Text('出現時期 (目安)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(startAgeCtrl, '開始年齢 (歳)', type: TextInputType.number)),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text('〜'),
                            ),
                            Expanded(child: _buildTextField(endAgeCtrl, '終了年齢 (歳)', type: TextInputType.number)),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 意味
                        _buildTextField(meaningCtrl, 'この時期の意味・目的', maxLines: 2),
                        const SizedBox(height: 24),

                        // よくある姿（動的リスト）
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('よくある姿 (行動例)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('行動を追加'),
                              onPressed: () {
                                setStateDialog(() {
                                  behaviorCtrls.add(TextEditingController());
                                });
                              },
                            ),
                          ],
                        ),
                        ...behaviorCtrls.asMap().entries.map((entry) {
                          int i = entry.key;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: entry.value,
                                    decoration: const InputDecoration(
                                      hintText: '例：同じ道順じゃないと泣く',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      filled: true, fillColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (behaviorCtrls.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                    onPressed: () => setStateDialog(() => behaviorCtrls.removeAt(i)),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),

                        const SizedBox(height: 24),

                        // アドバイス
                        _buildTextField(adviceCtrl, '親へのアドバイス・関わり方', maxLines: 3, icon: Icons.lightbulb_outline),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                ElevatedButton(
                  onPressed: () async {
                    final newBehaviors = behaviorCtrls
                        .map((c) => c.text.trim())
                        .where((t) => t.isNotEmpty).toList();

                    final saveData = {
                      'name': nameCtrl.text,
                      'startAge': double.tryParse(startAgeCtrl.text) ?? 0.0,
                      'endAge': double.tryParse(endAgeCtrl.text) ?? 0.0,
                      'meaning': meaningCtrl.text,
                      'behaviors': newBehaviors,
                      'advice': adviceCtrl.text,
                    };

                    if (isEditing) {
                      await _periodsRef.doc(doc.id).update(saveData);
                    } else {
                      await _periodsRef.add(saveData);
                    }
                    
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {IconData? icon, int maxLines = 1, TextInputType? type}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
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