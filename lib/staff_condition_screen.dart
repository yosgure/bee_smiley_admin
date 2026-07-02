import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_theme.dart';
import 'widgets/app_feedback.dart';
import 'widgets/condition_review.dart';

/// 職員向け・コンディション面談ビュー（構想4枚目「今月のコンディションまとめ」）。
///
/// 保護者が記録した日次きろく（キャラ・疲れ度・メモ）と月1かんたんシートを
/// 月単位で閲覧し、面談メモ（職員コメント3項目）を残す。
/// コメントは condition_sheets の同月 doc に staff* フィールドとして merge 保存し、
/// 保護者側「ふりかえり」にも「先生からのコメント」として表示される。
///
/// CRM サイドパネルの「コンディション」ボタンから AdminShell.showOverlay で開く。
class StaffConditionScreen extends StatefulWidget {
  final String studentId; // `${familyUid}_${childFirstName}`
  final String familyUid;
  final String childName; // 表示用（姓 名 など自由）
  final VoidCallback? onClose;
  final String? staffUid;

  /// テスト時に FakeFirebaseFirestore を注入するための口。通常は null。
  final FirebaseFirestore? firestore;

  const StaffConditionScreen({
    super.key,
    required this.studentId,
    required this.familyUid,
    required this.childName,
    this.onClose,
    this.staffUid,
    this.firestore,
  });

  @override
  State<StaffConditionScreen> createState() => _StaffConditionScreenState();
}

class _StaffConditionScreenState extends State<StaffConditionScreen> {
  FirebaseFirestore get _fs => widget.firestore ?? FirebaseFirestore.instance;

  late DateTime _month;
  // monthKey → dateKey → 日次データ / monthKey → 月次シート（null = 未記入）
  final Map<String, Map<String, Map<String, dynamic>>> _monthCache = {};
  final Map<String, Map<String, dynamic>?> _sheetCache = {};
  bool _loading = true;
  bool _saving = false;

  final _summaryCtl = TextEditingController();
  final _homeTipCtl = TextEditingController();
  final _classroomCtl = TextEditingController();

  static String _dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static String _monthKey(DateTime d) => DateFormat('yyyy-MM').format(d);

  String get _mk => _monthKey(_month);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load(_month);
  }

  @override
  void dispose() {
    _summaryCtl.dispose();
    _homeTipCtl.dispose();
    _classroomCtl.dispose();
    super.dispose();
  }

  Future<void> _load(DateTime month) async {
    final mk = _monthKey(month);
    if (_monthCache.containsKey(mk)) {
      _syncCommentControllers(mk);
      setState(() {});
      return;
    }
    setState(() => _loading = true);

    try {
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      final dateKeys = List.generate(
          lastDay, (i) => _dateKey(DateTime(month.year, month.month, i + 1)));

      final results = await Future.wait([
        ...dateKeys.map((k) => _fs
            .collection('condition_daily')
            .doc('${widget.studentId}_$k')
            .get()),
        _fs.collection('condition_sheets').doc('${widget.studentId}_$mk').get(),
      ]);

      if (!mounted) return;
      final map = <String, Map<String, dynamic>>{};
      for (var i = 0; i < dateKeys.length; i++) {
        if (results[i].exists) map[dateKeys[i]] = results[i].data()!;
      }
      final sheetDoc = results.last;
      _monthCache[mk] = map;
      _sheetCache[mk] = sheetDoc.exists ? sheetDoc.data() : null;
      _syncCommentControllers(mk);
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('staff condition load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _syncCommentControllers(String mk) {
    final sheet = _sheetCache[mk];
    _summaryCtl.text = (sheet?['staffSummary'] ?? '').toString();
    _homeTipCtl.text = (sheet?['staffHomeTip'] ?? '').toString();
    _classroomCtl.text = (sheet?['staffClassroomSupport'] ?? '').toString();
  }

  Future<void> _saveComment() async {
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        // シート未作成の月に職員が先にコメントする場合に備えて基本情報も入れる
        'studentId': widget.studentId,
        'familyUid': widget.familyUid,
        'childName': widget.childName,
        'monthKey': _mk,
        'month': Timestamp.fromDate(_month),
        'type': 'monthly',
        'staffSummary': _summaryCtl.text.trim(),
        'staffHomeTip': _homeTipCtl.text.trim(),
        'staffClassroomSupport': _classroomCtl.text.trim(),
        'staffCommentUpdatedAt': FieldValue.serverTimestamp(),
        if (widget.staffUid != null) 'staffCommentUpdatedBy': widget.staffUid,
      };
      await _fs
          .collection('condition_sheets')
          .doc('${widget.studentId}_$_mk')
          .set(payload, SetOptions(merge: true));

      // ローカルキャッシュにも反映
      final sheet =
          Map<String, dynamic>.from(_sheetCache[_mk] ?? <String, dynamic>{});
      sheet['staffSummary'] = _summaryCtl.text.trim();
      sheet['staffHomeTip'] = _homeTipCtl.text.trim();
      sheet['staffClassroomSupport'] = _classroomCtl.text.trim();
      _sheetCache[_mk] = sheet;

      if (!mounted) return;
      AppFeedback.success(context, '面談コメントを保存しました');
    } catch (e) {
      if (mounted) AppFeedback.error(context, '保存に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;
    final monthData = _monthCache[_mk];
    final sheet = _sheetCache[_mk];

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildMonthNav(isCurrentMonth),
            Expanded(
              child: _loading || monthData == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (monthData.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: context.colors.cardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: context.colors.borderLight),
                            ),
                            child: Text('この月の毎日のきろくはありません',
                                style: TextStyle(
                                    color: context.colors.textSecondary)),
                          )
                        else
                          ConditionReviewCards(
                              month: _month, monthData: monthData),
                        const SizedBox(height: 16),
                        _buildSheetSummaryCard(sheet),
                        const SizedBox(height: 16),
                        _buildStaffCommentEditor(),
                        const SizedBox(height: 32),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border(bottom: BorderSide(color: context.colors.borderLight)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 20),
            onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              '${widget.childName}のコンディション（面談用）',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: AppTextSize.title, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildMonthNav(bool isCurrentMonth) {
    return Container(
      color: context.colors.cardBg,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              final prev = DateTime(_month.year, _month.month - 1);
              setState(() => _month = prev);
              _load(prev);
            },
          ),
          Expanded(
            child: Text(
              DateFormat('yyyy年 M月', 'ja').format(_month),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: AppTextSize.bodyLarge, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isCurrentMonth
                ? null
                : () {
                    final next = DateTime(_month.year, _month.month + 1);
                    setState(() => _month = next);
                    _load(next);
                  },
          ),
        ],
      ),
    );
  }

  // ---------------- 月1かんたんシートの要約（読み取り専用） ----------------
  Widget _buildSheetSummaryCard(Map<String, dynamic>? sheet) {
    final rows = <MapEntry<String, String>>[];
    if (sheet != null) {
      final sleep = (sheet['sleep'] as Map?) ?? {};
      final schedule = (sheet['schedule'] as Map?) ?? {};
      final media = (sheet['media'] as Map?) ?? {};
      final mediaStop = (sheet['mediaStop'] as Map?) ?? {};

      void add(String label, dynamic v) {
        final s = (v ?? '').toString().trim();
        if (s.isNotEmpty) rows.add(MapEntry(label, s));
      }

      final bedtime = (sleep['bedtime'] ?? '').toString();
      final wakeTime = (sleep['wakeTime'] ?? '').toString();
      if (bedtime.isNotEmpty || wakeTime.isNotEmpty) {
        add('睡眠時間帯', [
          if (bedtime.isNotEmpty) '就寝 $bedtime',
          if (wakeTime.isNotEmpty) '起床 $wakeTime',
        ].join(' / '));
      }
      add('寝つき', sleep['fallAsleep']);
      add('夜中に起きる', sleep['nightWaking']);
      add('朝の機嫌', sleep['morningMood']);

      final checked = schedule.entries
          .where((e) => e.value == true)
          .map((e) => e.key.toString())
          .toList();
      if (checked.isNotEmpty) add('予定量', checked.join('、'));

      const mediaLabels = {
        'tv': 'テレビ',
        'youtube': 'YouTube',
        'game': 'ゲーム',
        'tablet': 'スマホ・タブレット',
      };
      final mediaParts = <String>[];
      mediaLabels.forEach((k, label) {
        final v = (media[k] ?? '').toString().trim();
        if (v.isNotEmpty) mediaParts.add('$label: $v');
      });
      if (mediaParts.isNotEmpty) add('メディア時間', mediaParts.join(' / '));

      final timings = (sheet['mediaTimings'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      if (timings.isNotEmpty) add('よく見るタイミング', timings.join('、'));
      add('声かけでやめられる', mediaStop['voiceStop']);
      add('やめる時に泣く・怒る', mediaStop['cryAngry']);
      add('気になった行動', sheet['concernedBehavior']);
      add('安定していた場面', sheet['stableScenes']);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.assignment_outlined,
                  color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text('保護者の月1かんたんシート',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyLarge,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text('この月のかんたんシートは未記入です',
                style: TextStyle(color: context.colors.textSecondary))
          else
            ...rows.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 128,
                        child: Text(e.key,
                            style: TextStyle(
                                fontSize: AppTextSize.small,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textSecondary)),
                      ),
                      Expanded(
                        child: Text(e.value,
                            style: const TextStyle(
                                fontSize: AppTextSize.body, height: 1.5)),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  // ---------------- 職員コメント（面談メモ） ----------------
  Widget _buildStaffCommentEditor() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.school, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text('面談コメント（保護者にも表示されます）',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyLarge,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _summaryCtl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '今月の見立て（どんな時に安定 / 疲れたか）',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _homeTipCtl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '来月、家庭で試す小さな工夫',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _classroomCtl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '教室で継続する支援',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveComment,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('コメントを保存',
                      style: TextStyle(
                          fontSize: AppTextSize.bodyLarge,
                          fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
