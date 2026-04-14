import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'web_helpers_stub.dart'
    if (dart.library.html) 'web_helpers.dart' as web_helpers;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'ai_chat_history_screen.dart';
import 'app_theme.dart';

class AiChatScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final Map<String, dynamic>? studentInfo;
  final Map<String, dynamic>? supportPlan;
  final String? existingSessionId;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final String? initialMessage;

  const AiChatScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentInfo,
    this.supportPlan,
    this.existingSessionId,
    this.showBackButton = true,
    this.onBackPressed,
    this.initialMessage,
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

  Map<String, dynamic>? _pendingUserMessage;
  bool _isWaitingForAiResponse = false;

  String? _hugAssessment;
  List<Map<String, String>> _pastSummaries = [];
  bool _isSummarizing = false;

  int _previousMessageCount = 0;

  // 添付ファイル
  List<_AttachedFile> _attachedFiles = [];
  bool _isUploading = false;

  // 入力状態
  bool _hasText = false;

  // hug送信失敗バナー（セッション内のみ保持）
  // 各要素: {category, content, date(DateTime), studentId, studentName, recorderName, recorderId, error}
  final List<Map<String, dynamic>> _failedHugSends = [];

  // スラッシュコマンド
  bool _showSlashMenu = false;
  String _slashFilter = '';
  List<Map<String, dynamic>> _commands = [];

  // エリシテーション
  bool _elicitationMode = false;
  Map<String, dynamic>? _elicitationCommand;
  int _elicitationStep = 0;
  List<String> _elicitationAnswers = [];
  final _elicitationTextController = TextEditingController();

  // フリーフォーム（自由記述）モード
  bool _freeformMode = false;
  Map<String, dynamic>? _freeformCommand;
  final _freeformTextController = TextEditingController();

  // ドラッグ&ドロップ用
  StreamSubscription? _dragOverSub;
  StreamSubscription? _dragLeaveSub;
  StreamSubscription? _dropSub;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _initSession();
    _loadCommands();
    _setupHtmlDropListeners();
  }

  @override
  void dispose() {
    _summarizeCurrentSession();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _elicitationTextController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _dragOverSub?.cancel();
    _dragLeaveSub?.cancel();
    _dropSub?.cancel();
    super.dispose();
  }

  void _setupHtmlDropListeners() {
    final subs = <StreamSubscription?>[];
    web_helpers.setupHtmlDropListeners(
      onDragStateChanged: (isDrag) {
        if (isDrag != _isDragOver && mounted) {
          setState(() => _isDragOver = isDrag);
        }
      },
      onFileDropped: (fileName, bytes, size) {
        final ext = fileName.split('.').last.toLowerCase();
        final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
        if (mounted) {
          setState(() {
            _attachedFiles.add(_AttachedFile(
              name: fileName,
              bytes: Uint8List.fromList(bytes),
              type: isImage ? _FileType.image : _FileType.file,
              fileSize: size,
            ));
          });
        }
      },
      subscriptions: subs,
    );
    if (subs.length >= 3) {
      _dragOverSub = subs[0];
      _dragLeaveSub = subs[1];
      _dropSub = subs[2];
    }
  }

  Future<void> _loadCommands() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ai_chat_commands')
          .get();

      if (mounted) {
        setState(() {
          _commands = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading commands: $e');
    }
  }

  void _onTextChanged() {
    final text = _textController.text;
    final newHasText = text.trim().isNotEmpty;
    if (newHasText != _hasText) {
      setState(() => _hasText = newHasText);
    }

    // スラッシュコマンド検出（エリシテーション中でない時のみ）
    if (!_elicitationMode && text.startsWith('/')) {
      final filter = text.substring(1).toLowerCase();
      setState(() {
        _showSlashMenu = true;
        _slashFilter = filter;
      });
    } else if (_showSlashMenu) {
      setState(() {
        _showSlashMenu = false;
        _slashFilter = '';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredSlashCommands {
    if (_slashFilter.isEmpty) return _commands;
    return _commands
        .where((c) =>
            (c['label'] as String? ?? '').toLowerCase().contains(_slashFilter) ||
            (c['id'] as String? ?? '').contains(_slashFilter))
        .toList();
  }

  void _selectSlashCommand(Map<String, dynamic> cmd) {
    final questions = cmd['questions'] as List<dynamic>? ?? [];
    final isFreeform = cmd['freeform'] == true;

    if (isFreeform) {
      // フリーフォーム（自由記述）モード開始
      setState(() {
        _showSlashMenu = false;
        _slashFilter = '';
        _freeformMode = true;
        _freeformCommand = cmd;
      });
      _textController.clear();
      _freeformTextController.clear();
      return;
    }

    if (questions.isEmpty) {
      // 質問がなければ普通のタグ方式
      setState(() {
        _showSlashMenu = false;
        _slashFilter = '';
      });
      _textController.clear();
      _focusNode.requestFocus();
      return;
    }

    // エリシテーションモード開始
    setState(() {
      _showSlashMenu = false;
      _slashFilter = '';
      _elicitationMode = true;
      _elicitationCommand = cmd;
      _elicitationStep = 0;
      _elicitationAnswers = List.filled(questions.length, '');
    });
    _textController.clear();
    _elicitationTextController.clear();
  }

  void _cancelElicitation() {
    setState(() {
      _elicitationMode = false;
      _elicitationCommand = null;
      _elicitationStep = 0;
      _elicitationAnswers = [];
    });
    _elicitationTextController.clear();
  }

  void _cancelFreeform() {
    setState(() {
      _freeformMode = false;
      _freeformCommand = null;
    });
    _freeformTextController.clear();
  }

  static const _defaultCareRecordScript = '''以下の自由記述をもとに、この児童の個別支援計画を参考にしながら、ケア記録を生成してください。

【出力形式】以下の体裁で出力すること。デスマス調ではなく言い切りの形（である調・体言止め）で記述すること。

1. 来所時の様子
（来所時の表情・体調・気分・入室の様子を記載）

2. 本日の活動内容
（実施した活動の内容を具体的に記載）

3. 個別支援計画との関連
（本日の活動が個別支援計画のどの目標に対応しているかを記載）

4. 取り組みの様子・できたこと
（活動中の児童の反応、成長が見られた点、できたことを記載）

5. 支援内容・配慮
（スタッフが行った支援や環境調整、配慮事項を記載）

6. 課題と継続したい支援
（今後の課題、次回以降も継続すべき支援を記載）

【注意事項】
- 自由記述に書かれていない情報を捏造しないこと
- 個別支援計画の目標と活動内容の関連づけは、無理に結びつけず、関連がある場合のみ記載すること
- 記述が少ない項目は、入力内容から読み取れる範囲で簡潔に記載すること
- 各項目は1〜3文程度で簡潔にまとめること''';

  void _submitFreeform() {
    final cmd = _freeformCommand!;
    var script = cmd['script'] as String? ?? '';
    final label = cmd['label'] as String? ?? '';
    final text = _freeformTextController.text.trim();
    if (text.isEmpty) return;

    // スクリプトが空の場合はデフォルトのケア記録スクリプトを使用
    if (script.isEmpty) {
      script = _defaultCareRecordScript;
    }

    // フォーマット指示をメッセージ自体に埋め込む
    final message = '/$label\n\n【スタッフの記録】\n$text\n\n【出力指示】\n$script';

    setState(() {
      _freeformMode = false;
      _freeformCommand = null;
    });
    _freeformTextController.clear();

    _textController.text = message;
    _sendMessageWithScript(script);
  }

  void _answerElicitation(String answer) {
    final questions = _elicitationCommand!['questions'] as List<dynamic>;
    setState(() {
      _elicitationAnswers[_elicitationStep] = answer;
    });

    if (_elicitationStep < questions.length - 1) {
      // 次の質問へ
      setState(() {
        _elicitationStep++;
      });
      _elicitationTextController.clear();
    }
    // 最後の質問なら送信ボタンで送信
  }

  /// Enterキーで「次へ」ボタンと同じ動作（最終ステップなら送信）
  void _advanceElicitationFromKey() {
    if (_elicitationCommand == null) return;
    final questions = _elicitationCommand!['questions'] as List<dynamic>;
    if (_elicitationStep >= questions.length) return;

    final currentQ = questions[_elicitationStep] as Map<String, dynamic>;
    final isRequired = currentQ['required'] == true;
    final currentAnswer = _elicitationTextController.text.trim();
    final isLast = _elicitationStep == questions.length - 1;

    // 必須で未入力なら何もしない
    if (isRequired && currentAnswer.isEmpty) return;

    // 現在の入力を保存
    setState(() {
      _elicitationAnswers[_elicitationStep] = currentAnswer;
    });

    if (isLast) {
      _submitElicitation();
    } else {
      setState(() => _elicitationStep++);
      _elicitationTextController.clear();
    }
  }

  void _goBackElicitation() {
    if (_elicitationStep > 0) {
      setState(() {
        _elicitationStep--;
      });
      _elicitationTextController.text = _elicitationAnswers[_elicitationStep];
    }
  }

  void _submitElicitation() {
    final cmd = _elicitationCommand!;
    final questions = cmd['questions'] as List<dynamic>;
    final script = cmd['script'] as String? ?? '';
    final label = cmd['label'] as String? ?? '';

    // 回答をまとめてメッセージ化
    final buffer = StringBuffer();
    buffer.writeln('/$label');
    buffer.writeln();
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i] as Map<String, dynamic>;
      final questionText = q['question'] as String? ?? '';
      final answer = _elicitationAnswers[i];
      if (answer.isNotEmpty) {
        buffer.writeln('$questionText: $answer');
      }
    }

    final message = buffer.toString().trim();

    // エリシテーション終了
    setState(() {
      _elicitationMode = false;
      _elicitationCommand = null;
      _elicitationStep = 0;
      _elicitationAnswers = [];
    });
    _elicitationTextController.clear();

    // メッセージ送信
    _textController.text = message;
    _sendMessageWithScript(script);
  }

  Future<void> _sendMessageWithScript(String script) async {
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

    _scrollToBottom();

    try {
      final callable = _functions.httpsCallable('sendAiMessage');
      await callable.call({
        'sessionId': _sessionId,
        'message': messageText,
        'context': _buildContext(),
        if (script.isNotEmpty) 'commandScript': script,
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
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _initSession() async {
    try {
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

      if (!isFreeChat) {
        final today = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day);
        final myUid = currentUser?.uid ?? '';

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

        final allSessionsSnap = await FirebaseFirestore.instance
            .collection('ai_chat_sessions')
            .where('studentId', isEqualTo: widget.studentId)
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        final allSessions = allSessionsSnap.docs;

        if (allSessions.isNotEmpty) {
          final summaries = <Map<String, String>>[];
          for (final session in allSessions) {
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

          final todaySessions = allSessions.where((doc) {
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
            _sendInitialMessageIfNeeded();
            return;
          }
        }
      }

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
      if (_hugAssessment != null && _hugAssessment!.isNotEmpty) {
        sessionData['hugAssessment'] = _hugAssessment;
      }
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
      _sendInitialMessageIfNeeded();
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

  void _sendInitialMessageIfNeeded() {
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _textController.text = widget.initialMessage!;
        // 入力欄にセットするだけ。ユーザーが確認・編集してから送信する
      });
    }
  }

  Map<String, dynamic> _buildContext() {
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
    final hasAttachments = _attachedFiles.isNotEmpty;
    if ((messageText.isEmpty && !hasAttachments) || _isSending || _sessionId == null) return;

    _textController.clear();
    _focusNode.unfocus();

    final filesToUpload = List<_AttachedFile>.from(_attachedFiles);

    final displayMessage = messageText.isNotEmpty
        ? messageText
        : (hasAttachments ? '添付ファイルを送信しました' : '');

    setState(() {
      _isSending = true;
      _isUploading = hasAttachments;
      _attachedFiles = [];
      _pendingUserMessage = {
        'role': 'user',
        'content': displayMessage,
        'createdAt': Timestamp.now(),
        'status': 'sending',
        if (hasAttachments)
          'pendingAttachments': filesToUpload.map((f) => {
            'name': f.name,
            'type': f.type == _FileType.image ? 'image' : 'file',
          }).toList(),
      };
      _isWaitingForAiResponse = true;
    });

    _scrollToBottom();

    try {
      // ファイルをアップロード
      List<Map<String, dynamic>> uploadedFiles = [];
      if (filesToUpload.isNotEmpty) {
        for (final file in filesToUpload) {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
          final ref = FirebaseStorage.instance
              .ref()
              .child('ai_chat_uploads/$_sessionId/$fileName');

          if (file.type == _FileType.image) {
            await ref.putData(file.bytes, SettableMetadata(contentType: 'image/jpeg'));
          } else {
            await ref.putData(file.bytes);
          }

          final url = await ref.getDownloadURL();
          uploadedFiles.add({
            'url': url,
            'name': file.name,
            'type': file.type == _FileType.image ? 'image' : 'file',
            'size': file.fileSize ?? file.bytes.length,
          });
        }
        setState(() => _isUploading = false);
      }

      // メッセージにファイル情報を含めて送信
      final fullMessage = messageText.isNotEmpty
          ? messageText
          : (uploadedFiles.isNotEmpty ? '添付ファイルを送信しました' : '');

      final callable = _functions.httpsCallable('sendAiMessage');
      final callData = <String, dynamic>{
        'sessionId': _sessionId,
        'message': fullMessage,
        'context': _buildContext(),
        if (uploadedFiles.isNotEmpty) 'attachments': uploadedFiles,
      };
      await callable.call(callData);

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
          _isUploading = false;
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp']
        .contains(file.extension?.toLowerCase());

    setState(() {
      _attachedFiles.add(_AttachedFile(
        name: file.name,
        bytes: file.bytes!,
        type: isImage ? _FileType.image : _FileType.file,
        fileSize: file.size,
      ));
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachedFiles.removeAt(index);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.colors.aiAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.description, color: context.colors.aiAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Text('HUGアセスメント情報', style: TextStyle(fontSize: 16, color: context.colors.textPrimary)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HUGからコピーしたアセスメント情報を貼り付けてください',
                style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 10,
                decoration: InputDecoration(
                  hintText: '症状、得意なこと、気をつけてほしいこと など...',
                  filled: true,
                  fillColor: context.colors.tagBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.borderMedium),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.aiAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('キャンセル', style: TextStyle(color: context.colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              await _saveHugAssessment(text.isEmpty ? null : text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.aiAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  /// AI生成コンテンツをhugに送信するダイアログを表示
  Future<void> _showSaveContentDialog(String content, {String? defaultCommandLabel}) async {
    final textController = TextEditingController(text: content);
    DateTime selectedDate = DateTime.now();
    final currentUser = FirebaseAuth.instance.currentUser;
    final staffName = _staffName ?? 'スタッフ';

    // コマンド一覧からカテゴリを構築（「その他」を末尾に追加）
    final commandLabels = _commands
        .map((c) => c['label'] as String? ?? '')
        .where((l) => l.isNotEmpty)
        .toList();
    if (!commandLabels.contains('その他')) {
      commandLabels.add('その他');
    }

    // デフォルト選択: スラッシュコマンドで使ったラベル、なければ先頭
    String selectedCategory = defaultCommandLabel ?? (commandLabels.isNotEmpty ? commandLabels.first : 'その他');
    if (!commandLabels.contains(selectedCategory)) {
      selectedCategory = commandLabels.isNotEmpty ? commandLabels.first : 'その他';
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('hugへ送信'),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // カテゴリ選択
                    Row(
                      children: [
                        const Text('カテゴリ: ',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: selectedCategory,
                          underline: const SizedBox(),
                          borderRadius: BorderRadius.circular(8),
                          items: commandLabels.map((label) {
                            return DropdownMenuItem(
                                value: label, child: Text(label));
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => selectedCategory = v);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 生徒名（表示のみ）
                    Row(
                      children: [
                        const Text('生徒名: ',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(widget.studentName,
                            style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 記録者名（表示のみ）
                    Row(
                      children: [
                        const Text('記録者: ',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(staffName,
                            style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 日付（変更可能）
                    Row(
                      children: [
                        const Text('日付: ',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            DateFormat('yyyy/MM/dd').format(selectedDate),
                            style: const TextStyle(fontSize: 14),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 30)),
                              lastDate: DateTime.now(),
                              locale: const Locale('ja'),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedDate = picked;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 内容（編集可能）
                    const Text('内容:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 300,
                      child: TextField(
                        controller: textController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        style: const TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const Text('hugへ送信'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      final payload = <String, dynamic>{
        'category': selectedCategory,
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'content': textController.text,
        'date': Timestamp.fromDate(DateTime(
            selectedDate.year, selectedDate.month, selectedDate.day)),
        'recorderName': staffName,
        'recorderId': currentUser?.uid ?? '',
      };
      await _sendToHugDirect(payload);
    }
    textController.dispose();
  }

  /// hugへ直接送信（B案: 保存→送信→削除を内部で透過実行）
  /// 失敗時はセッション内のリトライバナーに積む
  Future<void> _sendToHugDirect(Map<String, dynamic> payload) async {
    // 一時的に saved_ai_contents に保存
    String? tempDocId;
    try {
      final docRef = await FirebaseFirestore.instance
          .collection('saved_ai_contents')
          .add({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tempDocId = docRef.id;

      // syncToHug Cloud Function を呼び出し
      final callable = _functions.httpsCallable('syncToHug');
      final result = await callable.call({'contentIds': [tempDocId]});
      final resultData = result.data as Map<String, dynamic>;
      final successCount = resultData['successCount'] ?? 0;

      if (successCount > 0) {
        // 成功: 一時保存も既に削除されているはず（syncToHugが成功時に削除）
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${payload['category']}をhugに送信しました'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // 失敗: エラー情報取得
        final errors = (resultData['errors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final errorMsg = errors.isNotEmpty ? (errors.first['error'] ?? '不明なエラー') : '不明なエラー';
        // 一時保存ドキュメントを削除（バナー側で再送するときに新規作成し直す）
        await FirebaseFirestore.instance
            .collection('saved_ai_contents')
            .doc(tempDocId)
            .delete()
            .catchError((_) {});
        _addToFailedBanner(payload, errorMsg.toString());
      }
    } catch (e) {
      // 通信エラー等: 一時保存があれば削除
      if (tempDocId != null) {
        await FirebaseFirestore.instance
            .collection('saved_ai_contents')
            .doc(tempDocId)
            .delete()
            .catchError((_) {});
      }
      _addToFailedBanner(payload, e.toString());
    }
  }

  void _addToFailedBanner(Map<String, dynamic> payload, String error) {
    if (!mounted) return;
    setState(() {
      _failedHugSends.add({
        ...payload,
        'error': error,
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('hug送信に失敗しました: $error'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _retryFailedHugSend(int index) async {
    if (index < 0 || index >= _failedHugSends.length) return;
    final item = Map<String, dynamic>.from(_failedHugSends[index]);
    item.remove('error');
    setState(() => _failedHugSends.removeAt(index));
    await _sendToHugDirect(item);
  }

  void _discardFailedHugSend(int index) {
    if (index < 0 || index >= _failedHugSends.length) return;
    setState(() => _failedHugSends.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final isFreeChat = widget.studentId.startsWith('free_chat');

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.colors.scaffoldBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: context.colors.textSecondary,
                onPressed: widget.onBackPressed ?? () => Navigator.pop(context),
              )
            : null,
        title: Text(
          widget.studentName,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          if (!isFreeChat)
            IconButton(
              icon: Icon(
                _hugAssessment != null && _hugAssessment!.isNotEmpty
                    ? Icons.description
                    : Icons.description_outlined,
                color: _hugAssessment != null && _hugAssessment!.isNotEmpty
                    ? context.colors.aiAccent
                    : context.colors.textTertiary,
                size: 22,
              ),
              tooltip: 'HUGアセスメント',
              onPressed: _showHugAssessmentDialog,
            ),
          IconButton(
            icon: Icon(Icons.history_rounded, color: context.colors.textTertiary, size: 22),
            tooltip: '相談履歴',
            onPressed: _showChatHistory,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.colors.borderLight, height: 0.5),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: context.colors.aiAccent),
            )
          : Column(
              children: [
                if (_failedHugSends.isNotEmpty) _buildFailedHugBanner(),
                Expanded(child: _buildMessageList()),
                if (_showSlashMenu && !_elicitationMode && !_freeformMode) _buildSlashMenu(),
                if (_freeformMode)
                  _buildFreeformUI()
                else if (_elicitationMode)
                  _buildElicitationUI()
                else
                  _buildInputArea(),
              ],
            ),
    );
  }

  Widget _buildFailedHugBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.red.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'hug送信失敗 (${_failedHugSends.length}件)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...List.generate(_failedHugSends.length, (i) {
            final item = _failedHugSends[i];
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item['category']} / ${item['studentName']}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _retryFailedHugSend(i),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: Colors.blue,
                    ),
                    child: const Text('再送', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () => _discardFailedHugSend(i),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: Colors.grey,
                    ),
                    child: const Text('破棄', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWelcomeView() {
    final isFreeChat = widget.studentId.startsWith('free_chat');

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.aiAccent.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 24),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
                ).createShader(bounds),
                child: Text(
                  isFreeChat
                      ? 'こんにちは！\n何でもお気軽にどうぞ'
                      : '${widget.studentName}さんについて\nお手伝いします',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _commands.isNotEmpty
                    ? 'メッセージを入力するか、/ でコマンドを使ってみましょう'
                    : 'メッセージを入力して相談してみましょう',
                style: TextStyle(fontSize: 14, color: context.colors.textTertiary),
              ),
              if (_commands.isNotEmpty) const SizedBox(height: 24),
              // コマンド一覧をカードで表示（登録がある場合のみ）
              ...(_commands.map((cmd) {
                final label = cmd['label'] as String? ?? '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _selectSlashCommand(cmd),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.colors.borderLight),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: context.colors.aiAccentBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.tag_rounded, size: 18, color: context.colors.aiAccent),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text('/$label',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 20, color: context.colors.iconMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              })),
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

        // まだデータが来ていない（初回読み込み中）
        if (!snapshot.hasData && !snapshot.hasError) {
          return Center(
            child: CircularProgressIndicator(color: context.colors.aiAccent),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        final allMessages = <Map<String, dynamic>>[];
        for (final doc in docs) {
          allMessages.add({
            ...doc.data() as Map<String, dynamic>,
            'id': doc.id,
          });
        }

        if (_pendingUserMessage != null) {
          final pendingContent = _pendingUserMessage!['content'];
          final isDuplicate = allMessages.any((m) =>
              m['role'] == 'user' && m['content'] == pendingContent);
          if (!isDuplicate) {
            allMessages.add(_pendingUserMessage!);
          }
        }

        // 空の場合はウェルカム画面
        if (allMessages.isEmpty && !_isSending) {
          return _buildWelcomeView();
        }

        // スクロール制御
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;

          final currentCount = allMessages.length;
          final lastRole = allMessages.isNotEmpty ? allMessages.last['role'] : null;

          if (_previousMessageCount == 0 && currentCount > 0) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          } else if (currentCount > _previousMessageCount) {
            if (lastRole == 'assistant') {
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
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          }

          _previousMessageCount = currentCount;

        });

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              itemCount: allMessages.length + (_isWaitingForAiResponse ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == allMessages.length) {
                  return _buildTypingIndicator();
                }
                // AIメッセージの直前のユーザーメッセージからコマンドを検出
                String? usedCommandLabel;
                if (allMessages[index]['role'] == 'assistant' && index > 0) {
                  final prevMsg = allMessages[index - 1];
                  if (prevMsg['role'] == 'user') {
                    final prevContent = prevMsg['content'] as String? ?? '';
                    if (prevContent.startsWith('/')) {
                      final firstLine = prevContent.split('\n').first;
                      usedCommandLabel = firstLine.substring(1).trim();
                    }
                  }
                }
                return _buildMessageItem(allMessages[index], usedCommandLabel: usedCommandLabel);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.chipBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AnimatedDot(delay: 0),
                const SizedBox(width: 4),
                _AnimatedDot(delay: 150),
                const SizedBox(width: 4),
                _AnimatedDot(delay: 300),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg, {String? usedCommandLabel}) {
    final isUser = msg['role'] == 'user';
    var content = msg['content'] ?? '';
    // フリーフォームの出力指示部分を表示から除外
    if (isUser && content.contains('【出力指示】')) {
      content = content.split('【出力指示】')[0].trim();
    }
    // 【スタッフの記録】ラベルも除外
    content = content.replaceAll('【スタッフの記録】\n', '');
    final status = msg['status'];
    final isSending = status == 'sending';
    final attachments = msg['attachments'] as List<dynamic>? ?? [];
    final pendingAttachments = msg['pendingAttachments'] as List<dynamic>? ?? [];

    String timeStr = '';
    if (msg['createdAt'] != null) {
      final ts = msg['createdAt'] as Timestamp;
      timeStr = DateFormat('HH:mm').format(ts.toDate());
    }

    if (isUser) {
      return _buildUserMessage(content, timeStr, isSending,
          attachments: attachments, pendingAttachments: pendingAttachments);
    } else {
      return _buildAiMessage(content, timeStr, usedCommandLabel: usedCommandLabel);
    }
  }

  Widget _buildUserMessage(String content, String timeStr, bool isSending, {
    List<dynamic> attachments = const [],
    List<dynamic> pendingAttachments = const [],
  }) {
    final allAttachments = attachments.isNotEmpty ? attachments : pendingAttachments;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 添付ファイル表示
          if (allAttachments.isNotEmpty)
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              margin: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: allAttachments.map((att) {
                  final a = att is Map<String, dynamic> ? att : <String, dynamic>{};
                  final type = a['type'] ?? 'file';
                  final url = a['url'] as String?;
                  final name = a['name'] ?? 'ファイル';
                  final isPending = attachments.isEmpty;

                  if (type == 'image' && url != null) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        width: 200,
                        height: 150,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            width: 200,
                            height: 150,
                            decoration: BoxDecoration(
                              color: context.colors.borderLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: context.colors.aiAccent,
                                strokeWidth: 2,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }

                  // ファイル（非画像）or pending
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isPending ? context.colors.borderLight : context.colors.inputFill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type == 'image' ? Icons.photo : Icons.insert_drive_file_rounded,
                          size: 18,
                          color: isPending ? context.colors.iconMuted : context.colors.aiAccent,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 12,
                              color: isPending ? context.colors.textTertiary : context.colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPending) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: context.colors.iconMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          // テキスト
          if (content.isNotEmpty && content != '添付ファイルを送信しました')
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.chatMyBubble,
                borderRadius: BorderRadius.circular(20),
              ),
              child: SelectableText(
                content,
                style: TextStyle(
                  fontSize: 15,
                  color: isSending ? context.colors.textHint : context.colors.chatMyBubbleText,
                  height: 1.5,
                ),
              ),
            ),
          if (timeStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSending) ...[
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: context.colors.iconMuted,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    timeStr,
                    style: TextStyle(fontSize: 11, color: context.colors.textHint),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAiMessage(String content, String timeStr, {String? usedCommandLabel}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
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
                  style: TextStyle(
                    fontSize: 15,
                    color: context.colors.textPrimary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 6),
                // アクションボタン（コピー・保存）
                Row(
                  children: [
                    _AiMessageActionButton(
                      icon: Icons.content_copy_rounded,
                      tooltip: 'コピー',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('コピーしました'),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 2),
                    _AiMessageActionButton(
                      icon: Icons.bookmark_outline_rounded,
                      tooltip: '保存',
                      onTap: () => _showSaveContentDialog(content, defaultCommandLabel: usedCommandLabel),
                    ),
                    const Spacer(),
                    if (timeStr.isNotEmpty)
                      Text(
                        timeStr,
                        style: TextStyle(fontSize: 11, color: context.colors.textHint),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreeformUI() {
    final cmd = _freeformCommand!;
    final label = cmd['label'] as String? ?? '';
    final description = cmd['description'] as String? ?? '';
    final hasText = _freeformTextController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(color: context.colors.scaffoldBg),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.hoverBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.aiAccent.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.shadow.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '/$label',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '自由記述',
                          style: TextStyle(fontSize: 12, color: context.colors.textTertiary),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _cancelFreeform,
                          child: Text('キャンセル',
                              style: TextStyle(fontSize: 12, color: context.colors.textTertiary)),
                        ),
                      ],
                    ),
                  ),
                  // 説明文
                  if (description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        description,
                        style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                      ),
                    ),
                  // テキスト入力エリア
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: TextField(
                      controller: _freeformTextController,
                      maxLines: 6,
                      minLines: 4,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(fontSize: 14, color: context.colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '今日の様子を自由に記入してください...',
                        hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
                        filled: true,
                        fillColor: context.colors.cardBg,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.borderMedium),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.borderMedium),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.colors.aiAccent),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  // 送信ボタン
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        const Spacer(),
                        GestureDetector(
                          onTap: hasText ? _submitFreeform : null,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: hasText
                                  ? LinearGradient(
                                      colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
                                    )
                                  : null,
                              color: hasText ? null : context.colors.borderMedium,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildElicitationUI() {
    final cmd = _elicitationCommand!;
    final questions = cmd['questions'] as List<dynamic>;
    final label = cmd['label'] as String? ?? '';
    final currentQ = questions[_elicitationStep] as Map<String, dynamic>;
    final questionText = currentQ['question'] as String? ?? '';
    final type = currentQ['type'] as String? ?? 'text';
    final options = (currentQ['options'] as List<dynamic>?)?.cast<String>() ?? [];
    final isLast = _elicitationStep == questions.length - 1;
    final isRequired = currentQ['required'] as bool? ?? false;
    final currentAnswer = _elicitationAnswers[_elicitationStep];
    final allAnswered = !_elicitationAnswers.any((a) {
      final idx = _elicitationAnswers.indexOf(a);
      final q = questions[idx] as Map<String, dynamic>;
      final req = q['required'] as bool? ?? false;
      return req && a.isEmpty;
    });

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(color: context.colors.scaffoldBg),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.hoverBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.aiAccent.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.shadow.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー: コマンド名 + 進捗 + キャンセル
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '/$label',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${_elicitationStep + 1} / ${questions.length}',
                          style: TextStyle(fontSize: 12, color: context.colors.textTertiary),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _cancelElicitation,
                          child: Text('キャンセル',
                              style: TextStyle(fontSize: 12, color: context.colors.textTertiary)),
                        ),
                      ],
                    ),
                  ),
                  // プログレスバー
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_elicitationStep + 1) / questions.length,
                        backgroundColor: context.colors.borderLight,
                        valueColor: AlwaysStoppedAnimation(context.colors.aiAccent),
                        minHeight: 3,
                      ),
                    ),
                  ),
                  // 質問
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Text(
                      questionText,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
                    ),
                  ),
                  // 回答エリア
                  if (type == 'select')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: options.map((opt) {
                          final isSelected = currentAnswer == opt;
                          return GestureDetector(
                            onTap: () => _answerElicitation(opt),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? context.colors.aiAccent
                                    : context.colors.cardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? context.colors.aiAccent
                                      : context.colors.borderMedium,
                                ),
                              ),
                              child: Text(
                                opt,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isSelected ? Colors.white : context.colors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  else if (type == 'select_or_text') ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: options.map((opt) {
                          final isSelected = currentAnswer == opt;
                          return GestureDetector(
                            onTap: () {
                              _elicitationTextController.clear();
                              _answerElicitation(opt);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? context.colors.aiAccent : context.colors.cardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected ? context.colors.aiAccent : context.colors.borderMedium,
                                ),
                              ),
                              child: Text(
                                opt,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isSelected ? Colors.white : context.colors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (_elicitationTextController.value.composing.isValid) {
                            return KeyEventResult.ignored;
                          }
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            _advanceElicitationFromKey();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _elicitationTextController,
                          style: TextStyle(fontSize: 14, color: context.colors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'その他（自由入力）',
                            hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
                            filled: true,
                            fillColor: context.colors.cardBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: context.colors.borderMedium),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: context.colors.borderMedium),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: context.colors.aiAccent),
                            ),
                          ),
                          onChanged: (v) {
                            if (v.trim().isNotEmpty) {
                              setState(() {
                                _elicitationAnswers[_elicitationStep] = v.trim();
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ] else
                    // text
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (_elicitationTextController.value.composing.isValid) {
                            return KeyEventResult.ignored;
                          }
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            _advanceElicitationFromKey();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _elicitationTextController,
                          maxLines: 3,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(fontSize: 14, color: context.colors.textPrimary),
                          decoration: InputDecoration(
                            hintText: currentQ['placeholder'] as String? ?? '回答を入力...',
                            hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
                            filled: true,
                            fillColor: context.colors.cardBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: context.colors.borderMedium),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: context.colors.borderMedium),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: context.colors.aiAccent),
                            ),
                          ),
                          onChanged: (v) {
                            setState(() {
                              _elicitationAnswers[_elicitationStep] = v.trim();
                            });
                          },
                        ),
                      ),
                    ),
                  // 下部ボタン
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        if (_elicitationStep > 0)
                          TextButton.icon(
                            onPressed: _goBackElicitation,
                            icon: const Icon(Icons.arrow_back_rounded, size: 16),
                            label: const Text('戻る', style: TextStyle(fontSize: 13)),
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.textSecondary,
                            ),
                          ),
                        // 必須でなければスキップボタン
                        if (!isRequired && !isLast && currentAnswer.isEmpty)
                          TextButton(
                            onPressed: () {
                              setState(() => _elicitationStep++);
                              _elicitationTextController.clear();
                            },
                            child: Text('スキップ',
                                style: TextStyle(fontSize: 13, color: context.colors.textTertiary)),
                          ),
                        const Spacer(),
                        // 次へ / 送信ボタン（上矢印）
                        if (type == 'text' || type == 'select_or_text' || isLast) ...[
                          if (!isLast)
                            // 次へボタン
                            GestureDetector(
                              onTap: (currentAnswer.isNotEmpty || !isRequired)
                                  ? () {
                                      setState(() => _elicitationStep++);
                                      _elicitationTextController.clear();
                                    }
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: (currentAnswer.isNotEmpty || !isRequired)
                                      ? context.colors.aiAccent
                                      : context.colors.borderMedium,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('次へ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: (currentAnswer.isNotEmpty || !isRequired)
                                          ? Colors.white
                                          : context.colors.textTertiary,
                                    )),
                              ),
                            )
                          else
                            // 送信ボタン（上矢印）
                            GestureDetector(
                              onTap: allAnswered ? _submitElicitation : null,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  gradient: allAnswered
                                      ? LinearGradient(
                                          colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
                                        )
                                      : null,
                                  color: allAnswered ? null : context.colors.borderMedium,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlashMenu() {
    final commands = _filteredSlashCommands;
    if (commands.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.borderLight),
            boxShadow: [
              BoxShadow(
                color: context.colors.shadow.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'コマンド',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...commands.map((cmd) {
                final label = cmd['label'] as String? ?? '';

                return InkWell(
                  onTap: () => _selectSlashCommand(cmd),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: context.colors.aiAccentBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.tag_rounded, size: 16, color: context.colors.aiAccent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '/$label',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  bool _isDragOver = false;

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(color: context.colors.scaffoldBg),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: _buildDropTarget(
              child: Container(
                decoration: BoxDecoration(
                  color: _isDragOver
                      ? context.colors.aiAccent.withOpacity(0.06)
                      : context.colors.hoverBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isDragOver
                        ? context.colors.aiAccent.withOpacity(0.5)
                        : context.colors.borderMedium,
                    width: _isDragOver ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.shadow.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 添付ファイルプレビュー（入力欄内の上部）
                    if (_attachedFiles.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                        child: SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _attachedFiles.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              return _buildAttachmentPreview(_attachedFiles[index], index);
                            },
                          ),
                        ),
                      ),
                    // アップロード中
                    if (_isUploading)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: context.colors.aiAccent.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('アップロード中...',
                                style: TextStyle(fontSize: 11, color: context.colors.textTertiary)),
                          ],
                        ),
                      ),
                    // ドラッグオーバー時のヒント
                    if (_isDragOver)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.file_download_rounded,
                                size: 20, color: context.colors.aiAccent.withOpacity(0.6)),
                            const SizedBox(width: 8),
                            Text('ここにドロップして添付',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.colors.aiAccent.withOpacity(0.8),
                                  fontWeight: FontWeight.w500,
                                )),
                          ],
                        ),
                      ),
                    // テキスト入力行
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
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
                              maxLines: 8,
                              minLines: 1,
                              keyboardType: TextInputType.multiline,
                              enabled: !_isSending,
                              style: TextStyle(fontSize: 15, color: context.colors.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'メッセージを入力...',
                                hintStyle: TextStyle(color: context.colors.textHint),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 下段ツールバー
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Row(
                        children: [
                          // ファイル添付ボタン
                          _buildToolbarButton(
                            icon: Icons.attach_file_rounded,
                            tooltip: 'ファイルを添付',
                            onTap: _isSending ? null : _pickFile,
                          ),
                          // コマンドボタン
                          if (!_elicitationMode)
                            _buildToolbarButton(
                              icon: Icons.code_rounded,
                              tooltip: 'コマンド',
                              onTap: _isSending ? null : () {
                                setState(() {
                                  _showSlashMenu = !_showSlashMenu;
                                  _slashFilter = '';
                                });
                              },
                            ),
                          const Spacer(),
                          // 送信ボタン（常に表示、入力があればアクティブ）
                          GestureDetector(
                            onTap: (_hasText || _attachedFiles.isNotEmpty) && !_isSending
                                ? _sendMessage
                                : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                gradient: (_hasText || _attachedFiles.isNotEmpty) && !_isSending
                                    ? LinearGradient(
                                        colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
                                      )
                                    : null,
                                color: (_hasText || _attachedFiles.isNotEmpty) && !_isSending
                                    ? null
                                    : context.colors.borderMedium,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.arrow_upward_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: context.colors.textTertiary),
        ),
      ),
    );
  }

  Widget _buildDropTarget({required Widget child}) {
    // Flutter Web のドラッグ&ドロップは DragTarget では外部ファイルを受け取れないため
    // HTML の drag events を使う必要がある。
    // ここでは dart:html を使わずに、シンプルな実装として
    // Flutter の標準 DragTarget でアプリ内のドラッグに対応しつつ、
    // 見た目のフィードバックだけ提供する。
    // 外部ファイルのドロップは image_picker / file_picker で代替する。
    return child;
  }

  Widget _buildAttachmentPreview(_AttachedFile file, int index) {
    if (file.type == _FileType.image) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              file.bytes,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: _buildRemoveButton(index),
          ),
        ],
      );
    }

    // ファイル
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 140,
          height: 72,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.colors.borderMedium),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.colors.aiAccentBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.insert_drive_file_rounded,
                    size: 18, color: context.colors.aiAccent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (file.fileSize != null)
                      Text(
                        _formatFileSize(file.fileSize!),
                        style: TextStyle(fontSize: 10, color: context.colors.textTertiary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: _buildRemoveButton(index),
        ),
      ],
    );
  }

  Widget _buildRemoveButton(int index) {
    return GestureDetector(
      onTap: () => _removeAttachment(index),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: context.colors.textSecondary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 12),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildHistoryBottomSheet(BuildContext ctx) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: context.colors.aiAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.history_rounded, color: context.colors.aiAccent, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${widget.studentName} - 相談履歴',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: context.colors.textTertiary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.colors.borderLight),
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
                    return Center(
                      child: CircularProgressIndicator(color: context.colors.aiAccent),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_rounded, size: 48, color: context.colors.borderMedium),
                          const SizedBox(height: 12),
                          Text(
                            'まだ相談履歴がありません',
                            style: TextStyle(color: context.colors.textTertiary),
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

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isCurrentSession
                                ? context.colors.aiAccent.withOpacity(0.4)
                                : context.colors.borderLight,
                            width: isCurrentSession ? 1.5 : 1,
                          ),
                          color: isCurrentSession
                              ? context.colors.aiAccent.withOpacity(0.04)
                              : context.colors.cardBg,
                        ),
                        child: InkWell(
                          onTap: isCurrentSession
                              ? () => Navigator.pop(ctx)
                              : () {
                                  Navigator.pop(ctx);
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
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 16,
                                      color: isCurrentSession
                                          ? context.colors.aiAccent
                                          : context.colors.textTertiary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: isCurrentSession
                                            ? context.colors.aiAccent
                                            : context.colors.textPrimary,
                                      ),
                                    ),
                                    if (isCurrentSession) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [context.colors.aiGradientStart, context.colors.aiGradientEnd],
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          '現在',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    Text(
                                      '$messageCount件',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.colors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                                if (summary != null && summary.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: context.colors.aiAccent.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.summarize_rounded, size: 14,
                                            color: context.colors.aiAccent.withOpacity(0.6)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            summary,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.colors.textSecondary,
                                              height: 1.4,
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
                                      color: context.colors.textSecondary,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  staffName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.colors.textHint,
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
}

// ドットアニメーション
class _AnimatedDot extends StatefulWidget {
  final int delay;

  const _AnimatedDot({required this.delay});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -4 * _animation.value),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Color.lerp(
                context.colors.iconMuted,
                context.colors.aiAccent,
                _animation.value,
              ),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

// 添付ファイルの種類
enum _FileType { image, file }

// 添付ファイルデータ
class _AttachedFile {
  final String name;
  final Uint8List bytes;
  final _FileType type;
  final int? fileSize;

  const _AttachedFile({
    required this.name,
    required this.bytes,
    required this.type,
    this.fileSize,
  });
}

// AI応答のアクションボタン
class _AiMessageActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _AiMessageActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_AiMessageActionButton> createState() => _AiMessageActionButtonState();
}

class _AiMessageActionButtonState extends State<_AiMessageActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _isHovered ? context.colors.borderLight : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: context.colors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
