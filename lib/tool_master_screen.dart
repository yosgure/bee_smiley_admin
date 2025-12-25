import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

class ToolMasterScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ToolMasterScreen({super.key, this.onBack});

  @override
  State<ToolMasterScreen> createState() => _ToolMasterScreenState();
}

class _ToolMasterScreenState extends State<ToolMasterScreen> {
  final CollectionReference _toolsRef =
      FirebaseFirestore.instance.collection('tools');

  // 検索用
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.orange,
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

  // URLを開く関数
  Future<void> _launchURL(BuildContext context, String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
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
      body: Column(
        children: [
          // 検索窓
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '教具名で検索...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.orange),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          // リスト部分
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _toolsRef.snapshots(),
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
                    child: Text('教具が登録されていません。\n右下の「＋」で追加してください。', style: TextStyle(color: Colors.grey)),
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

                // 検索フィルタリング
                final filteredDocs = _searchQuery.isEmpty
                    ? docs
                    : docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final name = (data['name'] ?? '').toString().toLowerCase();
                        final furigana = (data['furigana'] ?? '').toString().toLowerCase();
                        final task = (data['task'] ?? '').toString().toLowerCase();
                        
                        return name.contains(_searchQuery) ||
                               furigana.contains(_searchQuery) ||
                               task.contains(_searchQuery);
                      }).toList();

                // 検索結果0件の場合
                if (filteredDocs.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          '「$_searchQuery」に一致する教具がありません',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                // リスト表示用のウィジェットリストを作成
                List<Widget> listWidgets = [];
                String currentHeader = '';

                for (var doc in filteredDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final furigana = data['furigana'] ?? '';
                  final header = _getKanaRow(furigana);

                  // 行が変わったらヘッダーを挿入
                  if (header != currentHeader) {
                    currentHeader = header;
                    listWidgets.add(_buildSectionHeader(header));
                  }

                  final hasVideo = (data['videoUrl'] as String? ?? '').isNotEmpty;

                  listWidgets.add(
                    Card(
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
                                onPressed: () => _launchURL(context, data['videoUrl']),
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
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: listWidgets,
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, 
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
            Future<void> pickImage() async {
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
                            onTap: pickImage,
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