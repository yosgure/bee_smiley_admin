import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

class AiChatHistoryScreen extends StatelessWidget {
  final String studentId;
  final String studentName;

  const AiChatHistoryScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_rounded, color: Color(0xFF7C3AED), size: 16),
            ),
            const SizedBox(width: 10),
            Text('$studentName - 相談履歴', style: const TextStyle(fontSize: 16)),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.grey.shade700),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 0.5),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ai_chat_sessions')
            .where('studentId', isEqualTo: studentId)
            .orderBy('updatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  'エラーが発生しました。\nFirestoreのインデックスが必要です:\n\n${snapshot.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'まだ相談履歴がありません',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildSessionCard(context, doc.id, data);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionCard(
      BuildContext context, String sessionId, Map<String, dynamic> data) {
    String dateStr = '';
    if (data['createdAt'] != null) {
      final ts = data['createdAt'] as Timestamp;
      dateStr = DateFormat('yyyy/MM/dd HH:mm', 'ja').format(ts.toDate());
    }

    final staffName = data['staffName'] ?? 'スタッフ';
    final lastMessage = data['lastMessage'] ?? '';
    final summary = data['summary'] as String?;
    final messageCount = data['messageCount'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _openSessionDetail(context, sessionId, data),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    dateStr,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    '$messageCount件',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  staffName,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
              if (summary != null && summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.summarize_rounded, size: 14,
                          color: const Color(0xFF7C3AED).withOpacity(0.5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (lastMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  lastMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openSessionDetail(
      BuildContext context, String sessionId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatSessionDetailScreen(
          sessionId: sessionId,
          studentName: studentName,
          sessionData: data,
        ),
      ),
    );
  }
}

// ==========================================
// セッション詳細画面（過去の会話を閲覧）
// ==========================================

class AiChatSessionDetailScreen extends StatelessWidget {
  final String sessionId;
  final String studentName;
  final Map<String, dynamic> sessionData;

  const AiChatSessionDetailScreen({
    super.key,
    required this.sessionId,
    required this.studentName,
    required this.sessionData,
  });

  @override
  Widget build(BuildContext context) {
    String dateStr = '';
    if (sessionData['createdAt'] != null) {
      final ts = sessionData['createdAt'] as Timestamp;
      dateStr = DateFormat('yyyy/MM/dd HH:mm', 'ja').format(ts.toDate());
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('$studentName - $dateStr', style: const TextStyle(fontSize: 15)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.grey.shade700),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 0.5),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ai_chat_sessions')
            .doc(sessionId)
            .collection('messages')
            .orderBy('createdAt', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('メッセージがありません'));
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final msg = docs[index].data() as Map<String, dynamic>;
                  return _buildMessageItem(context, msg);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageItem(BuildContext context, Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final content = msg['content'] ?? '';

    String timeStr = '';
    if (msg['createdAt'] != null) {
      final ts = msg['createdAt'] as Timestamp;
      timeStr = DateFormat('HH:mm').format(ts.toDate());
    }

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: SelectableText(
                content,
                style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
              ),
            ),
            if (timeStr.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Text(
                  timeStr,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  content,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                    height: 1.6,
                  ),
                ),
                if (timeStr.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      timeStr,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
