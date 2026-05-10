import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';
import 'crm/campaign_section.dart';
import 'crm/crm_home_screen.dart';
import 'main.dart';
import 'services/undo_service.dart';
import 'services/crm_family_sync.dart';
import 'services/crm_lead_adapter.dart';

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

  // F_lead_detail_refactor (Phase 2): LINE は実運用で未使用のため UI から削除。
  // スキーマ ('line') は既存データ保護のため保持（書き込み禁止、表示なし）。
  static const List<({String id, String label})> channels = [
    (id: 'tel', label: '電話'),
    (id: 'email', label: 'メール'),
    (id: 'visit', label: '来所'),
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

  // F_lead_detail_refactor (Phase 2): 'line' を活動種別から削除。
  // 既存履歴に 'line' が残っているデータは表示時にラベル fallback で対応。
  static const List<({String id, String label})> activityTypes = [
    (id: 'tel', label: '電話'),
    (id: 'email', label: 'メール'),
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
  // 0: 今やること（旧ホーム+督促を統合）、1: リード一覧（旧パイプラインカンバン）、2: 分析
  // 入会済み・離脱タブは削除（入会後は BSP 管理画面に任せる）
  int _viewMode = 0;

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
        title: Row(
          children: [
            const Text('CRM',
                style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.w600)),
            Expanded(
              child: Center(
                child: _ViewModeTabs(
                  value: _viewMode,
                  onChanged: (v) => setState(() => _viewMode = v),
                ),
              ),
            ),
          ],
        ),
        // ダークモード時に AppBar が真っ黒になるよう scaffoldBg を使う。
        backgroundColor: context.colors.scaffoldBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        automaticallyImplyLeading: false,
        actions: [
          // CSV インポート / 再読込はあまり使わないため、より頻度の高い「新規リード」を
          // 配置。CSV は管理タブのデータメンテナンスから。再読込はブラウザリロードで代替。
          if (_viewMode != 2)
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              child: FilledButton.icon(
                onPressed: _openNewLead,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新規リード'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                      fontSize: AppTextSize.small, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      // FAB 廃止。AppBar の「新規リード」ボタンに統合。
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return StreamBuilder<List<LeadView>>(
      stream: watchLeadsFromPlusFamilies(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          return Center(
              child: Text('読み込みエラー: ${snap.error}',
                  style: TextStyle(color: context.colors.textSecondary)));
        }
        final docs = snap.data ?? [];
        if (docs.isEmpty) return _emptyState();
        switch (_viewMode) {
          case 0:
            return CrmHomeScreen(docs: docs);
          case 1:
            return _CrmPipelineView(docs: docs);
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
              style: TextStyle(color: context.colors.textSecondary, fontSize: AppTextSize.bodyMd)),
          const SizedBox(height: 4),
          Text('右下の「新規リード」から登録できます',
              style: TextStyle(color: context.colors.textTertiary, fontSize: AppTextSize.small)),
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
  // 現在は AppBar から外したため未使用。再度必要になったら呼び出し元を復活させる。
  // ------------------------------------------------------------
  // ignore: unused_element
  Future<void> _importFromNotionCsv() async {
    final confirmed = await AppFeedback.confirm(context, title: 'NotionエクスポートCSVをインポート', message: '選択したCSVをリードとして一括登録します。\n'
            '同じCSVを二度インポートすると重複するので注意してください。\n\n続行しますか？', confirmLabel: '選択', cancelLabel: 'キャンセル');
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
      _snack('行がありません', AppColors.warning);
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

    int ok = 0;
    int skipped = 0;
    // Undo 用: 作成した plus_families ドキュメントID を追跡
    final createdIds = <String>[];

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
          // CSV に lossReason 列が無いため、自由記述（lossDetail）のみ取り込み、
          // lossReason は null（未分類）として残す。後でデータベースタブの
          // 「未分類失注」フィルタから手動で再分類する想定。
          'lossReason': null,
          'lossDetail': stage == 'lost' ? get(row, iLoss) : '',
          'reapproachOk': true,
          'memo': get(row, iMemo),
          'activities': <Map<String, dynamic>>[],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdBy': 'import:notion:${user?.uid ?? ''}',
        };
        // plus_families に upsert（保護者一致なら家族マージ、無ければ新規作成）
        final newLeadId = 'notion_${DateTime.now().millisecondsSinceEpoch}_$r';
        final familyId = await CrmFamilySync.upsertLead(
          leadId: newLeadId,
          leadData: data,
        );
        createdIds.add(familyId);
        ok++;
      }
      messenger.hideCurrentSnackBar();
      if (mounted) setState(() {});
      if (createdIds.isNotEmpty && mounted) {
        // インポート結果のUndoはスキップ（plus_families は他データと統合されているため
        // 単純に doc 削除で復元できない）。手動で個別削除を依頼する。
        _snack('インポート完了: $ok件（スキップ $skipped）。Undo はサポート外', AppColors.success);
      } else {
        _snack('インポート完了: $ok件（スキップ $skipped）', AppColors.success);
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      _snack('インポート失敗: $e', AppColors.error);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
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
// 上部ビュー切替タブ（軽量・無装飾）
// ============================================================
class _ViewModeTabs extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _ViewModeTabs({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ViewModeTab(label: 'リード', selected: value == 0, onTap: () => onChanged(0)),
            const SizedBox(width: 8),
            _ViewModeTab(label: 'データベース', selected: value == 1, onTap: () => onChanged(1)),
            const SizedBox(width: 8),
            _ViewModeTab(label: '分析', selected: value == 2, onTap: () => onChanged(2)),
          ],
        ),
      ),
    );
  }
}

class _ViewModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ViewModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: TextStyle(
            fontSize: AppTextSize.body,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CRM-03: テーブルビュー
// ============================================================
class _CrmTableView extends StatelessWidget {
  final List<LeadView> docs;
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
  final LeadView doc;
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
                            fontSize: AppTextSize.caption,
                            color: color,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      childName.isEmpty ? '(児童名未入力)' : childName,
                      style: TextStyle(
                          fontSize: AppTextSize.bodyMd,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textPrimary),
                    ),
                  ),
                  if (source.isNotEmpty)
                    Text(CrmOptions.labelOf(CrmOptions.sources, source),
                        style: TextStyle(
                            fontSize: AppTextSize.caption,
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
              // 入会手続中はHUG必須項目の進捗バーを表示（契約完了までの埋まり具合）
              if (stage == 'onboarding') ...[
                const SizedBox(height: 8),
                _HugProgressBar(data: d),
              ],
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
        Text(text, style: TextStyle(fontSize: AppTextSize.caption, color: c)),
      ],
    );
  }
}

/// HUG連携必須13項目の入力率を進捗バーで可視化。
/// 100% で「契約完了」可能を示す。CRM lead 互換のフラットマップを受け取る。
class _HugProgressBar extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HugProgressBar({required this.data});

  static (int filled, int total) _count(Map<String, dynamic> d) {
    bool s(String k) => (d[k] as String? ?? '').trim().isNotEmpty;
    final rc = d['recipientCertificate'];
    final rcMap = rc is Map ? Map<String, dynamic>.from(rc) : <String, dynamic>{};
    bool rs(String k) => (rcMap[k] as String? ?? '').trim().isNotEmpty;
    int hits = 0;
    if (s('parentLastName')) hits++;
    if (s('parentFirstName')) hits++;
    if (s('parentKana')) hits++;
    if (s('postalCode')) hits++;
    if (s('prefecture')) hits++;
    if (s('city')) hits++;
    if (s('parentTel')) hits++;
    if (s('childFirstName')) hits++;
    if (s('childKana')) hits++;
    if (d['childBirthDate'] != null) hits++;
    if (s('childGender')) hits++;
    if (s('allergy')) hits++;
    // 受給者証4項目（startAt は Timestamp か Map）
    if (rcMap['startAt'] != null) hits++;
    if (rs('number')) hits++;
    if (rs('service')) hits++;
    if (rcMap['monthlyLimit'] != null) hits++;
    return (hits, 16);
  }

  @override
  Widget build(BuildContext context) {
    final (filled, total) = _count(data);
    final ratio = filled / total;
    final isComplete = filled == total;
    final color = isComplete ? AppColors.success : AppColors.info;
    return Row(
      children: [
        Icon(
          isComplete ? Icons.check_circle : Icons.assignment_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: context.colors.borderLight,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isComplete ? '契約OK' : 'HUG項目 $filled/$total',
          style: TextStyle(
            fontSize: AppTextSize.caption,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
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
  final LeadView doc;
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

/// パイプライン: 検討中 + 入会手続中 を次回対応期日昇順で並べる
class _CrmPipelineView extends StatefulWidget {
  final List<LeadView> docs;
  const _CrmPipelineView({required this.docs});

  @override
  State<_CrmPipelineView> createState() => _CrmPipelineViewState();
}

class _CrmPipelineViewState extends State<_CrmPipelineView> {
  // v3.5: データベースタブを検索/フィルタ/ソート対応に刷新。
  String _searchText = '';
  // ステージ複数選択フィルタ。デフォルトは進行中（検討中 + 入会手続中 + 入会）。
  final Set<String> _stageFilter = {'considering', 'onboarding', 'won'};
  bool _includeWithdrawn = false;
  bool _includeLost = false;
  String _sortBy = 'inquiredAt'; // inquiredAt / enrolledAt / nextActionAt
  bool _sortDesc = true;

  static const _stageOptions = [
    ('considering', '検討中'),
    ('onboarding', '入会手続中'),
    ('won', '入会'),
  ];

  static const _sortOptions = [
    ('inquiredAt', '問い合わせ日'),
    ('enrolledAt', '入会日'),
    ('nextActionAt', '次のアクション期日'),
    ('lastActivityAt', '最終接触日'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final search = _searchText.trim().toLowerCase();

    final filtered = widget.docs.where((d) {
      final m = d.data();
      final stage = m['stage'] as String? ?? 'considering';

      // ステージフィルタ
      final inMain = _stageFilter.contains(stage);
      final isLost = stage == 'lost';
      final isWithdrawn = stage == 'withdrawn';
      if (!inMain &&
          !(_includeLost && isLost) &&
          !(_includeWithdrawn && isWithdrawn)) {
        return false;
      }

      // 検索
      if (search.isNotEmpty) {
        final childName =
            '${m['childLastName'] ?? ''}${m['childFirstName'] ?? ''}'
                .toLowerCase();
        final parentName =
            '${m['parentLastName'] ?? ''}${m['parentFirstName'] ?? ''}'
                .toLowerCase();
        final tel = (m['parentTel'] as String? ?? '');
        if (!childName.contains(search) &&
            !parentName.contains(search) &&
            !tel.contains(search)) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final ad = (a.data()[_sortBy] as Timestamp?)?.toDate();
      final bd = (b.data()[_sortBy] as Timestamp?)?.toDate();
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return _sortDesc ? bd.compareTo(ad) : ad.compareTo(bd);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 検索バー
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: TextField(
            decoration: InputDecoration(
              hintText: '児童名・保護者名・電話で検索',
              hintStyle: TextStyle(
                  fontSize: AppTextSize.body, color: c.textTertiary),
              prefixIcon:
                  Icon(Icons.search, size: 18, color: c.textTertiary),
              suffixIcon: _searchText.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() => _searchText = ''),
                    ),
              isDense: true,
              filled: true,
              fillColor: c.cardBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.borderLight)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.borderLight)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: AppColors.primary, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 8),
            ),
            style: TextStyle(
                fontSize: AppTextSize.body, color: c.textPrimary),
            onChanged: (v) => setState(() => _searchText = v),
          ),
        ),
        // ステージフィルタ
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (id, label) in _stageOptions)
                FilterChip(
                  label: Text(label,
                      style:
                          const TextStyle(fontSize: AppTextSize.caption)),
                  selected: _stageFilter.contains(id),
                  onSelected: (s) => setState(() {
                    if (s) {
                      _stageFilter.add(id);
                    } else {
                      _stageFilter.remove(id);
                    }
                  }),
                ),
              FilterChip(
                label: const Text('失注を含む',
                    style: TextStyle(fontSize: AppTextSize.caption)),
                selected: _includeLost,
                onSelected: (s) => setState(() => _includeLost = s),
              ),
              FilterChip(
                label: const Text('退会を含む',
                    style: TextStyle(fontSize: AppTextSize.caption)),
                selected: _includeWithdrawn,
                onSelected: (s) =>
                    setState(() => _includeWithdrawn = s),
              ),
            ],
          ),
        ),
        // ソート + 件数
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Text('${filtered.length} 件',
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textSecondary,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Text('ソート:',
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textSecondary)),
              const SizedBox(width: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sortBy,
                  isDense: true,
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textPrimary),
                  items: [
                    for (final (id, label) in _sortOptions)
                      DropdownMenuItem(value: id, child: Text(label)),
                  ],
                  onChanged: (v) => setState(
                      () => _sortBy = v ?? 'inquiredAt'),
                ),
              ),
              IconButton(
                icon: Icon(
                    _sortDesc
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    size: 16,
                    color: c.textSecondary),
                tooltip: _sortDesc ? '降順' : '昇順',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 28, minHeight: 28),
                onPressed: () =>
                    setState(() => _sortDesc = !_sortDesc),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text('該当なし',
                      style: TextStyle(color: c.textSecondary)),
                )
              : _CrmTableView(docs: filtered),
        ),
      ],
    );
  }
}


// ============================================================
// CRM-04: 分析ビュー（経営者向けダッシュボード）
// ============================================================
class _CrmDashboardView extends StatefulWidget {
  final List<LeadView> docs;
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
              _kpiCard(context, '総問い合わせ', '$totalInquiries', AppColors.info),
              const SizedBox(width: 8),
              _kpiCard(context, '入会数', '$wonCount', AppColors.success),
              const SizedBox(width: 8),
              _kpiCard(context, '入会率',
                  '${winRate.toStringAsFixed(1)}%', AppColors.aiAccent),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _kpiCard(context, '体験率',
                  '${trialRate.toStringAsFixed(1)}%', AppColors.secondary),
              const SizedBox(width: 8),
              _kpiCard(context, '体験→入会',
                  '${trialToWin.toStringAsFixed(1)}%', AppColors.warning),
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
          // F2: Campaign カンバン。クライアント集計、Cloud Functions 自動集計は F6 で導入予定。
          CampaignSection(docs: widget.docs),

          const SizedBox(height: 16),
          _sectionTitle(context, 'ステージ滞留日数'),
          const SizedBox(height: 8),
          _stageIdleCard(
              context,
              '検討中',
              avgConsideringIdle,
              staleConsideringCount,
              staleConsidering,
              AppColors.warning),
          _stageIdleCard(
              context,
              '入会手続中',
              avgProcessingIdle,
              staleProcessingCount,
              staleProcessing,
              AppColors.aiAccent),

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
                        fontSize: AppTextSize.small,
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
                              fontSize: AppTextSize.small,
                              color: context.colors.textPrimary))),
                  Expanded(
                      child: Text('$t',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AppTextSize.small))),
                  Expanded(
                      child: Text('$tr',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AppTextSize.small))),
                  Expanded(
                      child: Text('$w',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AppTextSize.small))),
                  Expanded(
                      child: Text('${trialRate.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: AppTextSize.small, color: AppColors.secondary))),
                  Expanded(
                      child: Text('${winRate.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: AppTextSize.small, fontWeight: FontWeight.bold))),
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
        fontSize: AppTextSize.caption,
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
                        fontSize: AppTextSize.small,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                    '平均滞留: ${avgIdle == null ? '-' : '${avgIdle.toStringAsFixed(1)}日'}',
                    style: TextStyle(
                        fontSize: AppTextSize.caption, color: context.colors.textSecondary)),
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
                      fontSize: AppTextSize.caption,
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
                            fontSize: AppTextSize.small,
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
                              color: AppColors.info.withValues(alpha: 0.55),
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
                        style: const TextStyle(fontSize: AppTextSize.caption))),
                SizedBox(
                    width: 70,
                    child: Text('入会$w(${rate.toStringAsFixed(0)}%)',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: AppColors.success,
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
                  fontSize: AppTextSize.hero,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary)),
          const SizedBox(width: 6),
          Text('日',
              style: TextStyle(
                  fontSize: AppTextSize.bodyMd, color: context.colors.textSecondary)),
          const SizedBox(width: 16),
          Expanded(
            child: Text('$sampleCount$hint',
                style: TextStyle(
                    fontSize: AppTextSize.caption, color: context.colors.textSecondary)),
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
                    fontSize: AppTextSize.caption, color: context.colors.textSecondary)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: AppTextSize.display, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(text,
        style: TextStyle(
            fontSize: AppTextSize.body,
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
                      fontSize: AppTextSize.small, color: context.colors.textPrimary))),
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
                      fontSize: AppTextSize.small,
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
                        fontSize: AppTextSize.small, color: context.colors.textPrimary))),
            Expanded(
              child: Text('$total件',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: AppTextSize.small, color: context.colors.textSecondary)),
            ),
            Expanded(
              child: Text('入会$won',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: AppTextSize.small, color: AppColors.success)),
            ),
            Expanded(
              child: Text('${winRate.toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: AppTextSize.small, fontWeight: FontWeight.bold)),
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
  final LeadView? doc;
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
  final _allergyCtrl = TextEditingController(); // HUG必須
  String _permitStatus = 'none';

  // 保護者
  final _parentLastNameCtrl = TextEditingController();
  final _parentFirstNameCtrl = TextEditingController();
  final _parentKanaCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _lineCtrl = TextEditingController();
  String _preferredChannel = 'tel';
  // 住所はHUG連携のため郵便番号 + 都道府県 + 市町村・番地に分離
  final _postalCodeCtrl = TextEditingController();
  String _prefecture = '';
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController(); // 旧フィールド（移行用に残置）

  // 受給者証情報（HUG必須一式）
  DateTime? _recipientStartAt;
  final _recipientNumberCtrl = TextEditingController();
  String _recipientService = 'after_school'; // after_school | child_dev
  final _recipientMonthlyLimitCtrl = TextEditingController();

  // 案件
  String _stage = 'considering';
  String _confidence = 'B';
  String _source = 'instagram';
  final _sourceDetailCtrl = TextEditingController();
  // F2: 紐付け施策（任意）。null = 未紐付け。実行中(running)の Campaign のみ選択可。
  String? _sourceCampaignId;
  final _preferredDaysCtrl = TextEditingController();
  final _preferredTimeCtrl = TextEditingController();
  final _preferredStartCtrl = TextEditingController();

  // 主訴
  final _mainConcernCtrl = TextEditingController();
  final _likesCtrl = TextEditingController();
  final _dislikesCtrl = TextEditingController();
  final _trialNotesCtrl = TextEditingController();

  // v3.5: 学年 / 既往歴 / 診断名（フォーム取り込み + 児童マスタ画面で編集）
  final _gradeCtrl = TextEditingController();
  final _medicalHistoryCtrl = TextEditingController();
  final _diagnosisCtrl = TextEditingController();

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
      // フォーム自動取り込みの未読フラグを既読化（児童ごと）。
      // 既に既読なら何もしないので毎回呼んでも安全。
      widget.doc!.markRead();
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
      _postalCodeCtrl.text = d['postalCode'] ?? '';
      _prefecture = d['prefecture'] ?? '';
      _cityCtrl.text = d['city'] ?? '';
      _allergyCtrl.text = d['allergy'] ?? '';
      // 受給者証情報（ネスト構造）
      final rc = d['recipientCertificate'];
      if (rc is Map) {
        final m = Map<String, dynamic>.from(rc);
        _recipientStartAt = (m['startAt'] as Timestamp?)?.toDate();
        _recipientNumberCtrl.text = (m['number'] ?? '').toString();
        _recipientService = (m['service'] ?? 'after_school').toString();
        final lim = m['monthlyLimit'];
        _recipientMonthlyLimitCtrl.text = lim == null ? '' : lim.toString();
      }
      _stage = d['stage'] ?? 'considering';
      _confidence = d['confidence'] ?? 'B';
      _source = d['source'] ?? 'instagram';
      _sourceDetailCtrl.text = d['sourceDetail'] ?? '';
      _sourceCampaignId = d['sourceCampaignId'] as String?;
      _preferredDaysCtrl.text = d['preferredDays'] ?? '';
      _preferredTimeCtrl.text = d['preferredTimeSlots'] ?? '';
      _preferredStartCtrl.text = d['preferredStart'] ?? '';
      _gradeCtrl.text = d['grade'] ?? '';
      _medicalHistoryCtrl.text = d['medicalHistory'] ?? '';
      _diagnosisCtrl.text = d['diagnosis'] ?? '';
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
      _postalCodeCtrl,
      _cityCtrl,
      _allergyCtrl,
      _recipientNumberCtrl,
      _recipientMonthlyLimitCtrl,
      _sourceDetailCtrl,
      _preferredDaysCtrl,
      _preferredTimeCtrl,
      _preferredStartCtrl,
      _mainConcernCtrl,
      _likesCtrl,
      _dislikesCtrl,
      _trialNotesCtrl,
      _gradeCtrl,
      _medicalHistoryCtrl,
      _diagnosisCtrl,
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
      AppFeedback.warning(context, '失注理由を選択してください');
      return;
    }
    if (_stage == 'lost' &&
        _lossReason == 'other' &&
        _lossDetailCtrl.text.trim().isEmpty) {
      AppFeedback.warning(context, '失注理由「その他」の詳細を入力してください');
      return;
    }
    if (_stage == 'withdrawn' &&
        (_withdrawReason == null || _withdrawReason!.isEmpty)) {
      AppFeedback.warning(context, '退会理由を選択してください');
      return;
    }
    if (_stage == 'withdrawn' &&
        _withdrawReason == 'other' &&
        _withdrawDetailCtrl.text.trim().isEmpty) {
      AppFeedback.warning(context, '退会理由「その他」の詳細を入力してください');
      return;
    }
    // 旧ステージからの遷移ルール検証（新規作成時は検証不要）
    if (_isEdit) {
      final prevStage = widget.doc!.data()['stage'] as String? ?? 'considering';
      if (!CrmOptions.canTransition(prevStage, _stage)) {
        AppFeedback.warning(context, '「${CrmOptions.stageLabel(prevStage)}」→「${CrmOptions.stageLabel(_stage)}」への遷移は許可されていません');
        return;
      }
    }
    // 念のため、保存時点で 'lost' / 'withdrawn' なら日付を補完する
    if (_stage == 'lost' && _lostAt == null) {
      _lostAt = DateTime.now();
    }
    if (_stage == 'withdrawn' && _withdrawnAt == null) {
      _withdrawnAt = DateTime.now();
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
      'sourceCampaignId': _sourceCampaignId,
      'preferredDays': _preferredDaysCtrl.text.trim(),
      'preferredTimeSlots': _preferredTimeCtrl.text.trim(),
      'preferredStart': _preferredStartCtrl.text.trim(),
      'mainConcern': _mainConcernCtrl.text.trim(),
      'likes': _likesCtrl.text.trim(),
      'dislikes': _dislikesCtrl.text.trim(),
      'trialNotes': _trialNotesCtrl.text.trim(),
      'grade': _gradeCtrl.text.trim(),
      'medicalHistory': _medicalHistoryCtrl.text.trim(),
      'diagnosis': _diagnosisCtrl.text.trim(),
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
      'postalCode': _postalCodeCtrl.text.trim(),
      'prefecture': _prefecture,
      'city': _cityCtrl.text.trim(),
      'allergy': _allergyCtrl.text.trim(),
      'recipientCertificate': _buildRecipientCertificate(),
      'updatedAt': now,
      'updatedBy': user?.uid ?? '',
    };
    try {
      if (_isEdit) {
        // LeadView.update() がフラット形式を plus_families.children[index] と
        // family レベルに振り分けて適用する。
        await widget.doc!.reference.update(data);
      } else {
        // 新規リードは plus_families に新 family + child[0] として作成。
        // 一意な leadId をローカル生成し、children[].sourceLeadId に記録する。
        data['createdAt'] = now;
        data['createdBy'] = user?.uid ?? '';
        data['activities'] = <Map<String, dynamic>>[];
        final newLeadId = 'lead_${DateTime.now().millisecondsSinceEpoch}';
        await CrmFamilySync.upsertLead(
          leadId: newLeadId,
          leadData: data,
        );
      }
      if (mounted) {
        AppFeedback.success(context, _isEdit ? '更新しました' : '登録しました');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '保存失敗: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final ok = await AppFeedback.confirm(
      context,
      title: 'このリードを削除しますか？',
      message: 'この操作は取り消せません。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok) return;
    try {
      await widget.doc!.reference.delete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '削除失敗: $e');
      }
    }
  }

  Future<void> _addActivity() async {
    if (!_isEdit) {
      AppFeedback.warning(context, '先にリードを保存してください');
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
      // plus_families.children[].activities に追記。
      // FieldValue.arrayUnion は配列要素内で使えないため、現在のリストに append して
      // 新しいリストとして書き込む。
      final currentActivities = List<Map<String, dynamic>>.from(
          (widget.doc!.data()['activities'] as List? ?? [])
              .map((a) => Map<String, dynamic>.from(a as Map)));
      currentActivities.add(entry);
      await widget.doc!.reference.update({
        'activities': currentActivities,
        // 督促タブで「最終アクションからの経過日数」を算出するため最終活動日を保存
        'lastActivityAt': Timestamp.fromDate(result['at']),
        'updatedAt': Timestamp.now(),
      });
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '追加失敗: $e');
      }
    }
  }

  Future<void> _removeActivity(Map<String, dynamic> entry) async {
    final ok = await AppFeedback.confirm(
      context,
      title: 'この履歴を削除しますか？',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok) return;
    try {
      final currentActivities = List<Map<String, dynamic>>.from(
          (widget.doc!.data()['activities'] as List? ?? [])
              .map((a) => Map<String, dynamic>.from(a as Map)));
      currentActivities.removeWhere((a) =>
          a['id'] != null && entry['id'] != null && a['id'] == entry['id']);
      await widget.doc!.reference.update({
        'activities': currentActivities,
        'updatedAt': Timestamp.now(),
      });
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '削除失敗: $e');
      }
    }
  }

  /// 受給者証情報のネスト Map を構築（空ならnull）。
  Map<String, dynamic>? _buildRecipientCertificate() {
    final m = <String, dynamic>{};
    if (_recipientStartAt != null) {
      m['startAt'] = Timestamp.fromDate(_recipientStartAt!);
    }
    final num_ = _recipientNumberCtrl.text.trim();
    if (num_.isNotEmpty) m['number'] = num_;
    if (_recipientService.isNotEmpty) m['service'] = _recipientService;
    final lim = int.tryParse(_recipientMonthlyLimitCtrl.text.trim());
    if (lim != null) m['monthlyLimit'] = lim;
    return m.isEmpty ? null : m;
  }

  /// 入会処理 = HUGに登録できる状態にする。HUG画面で必須マークが付いている全項目を要求。
  /// 確認ソース: hug-beesmiley.link/hug/wm/profile_parent.php?mode=edit と
  ///             hug-beesmiley.link/hug/wm/profile_children.php?mode=edit
  List<String> _validateEnrollmentRequirements() {
    final missing = <String>[];
    // 保護者（HUG必須6項目）
    if (_parentLastNameCtrl.text.trim().isEmpty) missing.add('保護者の姓');
    if (_parentFirstNameCtrl.text.trim().isEmpty) missing.add('保護者の名');
    if (_parentKanaCtrl.text.trim().isEmpty) missing.add('保護者のふりがな');
    if (_postalCodeCtrl.text.trim().isEmpty) missing.add('郵便番号');
    if (_prefecture.isEmpty) missing.add('都道府県');
    if (_cityCtrl.text.trim().isEmpty) missing.add('市町村・番地');
    if (_telCtrl.text.trim().isEmpty) missing.add('保護者の電話番号');
    // 児童（HUG必須5項目 + 保護者紐付けは family があればOK）
    if (_childFirstNameCtrl.text.trim().isEmpty) missing.add('児童の名前');
    if (_childKanaCtrl.text.trim().isEmpty) missing.add('児童のふりがな');
    if (_childBirthDate == null) missing.add('児童の生年月日');
    if (_childGender.isEmpty) missing.add('児童の性別');
    if (_allergyCtrl.text.trim().isEmpty) missing.add('アレルギー（無ければ「なし」と入力）');
    // 受給者証（HUG必須4項目）
    if (_recipientStartAt == null) missing.add('受給者証の利用開始日');
    if (_recipientNumberCtrl.text.trim().isEmpty) missing.add('受給者証番号');
    if (_recipientService.isEmpty) missing.add('利用サービス（放デイ/児童発達支援）');
    if (int.tryParse(_recipientMonthlyLimitCtrl.text.trim()) == null) {
      missing.add('負担上限月額');
    }
    return missing;
  }

  Future<void> _convertToFamily() async {
    if (!_isEdit) {
      AppFeedback.warning(context, '先にリードを保存してください');
      return;
    }
    // HUG連携・保護者児童管理に必要な必須項目チェック
    final missing = _validateEnrollmentRequirements();
    if (missing.isNotEmpty) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('入会処理に必要な情報が不足しています'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('以下の項目を入力してから再度お試しください。'),
                  const SizedBox(height: 8),
                  const Text('（HUG への登録に必要な情報です）',
                      style: TextStyle(fontSize: AppTextSize.small)),
                  const SizedBox(height: 12),
                  ...missing.map((m) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                size: 16, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(child: Text('・$m')),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      }
      return;
    }
    final ok = await AppFeedback.confirm(
      context,
      title: '入会処理',
      message: 'このリードのステージを「入会」にします。\nよろしいですか？',
      confirmLabel: '入会処理',
      cancelLabel: 'キャンセル',
    );
    if (ok != true) return;
    try {
      final enrolledAt = DateTime.now();
      // plus_families.children[i] の stage / status / enrolledAt を更新（一発のトランザクション）
      await widget.doc!.reference.update({
        'stage': 'won',
        'status': '入会',
        'enrolledAt': Timestamp.fromDate(enrolledAt),
        'updatedAt': Timestamp.now(),
      });
      if (mounted) {
        setState(() {
          _stage = 'won';
          _enrolledAt = enrolledAt;
        });
        AppFeedback.success(context, '入会処理が完了しました');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '入会処理失敗: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: Text(_isEdit ? 'リード詳細' : '新規リード',
            style:
                const TextStyle(fontSize: AppTextSize.title, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (_isEdit)
            IconButton(
                icon: Icon(Icons.delete_outline, color: AppColors.errorBorder),
                onPressed: _delete),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              if (_isEdit && _stage != 'won')
                Expanded(
                  child: () {
                    // HUG必須項目が全部埋まっていれば「契約完了」緑塗りボタンで目立たせる、
                    // 不足があれば「入会処理」グレー枠（押すとダイアログで不足項目列挙）
                    final missing = _validateEnrollmentRequirements();
                    final ready = missing.isEmpty;
                    if (ready) {
                      return ElevatedButton.icon(
                        onPressed: _convertToFamily,
                        icon: const Icon(Icons.check_circle, size: 20),
                        label: const Text('契約完了',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextSize.bodyMd)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 2,
                        ),
                      );
                    }
                    return OutlinedButton.icon(
                      onPressed: _convertToFamily,
                      icon: const Icon(Icons.how_to_reg, size: 18),
                      label: Text('契約完了 (HUG項目: ${16 - missing.length}/16)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.successDark,
                        side: BorderSide(color: AppColors.successBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    );
                  }(),
                ),
              if (_isEdit && _stage != 'won')
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
                              fontSize: AppTextSize.bodyMd, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
      // v3.5.1: 児童マスタ画面は 1 ペイン化（対応履歴はサイドパネル側に集約済み）。
      body: _buildForm(),
    );
  }

  /// v3.5: 児童マスタ画面（罫線テーブル形式）。
  /// 旧 _buildForm は _buildFormLegacy として保留（dead code、後で削除）。
  Widget _buildForm({bool showActivities = false}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_convertedFamilyId != null && _stage == 'won')
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.successBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '保護者・児童マスタに入会済（ID: $_convertedFamilyId）',
                        style: TextStyle(
                            fontSize: AppTextSize.small,
                            color: AppColors.successDark,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

          // ── [1] 児童基本情報 ──
          _section2('児童基本情報', [
            _tableRowSplit(
                '姓 / 名',
                _plainTextField(_childLastNameCtrl, hint: '姓'),
                _plainTextField(_childFirstNameCtrl, hint: '名'),
                required: true),
            _tableRow('ふりがな', _plainTextField(_childKanaCtrl)),
            _tableRowSplit(
                '生年月日 / 性別',
                _plainDateField(_childBirthDate,
                    (d) => setState(() => _childBirthDate = d),
                    nullable: true),
                _genderSelector()),
            _tableRow('園・学校', _plainTextField(_kindergartenCtrl)),
            _tableRow('学年',
                _plainTextField(_gradeCtrl, hint: '例: 年中、小1'),
                isLast: true),
          ]),

          // ── [2] 保護者情報 ──
          _section2('保護者情報', [
            _tableRowSplit(
                '姓 / 名',
                _plainTextField(_parentLastNameCtrl, hint: '姓'),
                _plainTextField(_parentFirstNameCtrl, hint: '名'),
                required: true),
            _tableRow('ふりがな', _plainTextField(_parentKanaCtrl)),
            _tableRow(
                '電話',
                _plainTextField(_telCtrl,
                    keyboardType: TextInputType.phone),
                required: true),
            _tableRow(
                'メール',
                _plainTextField(_emailCtrl,
                    keyboardType: TextInputType.emailAddress)),
            _tableRow('連絡優先', _channelSelector()),
            _tableRowSplit(
                '郵便番号 / 都道府県',
                _plainTextField(_postalCodeCtrl,
                    keyboardType: TextInputType.number,
                    hint: '251-0042'),
                _prefectureSelector()),
            _tableRow('市町村・番地',
                _plainTextField(_cityCtrl, hint: '藤沢市…'),
                isLast: true),
          ]),

          // ── [3] 受給者証 ──
          _section2('受給者証情報（HUG必須）', [
            _tableRow('受給者証の有無', _permitSelector(),
                isLast: _permitStatus != 'have'),
            if (_permitStatus == 'have') ...[
              _tableRow(
                  '受給者証番号', _plainTextField(_recipientNumberCtrl),
                  required: true),
              _tableRow('サービス種別', _recipientServiceSelector(),
                  required: true),
              _tableRow(
                  '利用開始日',
                  _plainDateField(_recipientStartAt,
                      (d) => setState(() => _recipientStartAt = d),
                      nullable: true),
                  required: true),
              _tableRow(
                  '負担上限月額（円）',
                  _plainTextField(_recipientMonthlyLimitCtrl,
                      keyboardType: TextInputType.number,
                      hint: '4600'),
                  required: true,
                  isLast: true),
            ],
          ]),

          // ── [4] アレルギー・医療情報 ──
          _section2('アレルギー・医療情報', [
            _tableRow('アレルギー',
                _plainTextField(_allergyCtrl, hint: '無ければ「なし」')),
            _tableRow('既往歴', _plainTextField(_medicalHistoryCtrl)),
            _tableRow('診断名', _plainTextField(_diagnosisCtrl),
                isLast: true),
          ]),

          // ── [5] 媒体・流入経路 ──
          _section2('媒体・流入経路', [
            _tableRow('媒体', _sourceDropdown()),
            _tableRow(
                '問い合わせ日',
                _plainDateField(_inquiredAt,
                    (d) => setState(() => _inquiredAt = d)),
                required: true),
            _tableRow(
                '体験日',
                _plainDateField(_trialAt,
                    (d) => setState(() => _trialAt = d),
                    nullable: true),
                isLast: true),
          ]),

          // ── [6] 失注/退会情報（条件付き） ──
          if (_stage == 'lost')
            _section2('失注情報', [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: _lossReasonSelector(),
              ),
              _tableRow('失注詳細', _plainTextField(_lossDetailCtrl)),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                child: CheckboxListTile(
                  value: _reapproachOk,
                  onChanged: (v) =>
                      setState(() => _reapproachOk = v ?? true),
                  title: Text('再アプローチ可',
                      style: TextStyle(
                          fontSize: AppTextSize.body,
                          color: context.colors.textPrimary)),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ]),
          if (_stage == 'withdrawn')
            _section2('退会情報', [
              _tableRow(
                  '退会日',
                  _plainDateField(_withdrawnAt,
                      (d) => setState(() => _withdrawnAt = d),
                      nullable: true),
                  required: true),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: _withdrawReasonSelector(),
              ),
              _tableRow('退会詳細',
                  _plainTextField(_withdrawDetailCtrl),
                  isLast: true),
            ]),

          if (showActivities) ...[
            const SizedBox(height: 16),
            _buildActivitySection(),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // セクションカード + 罫線テーブル ヘルパー（v3.5）
  // ============================================================

  Widget _section2(String title, List<Widget> rows) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: c.scaffoldBgAlt,
              border: Border(bottom: BorderSide(color: c.borderLight)),
            ),
            child: Text(title,
                style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary)),
          ),
          for (final row in rows) row,
        ],
      ),
    );
  }

  Widget _tableRow(String label, Widget input,
      {bool required = false, bool isLast = false}) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom:
                    BorderSide(color: c.borderLight, width: 0.5)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 140,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.scaffoldBgAlt,
                border: Border(
                    right: BorderSide(
                        color: c.borderLight, width: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: c.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (required)
                    Container(
                      margin: const EdgeInsets.only(top: 2, left: 4),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: context.alerts.urgent.icon,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                child: input,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableRowSplit(String label, Widget left, Widget right,
      {bool required = false, bool isLast = false}) {
    return _tableRow(
      label,
      Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 8),
          Expanded(child: right),
        ],
      ),
      required: required,
      isLast: isLast,
    );
  }

  Widget _plainTextField(TextEditingController ctrl,
      {String? hint,
      TextInputType? keyboardType,
      int maxLines = 1}) {
    final c = context.colors;
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style:
          TextStyle(fontSize: AppTextSize.body, color: c.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            fontSize: AppTextSize.body, color: c.textTertiary),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: UnderlineInputBorder(
          borderSide:
              BorderSide(color: AppColors.primary, width: 1.5),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }

  Widget _plainDateField(
      DateTime? value, void Function(DateTime) onPick,
      {bool nullable = false}) {
    final c = context.colors;
    final display = value == null
        ? '未設定'
        : DateFormat('yyyy/M/d', 'ja').format(value);
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2010, 1, 1),
          lastDate: DateTime(2035, 12, 31),
        );
        if (picked != null) onPick(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.event_outlined,
                size: 16, color: c.textTertiary),
            const SizedBox(width: 6),
            Text(display,
                style: TextStyle(
                    fontSize: AppTextSize.body,
                    color: value == null
                        ? c.textTertiary
                        : c.textPrimary)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // _buildFormLegacy（旧仕様、保留中）
  // ============================================================
  // ignore: unused_element
  Widget _buildFormLegacy({bool showActivities = false}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_convertedFamilyId != null && _stage == 'won')
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.successBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('保護者・児童マスタに入会済（ID: $_convertedFamilyId）',
                        style: TextStyle(
                            fontSize: AppTextSize.small,
                            color: AppColors.successDark,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          _section('ステージ'),
          _stageSelector(),
          const SizedBox(height: 8),
          _PhaseStepper(
            stage: _stage,
            hugFilled: 16 - _validateEnrollmentRequirements().length,
            hugTotal: 16,
          ),
          const SizedBox(height: 16),

          // ============================================================
          // ① 体験前（リード受付） — 連絡を取って体験まで持っていく
          // ============================================================
          _phaseHeader('① 体験前', '連絡を取って体験まで持っていく',
              icon: Icons.phone_in_talk_outlined, color: AppColors.info),
          _section('問い合わせ情報'),
          Row(
            children: [
              Expanded(
                  child: _dateField('問い合わせ日', _inquiredAt,
                      (d) => setState(() => _inquiredAt = d),
                      required: true)),
              const SizedBox(width: 8),
              Expanded(child: _sourceDropdown()),
            ],
          ),
          const SizedBox(height: 8),
          _textField('紹介者・媒体詳細', _sourceDetailCtrl,
              hint: '紹介者名・広告キーワードなど'),
          const SizedBox(height: 8),
          _campaignSelector(),
          const SizedBox(height: 12),
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
                  child: _dateField('生年月日', _childBirthDate,
                      (d) => setState(() => _childBirthDate = d),
                      nullable: true)),
              const SizedBox(width: 8),
              Expanded(child: _genderSelector()),
            ],
          ),
          const SizedBox(height: 8),
          _textField('保育園・幼稚園・学校', _kindergartenCtrl),
          const SizedBox(height: 12),
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
          _textField('メール', _emailCtrl,
              keyboardType: TextInputType.emailAddress),
          // F_lead_detail_refactor (Phase 2): LINE ID 入力欄を非表示化。
          // _lineCtrl と保存時の 'parentLine' 書き込みも下記で空文字にして無効化済み。
          const SizedBox(height: 8),
          _channelSelector(),
          const SizedBox(height: 12),
          _section('希望条件・確度'),
          _textField('希望曜日', _preferredDaysCtrl, hint: '例：月・水・金'),
          const SizedBox(height: 8),
          _textField('希望時間帯', _preferredTimeCtrl, hint: '例：放課後 16:00〜'),
          const SizedBox(height: 8),
          _textField('希望開始時期', _preferredStartCtrl, hint: '例：4月〜'),
          const SizedBox(height: 8),
          _confidenceSelector(),
          const SizedBox(height: 24),

          // ============================================================
          // ② 体験後（個別対応）— 体験で得た情報をもとに次のアクションを決める
          // ============================================================
          _phaseHeader('② 体験後', '体験で得た情報を残し、次のアクションを決める',
              icon: Icons.psychology_outlined, color: AppColors.accent),
          _section('体験'),
          _dateField('体験日', _trialAt, (d) => setState(() => _trialAt = d),
              nullable: true),
          const SizedBox(height: 8),
          _textField('体験で分かったこと', _trialNotesCtrl, maxLines: 4),
          const SizedBox(height: 12),
          _section('主訴・特性'),
          _textField('主訴', _mainConcernCtrl, maxLines: 3),
          const SizedBox(height: 8),
          _textField('好きなこと', _likesCtrl, maxLines: 2),
          const SizedBox(height: 8),
          _textField('苦手なこと', _dislikesCtrl, maxLines: 2),
          const SizedBox(height: 12),
          _section('ネクストアクション'),
          Row(
            children: [
              Expanded(
                  child: _dateField('次回対応期日', _nextActionAt,
                      (d) => setState(() => _nextActionAt = d),
                      nullable: true)),
            ],
          ),
          const SizedBox(height: 8),
          _textField('次回内容', _nextActionNoteCtrl,
              maxLines: 2, hint: '例：受給者証取得後に再連絡'),
          const SizedBox(height: 24),

          // ============================================================
          // ③ 入会前（HUG連携必須）— HUGに登録できる状態に整える
          // ============================================================
          _phaseHeader('③ 入会前', 'HUGに登録できる状態に必須項目を整える',
              icon: Icons.assignment_turned_in_outlined,
              color: AppColors.success),
          _section('住所（HUG必須）'),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: _textField('郵便番号', _postalCodeCtrl,
                    keyboardType: TextInputType.number, hint: '例: 251-0042'),
              ),
              const SizedBox(width: 8),
              Expanded(child: _prefectureSelector()),
            ],
          ),
          const SizedBox(height: 8),
          _textField('市町村・番地', _cityCtrl,
              hint: '例: 藤沢市鵠沼桜が岡4-19-3'),
          const SizedBox(height: 8),
          _textField('住所（旧データ・表示専用）', _addressCtrl),
          const SizedBox(height: 12),
          _section('児童（HUG必須）'),
          _textField('アレルギー（無ければ「なし」）', _allergyCtrl),
          const SizedBox(height: 8),
          _permitSelector(),
          const SizedBox(height: 12),
          _section('受給者証情報（HUG必須）'),
          Row(
            children: [
              Expanded(
                child: _dateField('利用開始日', _recipientStartAt,
                    (d) => setState(() => _recipientStartAt = d),
                    nullable: true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _textField('受給者証番号', _recipientNumberCtrl),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _recipientServiceSelector()),
              const SizedBox(width: 8),
              Expanded(
                child: _textField('負担上限月額（円）',
                    _recipientMonthlyLimitCtrl,
                    keyboardType: TextInputType.number, hint: '例: 4600'),
              ),
            ],
          ),
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
                      fontSize: AppTextSize.body, color: context.colors.textPrimary)),
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
                    fontSize: AppTextSize.small, color: context.colors.textTertiary)),
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
                        fontSize: AppTextSize.xs,
                        color: color,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              if (at != null)
                Text(DateFormat('M/d (E) HH:mm', 'ja').format(at),
                    style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w600)),
              const Spacer(),
              if (author.isNotEmpty)
                Text(author,
                    style: TextStyle(
                        fontSize: AppTextSize.xs, color: context.colors.textTertiary)),
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
                      fontSize: AppTextSize.body,
                      color: context.colors.textPrimary,
                      height: 1.4)),
            ),
        ],
      ),
    );
  }

  Color _activityTypeColor(String type) {
    return switch (type) {
      'tel' => AppColors.success,
      'email' => AppColors.info,
      'line' => AppColors.success,
      'visit' => AppColors.aiAccent,
      'task' => AppColors.warning,
      _ => Colors.grey,
    };
  }

  // ---------------------------------------------------------- Form widgets

  Widget _section(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: AppTextSize.body,
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
            TextStyle(fontSize: AppTextSize.small, color: context.colors.textSecondary),
        hintStyle:
            TextStyle(fontSize: AppTextSize.small, color: context.colors.textTertiary),
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
              TextStyle(fontSize: AppTextSize.small, color: context.colors.textSecondary),
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
                    fontSize: AppTextSize.body,
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
              if (s.id == 'withdrawn' && _withdrawnAt == null) {
                _withdrawnAt = DateTime.now();
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
                    fontSize: AppTextSize.small,
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
            TextStyle(fontSize: AppTextSize.small, color: context.colors.textSecondary),
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
              child: Text(s.label, style: const TextStyle(fontSize: AppTextSize.body))))
          .toList(),
      onChanged: (v) => setState(() => _source = v ?? 'other'),
    );
  }

  // F2: 紐付け施策セレクタ。実行中(running)の Campaign のみリストに含める。
  // 既存 Lead の互換性: sourceCampaignId が null なら「（紐付けなし）」、
  // 値があるが該当 campaign が見つからない場合（例: archived 化）は値を保持して表示する。
  Widget _campaignSelector() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // composite index 不要にするため、businessId のみでサーバー側フィルタし、
      // status='running' はクライアント側で絞り込む。
      stream: FirebaseFirestore.instance
          .collection('campaigns')
          .where('businessId', isEqualTo: 'Plus')
          .snapshots(),
      builder: (context, snap) {
        final docs = (snap.data?.docs ?? [])
            .where((d) => (d.data()['status'] as String?) == 'running')
            .toList();
        final items = <DropdownMenuItem<String?>>[
          const DropdownMenuItem(value: null, child: Text('（紐付けなし）')),
          ...docs.map((d) {
            final name = (d.data()['name'] as String?) ?? d.id;
            return DropdownMenuItem(value: d.id, child: Text(name));
          }),
        ];
        // 現在の値が running 一覧に無い場合（archived など）はその id をプレースホルダで追加。
        final ids = docs.map((d) => d.id).toSet();
        if (_sourceCampaignId != null &&
            !ids.contains(_sourceCampaignId)) {
          items.insert(
            1,
            DropdownMenuItem(
                value: _sourceCampaignId,
                child: Text('（過去の施策: $_sourceCampaignId）')),
          );
        }
        return DropdownButtonFormField<String?>(
          initialValue: _sourceCampaignId,
          isDense: true,
          decoration: InputDecoration(
            labelText: '紐付け施策（任意）',
            labelStyle: TextStyle(
                fontSize: AppTextSize.small,
                color: context.colors.textSecondary),
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
          items: items,
          onChanged: (v) => setState(() => _sourceCampaignId = v),
        );
      },
    );
  }

  Widget _genderSelector() {
    // v3.5.1: 罫線テーブル内で使うのでラベル枠は外す。値は「男子/女子」で統一
    // （フォーム取り込みも同じ値を使うため）。「その他」は廃止。
    return Row(
      children: ['男子', '女子'].map((g) {
        final sel = _childGender == g;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(g,
                style: const TextStyle(fontSize: AppTextSize.caption)),
            selected: sel,
            onSelected: (_) =>
                setState(() => _childGender = sel ? '' : g),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        );
      }).toList(),
    );
  }

  Widget _permitSelector() {
    return Row(
      children: [
        Text('受給者証:',
            style: TextStyle(
                fontSize: AppTextSize.small, color: context.colors.textSecondary)),
        const SizedBox(width: 8),
        ...CrmOptions.permitStatus.map((s) {
          final sel = _permitStatus == s.id;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(s.label, style: const TextStyle(fontSize: AppTextSize.caption)),
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

  /// フェーズの見出し（① 体験前 / ② 体験後 / ③ 入会前 など）。
  /// 視覚的に縦長フォームを意味のある塊に分ける。
  Widget _phaseHeader(String label, String subtitle,
      {required IconData icon, required Color color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: AppTextSize.bodyMd,
                        fontWeight: FontWeight.bold,
                        color: color)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: context.colors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _prefectures = [
    '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
    '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
    '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県',
    '岐阜県', '静岡県', '愛知県', '三重県',
    '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県',
    '鳥取県', '島根県', '岡山県', '広島県', '山口県',
    '徳島県', '香川県', '愛媛県', '高知県',
    '福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県',
  ];

  Widget _prefectureSelector() {
    // v3.5.1: 罫線テーブル内で使うのでラベル枠を外し、コンパクトな Dropdown だけに
    final c = context.colors;
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        isDense: true,
        isExpanded: true,
        value: _prefecture.isEmpty ? null : _prefecture,
        hint: Text('選択',
            style: TextStyle(
                fontSize: AppTextSize.body, color: c.textTertiary)),
        style: TextStyle(
            fontSize: AppTextSize.body, color: c.textPrimary),
        items: _prefectures
            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
            .toList(),
        onChanged: (v) => setState(() => _prefecture = v ?? ''),
      ),
    );
  }

  Widget _recipientServiceSelector() {
    const services = [
      ('after_school', '放課後等デイサービス'),
      ('child_dev', '児童発達支援'),
    ];
    return InputDecorator(
      decoration: InputDecoration(
        labelText: '利用サービス',
        labelStyle: TextStyle(fontSize: AppTextSize.small),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          isExpanded: true,
          value: _recipientService,
          items: services
              .map((s) =>
                  DropdownMenuItem(value: s.$1, child: Text(s.$2)))
              .toList(),
          onChanged: (v) => setState(() => _recipientService = v ?? 'after_school'),
        ),
      ),
    );
  }

  Widget _channelSelector() {
    return Row(
      children: [
        Text('連絡優先:',
            style: TextStyle(
                fontSize: AppTextSize.small, color: context.colors.textSecondary)),
        const SizedBox(width: 8),
        ...CrmOptions.channels.map((s) {
          final sel = _preferredChannel == s.id;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(s.label, style: const TextStyle(fontSize: AppTextSize.caption)),
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
                fontSize: AppTextSize.small, color: context.colors.textSecondary)),
        const SizedBox(width: 8),
        ...CrmOptions.confidence.map((s) {
          final sel = _confidence == s.id;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(s.label, style: const TextStyle(fontSize: AppTextSize.caption)),
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
                    fontSize: AppTextSize.small,
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
                    fontSize: AppTextSize.small,
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
                      fontSize: AppTextSize.bodyLarge, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: CrmOptions.activityTypes.map((t) {
                  final sel = _type == t.id;
                  return ChoiceChip(
                    label: Text(t.label, style: const TextStyle(fontSize: AppTextSize.small)),
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
                      style: const TextStyle(fontSize: AppTextSize.body)),
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

/// 4 phase の進捗を上部に表示するステッパー。
/// 体験前 → 体験後 → 入会前 → 入会済 の流れを示し、現在のステージをハイライト。
class _PhaseStepper extends StatelessWidget {
  final String stage;
  final int hugFilled;
  final int hugTotal;
  const _PhaseStepper({
    required this.stage,
    required this.hugFilled,
    required this.hugTotal,
  });

  int get _activeIdx {
    switch (stage) {
      case 'considering':
        return 0;
      case 'onboarding':
        return 2; // ② 体験後 と ③ 入会前 の間（HUG埋まり次第で前後）
      case 'won':
        return 3;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['体験前', '体験後', '入会前', '入会済'];
    final active = _activeIdx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border.all(color: context.colors.borderLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            // 区切り線
            final left = i ~/ 2;
            final isPast = left < active;
            return Expanded(
              child: Container(
                height: 2,
                color: isPast ? AppColors.success : context.colors.borderLight,
              ),
            );
          }
          final idx = i ~/ 2;
          final isActive = idx == active;
          final isPast = idx < active;
          final color = isPast
              ? AppColors.success
              : isActive
                  ? AppColors.primary
                  : context.colors.textTertiary;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isActive || isPast ? color : Colors.transparent,
                  border: Border.all(color: color, width: 2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: isPast
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('${idx + 1}',
                        style: TextStyle(
                            fontSize: AppTextSize.caption,
                            fontWeight: FontWeight.bold,
                            color: isActive ? Colors.white : color)),
              ),
              const SizedBox(height: 2),
              Text(labels[idx],
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                      color: color)),
              if (idx == 2) // 入会前 にHUG進捗
                Text('$hugFilled/$hugTotal',
                    style: TextStyle(
                        fontSize: AppTextSize.caption - 1,
                        color: hugFilled == hugTotal
                            ? AppColors.success
                            : context.colors.textTertiary)),
            ],
          );
        }),
      ),
    );
  }
}
