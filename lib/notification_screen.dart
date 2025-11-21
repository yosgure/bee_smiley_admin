import 'dart:typed_data'; // Web対応用

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart'; // ファイル選択用
import 'package:url_launcher/url_launcher.dart'; // リンクを開く用
import 'package:intl/intl.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final CollectionReference _notificationsRef =
      FirebaseFirestore.instance.collection('notifications');

  Future<void> _launchURL(BuildContext context, String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ファイルを開けませんでした')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お知らせ'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: StreamBuilder<QuerySnapshot>(
        stream: _notificationsRef.orderBy('createdAt', descending: true).snapshots(),
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
              child: Text('お知らせはありません', style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              return _buildNotificationCard(doc.id, data);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NotificationCreateScreen()),
          );
        },
        backgroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/logo_beesmileymark.png'),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(String docId, Map<String, dynamic> item) {
    final Timestamp createdAt = item['createdAt'];
    final String dateStr = DateFormat('yyyy/MM/dd').format(createdAt.toDate());
    
    final String? fileUrl = item['fileUrl'];
    final String? fileName = item['fileName'];
    final String fileType = item['fileType'] ?? 'other'; // 'image' or 'pdf'

    IconData fileIcon = Icons.insert_drive_file;
    Color fileColor = Colors.grey;
    if (fileType == 'pdf') {
      fileIcon = Icons.picture_as_pdf;
      fileColor = Colors.red;
    } else if (fileType == 'image') {
      fileIcon = Icons.image;
      fileColor = Colors.green;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー（日付と削除ボタン）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                  onPressed: () => _deleteNotification(docId),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // タイトル
            Text(
              item['title'] ?? '無題',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            // 本文
            Text(
              item['detail'] ?? '',
              style: const TextStyle(height: 1.5, fontSize: 14),
            ),
            
            // 添付ファイル
            if (fileUrl != null && fileUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: () => _launchURL(context, fileUrl),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(fileIcon, color: fileColor, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName ?? '添付ファイル',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'タップして開く',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.open_in_new, color: Colors.grey, size: 20),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _deleteNotification(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: const Text('このお知らせを削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              await _notificationsRef.doc(docId).delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// お知らせ作成画面
// ==========================================
class NotificationCreateScreen extends StatefulWidget {
  const NotificationCreateScreen({super.key});

  @override
  State<NotificationCreateScreen> createState() => _NotificationCreateScreenState();
}

class _NotificationCreateScreenState extends State<NotificationCreateScreen> {
  final _titleController = TextEditingController();
  final _detailController = TextEditingController();
  
  Uint8List? _fileBytes; // Web対応のためバイトデータで保持
  String? _fileName;
  String? _fileExtension;
  bool _isUploading = false;

  // ファイル選択（画像 or PDF）
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true, // Webでは必須
      );

      if (result != null) {
        final file = result.files.first;
        setState(() {
          _fileBytes = file.bytes;
          _fileName = file.name;
          _fileExtension = file.extension;
        });
      }
    } catch (e) {
      debugPrint('File pick error: $e');
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('タイトルを入力してください')));
      return;
    }

    setState(() => _isUploading = true);

    try {
      String? fileUrl;
      String? fileType;

      // ファイルアップロード
      if (_fileBytes != null) {
        final String ext = _fileExtension ?? 'dat';
        if (['jpg', 'jpeg', 'png'].contains(ext.toLowerCase())) {
          fileType = 'image';
        } else if (ext.toLowerCase() == 'pdf') {
          fileType = 'pdf';
        }

        // Storageのパス: notifications/{timestamp}_{filename}
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('notifications')
            .child('${DateTime.now().millisecondsSinceEpoch}_$_fileName');
        
        // メタデータを設定してアップロード（PDFなどをブラウザで正しく開くため）
        final metadata = SettableMetadata(
          contentType: fileType == 'pdf' ? 'application/pdf' : 'image/jpeg',
        );

        await storageRef.putData(_fileBytes!, metadata);
        fileUrl = await storageRef.getDownloadURL();
      }

      // Firestoreに保存
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': _titleController.text,
        'detail': _detailController.text,
        'fileUrl': fileUrl,
        'fileName': _fileName,
        'fileType': fileType,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('お知らせを配信しました')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('お知らせ作成'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isUploading ? null : _submit,
            child: _isUploading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('配信', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('タイトル', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: '例：春の遠足について',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true, fillColor: Colors.white,
              ),
            ),
            
            const SizedBox(height: 24),

            const Text('詳細', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _detailController,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: '詳細内容を入力してください...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true, fillColor: Colors.white,
              ),
            ),

            const SizedBox(height: 24),

            const Text('添付ファイル (画像またはPDF)', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            
            if (_fileName == null)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  label: const Text('ファイルを選択', style: TextStyle(color: Colors.black87)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    Icon(
                      _fileExtension == 'pdf' ? Icons.picture_as_pdf : Icons.image,
                      color: _fileExtension == 'pdf' ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _fileName!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () {
                        setState(() {
                          _fileBytes = null;
                          _fileName = null;
                          _fileExtension = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}