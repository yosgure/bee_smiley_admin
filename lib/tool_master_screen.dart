import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart'; // ★追加: URLを開くためのパッケージ

class ToolMasterScreen extends StatefulWidget {
  const ToolMasterScreen({super.key});

  @override
  State<ToolMasterScreen> createState() => _ToolMasterScreenState();
}

class _ToolMasterScreenState extends State<ToolMasterScreen> {
  final CollectionReference _toolsRef =
      FirebaseFirestore.instance.collection('tools');

  // ★URLを開く関数
  Future<void> _launchURL(BuildContext context, String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      // 外部ブラウザ(YouTube等)で開くモードを指定
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('リンクを開けませんでした: $urlString')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教具マスタ'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: StreamBuilder<QuerySnapshot>(
        stream: _toolsRef.snapshots(),
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
              child: Text('教具が登録されていません。\n右下の「＋」で追加してください。', style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final hasVideo = (data['videoUrl'] as String? ?? '').isNotEmpty;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: data['imageUrl'] != null && (data['imageUrl'] as String).isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: CachedNetworkImage(
                              imageUrl: data['imageUrl'],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          )
                        : const Icon(Icons.extension, color: Colors.grey),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((data['furigana'] as String? ?? '').isNotEmpty)
                        Text(data['furigana'], style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      Text(data['name'] ?? '名称未設定', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.accessibility_new, size: 14, color: Colors.orange),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            data['task'] ?? '',
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasVideo)
                        IconButton(
                          icon: const Icon(Icons.play_circle_fill, color: Colors.red),
                          tooltip: '説明動画を見る',
                          onPressed: () => _launchURL(context, data['videoUrl']), // ★ここを変更
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.grey),
                        onPressed: () => _showEditDialog(doc: doc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteTool(doc.id, data['name']),
                      ),
                    ],
                  ),
                  onTap: () => _showEditDialog(doc: doc),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _deleteTool(String docId, String? name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('$name を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              await _toolsRef.doc(docId).delete();
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
    final data = isEditing ? (doc.data() as Map<String, dynamic>) : <String, dynamic>{};

    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final furiganaCtrl = TextEditingController(text: data['furigana'] ?? '');
    final taskCtrl = TextEditingController(text: data['task'] ?? '');
    final videoCtrl = TextEditingController(text: data['videoUrl'] ?? '');

    String? currentImageUrl = data['imageUrl'];
    File? pickedImageFile;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> _pickImage() async {
              final picker = ImagePicker();
              final picked = await picker.pickImage(source: ImageSource.gallery);
              if (picked != null) {
                setStateDialog(() {
                  pickedImageFile = File(picked.path);
                });
              }
            }

            return AlertDialog(
              title: Text(isEditing ? '教具の編集' : '教具の追加'),
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
                            onTap: _pickImage,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: pickedImageFile != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child: Image.file(pickedImageFile!, fit: BoxFit.cover),
                                    )
                                  : (currentImageUrl != null && currentImageUrl!.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(11),
                                          child: CachedNetworkImage(
                                            imageUrl: currentImageUrl!,
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                            errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                                          ),
                                        )
                                      : const Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.add_a_photo, color: Colors.grey),
                                            Text('写真', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                          ],
                                        )),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(nameCtrl, '教具名'),
                        const SizedBox(height: 8),
                        _buildTextField(furiganaCtrl, 'ふりがな'),
                        const SizedBox(height: 8),
                        _buildTextField(taskCtrl, '発達課題 (例: 指先の微細運動)', icon: Icons.accessibility_new),
                        const SizedBox(height: 8),
                        _buildTextField(videoCtrl, '説明動画URL (YouTubeなど)', icon: Icons.video_library),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                ElevatedButton(
                  onPressed: () async {
                    String? finalImageUrl = currentImageUrl;
                    if (pickedImageFile != null) {
                      final storageRef = FirebaseStorage.instance
                          .ref()
                          .child('tool_photos')
                          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
                      await storageRef.putFile(pickedImageFile!);
                      finalImageUrl = await storageRef.getDownloadURL();
                    }

                    final saveData = {
                      'name': nameCtrl.text,
                      'furigana': furiganaCtrl.text,
                      'task': taskCtrl.text,
                      'videoUrl': videoCtrl.text,
                      'imageUrl': finalImageUrl,
                    };

                    if (isEditing) {
                      await _toolsRef.doc(doc.id).update(saveData);
                    } else {
                      await _toolsRef.add(saveData);
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

  Widget _buildTextField(TextEditingController controller, String label, {IconData? icon}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey, size: 20) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}