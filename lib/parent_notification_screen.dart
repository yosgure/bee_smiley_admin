import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
import 'skeleton_loading.dart';

class ParentNotificationScreen extends StatefulWidget {
  const ParentNotificationScreen({super.key});

  @override
  State<ParentNotificationScreen> createState() => _ParentNotificationScreenState();
}

class _ParentNotificationScreenState extends State<ParentNotificationScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;
  String? _selectedNotificationId;

  @override
  Widget build(BuildContext context) {
    // 詳細画面が選択されている場合
    if (_selectedNotificationId != null) {
      return _buildNotificationDetail();
    }

    // 一覧画面
    return Column(
      children: [
        _buildHeader('お知らせ'),
        Expanded(child: _buildNotificationList()),
      ],
    );
  }

  Widget _buildHeader(String title, {bool showBack = false}) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showBack)
            Positioned(
              left: 0,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.black54),
                onPressed: () => setState(() => _selectedNotificationId = null),
              ),
            ),
          Center(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('エラー: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const NotificationListSkeleton();
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('お知らせはありません', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;

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
    );
  }

  Widget _buildNotificationCard(String id, Map<String, dynamic> data) {
    final title = data['title'] ?? 'タイトルなし';
    final body = data['body'] ?? '';
    final createdAt = data['createdAt'] as Timestamp?;
    final hasAttachment = data['attachmentUrl'] != null && data['attachmentUrl'].toString().isNotEmpty;

    String dateStr = '';
    if (createdAt != null) {
      dateStr = DateFormat('yyyy/MM/dd HH:mm').format(createdAt.toDate());
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedNotificationId = id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasAttachment)
                    const Icon(Icons.attach_file, size: 18, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                dateStr,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationDetail() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .doc(_selectedNotificationId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const NotificationListSkeleton();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return const Center(child: Text('お知らせが見つかりません'));
        }

        final title = data['title'] ?? 'タイトルなし';
        final body = data['body'] ?? '';
        final createdAt = data['createdAt'] as Timestamp?;
        final attachmentUrl = data['attachmentUrl'] as String?;
        final attachmentName = data['attachmentName'] as String?;

        String dateStr = '';
        if (createdAt != null) {
          dateStr = DateFormat('yyyy年M月d日 HH:mm').format(createdAt.toDate());
        }

        return Column(
          children: [
            _buildHeader('お知らせ', showBack: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // タイトル
                    Text(
                      title,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    // 日時
                    Text(
                      dateStr,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    // 本文
                    Text(
                      body,
                      style: const TextStyle(fontSize: 15, height: 1.6),
                    ),
                    // 添付ファイル
                    if (attachmentUrl != null && attachmentUrl.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      const Text(
                        '添付ファイル',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final Uri url = Uri.parse(attachmentUrl);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.description, color: AppColors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  attachmentName ?? 'ファイル',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              const Icon(Icons.download, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}