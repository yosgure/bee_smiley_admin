import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'assessment_edit_screen.dart';
import 'assessment_detail_screen.dart';
import 'app_theme.dart';
import 'classroom_utils.dart';
import 'lesson_quick_capture.dart';
import 'main.dart';

class AssessmentScreen extends StatefulWidget {
  final String? initialStudentId;
  final String? initialStudentName;

  const AssessmentScreen({
    super.key,
    this.initialStudentId,
    this.initialStudentName,
  });

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  List<String> _classrooms = [];
  String? _selectedClassroom;

  List<Map<String, dynamic>> _allStudents = [];

  // 「今のレッスン」セクション用：自分が現在の枠で担当している生徒
  List<Map<String, dynamic>> _currentLessonStudents = [];
  int? _currentSlotIndex;
  bool _quickCaptureBusy = false;

  String? _selectedStudentId;
  String _selectedStudentName = '';

  int _currentTabIndex = 0;
  bool _isLoading = true;

  String _searchQuery = '';
  final _searchController = TextEditingController();

  // モバイル用サイドバー表示
  bool _showSidebar = true;

  // 詳細画面を右ペインに表示する際のドキュメント
  DocumentSnapshot? _detailDoc;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredStudents {
    var list = _allStudents;
    if (_selectedClassroom != null) {
      list = list
          .where((s) => (s['classrooms'] as List<String>?)?.contains(_selectedClassroom) ?? false)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((s) {
        final name = (s['name'] as String? ?? '').toLowerCase();
        final kana = (s['kana'] as String? ?? '').toLowerCase();
        return name.contains(q) || kana.contains(q);
      }).toList();
    }
    return list;
  }

  Future<void> _fetchData() async {
    try {
      const classList = ['ビースマイリー湘南藤沢', 'ビースマイリー湘南台'];

      final familySnap = await FirebaseFirestore.instance.collection('families').get();
      final List<Map<String, dynamic>> studentList = [];

      for (var doc in familySnap.docs) {
        final data = doc.data();
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);

        for (var child in children) {
          final uid = data['uid'];
          final firstName = child['firstName'] ?? '';
          final lastName = data['lastName'] ?? '';
          final firstNameKana = child['firstNameKana'] ?? '';
          final lastNameKana = data['lastNameKana'] ?? '';

          final fullName = '$lastName $firstName';
          final fullKana = '$lastNameKana $firstNameKana';
          final classrooms = getChildClassrooms(child);
          final classroom = classrooms.join(', ');

          if (!classrooms.any((c) => classList.contains(c))) continue;

          final id = '${uid}_$firstName';

          studentList.add({
            'id': id,
            'name': fullName,
            'kana': fullKana,
            'classroom': classroom,
            'classrooms': classrooms,
          });
        }
      }

      studentList.sort((a, b) => (a['kana'] as String).compareTo(b['kana'] as String));

      if (mounted) {
        setState(() {
          _classrooms = classList;
          _allStudents = studentList;
          _isLoading = false;

          if (widget.initialStudentId != null) {
            _selectedStudentId = widget.initialStudentId;
            _selectedStudentName = widget.initialStudentName ?? '';
            final student = _allStudents.firstWhere(
              (s) => s['id'] == widget.initialStudentId,
              orElse: () => {},
            );
            if (student.isNotEmpty) {
              _selectedStudentName = student['name'] as String;
            }
            _showSidebar = false;
          }
        });
        _loadCurrentLessonStudents();
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCurrentLessonStudents() async {
    try {
      final list = await fetchCurrentLessonStudents(allStudents: _allStudents);
      if (mounted) {
        setState(() {
          _currentSlotIndex = currentSlotIndex();
          _currentLessonStudents = list;
        });
      }
    } catch (e) {
      debugPrint('current lesson load error: $e');
    }
  }

  Future<void> _onQuickCaptureTap(Map<String, dynamic> student) async {
    if (_quickCaptureBusy) return;
    setState(() => _quickCaptureBusy = true);
    try {
      await quickCapturePhoto(
        context: context,
        studentId: student['id'] as String,
        studentName: student['name'] as String,
      );
    } finally {
      if (mounted) setState(() => _quickCaptureBusy = false);
    }
  }

  void _selectStudent(Map<String, dynamic> student) {
    setState(() {
      _selectedStudentId = student['id'] as String;
      _selectedStudentName = student['name'] as String;
      _detailDoc = null;
      if (MediaQuery.of(context).size.width < 768) {
        _showSidebar = false;
      }
    });
  }

  void _openDetail(DocumentSnapshot doc) {
    setState(() {
      _detailDoc = doc;
    });
  }

  void _closeDetail() {
    setState(() {
      _detailDoc = null;
    });
  }

  void _onAddPressed() {
    if (_selectedStudentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('児童を選択してください')),
      );
      return;
    }
    final type = _currentTabIndex == 0 ? 'weekly' : 'monthly';
    final isWide = MediaQuery.of(context).size.width >= 600;
    if (isWide) {
      AdminShell.showOverlay(
        context,
        AssessmentEditScreen(
          studentId: _selectedStudentId!,
          studentName: _selectedStudentName,
          type: type,
          onClose: () => AdminShell.hideOverlay(context),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AssessmentEditScreen(
            studentId: _selectedStudentId!,
            studentName: _selectedStudentName,
            type: type,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: (!isDesktop && _showSidebar)
          ? AppBar(
              title: const Text('記録'),
              centerTitle: true,
              backgroundColor: context.colors.cardBg,
              elevation: 0,
              foregroundColor: context.colors.textPrimary,
              automaticallyImplyLeading: false,
            )
          : null,
      body: Row(
        children: [
          if (isDesktop || _showSidebar)
            SizedBox(
              width: isDesktop ? 280 : MediaQuery.of(context).size.width,
              child: _buildSidebar(context),
            ),
          if (isDesktop || !_showSidebar)
            Expanded(child: _buildContent(context, isDesktop)),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final students = _filteredStudents;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.hoverBg,
        border: Border(
          right: BorderSide(color: context.colors.borderLight, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          if (isDesktop)
            Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 12),
              child: Text(
                '記録',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          // 教室フィルタ
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: context.colors.borderLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedClassroom,
                  isExpanded: true,
                  hint: Text('全教室', style: TextStyle(fontSize: 13, color: context.colors.textHint)),
                  style: TextStyle(fontSize: 13, color: context.colors.textPrimary),
                  icon: Icon(Icons.expand_more, size: 16, color: context.colors.textHint),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text('全教室', style: TextStyle(fontSize: 13, color: context.colors.textPrimary)),
                    ),
                    ..._classrooms.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c, style: TextStyle(fontSize: 13, color: context.colors.textPrimary)),
                    )),
                  ],
                  onChanged: (val) => setState(() => _selectedClassroom = val),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
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
                style: TextStyle(fontSize: 13, color: context.colors.textPrimary),
                decoration: InputDecoration(
                  hintText: '検索...',
                  hintStyle: TextStyle(color: context.colors.textHint, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: context.colors.textHint, size: 16),
                  filled: false,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (_currentLessonStudents.isNotEmpty) _buildCurrentLessonSection(),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppColors.primary))
                : students.isEmpty
                    ? Center(child: Text('該当する児童がいません', style: TextStyle(color: context.colors.textTertiary, fontSize: 13)))
                    : _buildStudentListWithIndex(students),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentLessonSection() {
    final slot = _currentSlotIndex;
    final label = slot != null
        ? slotLabel(slot)
        : DateFormat('HH:mm〜').format(DateTime.now());
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.25), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
            child: Row(
              children: [
                Icon(Icons.photo_camera_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  '今のレッスン',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
                ),
                const Spacer(),
                Tooltip(
                  message: 'タップで撮影 → 今週の下書きに自動追加',
                  child: Icon(Icons.help_outline,
                      size: 14, color: context.colors.textHint),
                ),
              ],
            ),
          ),
          ..._currentLessonStudents.map((s) => _CurrentLessonTile(
                name: s['name'] as String? ?? '',
                onTap: () => _onQuickCaptureTap(s),
                disabled: _quickCaptureBusy,
              )),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isDesktop) {
    // 詳細表示中は詳細画面を描画（サイドバーは残す）
    if (_detailDoc != null) {
      return AssessmentDetailScreen(
        key: ValueKey('detail_${_detailDoc!.id}'),
        doc: _detailDoc!,
        onClose: _closeDetail,
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.colors.cardBg,
        appBar: AppBar(
          title: Text(
            _selectedStudentId != null ? _selectedStudentName : '',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          backgroundColor: context.colors.cardBg,
          elevation: 0,
          leading: !isDesktop
              ? IconButton(
                  icon: Icon(Icons.arrow_back_ios, color: context.colors.textPrimary, size: 20),
                  onPressed: () => setState(() => _showSidebar = true),
                )
              : null,
          bottom: TabBar(
            onTap: (index) => setState(() => _currentTabIndex = index),
            labelColor: AppColors.primary,
            unselectedLabelColor: context.colors.textSecondary,
            indicatorColor: AppColors.primary,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(text: '週次アセスメント'),
              Tab(text: '月次サマリ'),
            ],
          ),
        ),
        body: _selectedStudentId == null
            ? _buildWelcome()
            : TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWeeklyList(),
                  _buildMonthlyList(),
                ],
              ),
        floatingActionButton: _selectedStudentId != null
            ? FloatingActionButton.extended(
                heroTag: null,
                onPressed: _onAddPressed,
                backgroundColor: AppColors.primary,
                elevation: 4,
                icon: const Icon(Icons.edit, color: Colors.white, size: 18),
                label: Text(
                  _currentTabIndex == 0 ? '週次アセスメント作成' : '月次サマリ作成',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              )
            : null,
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
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.edit_note, color: AppColors.primary, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            '記録',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text('左の生徒を選んで記録を表示',
              style: TextStyle(fontSize: 13, color: context.colors.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildWeeklyList() {
    final query = FirebaseFirestore.instance
        .collection('assessments')
        .where('type', isEqualTo: 'weekly')
        .where('studentId', isEqualTo: _selectedStudentId)
        .orderBy('date', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('データがありません', style: TextStyle(color: context.colors.textTertiary, fontSize: 13)));
        }

        final docs = snapshot.data!.docs;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final date = (data['date'] as Timestamp).toDate();
                final records = List<Map<String, dynamic>>.from(data['entries'] ?? []);
                final toolNames = records
                    .where((r) => r['isQuickDraft'] != true)
                    .map((r) => r['tool'] as String? ?? '不明')
                    .join('、');
                int photoCount = 0;
                for (final r in records) {
                  final m = r['mediaItems'] as List?;
                  if (m != null) photoCount += m.length;
                }
                final hasOnlyQuickDraft = records.isNotEmpty &&
                    records.every((r) => r['isQuickDraft'] == true);

                return _RecordCard(
                  onTap: () => _openDetail(doc),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            DateFormat('yyyy/MM/dd (E)', 'ja').format(date),
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.colors.textPrimary),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(data['isPublished'] == true),
                          if (photoCount > 0) ...[
                            const SizedBox(width: 6),
                            _buildPhotoBadge(photoCount, hasOnlyQuickDraft),
                          ],
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded, color: context.colors.textTertiary, size: 18),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hasOnlyQuickDraft
                            ? '写真のみ（教具・コメント未入力）'
                            : (toolNames.isEmpty ? '記録なし' : toolNames),
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 12, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthlyList() {
    final query = FirebaseFirestore.instance
        .collection('assessments')
        .where('type', isEqualTo: 'monthly')
        .where('studentId', isEqualTo: _selectedStudentId)
        .orderBy('date', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('データがありません', style: TextStyle(color: context.colors.textTertiary, fontSize: 13)));
        }

        final docs = snapshot.data!.docs;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final date = (data['date'] as Timestamp).toDate();

                return _RecordCard(
                  onTap: () => _openDetail(doc),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            DateFormat('yyyy年 MM月', 'ja').format(date),
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.colors.textPrimary),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(data['isPublished'] == true),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded, color: context.colors.textTertiary, size: 18),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data['summary'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
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
      final kana = student['kana'] as String? ?? '';
      final header = _getKanaHeader(kana);
      if (header != lastHeader) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(header, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
        ));
        lastHeader = header;
      }
      final isActive = student['id'] == _selectedStudentId;
      items.add(_HoverableStudentItem(
        name: student['name'] as String? ?? '',
        isActive: isActive,
        onTap: () => _selectStudent(student),
      ));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: items,
    );
  }

  Widget _buildPhotoBadge(int count, bool emphasize) {
    final color = emphasize ? AppColors.primary : context.colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_camera_rounded, size: 10, color: color),
          const SizedBox(width: 3),
          Text('$count',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isPublished) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isPublished ? Colors.green.withValues(alpha: 0.1) : AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPublished ? Colors.green : AppColors.accent,
          width: 0.5,
        ),
      ),
      child: Text(
        isPublished ? '公開中' : '下書き',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isPublished ? Colors.green.shade700 : AppColors.accent.shade700,
        ),
      ),
    );
  }
}

class _CurrentLessonTile extends StatefulWidget {
  final String name;
  final VoidCallback onTap;
  final bool disabled;

  const _CurrentLessonTile({
    required this.name,
    required this.onTap,
    required this.disabled,
  });

  @override
  State<_CurrentLessonTile> createState() => _CurrentLessonTileState();
}

class _CurrentLessonTileState extends State<_CurrentLessonTile> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final firstChar = widget.name.isNotEmpty ? widget.name[0] : '?';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.disabled ? null : widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _pressed
                ? AppColors.primary.withOpacity(0.18)
                : _hover
                    ? AppColors.primary.withOpacity(0.10)
                    : Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    firstChar,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text('撮影',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _RecordCard({required this.child, required this.onTap});

  @override
  State<_RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<_RecordCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hover ? context.colors.hoverBg : context.colors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.borderLight, width: 0.5),
          ),
          child: widget.child,
        ),
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
    final firstChar = widget.name.isNotEmpty ? widget.name[0] : '?';
    final isHighlighted = widget.isActive || _isHovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppColors.primary.withValues(alpha: 0.12)
                : _isHovered
                    ? context.colors.chipBg
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? AppColors.primary.withOpacity(0.15)
                      : _isHovered
                          ? context.colors.borderMedium
                          : context.colors.borderLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    firstChar,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: widget.isActive ? AppColors.primary : context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
                    color: widget.isActive ? AppColors.primary : context.colors.textPrimary,
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
