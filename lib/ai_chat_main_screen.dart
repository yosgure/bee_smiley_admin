import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'ai_chat_screen.dart';
import 'app_theme.dart';
import 'classroom_utils.dart';

class AiChatMainScreen extends StatefulWidget {
  final Map<String, dynamic>? initialStudent;

  const AiChatMainScreen({super.key, this.initialStudent});

  /// 外部から生徒を選択してチャットを開く
  static void openStudentChat(BuildContext context, {
    required String studentId,
    required String studentName,
    Map<String, dynamic>? studentInfo,
  }) {
    final state = context.findAncestorStateOfType<_AiChatMainScreenState>();
    if (state != null) {
      state._openStudentChatExternal(
        studentId: studentId,
        studentName: studentName,
        studentInfo: studentInfo,
      );
    }
  }

  @override
  State<AiChatMainScreen> createState() => _AiChatMainScreenState();
}

class _AiChatMainScreenState extends State<AiChatMainScreen> {
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _recentSessions = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // 現在選択中のチャット
  String? _activeStudentId;
  String? _activeStudentName;
  Map<String, dynamic>? _activeStudentInfo;
  String? _activeSessionId;

  // サイドバー表示切り替え（モバイル用）
  bool _showSidebar = true;

  // サイドバーのタブ
  int _sidebarTab = 0; // 0: 生徒一覧, 1: セッション履歴

  @override
  void initState() {
    super.initState();
    _loadStudents();
    _loadRecentSessions();

    // 外部から生徒指定がある場合
    if (widget.initialStudent != null) {
      _activeStudentId = widget.initialStudent!['studentId'];
      _activeStudentName = widget.initialStudent!['studentName'];
      _activeStudentInfo = widget.initialStudent!['studentInfo'] as Map<String, dynamic>?;
      _showSidebar = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    try {
      // プラス専用コレクションから児童一覧を取得（CRM一体化により families から分離済み）
      final snapshot = await FirebaseFirestore.instance
          .collection('plus_families')
          .get();

      final students = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final familyUid = data['uid'] as String? ?? doc.id;
        final rawLastName = data['lastName'] as String? ?? '';
        final rawFirstName = data['firstName'] as String? ?? '';
        // 旧データで lastName に親フルネームが入り firstName が空のケースを補正
        // （例: lastName='村田千明', firstName='' → lastName='村田'）
        final lastName = (rawFirstName.isEmpty && rawLastName.length >= 4 && !rawLastName.contains(' '))
            ? rawLastName.substring(0, 2)
            : rawLastName;
        final lastNameKana = data['lastNameKana'] as String? ?? '';
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);

        for (var child in children) {
          final firstName = child['firstName'] as String? ?? '';
          final classrooms = getChildClassrooms(child);
          final classroom = classrooms.join(', ');

          // 入会済みのみ表示（リード/失注/退会は除外）
          final status = child['status'] as String?;
          final isEnrolled = status == null || status == '入会';
          if (firstName.isNotEmpty && isEnrolled) {
            final studentId = child['studentId'] ?? '${familyUid}_$firstName';
            students.add({
              'name': '$lastName $firstName'.trim(),
              'firstName': firstName,
              'lastName': lastName,
              'lastNameKana': lastNameKana,
              'classroom': classroom,
              'familyUid': familyUid,
              'studentId': studentId,
            });
          }
        }
      }

      students.sort((a, b) {
        final kanaA = (a['lastNameKana'] as String?) ?? '';
        final kanaB = (b['lastNameKana'] as String?) ?? '';
        return kanaA.compareTo(kanaB);
      });

      if (mounted) {
        setState(() {
          _students = students;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRecentSessions() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ai_chat_sessions')
          .orderBy('updatedAt', descending: true)
          .limit(30)
          .get();

      if (mounted) {
        setState(() {
          _recentSessions = snapshot.docs.map((doc) {
            return {'docId': doc.id, ...doc.data()};
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading recent sessions: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_searchQuery.isEmpty) return _students;
    final q = _searchQuery.toLowerCase();
    return _students.where((s) {
      final name = (s['name'] as String? ?? '').toLowerCase();
      final kana = (s['lastNameKana'] as String? ?? '').toLowerCase();
      return name.contains(q) || kana.contains(q);
    }).toList();
  }

  /// 外部（プラス画面等）から呼び出し用
  void _openStudentChatExternal({
    required String studentId,
    required String studentName,
    Map<String, dynamic>? studentInfo,
  }) {
    setState(() {
      _activeStudentId = studentId;
      _activeStudentName = studentName;
      _activeStudentInfo = studentInfo;
      _activeSessionId = null;
      _showSidebar = false;
    });
  }

  void _openStudentChat(Map<String, dynamic> student) {
    final studentInfo = {
      'firstName': student['firstName'],
      'lastName': student['lastName'],
      'age': '',
      'gender': '',
      'classroom': student['classroom'] ?? 'プラス',
      'diagnosis': '',
    };
    setState(() {
      _activeStudentId = student['studentId'];
      _activeStudentName = student['name'];
      _activeStudentInfo = studentInfo;
      _activeSessionId = null;
      _showSidebar = false; // モバイルではサイドバーを閉じる
    });
  }

  void _openFreeChat() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    setState(() {
      _activeStudentId = 'free_chat_$uid';
      _activeStudentName = 'フリー相談';
      _activeStudentInfo = null;
      _activeSessionId = null;
      _showSidebar = false;
    });
  }

  void _openSession(Map<String, dynamic> session) {
    setState(() {
      _activeStudentId = session['studentId'] ?? '';
      _activeStudentName = session['studentName'] ?? 'フリー相談';
      _activeStudentInfo = null;
      _activeSessionId = session['docId'];
      _showSidebar = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 768;

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: (!isWide && _showSidebar)
          ? AppBar(
              title: const Text('AI相談'),
              centerTitle: true,
              backgroundColor: context.colors.cardBg,
              elevation: 0,
              foregroundColor: context.colors.textPrimary,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 22),
                  tooltip: '新規フリーチャット',
                  onPressed: _openFreeChat,
                ),
              ],
            )
          : null,
      body: Row(
        children: [
          // サイドバー（PC: 常に表示、モバイル: 切り替え）
          if (isWide || _showSidebar)
            SizedBox(
              width: isWide ? 280 : screenWidth,
              child: _buildSidebar(isWide),
            ),
          // メインチャットエリア
          if (isWide || !_showSidebar)
            Expanded(
              child: _activeStudentId != null
                  ? AiChatScreen(
                      key: ValueKey('${_activeStudentId}_${_activeSessionId ?? 'new'}'),
                      studentId: _activeStudentId!,
                      studentName: _activeStudentName ?? '',
                      studentInfo: _activeStudentInfo,
                      existingSessionId: _activeSessionId,
                      showBackButton: !isWide,
                      onBackPressed: () => setState(() => _showSidebar = true),
                    )
                  : _buildWelcome(),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar(bool isWide) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.hoverBg,
        border: Border(
          right: BorderSide(color: context.colors.borderLight, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // ヘッダー（デスクトップのみ、モバイルはAppBarが担当）
          if (isWide)
            Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 12),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Text('AI相談',
                            style: TextStyle(fontSize: AppTextSize.title, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
                      ),
                      Positioned(right: 0, child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // 新規フリーチャット
                      GestureDetector(
                        onTap: _openFreeChat,
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(Icons.edit_outlined, size: 18, color: context.colors.textSecondary),
                        ),
                      ),
                    ])),
                  ],
                  ),
                ],
              ),
            ),
          // タブ切り替え
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: context.colors.borderLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _buildTabButton(0, '生徒', Icons.people_outline_rounded),
                _buildTabButton(1, '履歴', Icons.history_rounded),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // コンテンツ
          Expanded(
            child: _sidebarTab == 0 ? _buildStudentList() : _buildSessionList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final selected = _sidebarTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _sidebarTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? context.colors.cardBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [BoxShadow(color: context.colors.shadow.withOpacity(0.05), blurRadius: 4)]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14,
                  color: selected ? context.colors.aiAccent : context.colors.textTertiary),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: AppTextSize.small,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? context.colors.aiAccent : context.colors.textSecondary,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentList() {
    return Column(
      children: [
        // 検索バー
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: context.colors.borderLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(fontSize: AppTextSize.body, color: context.colors.textPrimary),
              decoration: InputDecoration(
                hintText: '検索...',
                hintStyle: TextStyle(color: context.colors.textHint, fontSize: AppTextSize.body),
                prefixIcon: Icon(Icons.search_rounded, color: context.colors.textHint, size: 16),
                filled: false,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // 生徒一覧
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: context.colors.aiAccent))
              : _buildStudentListWithIndex(_filteredStudents),
        ),
      ],
    );
  }

  static String _getKanaHeader(String kana) {
    if (kana.isEmpty) return '他';
    final c = kana.codeUnitAt(0);
    if (c >= 0x3042 && c <= 0x304A) return 'あ';
    if (c >= 0x304B && c <= 0x3054) return 'か';
    if (c >= 0x3055 && c <= 0x305E) return 'さ';
    if (c >= 0x305F && c <= 0x3069) return 'た';
    if (c >= 0x306A && c <= 0x306E) return 'な';
    if (c >= 0x306F && c <= 0x307D) return 'は';
    if (c >= 0x307E && c <= 0x3082) return 'ま';
    if (c >= 0x3083 && c <= 0x3088) return 'や';
    if (c >= 0x3089 && c <= 0x308D) return 'ら';
    if (c >= 0x308E && c <= 0x3093) return 'わ';
    return '他';
  }

  Widget _buildStudentListWithIndex(List<Map<String, dynamic>> students) {
    final items = <Widget>[];
    String lastHeader = '';
    for (final student in students) {
      final kana = (student['lastNameKana'] as String? ?? '');
      final header = _getKanaHeader(kana);
      if (header != lastHeader) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(header, style: TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.bold, color: context.colors.aiAccent)),
        ));
        lastHeader = header;
      }
      final isActive = _activeStudentId == student['studentId'];
      items.add(_buildStudentItem(student, isActive));
    }
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: items);
  }

  Widget _buildStudentItem(Map<String, dynamic> student, bool isActive) {
    final name = student['name'] as String? ?? '';

    return _HoverableStudentItem(
      name: name,
      isActive: isActive,
      onTap: () => _openStudentChat(student),
    );
  }

  Widget _buildSessionList() {
    if (_recentSessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 40, color: context.colors.borderMedium),
            const SizedBox(height: 8),
            Text('履歴がありません',
                style: TextStyle(color: context.colors.textTertiary, fontSize: AppTextSize.body)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _recentSessions.length,
      itemBuilder: (context, index) {
        final session = _recentSessions[index];
        final isActive = _activeSessionId == session['docId'];
        return _buildSessionItem(session, isActive);
      },
    );
  }

  Widget _buildSessionItem(Map<String, dynamic> session, bool isActive) {
    final studentName = session['studentName'] ?? 'フリー相談';
    final lastMessage = session['lastMessage'] ?? '';
    final summary = session['summary'] as String?;
    final displayText = summary ?? lastMessage;

    String dateStr = '';
    if (session['updatedAt'] != null) {
      final ts = session['updatedAt'] as Timestamp;
      final date = ts.toDate();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 60) {
        dateStr = '${diff.inMinutes}分前';
      } else if (diff.inHours < 24) {
        dateStr = '${diff.inHours}時間前';
      } else if (diff.inDays < 7) {
        dateStr = '${diff.inDays}日前';
      } else {
        dateStr = DateFormat('M/d').format(date);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isActive ? context.colors.aiAccentBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: () => _openSession(session),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      studentName,
                      style: TextStyle(
                        fontSize: AppTextSize.body,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        color: isActive ? context.colors.aiAccent : context.colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(dateStr,
                      style: TextStyle(fontSize: AppTextSize.xs, color: context.colors.textTertiary)),
                ],
              ),
              if (displayText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  displayText,
                  style: TextStyle(fontSize: AppTextSize.caption, color: context.colors.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
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
            child: const Text(
              'AI相談',
              style: TextStyle(fontSize: AppTextSize.hero, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text('左の生徒を選んで相談を始めましょう',
              style: TextStyle(fontSize: AppTextSize.bodyMd, color: context.colors.textTertiary)),
        ],
      ),
    );
  }
}

class _HoverableStudentItem extends StatefulWidget {
  final String name;
  final bool isActive;
  final VoidCallback onTap;

  const _HoverableStudentItem({
    required this.name,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_HoverableStudentItem> createState() => _HoverableStudentItemState();
}

class _HoverableStudentItemState extends State<_HoverableStudentItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isActive || _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: widget.isActive
                ? context.colors.aiAccentBg
                : _isHovered
                    ? context.colors.chipBg
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? context.colors.aiAccent.withOpacity(0.15)
                      : _isHovered
                          ? context.colors.borderMedium
                          : context.colors.borderLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    widget.name.isNotEmpty ? widget.name[0] : '?',
                    style: TextStyle(
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.bold,
                      color: widget.isActive
                          ? context.colors.aiAccent
                          : context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
                    color: widget.isActive
                        ? context.colors.aiAccent
                        : context.colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
