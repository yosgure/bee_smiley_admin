import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'ai_chat_history_screen.dart';

class AiChatScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final Map<String, dynamic>? studentInfo;
  final Map<String, dynamic>? supportPlan;
  final String? existingSessionId;  // 既存セッションを開く場合
  final bool showBackButton;  // 戻るボタンを表示するか
  final VoidCallback? onBackPressed;  // 戻るボタン押下時のコールバック

  const AiChatScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentInfo,
    this.supportPlan,
    this.existingSessionId,
    this.showBackButton = true,
    this.onBackPressed,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast1');
  final currentUser = FirebaseAuth.instance.currentUser;

  String? _sessionId;
  bool _isLoading = true;
  bool _isSending = false;
  String? _staffName;

  // Optimistic UI用の一時メッセージ
  Map<String, dynamic>? _pendingUserMessage;
  bool _isWaitingForAiResponse = false;

  // HUGアセスメント情報
  String? _hugAssessment;

  // 過去セッションの要約（最新3件）
  List<Map<String, String>> _pastSummaries = [];

  // 要約生成済みフラグ（二重実行防止）
  bool _isSummarizing = false;

  // スクロール制御用
  int _previousMessageCount = 0;
  String? _lastMessageRole;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    // 画面を離れる時にセッションを要約（fire-and-forget）
    _summarizeCurrentSession();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    try {
      // スタッフ名を取得
      if (currentUser != null) {
        final staffSnap = await FirebaseFirestore.instance
            .collection('staffs')
            .where('uid', isEqualTo: currentUser!.uid)
            .limit(1)
            .get();
        if (staffSnap.docs.isNotEmpty) {
          _staffName = staffSnap.docs.first.data()['name'] ?? 'スタッフ';
        }
      }

      final isFreeChat = widget.studentId.startsWith('free_chat');

      // 既存セッションIDが指定されている場合はそのセッションを使用
      if (widget.existingSessionId != null) {
        final sessionDoc = await FirebaseFirestore.instance
            .collection('ai_chat_sessions')
            .doc(widget.existingSessionId)
            .get();
        if (sessionDoc.exists) {
          final sessionData = sessionDoc.data()!;
          if (mounted) {
            setState(() {
              _sessionId = widget.existingSessionId;
              _hugAssessment = sessionData['hugAssessment'] as String?;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // 生徒選択の場合のみ既存セッションを検索
      if (!isFreeChat) {
        final today = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day);
        final myUid = currentUser?.uid ?? '';

        // HUGアセスメントを全スタッフ横断で最新のものから検索（最新10件に制限）
        final hugSnap = await FirebaseFirestore.instance
            .collection('ai_chat_sessions')
            .where('studentId', isEqualTo: widget.studentId)
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        for (final session in hugSnap.docs) {
          final assessment = session.data()['hugAssessment'] as String?;
          if (assessment != null && assessment.isNotEmpty) {
            _hugAssessment = assessment;
            break;
          }
        }

        // 自分のセッションのみ取得（要約・今日のセッション用、最新10件に制限）
        final mySessionsSnap = await FirebaseFirestore.instance
            .collection('ai_chat_sessions')
            .where('studentId', isEqualTo: widget.studentId)
            .where('staffId', isEqualTo: myUid)
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        final mySessions = mySessionsSnap.docs;

        if (mySessions.isNotEmpty) {
          // 自分の過去セッションからsummaryを最新3件取得
          final summaries = <Map<String, String>>[];
          for (final session in mySessions) {
            final data = session.data();
            final summary = data['summary'] as String?;
            if (summary != null && summary.isNotEmpty) {
              final createdAt = data['createdAt'] as Timestamp?;
              String dateStr = '日付不明';
              if (createdAt != null) {
                dateStr = DateFormat('M/d').format(createdAt.toDate());
              }
              summaries.add({'date': dateStr, 'summary': summary});
              if (summaries.length >= 3) break;
            }
          }
          _pastSummaries = summaries;

          // 今日の自分のセッションがあればそれを使用
          final todaySessions = mySessions.where((doc) {
            final createdAt = doc.data()['createdAt'] as Timestamp?;
            return createdAt != null && createdAt.toDate().isAfter(startOfDay);
          }).toList();

          if (todaySessions.isNotEmpty) {
            if (mounted) {
              setState(() {
                _sessionId = todaySessions.first.id;
                _isLoading = false;
              });
            }
            return;
          }
        }
      }

      // 新規セッションを作成（過去のhugAssessment・要約を引き継ぐ）
      final sessionRef =
          FirebaseFirestore.instance.collection('ai_chat_sessions').doc();
      final sessionData = <String, dynamic>{
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'staffId': currentUser?.uid ?? '',
        'staffName': _staffName ?? 'スタッフ',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'messageCount': 0,
        'context': {
          'studentInfo': widget.studentInfo,
          'supportPlan': widget.supportPlan,
          'recentMonitorings': widget.supportPlan?['monitorings'] ?? [],
        },
      };
      // 過去セッションからhugAssessmentがあれば新規セッションにも保存
      if (_hugAssessment != null && _hugAssessment!.isNotEmpty) {
        sessionData['hugAssessment'] = _hugAssessment;
      }
      // 過去セッションの要約を新規セッションにも保存（参照用）
      if (_pastSummaries.isNotEmpty) {
        sessionData['pastSummaries'] = _pastSummaries;
      }
      await sessionRef.set(sessionData);

      if (mounted) {
        setState(() {
          _sessionId = sessionRef.id;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing session: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('セッションの作成に失敗しました: $e')),
        );
      }
    }
  }

  Map<String, dynamic> _buildContext() {
    // studentIdが'free_chat'で始まる場合は自由チャットモード
    final isFreeChat = widget.studentId.startsWith('free_chat');
    return {
      'studentInfo': isFreeChat ? null : widget.studentInfo,
      'supportPlan': isFreeChat ? null : widget.supportPlan,
      'recentMonitorings': isFreeChat ? [] : (widget.supportPlan?['monitorings'] ?? []),
      'hugAssessment': isFreeChat ? null : _hugAssessment,
      'pastSummaries': isFreeChat ? [] : _pastSummaries,
      'isFreeChat': isFreeChat,
    };
  }

  Future<void> _sendMessage() async {
    final messageText = _textController.text.trim();
    if (messageText.isEmpty || _isSending || _sessionId == null) return;

    _textController.clear();
    _focusNode.unfocus();

    setState(() {
      _isSending = true;
      _pendingUserMessage = {
        'role': 'user',
        'content': messageText,
        'createdAt': Timestamp.now(),
        'status': 'sending',
      };
      _isWaitingForAiResponse = true;
    });

    // スクロール
    _scrollToBottom();

    try {
      final callable = _functions.httpsCallable('sendAiMessage');
      await callable.call({
        'sessionId': _sessionId,
        'message': messageText,
        'context': _buildContext(),
      });

      if (mounted) {
        setState(() {
          _pendingUserMessage = null;
          _isWaitingForAiResponse = false;
        });
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        setState(() {
          _pendingUserMessage = null;
          _isWaitingForAiResponse = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('メッセージの送信に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showChatHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildHistoryBottomSheet(ctx),
    );
  }

  Widget _buildHistoryBottomSheet(BuildContext ctx) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // ハンドル
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // タイトル
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${widget.studentName} - 相談履歴',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // セッション一覧
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('ai_chat_sessions')
                    .where('studentId', isEqualTo: widget.studentId)
                    .orderBy('createdAt', descending: true)
                    .limit(30)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          'エラーが発生しました:\n${snapshot.error}',
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'まだ相談履歴がありません',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    );
                  }

                  final today = DateTime.now();
                  final startOfDay = DateTime(today.year, today.month, today.day);

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final isCurrentSession = doc.id == _sessionId;

                      // 日付
                      String dateStr = '';
                      bool isToday = false;
                      if (data['createdAt'] != null) {
                        final ts = data['createdAt'] as Timestamp;
                        final date = ts.toDate();
                        isToday = date.isAfter(startOfDay);
                        dateStr = isToday
                            ? '今日 ${DateFormat('HH:mm').format(date)}'
                            : DateFormat('yyyy/MM/dd HH:mm').format(date);
                      }

                      final staffName = data['staffName'] ?? 'スタッフ';
                      final lastMessage = data['lastMessage'] ?? '';
                      final summary = data['summary'] as String?;
                      final messageCount = data['messageCount'] ?? 0;

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isCurrentSession
                                ? Colors.purple.shade300
                                : Colors.grey.shade200,
                            width: isCurrentSession ? 2 : 1,
                          ),
                        ),
                        color: isCurrentSession
                            ? Colors.purple.shade50
                            : Colors.white,
                        child: InkWell(
                          onTap: isCurrentSession
                              ? () => Navigator.pop(ctx)
                              : () {
                                  Navigator.pop(ctx);
                                  // 読み取り専用で過去セッションを閲覧
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AiChatSessionDetailScreen(
                                        sessionId: doc.id,
                                        studentName: widget.studentName,
                                        sessionData: data,
                                      ),
                                    ),
                                  );
                                },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.smart_toy,
                                      size: 18,
                                      color: isCurrentSession
                                          ? Colors.purple.shade600
                                          : Colors.purple.shade400,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isCurrentSession
                                            ? Colors.purple.shade700
                                            : Colors.black87,
                                      ),
                                    ),
                                    if (isToday) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '今日',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.accent.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (isCurrentSession) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '現在',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    Text(
                                      '$messageCount件',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                // 要約があれば表示
                                if (summary != null && summary.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.summarize, size: 14,
                                            color: Colors.blue.shade400),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            summary,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blue.shade900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (lastMessage.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    lastMessage,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                                // スタッフ名
                                const SizedBox(height: 4),
                                Text(
                                  staffName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 画面離脱時にセッションの会話を自動要約（Cloud Functions経由）
  Future<void> _summarizeCurrentSession() async {
    if (_sessionId == null || _isSummarizing) return;
    _isSummarizing = true;

    try {
      final callable = _functions.httpsCallable('summarizeSession');
      await callable.call({'sessionId': _sessionId});
    } catch (e) {
      debugPrint('Error summarizing session: $e');
    }
  }

  void _showHugAssessmentDialog() {
    final controller = TextEditingController(text: _hugAssessment ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('HUGアセスメント情報'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HUGからコピーしたアセスメント情報を貼り付けてください',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 10,
                decoration: InputDecoration(
                  hintText: '症状、得意なこと、気をつけてほしいこと など...',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              await _saveHugAssessment(text.isEmpty ? null : text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade600,
            ),
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveHugAssessment(String? assessment) async {
    if (_sessionId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('ai_chat_sessions')
          .doc(_sessionId)
          .update({
        'hugAssessment': assessment,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _hugAssessment = assessment;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(assessment != null
                ? 'HUGアセスメント情報を保存しました'
                : 'HUGアセスメント情報を削除しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(widget.studentName),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.black54),
                onPressed: widget.onBackPressed ?? () => Navigator.pop(context),
              )
            : null,
        actions: [
          // HUGアセスメント情報ボタン
          IconButton(
            icon: Icon(
              _hugAssessment != null && _hugAssessment!.isNotEmpty
                  ? Icons.description
                  : Icons.description_outlined,
              color: _hugAssessment != null && _hugAssessment!.isNotEmpty
                  ? Colors.green
                  : AppColors.primary,
            ),
            tooltip: 'HUGアセスメント情報',
            onPressed: _showHugAssessmentDialog,
          ),
          // 履歴ボタン
          IconButton(
            icon: const Icon(Icons.history, color: AppColors.primary),
            tooltip: '相談履歴',
            onPressed: _showChatHistory,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade300, height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _buildMessageList()),
                if (_isSending) const LinearProgressIndicator(),
                _buildInputArea(),
              ],
            ),
    );
  }

  Widget _buildStudentInfoCard() {
    final info = widget.studentInfo;
    if (info == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white,
            backgroundImage: AssetImage('assets/logo_beesmileymark.png'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${info['lastName'] ?? ''} ${info['firstName'] ?? ''} さんの相談',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${info['age'] ?? ''}・${info['gender'] ?? ''}・${info['classroom'] ?? ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (info['diagnosis'] != null &&
                    info['diagnosis'].toString().isNotEmpty)
                  Text(
                    '診断: ${info['diagnosis']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHugAssessmentButton() {
    final hasAssessment = _hugAssessment != null && _hugAssessment!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: _showHugAssessmentDialog,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: hasAssessment ? Colors.green.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasAssessment ? Colors.green.shade200 : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasAssessment ? Icons.check_circle : Icons.add_circle_outline,
                size: 20,
                color: hasAssessment ? Colors.green.shade600 : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                hasAssessment ? 'HUGアセスメント情報 (追加済み)' : 'HUGアセスメント情報を追加',
                style: TextStyle(
                  fontSize: 13,
                  color: hasAssessment ? Colors.green.shade700 : Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.edit,
                size: 16,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_sessionId == null) {
      return const Center(child: Text('セッションを準備中...'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ai_chat_sessions')
          .doc(_sessionId)
          .collection('messages')
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('エラー: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];

        // Optimistic UI: pending messageとwaiting indicatorを追加
        final allMessages = <Map<String, dynamic>>[];

        for (final doc in docs) {
          allMessages.add({
            ...doc.data() as Map<String, dynamic>,
            'id': doc.id,
          });
        }

        // ペンディングのユーザーメッセージを追加（重複チェック）
        if (_pendingUserMessage != null) {
          final pendingContent = _pendingUserMessage!['content'];
          final isDuplicate = allMessages.any((m) =>
              m['role'] == 'user' && m['content'] == pendingContent);
          if (!isDuplicate) {
            allMessages.add(_pendingUserMessage!);
          }
        }

        // 空の場合は何も表示しない
        if (allMessages.isEmpty) {
          return const SizedBox.shrink();
        }

        // スクロール制御
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;

          final currentCount = allMessages.length;
          final lastRole = allMessages.isNotEmpty ? allMessages.last['role'] : null;

          // 初回表示時は最下部にスクロール
          if (_previousMessageCount == 0 && currentCount > 0) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          } else if (currentCount > _previousMessageCount) {
            // 新しいメッセージが追加された
            if (lastRole == 'assistant') {
              // AI応答: 最後から2番目のメッセージ（ユーザーの質問）の位置にスクロール
              final userMessageIndex = currentCount - 2;
              if (userMessageIndex >= 0) {
                final targetPosition = userMessageIndex * 80.0;
                _scrollController.animateTo(
                  targetPosition.clamp(0.0, _scrollController.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            } else if (lastRole == 'user') {
              // ユーザーメッセージ: 一番下にスクロール
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          }

          _previousMessageCount = currentCount;
          _lastMessageRole = lastRole;
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: allMessages.length,
          itemBuilder: (context, index) {
            return _buildMessageItem(allMessages[index]);
          },
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white,
            backgroundImage: AssetImage('assets/logo_beesmileymark.png'),
          ),
          const SizedBox(width: 8),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.purple.shade400,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'AIが考え中...',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final content = msg['content'] ?? '';
    final status = msg['status'];
    final isSending = status == 'sending';

    String timeStr = '';
    if (msg['createdAt'] != null) {
      final ts = msg['createdAt'] as Timestamp;
      timeStr = DateFormat('HH:mm').format(ts.toDate());
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isUser) ...[
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    backgroundImage: AssetImage('assets/logo_beesmileymark.png'),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.primary.withOpacity(0.2)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      content,
                      style: TextStyle(
                        fontSize: 15,
                        color: isSending ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ),
                ),
                if (isUser) const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSending)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                if (timeStr.isNotEmpty)
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (_textController.value.composing.isValid) {
                    return KeyEventResult.ignored;
                  }
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _sendMessage();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: null,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  enabled: !_isSending,
                  decoration: InputDecoration(
                    hintText: '相談...',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isSending ? null : _sendMessage,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isSending
                      ? Colors.grey.shade400
                      : Colors.purple.shade600,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
