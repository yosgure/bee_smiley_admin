import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'app_theme.dart';
import 'main.dart';

// ============================================================
// CRM-00: 選択肢マスタ
// ============================================================
class CrmOptions {
  /// パイプライン上に並べるステージ（左→右へ前進）
  static const List<({String id, String label, Color color})> stages = [
    (id: 'considering', label: '検討中', color: Color(0xFFFF9800)),
    (id: 'onboarding', label: '入会手続中', color: Color(0xFF9C27B0)),
    (id: 'won', label: '入会', color: Color(0xFF4CAF50)),
    (id: 'lost', label: '失注', color: Color(0xFF9E9E9E)),
  ];

  /// カンバンに表示する進行中ステージ（won/lostを除外）
  static const List<String> kanbanStages = [
    'considering',
    'onboarding',
  ];

  static const List<({String id, String label})> sources = [
    (id: 'instagram', label: 'Instagram'),
    (id: 'website', label: 'HP・Web検索'),
    (id: 'google_ads', label: 'Google広告'),
    (id: 'flyer', label: 'チラシ'),
    (id: 'referral_parent', label: '保護者紹介'),
    (id: 'referral_kindergarten', label: '園・学校紹介'),
    (id: 'referral_other', label: '事業所紹介'),
    (id: 'event', label: 'イベント・セミナー'),
    (id: 'walk_in', label: '飛び込み'),
    (id: 'other', label: 'その他'),
  ];

  static const List<({String id, String label})> lossReasons = [
    (id: 'price', label: '料金'),
    (id: 'distance', label: '距離・通所負担'),
    (id: 'schedule', label: '曜日・時間が合わず'),
    (id: 'competitor', label: '他社決定'),
    (id: 'no_reply', label: '連絡途絶'),
    (id: 'family_reason', label: '家庭事情'),
    (id: 'capacity', label: '受け入れ枠なし'),
    (id: 'not_match', label: '支援内容ミスマッチ'),
    (id: 'other', label: 'その他'),
  ];

  static const List<({String id, String label})> channels = [
    (id: 'tel', label: '電話'),
    (id: 'email', label: 'メール'),
    (id: 'line', label: 'LINE'),
  ];

  static const List<({String id, String label})> confidence = [
    (id: 'A', label: 'A（高）'),
    (id: 'B', label: 'B（中）'),
    (id: 'C', label: 'C（低）'),
  ];

  static const List<({String id, String label})> permitStatus = [
    (id: 'none', label: '未申請'),
    (id: 'applying', label: '申請中'),
    (id: 'have', label: '取得済'),
  ];

  static const List<({String id, String label})> activityTypes = [
    (id: 'tel', label: '電話'),
    (id: 'email', label: 'メール'),
    (id: 'line', label: 'LINE'),
    (id: 'visit', label: '来所'),
    (id: 'memo', label: 'メモ'),
    (id: 'task', label: 'タスク'),
  ];

  static String labelOf(List<({String id, String label})> list, String id) {
    for (final o in list) {
      if (o.id == id) return o.label;
    }
    return id;
  }

  static ({String id, String label, Color color})? stageOf(String id) {
    for (final s in stages) {
      if (s.id == id) return s;
    }
    return null;
  }

  static String stageLabel(String id) => stageOf(id)?.label ?? id;
  static Color stageColor(String id) => stageOf(id)?.color ?? Colors.grey;
}

// ============================================================
// CRM-01: 一覧画面（カンバン / テーブル切替）
// ============================================================
class CrmLeadScreen extends StatefulWidget {
  final VoidCallback? onClose;
  const CrmLeadScreen({super.key, this.onClose});

  @override
  State<CrmLeadScreen> createState() => _CrmLeadScreenState();
}

class _CrmLeadScreenState extends State<CrmLeadScreen> {
  int _viewMode = 0; // 0: kanban, 1: table, 2: dashboard
  String _sourceFilter = 'all';
  String _stageFilter = 'all'; // table view用

  void _close() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      AdminShell.hideOverlay(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('CRM',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: _close,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file, size: 20),
            tooltip: 'CSVインポート（Notion）',
            onPressed: _importFromNotionCsv,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読込',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewLead,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('新規リード',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: context.colors.cardBg,
      child: Row(
        children: [
          // ビュー切替
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('カンバン'), icon: Icon(Icons.view_kanban_outlined, size: 16)),
              ButtonSegment(value: 1, label: Text('一覧'), icon: Icon(Icons.table_rows_outlined, size: 16)),
              ButtonSegment(value: 2, label: Text('分析'), icon: Icon(Icons.bar_chart, size: 16)),
            ],
            selected: {_viewMode},
            onSelectionChanged: (s) => setState(() => _viewMode = s.first),
            style: ButtonStyle(
              textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
              padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
          ),
          const SizedBox(width: 12),
          // 媒体フィルタ
          _filterDropdown(
            label: '媒体',
            value: _sourceFilter,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('すべて')),
              ...CrmOptions.sources.map(
                  (s) => DropdownMenuItem(value: s.id, child: Text(s.label))),
            ],
            onChanged: (v) => setState(() => _sourceFilter = v ?? 'all'),
          ),
          if (_viewMode == 1) ...[
            const SizedBox(width: 8),
            _filterDropdown(
              label: 'ステージ',
              value: _stageFilter,
              items: [
                const DropdownMenuItem(value: 'all', child: Text('すべて')),
                ...CrmOptions.stages.map(
                    (s) => DropdownMenuItem(value: s.id, child: Text(s.label))),
              ],
              onChanged: (v) => setState(() => _stageFilter = v ?? 'all'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.borderMedium),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label:',
              style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items,
              onChanged: onChanged,
              style: TextStyle(fontSize: 12, color: context.colors.textPrimary),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final stream = FirebaseFirestore.instance
        .collection('crm_leads')
        .orderBy('inquiredAt', descending: true)
        .limit(500)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          return Center(
              child: Text('読み込みエラー: ${snap.error}',
                  style: TextStyle(color: context.colors.textSecondary)));
        }
        var docs = snap.data?.docs ?? [];
        if (_sourceFilter != 'all') {
          docs = docs.where((d) => (d.data()['source'] ?? '') == _sourceFilter).toList();
        }
        if (docs.isEmpty) return _emptyState();
        switch (_viewMode) {
          case 0:
            return _CrmKanbanView(docs: docs);
          case 1:
            final list = _stageFilter == 'all'
                ? docs
                : docs.where((d) => (d.data()['stage'] ?? '') == _stageFilter).toList();
            return _CrmTableView(docs: list);
          case 2:
          default:
            return _CrmDashboardView(docs: docs);
        }
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline,
              size: 56, color: context.colors.textTertiary),
          const SizedBox(height: 12),
          Text('リードはまだありません',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
          const SizedBox(height: 4),
          Text('右下の「新規リード」から登録できます',
              style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _openNewLead() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CrmLeadEditScreen()),
    );
  }

  // ------------------------------------------------------------
  // CSVインポート（Notionエクスポート用・一回限り）
  // ------------------------------------------------------------
  Future<void> _importFromNotionCsv() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('NotionエクスポートCSVをインポート'),
        content: const Text(
            '選択したCSVをリードとして一括登録します。\n'
            '同じCSVを二度インポートすると重複するので注意してください。\n\n続行しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('選択',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) return;

    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      text = latin1.decode(bytes);
    }

    final rows = const CsvToListConverter(
            eol: '\n', shouldParseNumbers: false, allowInvalid: true)
        .convert(text);
    if (rows.length < 2) {
      _snack('行がありません', Colors.orange);
      return;
    }
    final header = rows.first.map((e) => e.toString().trim()).toList();
    int idx(String name) => header.indexOf(name);
    final iName = idx('名前');
    final iTel = idx('TEL') >= 0 ? idx('TEL') : idx(' TEL');
    final iArea = idx('お住いの地域');
    final iChild = idx('お子さまの名前');
    final iKana = idx('ふりがな');
    final iStatus = idx('ステータス');
    final iEmail = idx('メール');
    final iMainConcern = idx('主訴');
    final iAddress = idx('住所');
    final iTrialNotes = idx('体験で分かったこと/聞いたこと');
    final iTrial = idx('体験日');
    final iKinder = idx('保育園/幼稚園');
    final iMemo = idx('備考');
    final iInquired = idx('問い合わせ日');
    final iLikes = idx('好きなこと');
    final iNext = idx('対応期日');
    final iSource = idx('応募経路');
    final iGender = idx('性別');
    final iNextAction = idx('現状・ネクストアクション');
    final iDislikes = idx('苦手なこと');
    final iBirth = idx('誕生日');
    final iLoss = idx('辞退理由');

    String get(List<dynamic> row, int i) {
      if (i < 0 || i >= row.length) return '';
      return row[i].toString().trim();
    }

    DateTime? parseJpDate(String s) {
      final m = RegExp(r'(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日').firstMatch(s);
      if (m == null) return null;
      return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
          int.parse(m.group(3)!));
    }

    String mapStage(String s) {
      final v = s.trim();
      if (v == '辞退') return 'lost';
      if (v == '入会') return 'won';
      if (v == '入会準備中') return 'onboarding';
      return 'considering';
    }

    String mapSource(String s) {
      if (s.contains('Instagram') || s.contains('インスタ')) return 'instagram';
      if (s.contains('紹介')) return 'referral_other';
      if (s.contains('チラシ')) return 'flyer';
      if (s.contains('HP') || s.contains('Web') || s.contains('検索')) return 'website';
      return 'other';
    }

    final user = FirebaseAuth.instance.currentUser;
    final fs = FirebaseFirestore.instance;
    final col = fs.collection('crm_leads');

    int ok = 0;
    int skipped = 0;
    WriteBatch batch = fs.batch();
    int inBatch = 0;

    // 進捗スナックバー
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('インポート中...'), duration: Duration(seconds: 60)));

    try {
      for (int r = 1; r < rows.length; r++) {
        final row = rows[r];
        final parentFull = get(row, iName);
        final childName = get(row, iChild);
        final inquired = parseJpDate(get(row, iInquired));
        if (parentFull.isEmpty && childName.isEmpty && inquired == null) {
          skipped++;
          continue;
        }
        final cleaned = parentFull.replaceAll(RegExp(r'\s+'), ' ').trim();
        final parts = cleaned.split(' ');
        final pLast = parts.isNotEmpty ? parts[0] : '';
        final pFirst = parts.length >= 2 ? parts.sublist(1).join('') : '';
        final stage = mapStage(get(row, iStatus));
        final trialAt = parseJpDate(get(row, iTrial));
        final nextAt = parseJpDate(get(row, iNext));
        final birth = parseJpDate(get(row, iBirth));
        final source = mapSource(get(row, iSource));
        final addressParts = [get(row, iArea), get(row, iAddress)]
            .where((s) => s.isNotEmpty)
            .toList();
        final data = <String, dynamic>{
          'importSource': 'notion_initial',
          'childLastName': '',
          'childFirstName': childName,
          'childKana': get(row, iKana),
          'childGender': get(row, iGender),
          'childBirthDate':
              birth == null ? null : Timestamp.fromDate(birth),
          'kindergarten': get(row, iKinder),
          'permitStatus': 'none',
          'parentLastName': pLast,
          'parentFirstName': pFirst,
          'parentKana': '',
          'parentTel': get(row, iTel),
          'parentEmail': get(row, iEmail).replaceFirst(RegExp(r'^mailto:'), ''),
          'parentLine': '',
          'preferredChannel': 'tel',
          'address': addressParts.join(' '),
          'stage': stage,
          'confidence': stage == 'won'
              ? 'A'
              : stage == 'lost'
                  ? 'C'
                  : 'B',
          'source': source,
          'sourceDetail': get(row, iSource),
          'preferredDays': '',
          'preferredTimeSlots': '',
          'preferredStart': '',
          'mainConcern': get(row, iMainConcern),
          'likes': get(row, iLikes),
          'dislikes': get(row, iDislikes),
          'trialNotes': get(row, iTrialNotes),
          'nextActionAt':
              nextAt == null ? null : Timestamp.fromDate(nextAt),
          'nextActionNote': get(row, iNextAction),
          'inquiredAt': inquired == null
              ? FieldValue.serverTimestamp()
              : Timestamp.fromDate(inquired),
          'firstContactedAt': null,
          'trialAt':
              trialAt == null ? null : Timestamp.fromDate(trialAt),
          'enrolledAt': stage == 'won'
              ? (trialAt == null
                  ? (inquired == null
                      ? null
                      : Timestamp.fromDate(inquired))
                  : Timestamp.fromDate(trialAt))
              : null,
          'lostAt': stage == 'lost' && inquired != null
              ? Timestamp.fromDate(inquired)
              : null,
          'lossReason': stage == 'lost' ? 'other' : null,
          'lossDetail': stage == 'lost' ? get(row, iLoss) : '',
          'reapproachOk': true,
          'memo': get(row, iMemo),
          'activities': <Map<String, dynamic>>[],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdBy': 'import:notion:${user?.uid ?? ''}',
        };
        batch.set(col.doc(), data);
        inBatch++;
        ok++;
        if (inBatch >= 400) {
          await batch.commit();
          batch = fs.batch();
          inBatch = 0;
        }
      }
      if (inBatch > 0) await batch.commit();
      messenger.hideCurrentSnackBar();
      _snack('インポート完了: $ok件（スキップ $skipped）', Colors.green);
      if (mounted) setState(() {});
    } catch (e) {
      messenger.hideCurrentSnackBar();
      _snack('インポート失敗: $e', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}

// ============================================================
// CRM-02: カンバンビュー
// ============================================================
class _CrmKanbanView extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _CrmKanbanView({required this.docs});

  @override
  Widget build(BuildContext context) {
    final byStage = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final id in CrmOptions.kanbanStages) {
      byStage[id] = [];
    }
    byStage['won'] = [];
    byStage['lost'] = [];
    for (final d in docs) {
      final stage = d.data()['stage'] as String? ?? 'considering';
      (byStage[stage] ??= []).add(d);
    }

    final stages = [
      ...CrmOptions.kanbanStages,
      'won',
      'lost',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: stages
            .map((id) => _KanbanColumn(
                  stageId: id,
                  docs: byStage[id] ?? const [],
                ))
            .toList(),
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  final String stageId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _KanbanColumn({required this.stageId, required this.docs});

  @override
  Widget build(BuildContext context) {
    final color = CrmOptions.stageColor(stageId);
    final label = CrmOptions.stageLabel(stageId);
    return Container(
      width: 260,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.colors.scaffoldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(bottom: BorderSide(color: color, width: 2)),
            ),
            child: Row(
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(10)),
                  child: Text('${docs.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height - 220),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(6),
              itemCount: docs.length,
              itemBuilder: (c, i) => _LeadKanbanCard(doc: docs[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadKanbanCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _LeadKanbanCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final childName = _childFullName(d);
    final parentName = _parentFullName(d);
    final source = d['source'] as String? ?? '';
    final inquiredAt = (d['inquiredAt'] as Timestamp?)?.toDate();
    final nextAt = (d['nextActionAt'] as Timestamp?)?.toDate();
    final nextNote = d['nextActionNote'] as String? ?? '';
    final confidence = d['confidence'] as String? ?? '';
    final overdue = nextAt != null && nextAt.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: overdue ? Colors.red.shade300 : context.colors.borderLight,
            width: overdue ? 1 : 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => CrmLeadEditScreen(doc: doc))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      childName.isEmpty ? '(児童名未入力)' : childName,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (confidence.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: confidence == 'A'
                            ? Colors.red.shade400
                            : confidence == 'B'
                                ? Colors.orange.shade400
                                : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(confidence,
                          style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (parentName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('保: $parentName',
                      style: TextStyle(
                          fontSize: 11, color: context.colors.textSecondary),
                      overflow: TextOverflow.ellipsis),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (source.isNotEmpty)
                    _miniChip(context, CrmOptions.labelOf(CrmOptions.sources, source)),
                  if (inquiredAt != null)
                    _miniChip(context,
                        '問:${DateFormat('M/d').format(inquiredAt)}'),
                ],
              ),
              if (nextAt != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: overdue
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          overdue
                              ? Icons.warning_amber
                              : Icons.schedule,
                          size: 11,
                          color: overdue ? Colors.red : Colors.blue),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${DateFormat('M/d').format(nextAt)} $nextNote',
                          style: TextStyle(
                              fontSize: 10,
                              color: overdue
                                  ? Colors.red.shade700
                                  : Colors.blue.shade700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: context.colors.chipBg,
          borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
    );
  }
}

String _childFullName(Map<String, dynamic> d) {
  final l = (d['childLastName'] as String? ?? '').trim();
  final f = (d['childFirstName'] as String? ?? '').trim();
  return [l, f].where((s) => s.isNotEmpty).join(' ');
}

String _parentFullName(Map<String, dynamic> d) {
  final l = (d['parentLastName'] as String? ?? '').trim();
  final f = (d['parentFirstName'] as String? ?? '').trim();
  return [l, f].where((s) => s.isNotEmpty).join(' ');
}

// ============================================================
// CRM-03: テーブルビュー
// ============================================================
class _CrmTableView extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _CrmTableView({required this.docs});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: docs.length,
      itemBuilder: (c, i) => _LeadTableRow(doc: docs[i]),
    );
  }
}

class _LeadTableRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _LeadTableRow({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final stage = d['stage'] as String? ?? 'considering';
    final color = CrmOptions.stageColor(stage);
    final childName = _childFullName(d);
    final parentName = _parentFullName(d);
    final source = d['source'] as String? ?? '';
    final tel = d['parentTel'] as String? ?? '';
    final inquiredAt = (d['inquiredAt'] as Timestamp?)?.toDate();
    final trialAt = (d['trialAt'] as Timestamp?)?.toDate();
    final nextAt = (d['nextActionAt'] as Timestamp?)?.toDate();
    final overdue = nextAt != null && nextAt.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderLight, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => CrmLeadEditScreen(doc: doc))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color, width: 0.5),
                    ),
                    child: Text(CrmOptions.stageLabel(stage),
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      childName.isEmpty ? '(児童名未入力)' : childName,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textPrimary),
                    ),
                  ),
                  if (source.isNotEmpty)
                    Text(CrmOptions.labelOf(CrmOptions.sources, source),
                        style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textSecondary)),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (parentName.isNotEmpty)
                    _meta(context, Icons.person_outline, '保護者: $parentName'),
                  if (tel.isNotEmpty)
                    _meta(context, Icons.phone_outlined, tel),
                  if (inquiredAt != null)
                    _meta(context, Icons.mail_outline,
                        '問: ${DateFormat('M/d').format(inquiredAt)}'),
                  if (trialAt != null)
                    _meta(context, Icons.event_outlined,
                        '体験: ${DateFormat('M/d').format(trialAt)}'),
                  if (nextAt != null)
                    _meta(
                        context,
                        overdue ? Icons.warning_amber : Icons.schedule,
                        '次回: ${DateFormat('M/d').format(nextAt)}',
                        color: overdue ? Colors.red : Colors.blue),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text,
      {Color? color}) {
    final c = color ?? context.colors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: c)),
      ],
    );
  }
}

// ============================================================
// CRM-04: 分析ビュー
// ============================================================
class _CrmDashboardView extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _CrmDashboardView({required this.docs});

  @override
  Widget build(BuildContext context) {
    final stageCount = <String, int>{for (final s in CrmOptions.stages) s.id: 0};
    final sourceCount = <String, int>{};
    final sourceWon = <String, int>{};
    final lossReasonCount = <String, int>{};
    int trialDoneCount = 0;
    int wonCount = 0;
    int lostCount = 0;
    int totalInquiries = docs.length;

    for (final doc in docs) {
      final d = doc.data();
      final stage = d['stage'] as String? ?? 'considering';
      stageCount[stage] = (stageCount[stage] ?? 0) + 1;
      final src = d['source'] as String? ?? 'other';
      sourceCount[src] = (sourceCount[src] ?? 0) + 1;
      if (stage == 'won') {
        wonCount++;
        sourceWon[src] = (sourceWon[src] ?? 0) + 1;
      }
      if (stage == 'lost') {
        lostCount++;
        final r = d['lossReason'] as String? ?? 'other';
        lossReasonCount[r] = (lossReasonCount[r] ?? 0) + 1;
      }
      if (d['trialAt'] != null) trialDoneCount++;
    }

    final winRate =
        totalInquiries == 0 ? 0.0 : wonCount * 100 / totalInquiries;
    final trialRate =
        totalInquiries == 0 ? 0.0 : trialDoneCount * 100 / totalInquiries;
    final trialToWin =
        trialDoneCount == 0 ? 0.0 : wonCount * 100 / trialDoneCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // KPI
          Row(
            children: [
              _kpiCard(context, '総問い合わせ', '$totalInquiries', Colors.blue),
              const SizedBox(width: 8),
              _kpiCard(context, '入会数', '$wonCount', Colors.green),
              const SizedBox(width: 8),
              _kpiCard(context, '入会率',
                  '${winRate.toStringAsFixed(1)}%', Colors.deepPurple),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _kpiCard(context, '体験率',
                  '${trialRate.toStringAsFixed(1)}%', Colors.teal),
              const SizedBox(width: 8),
              _kpiCard(context, '体験→入会',
                  '${trialToWin.toStringAsFixed(1)}%', Colors.orange),
              const SizedBox(width: 8),
              _kpiCard(context, '失注', '$lostCount', Colors.grey),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'ステージ別件数'),
          const SizedBox(height: 8),
          ...CrmOptions.stages.map((s) => _bar(context, s.label,
              stageCount[s.id] ?? 0, totalInquiries, s.color)),
          const SizedBox(height: 16),
          _sectionTitle(context, '媒体別ファネル'),
          const SizedBox(height: 8),
          ...sourceCount.entries.map((e) {
            final won = sourceWon[e.key] ?? 0;
            final rate = e.value == 0 ? 0.0 : won * 100 / e.value;
            return _sourceRow(
                context,
                CrmOptions.labelOf(CrmOptions.sources, e.key),
                e.value,
                won,
                rate);
          }),
          if (lossReasonCount.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle(context, '失注理由'),
            const SizedBox(height: 8),
            ...lossReasonCount.entries.map((e) => _bar(
                context,
                CrmOptions.labelOf(CrmOptions.lossReasons, e.key),
                e.value,
                lostCount,
                Colors.grey)),
          ],
        ],
      ),
    );
  }

  Widget _kpiCard(BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: context.colors.textSecondary)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: context.colors.textPrimary));
  }

  Widget _bar(BuildContext context, String label, int value, int max, Color color) {
    final ratio = max == 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12, color: context.colors.textPrimary))),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                      color: context.colors.scaffoldBg,
                      borderRadius: BorderRadius.circular(4)),
                ),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
              width: 32,
              child: Text('$value',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary))),
        ],
      ),
    );
  }

  Widget _sourceRow(BuildContext context, String label, int total, int won,
      double winRate) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Row(
          children: [
            Expanded(
                flex: 3,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12, color: context.colors.textPrimary))),
            Expanded(
              child: Text('$total件',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12, color: context.colors.textSecondary)),
            ),
            Expanded(
              child: Text('入会$won',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12, color: Colors.green.shade700)),
            ),
            Expanded(
              child: Text('${winRate.toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CRM-05: 詳細・編集画面
// ============================================================
class CrmLeadEditScreen extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;
  const CrmLeadEditScreen({super.key, this.doc});

  @override
  State<CrmLeadEditScreen> createState() => _CrmLeadEditScreenState();
}

class _CrmLeadEditScreenState extends State<CrmLeadEditScreen> {
  // 児童
  final _childLastNameCtrl = TextEditingController();
  final _childFirstNameCtrl = TextEditingController();
  final _childKanaCtrl = TextEditingController();
  String _childGender = '';
  DateTime? _childBirthDate;
  final _kindergartenCtrl = TextEditingController();
  String _permitStatus = 'none';

  // 保護者
  final _parentLastNameCtrl = TextEditingController();
  final _parentFirstNameCtrl = TextEditingController();
  final _parentKanaCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _lineCtrl = TextEditingController();
  String _preferredChannel = 'tel';
  final _addressCtrl = TextEditingController();

  // 案件
  String _stage = 'considering';
  String _confidence = 'B';
  String _source = 'instagram';
  final _sourceDetailCtrl = TextEditingController();
  final _preferredDaysCtrl = TextEditingController();
  final _preferredTimeCtrl = TextEditingController();
  final _preferredStartCtrl = TextEditingController();

  // 主訴
  final _mainConcernCtrl = TextEditingController();
  final _likesCtrl = TextEditingController();
  final _dislikesCtrl = TextEditingController();
  final _trialNotesCtrl = TextEditingController();

  // ネクスト
  DateTime? _nextActionAt;
  final _nextActionNoteCtrl = TextEditingController();

  // タイムスタンプ
  DateTime _inquiredAt = DateTime.now();
  DateTime? _firstContactedAt;
  DateTime? _trialAt;
  DateTime? _enrolledAt;
  DateTime? _lostAt;

  // 失注
  String? _lossReason;
  final _lossDetailCtrl = TextEditingController();
  bool _reapproachOk = true;

  final _memoCtrl = TextEditingController();

  bool _saving = false;
  String? _convertedFamilyId;

  bool get _isEdit => widget.doc != null;

  @override
  void initState() {
    super.initState();
    if (widget.doc != null) {
      final d = widget.doc!.data();
      _childLastNameCtrl.text = d['childLastName'] ?? '';
      _childFirstNameCtrl.text = d['childFirstName'] ?? '';
      _childKanaCtrl.text = d['childKana'] ?? '';
      _childGender = d['childGender'] ?? '';
      _childBirthDate = (d['childBirthDate'] as Timestamp?)?.toDate();
      _kindergartenCtrl.text = d['kindergarten'] ?? '';
      _permitStatus = d['permitStatus'] ?? 'none';
      _parentLastNameCtrl.text = d['parentLastName'] ?? '';
      _parentFirstNameCtrl.text = d['parentFirstName'] ?? '';
      _parentKanaCtrl.text = d['parentKana'] ?? '';
      _telCtrl.text = d['parentTel'] ?? '';
      _emailCtrl.text = d['parentEmail'] ?? '';
      _lineCtrl.text = d['parentLine'] ?? '';
      _preferredChannel = d['preferredChannel'] ?? 'tel';
      _addressCtrl.text = d['address'] ?? '';
      _stage = d['stage'] ?? 'considering';
      _confidence = d['confidence'] ?? 'B';
      _source = d['source'] ?? 'instagram';
      _sourceDetailCtrl.text = d['sourceDetail'] ?? '';
      _preferredDaysCtrl.text = d['preferredDays'] ?? '';
      _preferredTimeCtrl.text = d['preferredTimeSlots'] ?? '';
      _preferredStartCtrl.text = d['preferredStart'] ?? '';
      _mainConcernCtrl.text = d['mainConcern'] ?? '';
      _likesCtrl.text = d['likes'] ?? '';
      _dislikesCtrl.text = d['dislikes'] ?? '';
      _trialNotesCtrl.text = d['trialNotes'] ?? '';
      _nextActionAt = (d['nextActionAt'] as Timestamp?)?.toDate();
      _nextActionNoteCtrl.text = d['nextActionNote'] ?? '';
      _inquiredAt =
          (d['inquiredAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      _firstContactedAt = (d['firstContactedAt'] as Timestamp?)?.toDate();
      _trialAt = (d['trialAt'] as Timestamp?)?.toDate();
      _enrolledAt = (d['enrolledAt'] as Timestamp?)?.toDate();
      _lostAt = (d['lostAt'] as Timestamp?)?.toDate();
      _lossReason = d['lossReason'];
      _lossDetailCtrl.text = d['lossDetail'] ?? '';
      _reapproachOk = d['reapproachOk'] ?? true;
      _memoCtrl.text = d['memo'] ?? '';
      _convertedFamilyId = d['convertedFamilyId'];
    }
  }

  @override
  void dispose() {
    for (final c in [
      _childLastNameCtrl,
      _childFirstNameCtrl,
      _childKanaCtrl,
      _kindergartenCtrl,
      _parentLastNameCtrl,
      _parentFirstNameCtrl,
      _parentKanaCtrl,
      _telCtrl,
      _emailCtrl,
      _lineCtrl,
      _addressCtrl,
      _sourceDetailCtrl,
      _preferredDaysCtrl,
      _preferredTimeCtrl,
      _preferredStartCtrl,
      _mainConcernCtrl,
      _likesCtrl,
      _dislikesCtrl,
      _trialNotesCtrl,
      _nextActionNoteCtrl,
      _lossDetailCtrl,
      _memoCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _childLastNameCtrl.text.trim().isNotEmpty ||
      _childFirstNameCtrl.text.trim().isNotEmpty ||
      _parentLastNameCtrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final user = FirebaseAuth.instance.currentUser;
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'childLastName': _childLastNameCtrl.text.trim(),
      'childFirstName': _childFirstNameCtrl.text.trim(),
      'childKana': _childKanaCtrl.text.trim(),
      'childGender': _childGender,
      'childBirthDate':
          _childBirthDate == null ? null : Timestamp.fromDate(_childBirthDate!),
      'kindergarten': _kindergartenCtrl.text.trim(),
      'permitStatus': _permitStatus,
      'parentLastName': _parentLastNameCtrl.text.trim(),
      'parentFirstName': _parentFirstNameCtrl.text.trim(),
      'parentKana': _parentKanaCtrl.text.trim(),
      'parentTel': _telCtrl.text.trim(),
      'parentEmail': _emailCtrl.text.trim(),
      'parentLine': _lineCtrl.text.trim(),
      'preferredChannel': _preferredChannel,
      'address': _addressCtrl.text.trim(),
      'stage': _stage,
      'confidence': _confidence,
      'source': _source,
      'sourceDetail': _sourceDetailCtrl.text.trim(),
      'preferredDays': _preferredDaysCtrl.text.trim(),
      'preferredTimeSlots': _preferredTimeCtrl.text.trim(),
      'preferredStart': _preferredStartCtrl.text.trim(),
      'mainConcern': _mainConcernCtrl.text.trim(),
      'likes': _likesCtrl.text.trim(),
      'dislikes': _dislikesCtrl.text.trim(),
      'trialNotes': _trialNotesCtrl.text.trim(),
      'nextActionAt':
          _nextActionAt == null ? null : Timestamp.fromDate(_nextActionAt!),
      'nextActionNote': _nextActionNoteCtrl.text.trim(),
      'inquiredAt': Timestamp.fromDate(_inquiredAt),
      'firstContactedAt': _firstContactedAt == null
          ? null
          : Timestamp.fromDate(_firstContactedAt!),
      'trialAt': _trialAt == null ? null : Timestamp.fromDate(_trialAt!),
      'enrolledAt':
          _enrolledAt == null ? null : Timestamp.fromDate(_enrolledAt!),
      'lostAt': _lostAt == null ? null : Timestamp.fromDate(_lostAt!),
      'lossReason': _lossReason,
      'lossDetail': _lossDetailCtrl.text.trim(),
      'reapproachOk': _reapproachOk,
      'memo': _memoCtrl.text.trim(),
      'updatedAt': now,
      'updatedBy': user?.uid ?? '',
    };
    try {
      if (_isEdit) {
        await widget.doc!.reference.update(data);
      } else {
        data['createdAt'] = now;
        data['createdBy'] = user?.uid ?? '';
        data['activities'] = <Map<String, dynamic>>[];
        await FirebaseFirestore.instance.collection('crm_leads').add(data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isEdit ? '更新しました' : '登録しました'),
            backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失敗: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('このリードを削除しますか？'),
        content: const Text('この操作は取り消せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child:
                  const Text('削除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.doc!.reference.delete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('削除失敗: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _addActivity() async {
    if (!_isEdit) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('先にリードを保存してください'), backgroundColor: Colors.orange));
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AddActivityDialog(),
    );
    if (result == null) return;
    final user = FirebaseAuth.instance.currentUser;
    String authorName = '';
    if (user != null) {
      try {
        final s = await FirebaseFirestore.instance
            .collection('staffs')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (s.docs.isNotEmpty) authorName = s.docs.first.data()['name'] ?? '';
      } catch (_) {}
    }
    final entry = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': result['type'],
      'body': result['body'],
      'at': Timestamp.fromDate(result['at']),
      'authorId': user?.uid ?? '',
      'authorName': authorName,
    };
    try {
      await widget.doc!.reference.update({
        'activities': FieldValue.arrayUnion([entry]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('追加失敗: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _removeActivity(Map<String, dynamic> entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この履歴を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child:
                  const Text('削除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.doc!.reference.update({
        'activities': FieldValue.arrayRemove([entry]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('削除失敗: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _convertToFamily() async {
    if (!_isEdit) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('先にリードを保存してください'), backgroundColor: Colors.orange));
      return;
    }
    if (_convertedFamilyId != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('すでに保護者・児童マスタに登録済みです'),
          backgroundColor: Colors.orange));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('入会処理'),
        content: const Text(
            'このリードを保護者・児童マスタに登録し、ステージを「入会」にします。\nよろしいですか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('入会処理',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      final now = FieldValue.serverTimestamp();
      final familyData = <String, dynamic>{
        'uid': '',
        'lastName': _parentLastNameCtrl.text.trim(),
        'firstName': _parentFirstNameCtrl.text.trim(),
        'lastNameKana': _parentKanaCtrl.text.trim(),
        'tel': _telCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'children': [
          {
            'firstName': _childFirstNameCtrl.text.trim(),
            'lastName': _childLastNameCtrl.text.trim(),
            'kana': _childKanaCtrl.text.trim(),
            'gender': _childGender,
            'birthDate': _childBirthDate == null
                ? null
                : Timestamp.fromDate(_childBirthDate!),
            'classrooms': ['ビースマイリープラス湘南藤沢'],
            'kindergarten': _kindergartenCtrl.text.trim(),
            'mainConcern': _mainConcernCtrl.text.trim(),
            'likes': _likesCtrl.text.trim(),
            'dislikes': _dislikesCtrl.text.trim(),
          }
        ],
        'sourceLeadId': widget.doc!.id,
        'createdAt': now,
        'createdBy': user?.uid ?? '',
      };
      final ref =
          await FirebaseFirestore.instance.collection('families').add(familyData);
      final enrolledAt = DateTime.now();
      await widget.doc!.reference.update({
        'stage': 'won',
        'enrolledAt': Timestamp.fromDate(enrolledAt),
        'convertedFamilyId': ref.id,
        'convertedAt': now,
        'updatedAt': now,
      });
      if (mounted) {
        setState(() {
          _stage = 'won';
          _enrolledAt = enrolledAt;
          _convertedFamilyId = ref.id;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('入会処理が完了しました'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('入会処理失敗: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: Text(_isEdit ? 'リード詳細' : '新規リード',
            style:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (_isEdit)
            IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                onPressed: _delete),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              if (_isEdit && _stage != 'won' && _convertedFamilyId == null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _convertToFamily,
                    icon: const Icon(Icons.how_to_reg, size: 18),
                    label: const Text('入会処理'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              if (_isEdit && _stage != 'won' && _convertedFamilyId == null)
                const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: (_canSave && !_saving) ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(_isEdit ? '更新' : '登録',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
      body: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildForm()),
                Container(
                    width: 1, color: context.colors.borderLight),
                Expanded(flex: 2, child: _buildActivityPanel()),
              ],
            )
          : _buildForm(showActivities: true),
    );
  }

  Widget _buildForm({bool showActivities = false}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_convertedFamilyId != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: Colors.green.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('保護者・児童マスタに登録済（ID: $_convertedFamilyId）',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          _section('ステージ'),
          _stageSelector(),
          const SizedBox(height: 16),
          _section('問い合わせ情報'),
          Row(
            children: [
              Expanded(
                  child: _dateField(
                      '問い合わせ日', _inquiredAt,
                      (d) => setState(() => _inquiredAt = d),
                      required: true)),
              const SizedBox(width: 8),
              Expanded(child: _sourceDropdown()),
            ],
          ),
          const SizedBox(height: 8),
          _textField('紹介者・媒体詳細', _sourceDetailCtrl,
              hint: '紹介者名・広告キーワードなど'),
          const SizedBox(height: 16),
          _section('児童'),
          Row(
            children: [
              Expanded(child: _textField('姓', _childLastNameCtrl)),
              const SizedBox(width: 8),
              Expanded(child: _textField('名', _childFirstNameCtrl)),
            ],
          ),
          const SizedBox(height: 8),
          _textField('ふりがな', _childKanaCtrl),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _dateField(
                      '生年月日',
                      _childBirthDate,
                      (d) => setState(() => _childBirthDate = d),
                      nullable: true)),
              const SizedBox(width: 8),
              Expanded(child: _genderSelector()),
            ],
          ),
          const SizedBox(height: 8),
          _textField('保育園・幼稚園・学校', _kindergartenCtrl),
          const SizedBox(height: 8),
          _permitSelector(),
          const SizedBox(height: 16),
          _section('保護者・連絡先'),
          Row(
            children: [
              Expanded(child: _textField('姓', _parentLastNameCtrl)),
              const SizedBox(width: 8),
              Expanded(child: _textField('名', _parentFirstNameCtrl)),
            ],
          ),
          const SizedBox(height: 8),
          _textField('ふりがな', _parentKanaCtrl),
          const SizedBox(height: 8),
          _textField('電話番号', _telCtrl, keyboardType: TextInputType.phone),
          const SizedBox(height: 8),
          _textField('メール', _emailCtrl, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 8),
          _textField('LINE ID', _lineCtrl),
          const SizedBox(height: 8),
          _channelSelector(),
          const SizedBox(height: 8),
          _textField('住所', _addressCtrl),
          const SizedBox(height: 16),
          _section('希望条件'),
          _textField('希望曜日', _preferredDaysCtrl, hint: '例：月・水・金'),
          const SizedBox(height: 8),
          _textField('希望時間帯', _preferredTimeCtrl, hint: '例：放課後 16:00〜'),
          const SizedBox(height: 8),
          _textField('希望開始時期', _preferredStartCtrl, hint: '例：4月〜'),
          const SizedBox(height: 8),
          _confidenceSelector(),
          const SizedBox(height: 16),
          _section('主訴・特性'),
          _textField('主訴', _mainConcernCtrl, maxLines: 3),
          const SizedBox(height: 8),
          _textField('好きなこと', _likesCtrl, maxLines: 2),
          const SizedBox(height: 8),
          _textField('苦手なこと', _dislikesCtrl, maxLines: 2),
          const SizedBox(height: 16),
          _section('体験'),
          _dateField('体験日', _trialAt, (d) => setState(() => _trialAt = d),
              nullable: true),
          const SizedBox(height: 8),
          _textField('体験で分かったこと', _trialNotesCtrl, maxLines: 4),
          const SizedBox(height: 16),
          _section('ネクストアクション'),
          Row(
            children: [
              Expanded(
                  child: _dateField(
                      '次回対応期日',
                      _nextActionAt,
                      (d) => setState(() => _nextActionAt = d),
                      nullable: true)),
            ],
          ),
          const SizedBox(height: 8),
          _textField('次回内容', _nextActionNoteCtrl, maxLines: 2,
              hint: '例：受給者証取得後に再連絡'),
          if (_stage == 'lost') ...[
            const SizedBox(height: 16),
            _section('失注情報'),
            _lossReasonSelector(),
            const SizedBox(height: 8),
            _textField('失注詳細', _lossDetailCtrl, maxLines: 3),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _reapproachOk,
              onChanged: (v) => setState(() => _reapproachOk = v ?? true),
              title: Text('再アプローチ可',
                  style: TextStyle(
                      fontSize: 13, color: context.colors.textPrimary)),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
          const SizedBox(height: 16),
          _section('メモ'),
          _textField('内部メモ', _memoCtrl, maxLines: 4),
          if (showActivities) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            _buildActivitySection(),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SingleChildScrollView(child: _buildActivitySection()),
    );
  }

  Widget _buildActivitySection() {
    final activities = _isEdit
        ? List<Map<String, dynamic>>.from(
            (widget.doc!.data())['activities'] ?? [])
        : <Map<String, dynamic>>[];
    activities.sort((a, b) {
      final ta = (a['at'] as Timestamp?)?.toDate();
      final tb = (b['at'] as Timestamp?)?.toDate();
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _section('対応履歴'),
            const Spacer(),
            TextButton.icon(
              onPressed: _addActivity,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加'),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (activities.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            child: Text('まだ履歴がありません',
                style: TextStyle(
                    fontSize: 12, color: context.colors.textTertiary)),
          )
        else
          ...activities.map((a) => _activityTile(a)),
      ],
    );
  }

  Widget _activityTile(Map<String, dynamic> a) {
    final at = (a['at'] as Timestamp?)?.toDate();
    final type = a['type'] as String? ?? 'memo';
    final body = a['body'] as String? ?? '';
    final author = a['authorName'] as String? ?? '';
    final color = _activityTypeColor(type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(
                    CrmOptions.labelOf(CrmOptions.activityTypes, type),
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              if (at != null)
                Text(DateFormat('M/d (E) HH:mm', 'ja').format(at),
                    style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w600)),
              const Spacer(),
              if (author.isNotEmpty)
                Text(author,
                    style: TextStyle(
                        fontSize: 10, color: context.colors.textTertiary)),
              InkWell(
                onTap: () => _removeActivity(a),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close,
                      size: 14, color: context.colors.textTertiary),
                ),
              ),
            ],
          ),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(body,
                  style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textPrimary,
                      height: 1.4)),
            ),
        ],
      ),
    );
  }

  Color _activityTypeColor(String type) {
    return switch (type) {
      'tel' => Colors.green,
      'email' => Colors.blue,
      'line' => Colors.lightGreen,
      'visit' => Colors.purple,
      'task' => Colors.orange,
      _ => Colors.grey,
    };
  }

  // ---------------------------------------------------------- Form widgets

  Widget _section(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary)),
    );
  }

  Widget _textField(String label, TextEditingController c,
      {int maxLines = 1, String? hint, TextInputType? keyboardType}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle:
            TextStyle(fontSize: 12, color: context.colors.textSecondary),
        hintStyle:
            TextStyle(fontSize: 12, color: context.colors.textTertiary),
        isDense: true,
        filled: true,
        fillColor: context.colors.cardBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: context.colors.borderLight),
        ),
      ),
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick,
      {bool nullable = false, bool required = false}) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2010),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
        );
        if (d != null) onPick(d);
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: '$label${required ? " *" : ""}',
          labelStyle:
              TextStyle(fontSize: 12, color: context.colors.textSecondary),
          isDense: true,
          filled: true,
          fillColor: context.colors.cardBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: context.colors.borderLight),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null
                    ? '未設定'
                    : DateFormat('yyyy/M/d (E)', 'ja').format(value),
                style: TextStyle(
                    fontSize: 13,
                    color: value == null
                        ? context.colors.textTertiary
                        : context.colors.textPrimary),
              ),
            ),
            if (nullable && value != null)
              InkWell(
                onTap: () {
                  // setStateを子で呼ぶため、onPickではなく明示削除
                  // ここでは簡易的に Date(0) を渡す代わりに null 想定の処理
                  // 利用側で個別に「クリア」アクションを実装するならここを拡張
                },
                child: Icon(Icons.close,
                    size: 14, color: context.colors.textTertiary),
              ),
            const Icon(Icons.calendar_today, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _stageSelector() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: CrmOptions.stages.map((s) {
        final sel = _stage == s.id;
        return GestureDetector(
          onTap: () {
            setState(() {
              _stage = s.id;
              if (s.id == 'lost' && _lostAt == null) {
                _lostAt = DateTime.now();
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? s.color.withValues(alpha: 0.18) : context.colors.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: sel ? s.color : context.colors.borderMedium,
                  width: sel ? 1.5 : 0.8),
            ),
            child: Text(s.label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    color: sel ? s.color : context.colors.textPrimary)),
          ),
        );
      }).toList(),
    );
  }

  Widget _sourceDropdown() {
    return DropdownButtonFormField<String>(
      value: _source,
      isDense: true,
      decoration: InputDecoration(
        labelText: '流入媒体',
        labelStyle:
            TextStyle(fontSize: 12, color: context.colors.textSecondary),
        isDense: true,
        filled: true,
        fillColor: context.colors.cardBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: context.colors.borderLight),
        ),
      ),
      items: CrmOptions.sources
          .map((s) => DropdownMenuItem(
              value: s.id,
              child: Text(s.label, style: const TextStyle(fontSize: 13))))
          .toList(),
      onChanged: (v) => setState(() => _source = v ?? 'other'),
    );
  }

  Widget _genderSelector() {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: '性別',
        labelStyle:
            TextStyle(fontSize: 12, color: context.colors.textSecondary),
        isDense: true,
        filled: true,
        fillColor: context.colors.cardBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: context.colors.borderLight),
        ),
      ),
      child: Row(
        children: ['男', '女', 'その他'].map((g) {
          final sel = _childGender == g;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(g, style: const TextStyle(fontSize: 11)),
              selected: sel,
              onSelected: (_) => setState(() => _childGender = sel ? '' : g),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _permitSelector() {
    return Row(
      children: [
        Text('受給者証:',
            style: TextStyle(
                fontSize: 12, color: context.colors.textSecondary)),
        const SizedBox(width: 8),
        ...CrmOptions.permitStatus.map((s) {
          final sel = _permitStatus == s.id;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(s.label, style: const TextStyle(fontSize: 11)),
              selected: sel,
              onSelected: (_) => setState(() => _permitStatus = s.id),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }),
      ],
    );
  }

  Widget _channelSelector() {
    return Row(
      children: [
        Text('連絡優先:',
            style: TextStyle(
                fontSize: 12, color: context.colors.textSecondary)),
        const SizedBox(width: 8),
        ...CrmOptions.channels.map((s) {
          final sel = _preferredChannel == s.id;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(s.label, style: const TextStyle(fontSize: 11)),
              selected: sel,
              onSelected: (_) => setState(() => _preferredChannel = s.id),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }),
      ],
    );
  }

  Widget _confidenceSelector() {
    return Row(
      children: [
        Text('入会確度:',
            style: TextStyle(
                fontSize: 12, color: context.colors.textSecondary)),
        const SizedBox(width: 8),
        ...CrmOptions.confidence.map((s) {
          final sel = _confidence == s.id;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(s.label, style: const TextStyle(fontSize: 11)),
              selected: sel,
              onSelected: (_) => setState(() => _confidence = s.id),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }),
      ],
    );
  }

  Widget _lossReasonSelector() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: CrmOptions.lossReasons.map((s) {
        final sel = _lossReason == s.id;
        return GestureDetector(
          onTap: () => setState(() => _lossReason = s.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: sel
                  ? Colors.red.withValues(alpha: 0.12)
                  : context.colors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: sel
                      ? Colors.red.shade400
                      : context.colors.borderMedium,
                  width: sel ? 1.5 : 0.8),
            ),
            child: Text(s.label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    color: sel
                        ? Colors.red.shade700
                        : context.colors.textPrimary)),
          ),
        );
      }).toList(),
    );
  }
}

// ============================================================
// CRM-06: 履歴追加ダイアログ
// ============================================================
class _AddActivityDialog extends StatefulWidget {
  const _AddActivityDialog();

  @override
  State<_AddActivityDialog> createState() => _AddActivityDialogState();
}

class _AddActivityDialogState extends State<_AddActivityDialog> {
  String _type = 'tel';
  DateTime _at = DateTime.now();
  final _bodyCtrl = TextEditingController();

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('対応履歴を追加',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: CrmOptions.activityTypes.map((t) {
                  final sel = _type == t.id;
                  return ChoiceChip(
                    label: Text(t.label, style: const TextStyle(fontSize: 12)),
                    selected: sel,
                    onSelected: (_) => setState(() => _type = t.id),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDateTime,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: '日時',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                      DateFormat('yyyy/M/d (E) HH:mm', 'ja').format(_at),
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: '内容',
                  hintText: '例：折り返しの電話。次回火曜に体験予約。',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('キャンセル')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (_bodyCtrl.text.trim().isEmpty) return;
                      Navigator.pop(context, {
                        'type': _type,
                        'at': _at,
                        'body': _bodyCtrl.text.trim(),
                      });
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                    child: const Text('追加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
