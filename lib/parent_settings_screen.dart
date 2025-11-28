import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'app_theme.dart';

class ParentSettingsScreen extends StatefulWidget {
  final Map<String, dynamic>? familyData;
  final List<Map<String, dynamic>> children;
  final int selectedChildIndex;
  final Function(int) onChildChanged;
  final VoidCallback onFamilyUpdated;

  const ParentSettingsScreen({
    super.key,
    required this.familyData,
    required this.children,
    required this.selectedChildIndex,
    required this.onChildChanged,
    required this.onFamilyUpdated,
  });

  @override
  State<ParentSettingsScreen> createState() => _ParentSettingsScreenState();
}

class _ParentSettingsScreenState extends State<ParentSettingsScreen> {
  bool _isUploading = false;

  // 現在選択中の子ども
  Map<String, dynamic>? get _currentChild {
    if (widget.children.isEmpty) return null;
    return widget.children[widget.selectedChildIndex];
  }

  // 子どもの表示名
  String get _currentChildName {
    if (_currentChild == null || widget.familyData == null) return '';
    final lastName = widget.familyData!['lastName'] ?? '';
    final firstName = _currentChild!['firstName'] ?? '';
    return '$lastName $firstName';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader('設定'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 子どもの情報セクション
              _buildSectionTitle('お子さま情報'),
              const SizedBox(height: 8),
              _buildChildCard(),
              
              const SizedBox(height: 24),
              
              // 子どもの写真変更
              _buildSectionTitle('写真の変更'),
              const SizedBox(height: 8),
              _buildPhotoSection(),
              
              const SizedBox(height: 32),
              
              // ログアウト
              _buildLogoutButton(),
              
              const SizedBox(height: 32),
              
              // アプリ情報
              Center(
                child: Text(
                  'Beesmiley v1.0.0',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String title) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade600,
      ),
    );
  }

  Widget _buildChildCard() {
    if (widget.children.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const Text('お子さまの情報がありません'),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 複数の子どもがいる場合は選択UI
            if (widget.children.length > 1) ...[
              ...widget.children.asMap().entries.map((entry) {
                final index = entry.key;
                final child = entry.value;
                final lastName = widget.familyData?['lastName'] ?? '';
                final firstName = child['firstName'] ?? '';
                final isSelected = index == widget.selectedChildIndex;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isSelected 
                        ? AppColors.primary.withOpacity(0.1) 
                        : Colors.grey.shade100,
                    backgroundImage: child['photoUrl'] != null 
                        ? NetworkImage(child['photoUrl']) 
                        : null,
                    child: child['photoUrl'] == null
                        ? Icon(Icons.child_care, color: isSelected ? AppColors.primary : Colors.grey)
                        : null,
                  ),
                  title: Text(
                    '$lastName $firstName',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(child['classroom'] ?? ''),
                  trailing: isSelected 
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : null,
                  onTap: () => widget.onChildChanged(index),
                );
              }),
            ] else ...[
              // 1人の場合はシンプル表示
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    backgroundImage: _currentChild?['photoUrl'] != null 
                        ? NetworkImage(_currentChild!['photoUrl']) 
                        : null,
                    child: _currentChild?['photoUrl'] == null
                        ? const Icon(Icons.child_care, size: 30, color: AppColors.primary)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentChildName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentChild?['classroom'] ?? '',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 現在の写真
            GestureDetector(
              onTap: _isUploading ? null : _pickAndUploadPhoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: _currentChild?['photoUrl'] != null 
                        ? NetworkImage(_currentChild!['photoUrl']) 
                        : null,
                    child: _currentChild?['photoUrl'] == null
                        ? const Icon(Icons.child_care, size: 50, color: Colors.grey)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                  if (_isUploading)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'タップして写真を変更',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showLogoutDialog,
        icon: const Icon(Icons.logout, color: Colors.red),
        label: const Text('ログアウト', style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
    if (picked == null) return;

    setState(() => _isUploading = true);

    try {
      final bytes = await picked.readAsBytes();
      final uid = widget.familyData?['uid'];
      final firstName = _currentChild?['firstName'];
      if (uid == null || firstName == null) throw Exception('データが不足しています');

      // Firebase Storageにアップロード
      final fileName = '${uid}_$firstName.jpg';
      final ref = FirebaseStorage.instance.ref().child('child_photos/$fileName');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final photoUrl = await ref.getDownloadURL();

      // Firestoreを更新
      final familyDoc = await FirebaseFirestore.instance
          .collection('families')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (familyDoc.docs.isNotEmpty) {
        final docId = familyDoc.docs.first.id;
        final children = List<Map<String, dynamic>>.from(
          familyDoc.docs.first.data()['children'] ?? []
        );

        // 該当の子どもの写真URLを更新
        for (int i = 0; i < children.length; i++) {
          if (children[i]['firstName'] == firstName) {
            children[i]['photoUrl'] = photoUrl;
            break;
          }
        }

        await FirebaseFirestore.instance
            .collection('families')
            .doc(docId)
            .update({'children': children});

        // 親画面に更新を通知
        widget.onFamilyUpdated();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('写真を更新しました')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('アップロードに失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseAuth.instance.signOut();
              // AuthCheckWrapperが自動でログイン画面に戻すので、何もしなくてOK
            },
            child: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}