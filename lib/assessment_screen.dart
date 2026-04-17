import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'assessment_edit_screen.dart';
import 'assessment_detail_screen.dart';
import 'app_theme.dart';
import 'classroom_utils.dart';
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
  String? _selectedClassroom; // null = 全教室

  List<Map<String, dynamic>> _allStudents = [];

  String? _selectedStudentId;
  String _selectedStudentName = '';

  int _currentTabIndex = 0;
  bool _isLoading = true;

  String _searchQuery = '';
  final _searchController = TextEditingController();

  // モバイル用サイドバー表示
  bool _showSidebar = true;

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
    // 教室フィルタ
    if (_selectedClassroom != null) {
      list = list
          .where((s) => (s['classrooms'] as List<String>?)?.contains(_selectedClassroom) ?? false)
          .toList();
    }
    // 検索フィルタ
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

          // アセスメント対象教室に所属する子だけ
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

          // 外部から生徒指定で開いた場合
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
            _showSidebar = false; // 直接アクセス時はコンテンツ表示
          }
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectStudent(Map<String, dynamic> student) {
    setState(() {
      _selectedStudentId = student['id'] as String;
      _selectedStudentName = student['name'] as String;
      // モバイルではコンテンツ表示に切り替え
      if (MediaQuery.of(context).size.width < 768) {
        _showSidebar = false;
      }
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
      backgroundColor: context.colors.cardBg,
      appBar: (!isDesktop && _showSidebar)
          ? AppBar(
              title: const Text('アセスメント'),
              centerTitle: true,
              backgroundColor: context.colors.cardBg,
              elevation: 0,
              foregroundColor: context.colors.textPrimary,
              automaticallyImplyLeading: false,
            )
          : null,
      body: Row(
        children: [
          // 左サイドバー
          if (isDesktop || _showSidebar)
            SizedBox(
              width: isDesktop ? 280 : MediaQuery.of(context).size.width,
              child: _buildSidebar(context),
            ),
          if (isDesktop) VerticalDivider(thickness: 1, width: 1, color: context.colors.borderLight),
          // 右コンテンツ
          if (isDesktop || !_showSidebar)
            Expanded(child: _buildContent(context, isDesktop)),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final students = _filteredStudents;
    return Column(
      children: [
        // ヘッダー（デスクトップのみ、モバイルはAppBarがタイトルを担当）
        if (isDesktop)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: const Text(
              'アセスメント',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        // 教室フィルタ
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: context.colors.inputFill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedClassroom,
                isExpanded: true,
                hint: const Text('全教室', style: TextStyle(fontSize: 13)),
                style: TextStyle(fontSize: 13, color: context.colors.textPrimary),
                icon: Icon(Icons.expand_more, size: 18, color: context.colors.textSecondary),
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
        // 検索バー
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '検索...',
              hintStyle: TextStyle(fontSize: 13, color: context.colors.textTertiary),
              prefixIcon: Icon(Icons.search, size: 18, color: context.colors.textTertiary),
              filled: true,
              fillColor: context.colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              isDense: true,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        const SizedBox(height: 4),
        // 生徒一覧
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : students.isEmpty
                  ? Center(child: Text('該当する児童がいません', style: TextStyle(color: context.colors.textSecondary, fontSize: 13)))
                  : _buildStudentListWithIndex(students),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, bool isDesktop) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.colors.cardBg,
        appBar: AppBar(
          title: Text(
            _selectedStudentId != null ? _selectedStudentName : '',
            style: const TextStyle(fontSize: 16),
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
            tabs: const [
              Tab(text: '週次アセスメント'),
              Tab(text: '月次サマリ'),
            ],
          ),
        ),
        body: _selectedStudentId == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.assignment_outlined, size: 64, color: context.colors.textTertiary),
                    const SizedBox(height: 16),
                    Text('左の生徒を選んでアセスメントを表示',
                        style: TextStyle(color: context.colors.textSecondary)),
                  ],
                ),
              )
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
                icon: const Icon(Icons.edit, color: Colors.white),
                label: Text(
                  _currentTabIndex == 0 ? '週次アセスメント作成' : '月次サマリ作成',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              )
            : null,
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
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('データがありません', style: TextStyle(color: context.colors.textSecondary)));
        }

        final docs = snapshot.data!.docs;
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
                final date = (data['date'] as Timestamp).toDate();
                final records = List<Map<String, dynamic>>.from(data['entries'] ?? []);
                final toolNames = records.map((r) => r['tool'] as String? ?? '不明').join('、');

                return Card(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => AssessmentDetailScreen(doc: doc),
                      ));
                    },
                    borderRadius: AppStyles.radius,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                DateFormat('yyyy/MM/dd (E)', 'ja').format(date),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(width: 8),
                              _buildStatusBadge(data['isPublished'] == true),
                              const Spacer(),
                              Icon(Icons.chevron_right, color: context.colors.textSecondary),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            toolNames.isEmpty ? '記録なし' : toolNames,
                            style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
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
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('データがありません', style: TextStyle(color: context.colors.textSecondary)));
        }

        final docs = snapshot.data!.docs;
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
                final date = (data['date'] as Timestamp).toDate();

                return Card(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => AssessmentDetailScreen(doc: doc),
                      ));
                    },
                    borderRadius: AppStyles.radius,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                DateFormat('yyyy年 MM月', 'ja').format(date),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(width: 8),
                              _buildStatusBadge(data['isPublished'] == true),
                              const Spacer(),
                              Icon(Icons.chevron_right, color: context.colors.textSecondary),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            data['summary'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
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
    // 五十音ヘッダー付きリストを構築
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
    return ListView(children: items);
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
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isPublished ? Colors.green.shade700 : AppColors.accent.shade700,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: widget.isActive
              ? AppColors.primary.withValues(alpha: 0.12)
              : _isHovered
                  ? context.colors.hoverBg
                  : Colors.transparent,
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: widget.isActive
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : context.colors.chipBg,
                child: Text(
                  firstChar,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: widget.isActive ? AppColors.primary : context.colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: widget.isActive ? FontWeight.bold : FontWeight.normal,
                    color: widget.isActive ? AppColors.primary : context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
