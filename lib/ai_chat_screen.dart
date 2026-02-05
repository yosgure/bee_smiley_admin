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

  const AiChatScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentInfo,
    this.supportPlan,
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

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
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

      // 既存のセッションを検索（今日作成されたもの）
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      // インデックス不要のシンプルなクエリ
      final sessionsSnap = await FirebaseFirestore.instance
          .collection('ai_chat_sessions')
          .where('studentId', isEqualTo: widget.studentId)
          .get();

      // クライアント側でフィルタ・ソート
      final sessions = sessionsSnap.docs.where((doc) {
        final data = doc.data();
        if (data['staffId'] != (currentUser?.uid ?? '')) return false;
        final createdAt = data['createdAt'] as Timestamp?;
        return createdAt != null && createdAt.toDate().isAfter(startOfDay);
      }).toList();

      // 最新のセッションを使用
      if (sessions.isNotEmpty) {
        sessions.sort((a, b) {
          final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return bTime.compareTo(aTime);
        });
        final sessionData = sessions.first.data();
        if (mounted) {
          setState(() {
            _sessionId = sessions.first.id;
            _hugAssessment = sessionData['hugAssessment'] as String?;
            _isLoading = false;
          });
        }
        return;
      }

      // 新規セッションを作成
      final sessionRef =
          FirebaseFirestore.instance.collection('ai_chat_sessions').doc();
      await sessionRef.set({
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
      });

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
    return {
      'studentInfo': widget.studentInfo,
      'supportPlan': widget.supportPlan,
      'recentMonitorings': widget.supportPlan?['monitorings'] ?? [],
      'hugAssessment': _hugAssessment,
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatHistoryScreen(
          studentId: widget.studentId,
          studentName: widget.studentName,
        ),
      ),
    );
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
        title: Text('${widget.studentName} - AI相談'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
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
                _buildStudentInfoCard(),
                _buildHugAssessmentButton(),
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
          Icon(Icons.smart_toy, color: Colors.purple.shade400, size: 32),
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

        // ペンディングのユーザーメッセージを追加
        if (_pendingUserMessage != null) {
          allMessages.add(_pendingUserMessage!);
        }

        if (allMessages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    '個別支援計画について\nAIに相談してみましょう',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: allMessages.length + (_isWaitingForAiResponse ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == allMessages.length && _isWaitingForAiResponse) {
              return _buildTypingIndicator();
            }
            return _buildMessageItem(allMessages[index]);
          },
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
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
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.purple.shade100,
                    child: Icon(Icons.smart_toy,
                        size: 18, color: Colors.purple.shade700),
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
                    hintText: '個別支援計画について相談...',
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
