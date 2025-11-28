import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';

class ParentEventScreen extends StatefulWidget {
  final String? childId;
  final String? classroom;

  const ParentEventScreen({
    super.key,
    this.childId,
    this.classroom,
  });

  @override
  State<ParentEventScreen> createState() => _ParentEventScreenState();
}

class _ParentEventScreenState extends State<ParentEventScreen> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader('イベント'),
        Expanded(child: _buildEventList()),
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

  Widget _buildEventList() {
    // 今日以降のイベントのみ表示
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('eventDate', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
          .orderBy('eventDate', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('エラー: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('予定されているイベントはありません', style: TextStyle(color: Colors.grey)),
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
            return _buildEventCard(data);
          },
        );
      },
    );
  }

  Widget _buildEventCard(Map<String, dynamic> data) {
    final title = data['title'] ?? 'イベント';
    final eventDate = data['eventDate'];
    final startTime = data['startTime'] as String? ?? '';
    final endTime = data['endTime'] as String? ?? '';
    final location = data['location'] as String?;
    final address = data['address'] as String?;
    final detail = data['detail'] as String?;
    final imageUrl = data['imageUrl'] as String?;
    final deadline = data['deadline'];
    final link = data['link'] as String?;

    // 日付フォーマット
    String dateStr = '';
    if (eventDate != null && eventDate is Timestamp) {
      final date = eventDate.toDate();
      dateStr = DateFormat('M月d日(E)', 'ja').format(date);
    }

    // 時間フォーマット
    String timeStr = '';
    if (startTime.isNotEmpty) {
      if (endTime.isNotEmpty) {
        timeStr = '$startTime〜$endTime';
      } else {
        timeStr = startTime;
      }
    }

    // 日時まとめ
    String dateTimeStr = dateStr;
    if (timeStr.isNotEmpty) {
      dateTimeStr = '$dateStr $timeStr';
    }

    // 締め切り
    String? deadlineStr;
    if (deadline != null && deadline is Timestamp) {
      deadlineStr = DateFormat('M月d日(E) HH:mm', 'ja').format(deadline.toDate());
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // メイン画像
          if (imageUrl != null && imageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                height: 180,
                color: Colors.grey.shade200,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                height: 180,
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
              ),
            )
          else
            Container(
              height: 120,
              width: double.infinity,
              color: AppColors.primary.withOpacity(0.1),
              child: const Icon(Icons.event, size: 48, color: AppColors.primary),
            ),
          
          // イベント情報
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 日時
                Text(
                  dateTimeStr,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                
                // タイトル
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                
                // 場所
                if (location != null && location.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.location_on, location),
                ],
                
                // 住所
                if (address != null && address.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow(Icons.map_outlined, address),
                ],
                
                // 締め切り
                if (deadlineStr != null) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow(Icons.timer_outlined, '締切: $deadlineStr', color: Colors.orange.shade700),
                ],
                
                // 詳細（一部表示）
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    detail,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                
                // 申し込みリンク
                if (link != null && link.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openLink(link),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('申し込み・詳細はこちら'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, {Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color ?? Colors.grey.shade500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color ?? Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}