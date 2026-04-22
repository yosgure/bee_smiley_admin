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
  /// withdrawn は「入会」からのみ遷移可能（入会後に退会したケース）。
  static const List<({String id, String label, Color color})> stages = [
    (id: 'considering', label: '検討中', color: Color(0xFFFF9800)),
    (id: 'onboarding', label: '入会手続中', color: Color(0xFF9C27B0)),
    (id: 'won', label: '入会', color: Color(0xFF4CAF50)),
    (id: 'lost', label: '失注', color: Color(0xFF9E9E9E)),
    (id: 'withdrawn', label: '退会', color: Color(0xFF6D4C41)),
  ];

  /// カンバンに表示する進行中ステージ（won/lost/withdrawnを除外）
  static const List<String> kanbanStages = [
    'considering',
    'onboarding',
  ];

  /// ステージ遷移の許可ルール（from → allowed to）。
  /// 「検討中」から直接「入会」へはスキップ禁止（入会手続中を経由）。
  /// 「退会」は「入会」からのみ可能。
  static const Map<String, List<String>> allowedStageTransitions = {
    'considering': ['onboarding', 'lost'],
    'onboarding': ['won', 'lost', 'considering'],
    'won': ['withdrawn'],
    'lost': ['considering'],
    'withdrawn': [],
  };

  static bool canTransition(String from, String to) {
    if (from == to) return true;
    return allowedStageTransitions[from]?.contains(to) ?? false;
  }

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
    (id: 'competitor', label: '他事業所に決定'),
    (id: 'permit_rejected', label: '受給者証が下りなかった'),
    (id: 'no_reply', label: '連絡が取れなくなった'),
    (id: 'price', label: '料金・費用面'),
    (id: 'distance', label: 'アクセス・立地'),
    (id: 'capacity', label: '空き枠のタイミング不一致'),
    (id: 'policy_mismatch', label: '事業所の方針と合わない'),
    (id: 'family_reason', label: '保護者の事情（引越し等）'),
    (id: 'trial_mismatch', label: '体験後に合わないと判断'),
    (id: 'other', label: 'その他'),
  ];

  /// 退会理由（入会→退会遷移時に必須入力）
  static const List<({String id, String label})> withdrawalReasons = [
    (id: 'graduation', label: '卒業（就学等）'),
    (id: 'relocation', label: '引越し'),
    (id: 'transfer', label: '他事業所へ移行'),
    (id: 'child_decision', label: '本人の意向'),
    (id: 'parent_policy', label: '保護者の方針変更'),
    (id: 'economic', label: '経済的理由'),
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
  // 0: 督促, 1: パイプライン, 2: 入会済み, 3: 離脱, 4: 分析
  int _viewMode = 0;
  String _sourceFilter = 'all';
  String _stageFilter = 'all'; // 未使用（旧テーブル互換用に残置）

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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('督促'), icon: Icon(Icons.campaign_outlined, size: 16)),
                ButtonSegment(value: 1, label: Text('パイプライン'), icon: Icon(Icons.timeline, size: 16)),
                ButtonSegment(value: 2, label: Text('入会済み'), icon: Icon(Icons.check_circle_outline, size: 16)),
                ButtonSegment(value: 3, label: Text('離脱'), icon: Icon(Icons.logout, size: 16)),
                ButtonSegment(value: 4, label: Text('分析'), icon: Icon(Icons.bar_chart, size: 16)),
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
          ],
        ),
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
            return _CrmDunningView(docs: docs);
          case 1:
            return _CrmPipelineView(docs: docs);
          case 2:
            return _CrmEnrolledView(docs: docs);
          case 3:
            return _CrmChurnView(docs: docs);
          case 4:
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
    final source = d['source'] as String? ?? '';
    final inquiredAt = (d['inquiredAt'] as Timestamp?)?.toDate();
    final nextAt = (d['nextActionAt'] as Timestamp?)?.toDate();
    final nextNote = d['nextActionNote'] as String? ?? '';
    final overdue = nextAt != null && nextAt.isBefore(DateTime.now());
    final alerts = context.alerts;
    final alertStyle = overdue ? alerts.urgent : alerts.info;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: overdue ? alerts.urgent.border : context.colors.borderLight,
          width: overdue ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => CrmLeadEditScreen(doc: doc))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                childName.isEmpty ? '(児童名未入力)' : childName,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary),
                overflow: TextOverflow.ellipsis,
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: alertStyle.background,
                    border: Border.all(color: alertStyle.border, width: 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        overdue ? Icons.warning_amber : Icons.schedule,
                        size: 11,
                        color: alertStyle.icon,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${DateFormat('M/d').format(nextAt)} $nextNote',
                          style: TextStyle(fontSize: 10, color: alertStyle.text),
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
  final cl = (d['childLastName'] as String? ?? '').trim();
  final cf = (d['childFirstName'] as String? ?? '').trim();
  final pl = (d['parentLastName'] as String? ?? '').trim();
  final last = cl.isNotEmpty ? cl : pl;
  return [last, cf].where((s) => s.isNotEmpty).join(' ');
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
    final source = d['source'] as String? ?? '';
    final tel = d['parentTel'] as String? ?? '';
    final inquiredAt = (d['inquiredAt'] as Timestamp?)?.toDate();
    final trialAt = (d['trialAt'] as Timestamp?)?.toDate();
    final nextAt = (d['nextActionAt'] as Timestamp?)?.toDate();
    final overdue = nextAt != null && nextAt.isBefore(DateTime.now());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? const Color(0xFF3A3D42) : const Color(0xFFE4E7EB),
            width: 1),
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
                        color: overdue ? context.alerts.urgent.icon : context.alerts.info.icon),
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
// CRM-Phase2: 督促 / パイプライン / 入会済み / 離脱 ビュー
// ============================================================

/// Dunning 判定しきい値（CLAUDE.md の CRM Design Rules と同期）
const int _staleConsideringDays = 3;
const int _staleProcessingDays = 7;

enum _DunningBucket { urgent, warning, today, upcoming }

class _BucketedLead {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final _DunningBucket bucket;
  final String reasonText;
  final int? daysIdle;
  const _BucketedLead({
    required this.doc,
    required this.bucket,
    required this.reasonText,
    this.daysIdle,
  });
}

class _CrmDunningView extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _CrmDunningView({required this.docs});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final threeDaysLater = todayStart.add(const Duration(days: 4));

    final buckets = <_DunningBucket, List<_BucketedLead>>{
      _DunningBucket.urgent: [],
      _DunningBucket.warning: [],
      _DunningBucket.today: [],
      _DunningBucket.upcoming: [],
    };

    for (final d in docs) {
      final data = d.data();
      final stage = data['stage'] as String? ?? 'considering';
      if (stage != 'considering' && stage != 'onboarding') continue;
      final lastActivityAt = (data['lastActivityAt'] as Timestamp?)?.toDate() ??
          (data['updatedAt'] as Timestamp?)?.toDate() ??
          (data['inquiredAt'] as Timestamp?)?.toDate();
      final nextActionAt = (data['nextActionAt'] as Timestamp?)?.toDate();
      final daysIdle = lastActivityAt == null
          ? null
          : now.difference(lastActivityAt).inDays;

      if (stage == 'onboarding' &&
          daysIdle != null &&
          daysIdle >= _staleProcessingDays) {
        buckets[_DunningBucket.urgent]!.add(_BucketedLead(
            doc: d,
            bucket: _DunningBucket.urgent,
            reasonText: '入会手続中・$daysIdle日放置',
            daysIdle: daysIdle));
        continue;
      }
      if (stage == 'considering' &&
          daysIdle != null &&
          daysIdle >= _staleConsideringDays) {
        buckets[_DunningBucket.warning]!.add(_BucketedLead(
            doc: d,
            bucket: _DunningBucket.warning,
            reasonText: '検討中・$daysIdle日放置',
            daysIdle: daysIdle));
        continue;
      }
      if (nextActionAt != null &&
          !nextActionAt.isBefore(todayStart) &&
          nextActionAt.isBefore(todayEnd)) {
        buckets[_DunningBucket.today]!.add(_BucketedLead(
            doc: d,
            bucket: _DunningBucket.today,
            reasonText: '今日の予定',
            daysIdle: daysIdle));
        continue;
      }
      if (nextActionAt != null &&
          nextActionAt.isBefore(threeDaysLater)) {
        buckets[_DunningBucket.upcoming]!.add(_BucketedLead(
            doc: d,
            bucket: _DunningBucket.upcoming,
            reasonText: '${DateFormat('M/d').format(nextActionAt)} 予定',
            daysIdle: daysIdle));
        continue;
      }
    }

    // 各バケット内で放置日数の多い順/予定日の近い順に並べる
    for (final b in buckets.values) {
      b.sort((a, c) {
        if (a.daysIdle != null && c.daysIdle != null) {
          return c.daysIdle!.compareTo(a.daysIdle!);
        }
        return 0;
      });
    }

    final totalCount = buckets.values.fold<int>(0, (s, l) => s + l.length);
    if (totalCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: context.colors.textTertiary),
            const SizedBox(height: 12),
            Text('今日の対応タスクはありません 🎉',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      children: [
        if (buckets[_DunningBucket.urgent]!.isNotEmpty)
          _section(context, '🔴 緊急放置', buckets[_DunningBucket.urgent]!,
              context.alerts.urgent),
        if (buckets[_DunningBucket.warning]!.isNotEmpty)
          _section(context, '🟠 要対応', buckets[_DunningBucket.warning]!,
              context.alerts.warning),
        if (buckets[_DunningBucket.today]!.isNotEmpty)
          _section(context, '🟡 今日の予定', buckets[_DunningBucket.today]!,
              context.alerts.warning),
        if (buckets[_DunningBucket.upcoming]!.isNotEmpty)
          _section(context, '🔵 明日以降（3日以内）', buckets[_DunningBucket.upcoming]!,
              context.alerts.info),
      ],
    );
  }

  Widget _section(BuildContext context, String title,
      List<_BucketedLead> items, AlertStyle style) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: style.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: style.border, width: 0.6),
                  ),
                  child: Text('${items.length}',
                      style: TextStyle(
                          fontSize: 10,
                          color: style.text,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          ...items.map((b) => _DunningLeadRow(item: b, style: style)),
        ],
      ),
    );
  }
}

class _DunningLeadRow extends StatelessWidget {
  final _BucketedLead item;
  final AlertStyle style;
  const _DunningLeadRow({required this.item, required this.style});

  @override
  Widget build(BuildContext context) {
    final data = item.doc.data();
    final childName = _childFullName(data);
    final stage = data['stage'] as String? ?? '';
    final nextAt = (data['nextActionAt'] as Timestamp?)?.toDate();
    final nextNote = data['nextActionNote'] as String? ?? '';
    final tel = data['parentTel'] as String? ?? '';
    final stageColor = CrmOptions.stageColor(stage);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: style.border, width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => CrmLeadEditScreen(doc: item.doc))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: stageColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                            border:
                                Border.all(color: stageColor, width: 0.5),
                          ),
                          child: Text(CrmOptions.stageLabel(stage),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: stageColor,
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
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(item.reasonText,
                        style: TextStyle(fontSize: 11, color: style.text)),
                    if (nextAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                          '次回: ${DateFormat('M/d').format(nextAt)} $nextNote',
                          style: TextStyle(
                              fontSize: 11,
                              color: context.colors.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (tel.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.phone, size: 18, color: style.icon),
                  tooltip: '電話: $tel',
                  onPressed: () {
                    // 電話URI起動は url_launcher 経由、ここでは詳細画面誘導のみ
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CrmLeadEditScreen(doc: item.doc)));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// パイプライン: 検討中 + 入会手続中 を次回対応期日昇順で並べる
class _CrmPipelineView extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _CrmPipelineView({required this.docs});

  @override
  Widget build(BuildContext context) {
    final filtered = docs.where((d) {
      final stage = d.data()['stage'] as String? ?? '';
      return stage == 'considering' || stage == 'onboarding';
    }).toList()
      ..sort((a, b) {
        final aNext = (a.data()['nextActionAt'] as Timestamp?)?.toDate();
        final bNext = (b.data()['nextActionAt'] as Timestamp?)?.toDate();
        if (aNext == null && bNext == null) return 0;
        if (aNext == null) return 1;
        if (bNext == null) return -1;
        return aNext.compareTo(bNext);
      });
    if (filtered.isEmpty) {
      return Center(
        child: Text('パイプライン対象のリードはありません',
            style: TextStyle(color: context.colors.textSecondary)),
      );
    }
    return _CrmTableView(docs: filtered);
  }
}

/// 入会済み: won を入会日降順で
class _CrmEnrolledView extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _CrmEnrolledView({required this.docs});

  @override
  Widget build(BuildContext context) {
    final filtered = docs.where((d) => (d.data()['stage'] ?? '') == 'won').toList()
      ..sort((a, b) {
        final aDate = (a.data()['enrolledAt'] as Timestamp?)?.toDate();
        final bDate = (b.data()['enrolledAt'] as Timestamp?)?.toDate();
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
    if (filtered.isEmpty) {
      return Center(
        child: Text('入会済みリードはまだありません',
            style: TextStyle(color: context.colors.textSecondary)),
      );
    }
    return _CrmTableView(docs: filtered);
  }
}

/// 離脱: lost + withdrawn。理由別件数バーを上に表示。
class _CrmChurnView extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _CrmChurnView({required this.docs});

  @override
  Widget build(BuildContext context) {
    final churned = docs.where((d) {
      final s = d.data()['stage'] ?? '';
      return s == 'lost' || s == 'withdrawn';
    }).toList();

    final lossCounts = <String, int>{};
    final withdrawCounts = <String, int>{};
    for (final d in churned) {
      final data = d.data();
      final stage = data['stage'];
      if (stage == 'lost') {
        final r = (data['lossReason'] as String?) ?? 'other';
        lossCounts[r] = (lossCounts[r] ?? 0) + 1;
      } else if (stage == 'withdrawn') {
        final r = (data['withdrawReason'] as String?) ?? 'other';
        withdrawCounts[r] = (withdrawCounts[r] ?? 0) + 1;
      }
    }

    if (churned.isEmpty) {
      return Center(
        child: Text('離脱リードはありません',
            style: TextStyle(color: context.colors.textSecondary)),
      );
    }

    churned.sort((a, b) {
      final aDate = (a.data()['updatedAt'] as Timestamp?)?.toDate();
      final bDate = (b.data()['updatedAt'] as Timestamp?)?.toDate();
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      children: [
        if (lossCounts.isNotEmpty)
          _reasonBlock(context, '失注理由',
              CrmOptions.lossReasons, lossCounts, context.alerts.urgent),
        if (withdrawCounts.isNotEmpty)
          _reasonBlock(context, '退会理由',
              CrmOptions.withdrawalReasons, withdrawCounts, context.alerts.warning),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text('全離脱リード（${churned.length}件）',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary)),
        ),
        ...churned.map((d) => _LeadTableRow(doc: d)),
      ],
    );
  }

  Widget _reasonBlock(
      BuildContext context,
      String title,
      List<({String id, String label})> reasons,
      Map<String, int> counts,
      AlertStyle style) {
    final total = counts.values.fold<int>(0, (s, n) => s + n);
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCompetitor = counts['competitor'] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: style.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$title（$total件）',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary)),
              if (title == '失注理由' && topCompetitor >= 3) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.alerts.urgent.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: context.alerts.urgent.border, width: 0.6),
                  ),
                  child: Text('競合分析推奨',
                      style: TextStyle(
                          fontSize: 10,
                          color: context.alerts.urgent.text,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ...sorted.map((e) {
            final label = CrmOptions.labelOf(reasons, e.key);
            final ratio = total == 0 ? 0.0 : e.value / total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                      width: 140,
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              color: context.colors.textSecondary),
                          overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor:
                          context.colors.borderLight.withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation(style.icon),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${e.value}',
                      style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ============================================================
// CRM-04: 分析ビュー（経営者向けダッシュボード）
// ============================================================
class _CrmDashboardView extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _CrmDashboardView({required this.docs});

  @override
  State<_CrmDashboardView> createState() => _CrmDashboardViewState();
}

enum _PeriodFilter { all, thisMonth, lastMonth, last3Months, ytd }

extension _PeriodFilterLabel on _PeriodFilter {
  String get label {
    switch (this) {
      case _PeriodFilter.all:
        return '全期間';
      case _PeriodFilter.thisMonth:
        return '今月';
      case _PeriodFilter.lastMonth:
        return '先月';
      case _PeriodFilter.last3Months:
        return '過去3ヶ月';
      case _PeriodFilter.ytd:
        return '年初来';
    }
  }

  bool includes(DateTime? t, DateTime now) {
    if (this == _PeriodFilter.all) return true;
    if (t == null) return false;
    switch (this) {
      case _PeriodFilter.thisMonth:
        return t.year == now.year && t.month == now.month;
      case _PeriodFilter.lastMonth:
        final prev = DateTime(now.year, now.month - 1);
        return t.year == prev.year && t.month == prev.month;
      case _PeriodFilter.last3Months:
        final from = DateTime(now.year, now.month - 2);
        return !t.isBefore(from);
      case _PeriodFilter.ytd:
        return t.year == now.year;
      case _PeriodFilter.all:
        return true;
    }
  }
}

class _CrmDashboardViewState extends State<_CrmDashboardView> {
  _PeriodFilter _period = _PeriodFilter.all;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    // 期間フィルタ: inquiredAt で判定（問い合わせの流入期間ベース）
    final docs = widget.docs
        .where((d) => _period
            .includes((d.data()['inquiredAt'] as Timestamp?)?.toDate(), now))
        .toList();

    final stageCount = <String, int>{for (final s in CrmOptions.stages) s.id: 0};
    final sourceTotal = <String, int>{};
    final sourceTrial = <String, int>{};
    final sourceWon = <String, int>{};
    final lossReasonCount = <String, int>{};
    final withdrawReasonCount = <String, int>{};
    final permitBucket = <String, int>{'none': 0, 'applying': 0, 'have': 0};
    final permitWon = <String, int>{'none': 0, 'applying': 0, 'have': 0};

    int trialDoneCount = 0;
    int wonCount = 0;
    int lostCount = 0;
    int withdrawnCount = 0;
    int totalInquiries = docs.length;

    // ステージ滞留日数（更新待ちリードの検出）
    const staleConsidering = _staleConsideringDays;
    const staleProcessing = _staleProcessingDays;
    final consideringIdleDays = <int>[];
    final processingIdleDays = <int>[];
    int staleConsideringCount = 0;
    int staleProcessingCount = 0;

    // 問い合わせ→初回体験 日数
    final inquiryToTrialDays = <int>[];

    for (final doc in docs) {
      final d = doc.data();
      final stage = d['stage'] as String? ?? 'considering';
      stageCount[stage] = (stageCount[stage] ?? 0) + 1;
      final src = d['source'] as String? ?? 'other';
      sourceTotal[src] = (sourceTotal[src] ?? 0) + 1;

      final permit = d['permitStatus'] as String? ?? 'none';
      permitBucket[permit] = (permitBucket[permit] ?? 0) + 1;

      final inquiredAt = (d['inquiredAt'] as Timestamp?)?.toDate();
      final trialAt = (d['trialAt'] as Timestamp?)?.toDate();
      final lastActivityAt = (d['lastActivityAt'] as Timestamp?)?.toDate() ??
          (d['updatedAt'] as Timestamp?)?.toDate() ??
          inquiredAt;

      if (trialAt != null) {
        trialDoneCount++;
        sourceTrial[src] = (sourceTrial[src] ?? 0) + 1;
        if (inquiredAt != null) {
          final diff = trialAt.difference(inquiredAt).inDays;
          if (diff >= 0 && diff <= 180) inquiryToTrialDays.add(diff);
        }
      }
      if (stage == 'won') {
        wonCount++;
        sourceWon[src] = (sourceWon[src] ?? 0) + 1;
        permitWon[permit] = (permitWon[permit] ?? 0) + 1;
      }
      if (stage == 'lost') {
        lostCount++;
        final r = d['lossReason'] as String? ?? 'other';
        lossReasonCount[r] = (lossReasonCount[r] ?? 0) + 1;
      }
      if (stage == 'withdrawn') {
        withdrawnCount++;
        final r = d['withdrawReason'] as String? ?? 'other';
        withdrawReasonCount[r] = (withdrawReasonCount[r] ?? 0) + 1;
      }

      if (stage == 'considering' && lastActivityAt != null) {
        final idle = todayStart.difference(lastActivityAt).inDays;
        consideringIdleDays.add(idle);
        if (idle >= staleConsidering) staleConsideringCount++;
      }
      if (stage == 'onboarding' && lastActivityAt != null) {
        final idle = todayStart.difference(lastActivityAt).inDays;
        processingIdleDays.add(idle);
        if (idle >= staleProcessing) staleProcessingCount++;
      }
    }

    final winRate =
        totalInquiries == 0 ? 0.0 : wonCount * 100 / totalInquiries;
    final trialRate =
        totalInquiries == 0 ? 0.0 : trialDoneCount * 100 / totalInquiries;
    final trialToWin =
        trialDoneCount == 0 ? 0.0 : wonCount * 100 / trialDoneCount;
    final avgInquiryToTrial = inquiryToTrialDays.isEmpty
        ? null
        : inquiryToTrialDays.reduce((a, b) => a + b) /
            inquiryToTrialDays.length;
    final avgConsideringIdle = consideringIdleDays.isEmpty
        ? null
        : consideringIdleDays.reduce((a, b) => a + b) /
            consideringIdleDays.length;
    final avgProcessingIdle = processingIdleDays.isEmpty
        ? null
        : processingIdleDays.reduce((a, b) => a + b) /
            processingIdleDays.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _periodSelector(),
          const SizedBox(height: 12),
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
          _sectionTitle(context, '媒体別KPI'),
          const SizedBox(height: 8),
          _sourceKpiTable(sourceTotal, sourceTrial, sourceWon),

          const SizedBox(height: 16),
          _sectionTitle(context, 'ステージ滞留日数'),
          const SizedBox(height: 8),
          _stageIdleCard(
              context,
              '検討中',
              avgConsideringIdle,
              staleConsideringCount,
              staleConsidering,
              Colors.orange),
          _stageIdleCard(
              context,
              '入会手続中',
              avgProcessingIdle,
              staleProcessingCount,
              staleProcessing,
              Colors.purple),

          const SizedBox(height: 16),
          _sectionTitle(context, '受給者証ステータス別ファネル'),
          const SizedBox(height: 8),
          _permitFunnel(permitBucket, permitWon),

          const SizedBox(height: 16),
          _sectionTitle(context, '問い合わせ → 初回体験 平均日数'),
          const SizedBox(height: 8),
          _avgDaysCard(
              context,
              avgInquiryToTrial,
              inquiryToTrialDays.length,
              '件の体験実績から算出'),

          if (lossReasonCount.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle(context, '失注理由ランキング'),
            const SizedBox(height: 8),
            ..._reasonRanking(lossReasonCount, CrmOptions.lossReasons,
                lostCount, context.alerts.urgent),
          ],
          if (withdrawReasonCount.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle(context, '退会理由ランキング'),
            const SizedBox(height: 8),
            ..._reasonRanking(
                withdrawReasonCount,
                CrmOptions.withdrawalReasons,
                withdrawnCount,
                context.alerts.warning),
          ],
        ],
      ),
    );
  }

  Widget _periodSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _PeriodFilter.values.map((p) {
          final sel = _period == p;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _period = p),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : context.colors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: sel
                          ? AppColors.primary
                          : context.colors.borderMedium,
                      width: sel ? 1.2 : 0.8),
                ),
                child: Text(p.label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.normal,
                        color: sel
                            ? AppColors.primary
                            : context.colors.textPrimary)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sourceKpiTable(Map<String, int> totals, Map<String, int> trials,
      Map<String, int> wons) {
    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        children: [
          _kpiTableHeader(),
          const Divider(height: 12),
          ...rows.map((e) {
            final t = e.value;
            final tr = trials[e.key] ?? 0;
            final w = wons[e.key] ?? 0;
            final trialRate = t == 0 ? 0.0 : tr * 100 / t;
            final winRate = t == 0 ? 0.0 : w * 100 / t;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text(
                          CrmOptions.labelOf(CrmOptions.sources, e.key),
                          style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textPrimary))),
                  Expanded(
                      child: Text('$t',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12))),
                  Expanded(
                      child: Text('$tr',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12))),
                  Expanded(
                      child: Text('$w',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12))),
                  Expanded(
                      child: Text('${trialRate.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 12, color: Colors.teal.shade700))),
                  Expanded(
                      child: Text('${winRate.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _kpiTableHeader() {
    final s = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: context.colors.textSecondary);
    return Row(
      children: [
        Expanded(flex: 3, child: Text('媒体', style: s)),
        Expanded(child: Text('問合せ', textAlign: TextAlign.right, style: s)),
        Expanded(child: Text('体験', textAlign: TextAlign.right, style: s)),
        Expanded(child: Text('入会', textAlign: TextAlign.right, style: s)),
        Expanded(child: Text('体験率', textAlign: TextAlign.right, style: s)),
        Expanded(child: Text('入会率', textAlign: TextAlign.right, style: s)),
      ],
    );
  }

  Widget _stageIdleCard(BuildContext context, String label, double? avgIdle,
      int staleCount, int threshold, Color color) {
    final urgent = context.alerts.urgent;
    final hasAlert = staleCount > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: hasAlert ? urgent.border : context.colors.borderLight,
            width: hasAlert ? 1.2 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 32,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                    '平均滞留: ${avgIdle == null ? '-' : '${avgIdle.toStringAsFixed(1)}日'}',
                    style: TextStyle(
                        fontSize: 11, color: context.colors.textSecondary)),
              ],
            ),
          ),
          if (hasAlert)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: urgent.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: urgent.border, width: 0.6),
              ),
              child: Text('$threshold日+ $staleCount件',
                  style: TextStyle(
                      fontSize: 11,
                      color: urgent.text,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _permitFunnel(Map<String, int> bucket, Map<String, int> won) {
    // 未申請 → 申請中 → 取得済 → 入会 の順に漏斗を描画
    final steps = [
      ('none', '未申請'),
      ('applying', '申請中'),
      ('have', '取得済'),
    ];
    final maxVal = bucket.values.fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        children: steps.map((e) {
          final id = e.$1;
          final label = e.$2;
          final total = bucket[id] ?? 0;
          final w = won[id] ?? 0;
          final rate = total == 0 ? 0.0 : w * 100 / total;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                    width: 60,
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textPrimary))),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 18,
                        decoration: BoxDecoration(
                            color: context.colors.scaffoldBg,
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      FractionallySizedBox(
                        widthFactor: maxVal == 0
                            ? 0.0
                            : (total / maxVal).clamp(0.0, 1.0),
                        child: Container(
                          height: 18,
                          decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                    width: 40,
                    child: Text('$total件',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11))),
                SizedBox(
                    width: 70,
                    child: Text('入会$w(${rate.toStringAsFixed(0)}%)',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _avgDaysCard(BuildContext context, double? avg, int sampleCount,
      String hint) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(avg == null ? '—' : avg.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary)),
          const SizedBox(width: 6),
          Text('日',
              style: TextStyle(
                  fontSize: 14, color: context.colors.textSecondary)),
          const SizedBox(width: 16),
          Expanded(
            child: Text('$sampleCount$hint',
                style: TextStyle(
                    fontSize: 11, color: context.colors.textSecondary)),
          ),
        ],
      ),
    );
  }

  List<Widget> _reasonRanking(
      Map<String, int> counts,
      List<({String id, String label})> master,
      int total,
      AlertStyle style) {
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) {
      final label = CrmOptions.labelOf(master, e.key);
      return _bar(context, label, e.value, total, style.icon);
    }).toList();
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

  // 退会
  String? _withdrawReason;
  DateTime? _withdrawnAt;
  final _withdrawDetailCtrl = TextEditingController();

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
      _withdrawReason = d['withdrawReason'];
      _withdrawDetailCtrl.text = d['withdrawDetail'] ?? '';
      _withdrawnAt = (d['withdrawnAt'] as Timestamp?)?.toDate();
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
      _withdrawDetailCtrl,
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
    // 失注/退会への遷移時は理由必須
    if (_stage == 'lost' && (_lossReason == null || _lossReason!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('失注理由を選択してください'), backgroundColor: Colors.orange));
      return;
    }
    if (_stage == 'withdrawn' &&
        (_withdrawReason == null || _withdrawReason!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('退会理由を選択してください'), backgroundColor: Colors.orange));
      return;
    }
    // 旧ステージからの遷移ルール検証（新規作成時は検証不要）
    if (_isEdit) {
      final prevStage = widget.doc!.data()['stage'] as String? ?? 'considering';
      if (!CrmOptions.canTransition(prevStage, _stage)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '「${CrmOptions.stageLabel(prevStage)}」→「${CrmOptions.stageLabel(_stage)}」への遷移は許可されていません'),
            backgroundColor: Colors.orange));
        return;
      }
    }
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
      'withdrawReason': _withdrawReason,
      'withdrawDetail': _withdrawDetailCtrl.text.trim(),
      'withdrawnAt': _withdrawnAt == null ? null : Timestamp.fromDate(_withdrawnAt!),
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
        // 督促タブで「最終アクションからの経過日数」を算出するため最終活動日を保存
        'lastActivityAt': Timestamp.fromDate(result['at']),
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
            _section('失注情報（理由は必須）'),
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
          if (_stage == 'withdrawn') ...[
            const SizedBox(height: 16),
            _section('退会情報（理由は必須）'),
            Row(
              children: [
                Expanded(
                  child: _dateField('退会日', _withdrawnAt,
                      (d) => setState(() => _withdrawnAt = d), nullable: true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _withdrawReasonSelector(),
            const SizedBox(height: 8),
            _textField('退会詳細', _withdrawDetailCtrl, maxLines: 3),
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

  Widget _withdrawReasonSelector() {
    final warning = context.alerts.warning;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: CrmOptions.withdrawalReasons.map((s) {
        final sel = _withdrawReason == s.id;
        return GestureDetector(
          onTap: () => setState(() => _withdrawReason = s.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? warning.background : context.colors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: sel ? warning.border : context.colors.borderMedium,
                  width: sel ? 1.5 : 0.8),
            ),
            child: Text(s.label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    color: sel ? warning.text : context.colors.textPrimary)),
          ),
        );
      }).toList(),
    );
  }

  Widget _lossReasonSelector() {
    final urgent = context.alerts.urgent;
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
              color: sel ? urgent.background : context.colors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: sel ? urgent.border : context.colors.borderMedium,
                  width: sel ? 1.5 : 0.8),
            ),
            child: Text(s.label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    color: sel ? urgent.text : context.colors.textPrimary)),
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
