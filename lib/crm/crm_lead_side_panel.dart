// F_lead_detail_refactor (Phase 2): リード詳細パネル新版。
//
// 概念整理:
// - 「次のアクション」は 1 リードに 1 つだけ（nextActionAt + nextActionNote）
// - メモは 3 種類:
//     (a) 対応履歴 = activities[]（過去の実施記録）
//     (b) 次のアクション = nextActionNote（未来の予定）
//     (c) プロフィールメモ = memo（常時メモ）
//   TODO: memo → profileNote にリネーム（Phase 1 スキーマ移行で実施）
// - 下部アクションは 3 ボタンのみ:
//     ① 履歴を追加  ② 次のアクションを更新  ③ ステージを進める（context 依存）
// - LINE は UI から削除（スキーマ保持）
//
// 旧実装は crm_lead_side_panel_legacy.dart に退避（無参照、1 ヶ月後物理削除）。

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../crm_lead_screen.dart' show CrmOptions, CrmLeadEditScreen;
import '../services/crm_lead_adapter.dart';
import '../widgets/app_feedback.dart';
import 'crm_home_utils.dart';
import 'crm_lead_model.dart';

class CrmLeadSidePanel extends StatefulWidget {
  final LeadView leadView;
  /// null = 閉じるボタン非表示・Esc 無効。
  /// 今日タブで常時表示する場合は null を渡す。
  final VoidCallback? onClose;

  const CrmLeadSidePanel({
    super.key,
    required this.leadView,
    this.onClose,
  });

  @override
  State<CrmLeadSidePanel> createState() => _CrmLeadSidePanelState();
}

class _CrmLeadSidePanelState extends State<CrmLeadSidePanel> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    // 注: markRead はここでは呼ばない。CrmHomeScreen は wide モードで
    // リスト先頭を自動選択するため、initState で既読化すると新規リードを
    // 視認する前にバッジが消えてしまう。既読化は明示クリック側（onSelectLead /
    // _LeadTableRow.onTap / CrmLeadEditScreen.initState）で行う。
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return KeyboardListener(
      focusNode: _focus,
      onKeyEvent: (event) {
        if (widget.onClose != null &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose!();
        }
      },
      child: Material(
        // panel 全体は scaffoldBgAlt（v3）。各セクションは cardBg で浮き出る。
        color: c.scaffoldBgAlt,
        elevation: 8,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.leadView.familyRef.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()));
            }
            if (!snap.data!.exists) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('リードが見つかりません',
                          style: TextStyle(color: c.textSecondary))));
            }
            final familyData = snap.data!.data();
            final children = (familyData?['children'] as List? ?? []);
            final idx = widget.leadView.childIndex;
            if (familyData == null || idx < 0 || idx >= children.length) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('リードが見つかりません',
                          style: TextStyle(color: c.textSecondary))));
            }
            final child = Map<String, dynamic>.from(children[idx] as Map);
            final flat = flattenChildToLeadShape(
                widget.leadView.familyDocId, familyData, child);
            final lead = CrmLead(
                id: widget.leadView.id,
                raw: flat,
                ref: widget.leadView.reference);
            return _PanelBody(
              lead: lead,
              leadRef: widget.leadView.reference,
              onClose: widget.onClose,
            );
          },
        ),
      ),
    );
  }
}

/// パネル本体。Header (固定) + スクロール領域 + 下部 3 ボタン (固定)。
class _PanelBody extends StatelessWidget {
  final CrmLead lead;
  final LeadViewReference leadRef;
  final VoidCallback? onClose;
  const _PanelBody({
    required this.lead,
    required this.leadRef,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(lead: lead, onClose: onClose),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProgressSection(lead: lead, leadRef: leadRef),
                const SizedBox(height: 12),
                _NextActionSection(lead: lead, leadRef: leadRef),
                const SizedBox(height: 12),
                _HistorySection(lead: lead, leadRef: leadRef),
                const SizedBox(height: 12),
                // v2.1+: 児童プロフィール（ケア情報含む）は基本情報セクションに集約済み。
                _BasicInfoSection(lead: lead, leadRef: leadRef),
              ],
            ),
          ),
        ),
        _BottomActions(lead: lead, leadRef: leadRef),
      ],
    );
  }
}

// ============================================================
// Header
// ============================================================
class _Header extends StatelessWidget {
  final CrmLead lead;
  final VoidCallback? onClose;
  const _Header({required this.lead, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // v3 改善 2: childLastName 空なら parentLastName を fallback。
    final lastName = lead.childLastName.isNotEmpty
        ? lead.childLastName
        : lead.parentLastName;
    final fullName = lastName.isEmpty && lead.childFirstName.isEmpty
        ? '（名前未登録）'
        : '$lastName ${lead.childFirstName}'.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      decoration: BoxDecoration(
        color: c.scaffoldBg,
        border: Border(bottom: BorderSide(color: c.borderLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    fullName,
                    style: TextStyle(
                        fontSize: AppTextSize.title,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _StagePill(stage: lead.stage),
                if (lead.parentTel.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        final uri = Uri.parse(
                            'tel:${lead.parentTel.replaceAll(RegExp(r"[^0-9+]"), "")}');
                        await launchUrl(uri);
                      },
                      child: Text(
                        lead.parentTel,
                        style: TextStyle(
                            fontSize: AppTextSize.body,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // v2 Step 3c: 編集ボタンを Header 右側に常時表示。
          FilledButton.tonalIcon(
            onPressed: () => _openLeadEditScreen(context, lead),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('編集'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: AppTextSize.small),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: c.textSecondary,
              tooltip: '閉じる (Esc)',
              onPressed: onClose,
            ),
          ],
        ],
      ),
    );
  }
}

class _StagePill extends StatelessWidget {
  final String stage;
  const _StagePill({required this.stage});

  @override
  Widget build(BuildContext context) {
    final color = CrmOptions.stageColor(stage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        CrmOptions.stageLabel(stage),
        style: TextStyle(
            fontSize: AppTextSize.caption,
            fontWeight: FontWeight.bold,
            color: color),
      ),
    );
  }
}

// ============================================================
// ============================================================
// 基本情報セクション（最下部、備考＝memo を含む）
// ============================================================
class _BasicInfoSection extends StatefulWidget {
  final CrmLead lead;
  final LeadViewReference leadRef;
  const _BasicInfoSection({required this.lead, required this.leadRef});

  @override
  State<_BasicInfoSection> createState() => _BasicInfoSectionState();
}

class _BasicInfoSectionState extends State<_BasicInfoSection> {
  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final c = context.colors;
    final leadRef = widget.leadRef;
    return _SectionCard(
      frameless: true,
      icon: Icons.contact_mail_outlined,
      title: '基本情報',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 連絡先 ──
          _editableNameRow(context, '保護者',
              lead.parentLastName, lead.parentFirstName, leadRef),
          _editablePhoneRow(context, '電話', lead.parentTel, leadRef),
          _editableEmailRow(context, 'メール', lead.parentEmail, leadRef),
          _editableSourceRow(context, '媒体', lead.source, leadRef),

          const SizedBox(height: 6),
          Divider(height: 1, color: c.borderLight),
          const SizedBox(height: 6),

          // ── 児童属性 ──
          _editableBirthDateRow(
              context, '生年月日', lead.childBirthDate, leadRef),
          _editableGenderRow(context, '性別', lead.childGender ?? '', leadRef),
          _editableSinglelineRow(context, '園', lead.kindergarten,
              'kindergarten', '◯◯幼稚園', leadRef),
          _editableSinglelineRow(context, '学年', lead.grade,
              'grade', '年中', leadRef),

          const SizedBox(height: 8),
          Divider(height: 1, color: c.borderLight),
          const SizedBox(height: 8),

          // ── アンケート + ヒアリング 2 層構造 ──
          _twoLayerField(context, '主訴',
              lead.mainConcern, lead.mainConcernHearing,
              'mainConcern', 'mainConcernHearing', leadRef),
          _twoLayerField(context, '好きなこと',
              lead.likes, lead.likesHearing,
              'likes', 'likesHearing', leadRef),
          _twoLayerField(context, '苦手なこと',
              lead.dislikes, lead.dislikesHearing,
              'dislikes', 'dislikesHearing', leadRef),
          _twoLayerField(context, '既往歴',
              lead.medicalHistory, lead.medicalHistoryHearing,
              'medicalHistory', 'medicalHistoryHearing', leadRef),
          _twoLayerField(context, '診断名',
              lead.diagnosis, lead.diagnosisHearing,
              'diagnosis', 'diagnosisHearing', leadRef),

          const SizedBox(height: 8),
          Divider(height: 1, color: c.borderLight),
          const SizedBox(height: 8),

          // ── 体験メモ（独立、2層化しない） ──
          _editableMultiline(context, '体験メモ', lead.trialNotes,
              'trialNotes', '発語は単語のみ 等', leadRef),
          // ── 備考 ──
          _editableMultiline(context, '備考', lead.memo, 'memo',
              'アレルギー、家庭事情、保護者意向など', leadRef),
        ],
      ),
    );
  }

  // ── 共通ヘルパー ──

  Widget _labelCol(BuildContext context, String label) {
    final c = context.colors;
    return SizedBox(
      width: 60,
      child: Text(label,
          style: TextStyle(
              fontSize: AppTextSize.caption, color: c.textSecondary)),
    );
  }

  /// 1 行テキスト編集（汎用）
  Widget _editableSinglelineRow(BuildContext context, String label,
      String value, String fieldKey, String hint, LeadViewReference leadRef) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _labelCol(context, label),
          Expanded(
            child: _InlineTextEditor(
              key: ValueKey('$fieldKey:$value'),
              initialText: value,
              hint: hint.isEmpty ? '未入力' : hint,
              maxLines: 1,
              onCommit: (text) async {
                if (text == value) return;
                await leadRef.update({fieldKey: text});
                if (mounted) {
                  AppFeedback.success(context, '$label を保存しました');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 複数行テキスト編集（既存・体験メモ・備考用）
  Widget _editableMultiline(BuildContext context, String label, String value,
      String fieldKey, String hint, LeadViewReference leadRef) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _labelCol(context, label),
          Expanded(
            child: _InlineTextEditor(
              key: ValueKey('$fieldKey:$value'),
              initialText: value,
              hint: hint.isEmpty ? '未入力' : hint,
              onCommit: (text) async {
                if (text == value) return;
                await leadRef.update({fieldKey: text});
                if (mounted) {
                  AppFeedback.success(context, '$label を保存しました');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 保護者氏名: 姓名を 1 つの欄で編集、保存時にスペース分割。
  Widget _editableNameRow(BuildContext context, String label,
      String last, String first, LeadViewReference leadRef) {
    final fullName = '$last $first'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _labelCol(context, label),
          Expanded(
            child: _InlineTextEditor(
              key: ValueKey('parentName:$fullName'),
              initialText: fullName,
              hint: '姓 名（スペース区切り）',
              maxLines: 1,
              onCommit: (text) async {
                if (text.trim() == fullName) return;
                final parts = text
                    .trim()
                    .split(RegExp(r'[\s　]+'))
                    .where((p) => p.isNotEmpty)
                    .toList();
                final newLast = parts.isNotEmpty ? parts.first : '';
                final newFirst =
                    parts.length > 1 ? parts.sublist(1).join('') : '';
                await leadRef.update({
                  'parentLastName': newLast,
                  'parentFirstName': newFirst,
                });
                if (mounted) {
                  AppFeedback.success(context, '保護者名を保存しました');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 電話: 編集テキスト + 発信アイコン分離
  Widget _editablePhoneRow(BuildContext context, String label,
      String tel, LeadViewReference leadRef) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _labelCol(context, label),
          Expanded(
            child: _InlineTextEditor(
              key: ValueKey('parentTel:$tel'),
              initialText: tel,
              hint: '09000000000',
              maxLines: 1,
              keyboardType: TextInputType.phone,
              onCommit: (text) async {
                if (text == tel) return;
                await leadRef.update({'parentTel': text});
                if (mounted) {
                  AppFeedback.success(context, '電話番号を保存しました');
                }
              },
            ),
          ),
          if (tel.isNotEmpty)
            IconButton(
              icon: Icon(Icons.phone_outlined,
                  size: 18, color: AppColors.primary),
              tooltip: '電話発信',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () async {
                final uri = Uri.parse(
                    'tel:${tel.replaceAll(RegExp(r"[^0-9+]"), "")}');
                final ok = await launchUrl(uri);
                if (!ok && mounted) {
                  await Clipboard.setData(ClipboardData(text: tel));
                  if (mounted) {
                    AppFeedback.info(
                        context, '電話発信できないためコピーしました: $tel');
                  }
                }
              },
            ),
        ],
      ),
    );
  }

  /// メール: 編集テキスト + メーラー起動アイコン分離
  Widget _editableEmailRow(BuildContext context, String label,
      String email, LeadViewReference leadRef) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _labelCol(context, label),
          Expanded(
            child: _InlineTextEditor(
              key: ValueKey('parentEmail:$email'),
              initialText: email,
              hint: 'name@example.com',
              maxLines: 1,
              keyboardType: TextInputType.emailAddress,
              onCommit: (text) async {
                if (text == email) return;
                await leadRef.update({'parentEmail': text});
                if (mounted) {
                  AppFeedback.success(context, 'メールを保存しました');
                }
              },
            ),
          ),
          if (email.isNotEmpty)
            IconButton(
              icon: Icon(Icons.mail_outline,
                  size: 18, color: AppColors.primary),
              tooltip: 'メール送信',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => launchUrl(Uri.parse('mailto:$email')),
            ),
        ],
      ),
    );
  }

  /// 媒体: ドロップダウン選択
  Widget _editableSourceRow(BuildContext context, String label,
      String value, LeadViewReference leadRef) {
    final c = context.colors;
    final options = CrmOptions.sources;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _labelCol(context, label),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: options.any((o) => o.id == value) ? value : null,
                isDense: true,
                hint: Text('未選択',
                    style: TextStyle(
                        fontSize: AppTextSize.body, color: c.textTertiary)),
                style: TextStyle(
                    fontSize: AppTextSize.body, color: c.textPrimary),
                items: [
                  for (final o in options)
                    DropdownMenuItem(
                      value: o.id,
                      child: Text(o.label),
                    ),
                ],
                onChanged: (v) async {
                  if (v == null || v == value) return;
                  await leadRef.update({'source': v});
                  if (mounted) {
                    AppFeedback.success(context, '媒体を保存しました');
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 生年月日: 日付ピッカー
  Widget _editableBirthDateRow(BuildContext context, String label,
      DateTime? value, LeadViewReference leadRef) {
    final c = context.colors;
    final display = value == null
        ? '未設定'
        : DateFormat('yyyy/M/d', 'ja').format(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _labelCol(context, label),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: value ?? DateTime(2020, 1, 1),
                  firstDate: DateTime(2010, 1, 1),
                  lastDate: DateTime.now(),
                );
                if (picked == null) return;
                final ts = Timestamp.fromDate(
                    DateTime(picked.year, picked.month, picked.day));
                await leadRef.update({'childBirthDate': ts});
                if (mounted) {
                  AppFeedback.success(context, '生年月日を保存しました');
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(display,
                    style: TextStyle(
                        fontSize: AppTextSize.body,
                        color: value == null
                            ? c.textTertiary
                            : c.textPrimary)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 性別: ChoiceChip 風の3択
  Widget _editableGenderRow(BuildContext context, String label,
      String value, LeadViewReference leadRef) {
    const choices = [
      ('男子', '男子'),
      ('女子', '女子'),
      ('その他', 'その他'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _labelCol(context, label),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                for (final (label2, v) in choices)
                  ChoiceChip(
                    label: Text(label2,
                        style: const TextStyle(
                            fontSize: AppTextSize.caption)),
                    selected: value == v,
                    onSelected: (s) async {
                      if (!s) return;
                      await leadRef.update({'childGender': v});
                      if (mounted) {
                        AppFeedback.success(context, '性別を保存しました');
                      }
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// アンケート + ヒアリング 2 層構造（v3.2: 左右レイアウト・案A）
  /// 左にアンケート（保護者の自記）、右にヒアリング（スタッフ追記）。
  /// サイドパネル幅を 67% に拡大したことで横並びが現実的に。
  Widget _twoLayerField(BuildContext context, String label,
      String intakeValue, String hearingValue,
      String intakeKey, String hearingKey, LeadViewReference leadRef) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 項目ラベル
          Text(label,
              style: TextStyle(
                  fontSize: AppTextSize.caption,
                  color: c.textSecondary,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _layerColumn(
                  context,
                  tagLabel: 'アンケート',
                  tagBg: c.scaffoldBgAlt,
                  tagFg: c.textSecondary,
                  value: intakeValue,
                  fieldKey: intakeKey,
                  hint: '保護者からの自記',
                  leadRef: leadRef,
                  humanLabel: '$label（アンケート）',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _layerColumn(
                  context,
                  tagLabel: 'ヒアリング',
                  tagBg: AppColors.primary.withValues(alpha: 0.15),
                  tagFg: AppColors.primary,
                  value: hearingValue,
                  fieldKey: hearingKey,
                  hint: 'ヒアリングで深掘りした内容',
                  leadRef: leadRef,
                  humanLabel: '$label（ヒアリング）',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 左右カラムの中身（タグ + 編集欄）。
  Widget _layerColumn(
    BuildContext context, {
    required String tagLabel,
    required Color tagBg,
    required Color tagFg,
    required String value,
    required String fieldKey,
    required String hint,
    required LeadViewReference leadRef,
    required String humanLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: tagBg,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(tagLabel,
                style: TextStyle(
                    fontSize: AppTextSize.xs,
                    fontWeight: FontWeight.bold,
                    color: tagFg)),
          ),
        ),
        const SizedBox(height: 4),
        _InlineTextEditor(
          key: ValueKey('$fieldKey:$value'),
          initialText: value,
          hint: hint,
          onCommit: (text) async {
            if (text == value) return;
            await leadRef.update({fieldKey: text});
            if (mounted) {
              AppFeedback.success(context, '$humanLabel を保存しました');
            }
          },
        ),
      ],
    );
  }
}

// ============================================================
// 次のアクションセクション（強調表示）
// ============================================================
class _NextActionSection extends StatelessWidget {
  final CrmLead lead;
  final LeadViewReference leadRef;
  const _NextActionSection({required this.lead, required this.leadRef});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final na = lead.nextActionAt;
    final note = lead.nextActionNote;
    final overdue = na != null && DateTime.now().isAfter(na);
    return _SectionCard(
      frameless: true,
      icon: Icons.flag_outlined,
      title: '次のアクション',
      titleColor: overdue ? AppColors.warning : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 内容エリア全体をクリックで編集（鉛筆アイコンを廃止）
          InkWell(
            onTap: () => _showUpdateNextActionDialog(context, lead, leadRef),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: na == null && note.isEmpty
                  ? Text('次のアクションが未設定です（クリックで設定）',
                      style: TextStyle(
                          fontSize: AppTextSize.body,
                          color: c.textTertiary,
                          fontStyle: FontStyle.italic))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (na != null)
                          Row(
                            children: [
                              Icon(
                                  overdue ? Icons.warning_amber : Icons.event,
                                  size: 16,
                                  color: overdue
                                      ? AppColors.warning
                                      : c.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('yyyy/M/d (E)', 'ja').format(na),
                                style: TextStyle(
                                    fontSize: AppTextSize.body,
                                    fontWeight: FontWeight.w600,
                                    color: overdue
                                        ? AppColors.warning
                                        : c.textPrimary),
                              ),
                              if (overdue) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('期限超過',
                                      style: TextStyle(
                                          fontSize: AppTextSize.xs,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(note,
                              style: TextStyle(
                                  fontSize: AppTextSize.body,
                                  color: c.textPrimary)),
                        ],
                      ],
                    ),
            ),
          ),
          if (na != null || note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () =>
                    _showCompleteNextActionDialog(context, lead, leadRef),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('完了して次を入力'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: AppTextSize.small),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// 対応履歴セクション（+ 追加ボタン付き）
// ============================================================
class _HistorySection extends StatelessWidget {
  final CrmLead lead;
  final LeadViewReference leadRef;
  const _HistorySection({required this.lead, required this.leadRef});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final activities = lead.activities.take(20).toList();
    return _SectionCard(
      frameless: true,
      icon: Icons.history,
      title: '対応履歴',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${lead.activities.length}件',
              style: TextStyle(
                  fontSize: AppTextSize.caption, color: c.textTertiary)),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: '履歴を追加',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _showAddHistoryDialog(context, lead, leadRef),
          ),
        ],
      ),
      child: activities.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('履歴はまだありません',
                  style: TextStyle(
                      fontSize: AppTextSize.body,
                      color: c.textTertiary,
                      fontStyle: FontStyle.italic)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final a in activities) _ActivityTile(activity: a),
              ],
            ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final CrmActivity activity;
  const _ActivityTile({required this.activity});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at =
        activity.at == null ? '' : DateFormat('M/d', 'ja').format(activity.at!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(at,
                style: TextStyle(
                    fontSize: AppTextSize.caption,
                    color: c.textTertiary)),
          ),
          Expanded(
            child: Text(
              activity.body.isEmpty ? '（内容なし）' : activity.body,
              style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: activity.body.isEmpty
                      ? c.textTertiary
                      : c.textPrimary,
                  fontStyle:
                      activity.body.isEmpty ? FontStyle.italic : null),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 下部固定アクション（ステージを進める のみ）
// ============================================================
class _BottomActions extends StatelessWidget {
  final CrmLead lead;
  final LeadViewReference leadRef;
  const _BottomActions({required this.lead, required this.leadRef});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.borderLight)),
      ),
      // 履歴追加・次のアクション更新は各セクションのアイコンに移動。
      // 下部はステージ進行のみ。
      child: _StageAdvanceButton(lead: lead, leadRef: leadRef),
    );
  }
}

class _StageAdvanceButton extends StatelessWidget {
  final CrmLead lead;
  final LeadViewReference leadRef;
  const _StageAdvanceButton({required this.lead, required this.leadRef});

  @override
  Widget build(BuildContext context) {
    final stage = lead.stage;
    String label;
    IconData icon;
    VoidCallback? primary;
    final hasLost = stage == 'considering' || stage == 'onboarding';

    switch (stage) {
      case 'considering':
        label = '入会手続き開始';
        icon = Icons.assignment_turned_in_outlined;
        primary = () => _showStartOnboardingDialog(context, lead, leadRef);
        break;
      case 'onboarding':
        label = '入会完了';
        icon = Icons.check_circle_outline;
        primary = () => _showWonDialog(context, lead, leadRef);
        break;
      case 'won':
        label = '退会処理';
        icon = Icons.logout;
        primary = () => _showWithdrawDialog(context, lead, leadRef);
        break;
      case 'lost':
        label = '検討中に戻す';
        icon = Icons.undo;
        primary = () => _reopenToConsidering(context, lead, leadRef);
        break;
      default:
        label = 'ステージ進行';
        icon = Icons.arrow_forward;
        primary = null;
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: primary,
            icon: Icon(icon, size: 16),
            label: Text(label, overflow: TextOverflow.ellipsis),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              textStyle: const TextStyle(fontSize: AppTextSize.small),
            ),
          ),
        ),
        if (hasLost)
          PopupMenuButton<String>(
            tooltip: 'その他',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (v) {
              if (v == 'lost') _showLostDialog(context, lead, leadRef);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'lost', child: Text('失注として記録')),
            ],
          ),
      ],
    );
  }
}

// ============================================================
// セクション共通カード
// ============================================================
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? titleColor;
  final Widget? trailing;
  final Widget child;
  /// 枠なし表示。タイトル + 本文のみ、背景・ボーダーなし。
  final bool frameless;
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.titleColor,
    this.trailing,
    this.frameless = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleRow = Row(
      children: [
        Icon(icon, size: 16, color: titleColor ?? c.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: AppTextSize.small,
                  fontWeight: FontWeight.w700,
                  color: titleColor ?? c.textPrimary)),
        ),
        if (trailing != null) trailing!,
      ],
    );
    // frameless = タイトルは枠外、本文は枠内
    if (frameless) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: titleRow,
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.borderLight),
            ),
            child: child,
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleRow,
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ============================================================
// 共通: 編集画面起動
// ============================================================
void _openLeadEditScreen(BuildContext context, CrmLead lead) {
  final parts = lead.id.split('#');
  if (parts.length != 2) return;
  final familyId = parts[0];
  final idx = int.tryParse(parts[1]) ?? 0;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CrmLeadEditScreen(
        doc: LeadView(
          familyDocId: familyId,
          childIndex: idx,
          flatData: lead.raw,
          familyRef: FirebaseFirestore.instance
              .collection('plus_families')
              .doc(familyId),
        ),
      ),
    ),
  );
}

// ============================================================
// アクションモーダル
// ============================================================

/// 履歴を追加（type / outcome / 内容）
Future<void> _showAddHistoryDialog(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  String type = 'tel';
  final body = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        title: const Text('履歴を追加'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(
                  labelText: '種別', border: OutlineInputBorder(), isDense: true),
                items: CrmOptions.activityTypes
                    .map((t) =>
                        DropdownMenuItem(value: t.id, child: Text(t.label)))
                    .toList(),
                onChanged: (v) => setS(() => type = v ?? 'tel'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: body,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '内容', border: OutlineInputBorder(), isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('追加')),
        ],
      );
    }),
  );
  if (ok != true) return;
  // 既存 activities 配列に prepend（model 側で降順ソートされる）
  final existing = (lead.raw['activities'] as List?)?.cast<dynamic>() ?? [];
  final entry = {
    'id': 'a_${DateTime.now().millisecondsSinceEpoch}',
    'type': type,
    'body': body.text.trim(),
    'at': Timestamp.now(),
    'authorId': user?.uid ?? '',
    'authorName': user?.displayName ?? '',
  };
  await leadRef.update({
    'activities': [...existing, entry],
    'lastActivityAt': Timestamp.now(),
  });
  if (context.mounted) AppFeedback.success(context, '履歴を追加しました');
}

/// 次のアクションの種別マスタ。
/// applicableStages: ステージで絞り込み（'*' = 全ステージ）
/// defaultDueDays: 種別選択時に「今日 + N 日」を期日デフォルトに
/// icon: ピル左に表示する絵文字（任意）
const _nextActionTypes = <({
  String id,
  String label,
  String icon,
  List<String> applicableStages,
  int defaultDueDays,
})>[
  // 検討中（v3: 業務フロー反映）
  (id: 'visit_other_facility', label: '他施設見学', icon: '🏫',
      applicableStages: ['considering'], defaultDueDays: 7),
  (id: 'family_consultation', label: '家族で相談', icon: '👨‍👩‍👧',
      applicableStages: ['considering'], defaultDueDays: 3),
  (id: 'day_increase_request', label: '日数増枠対応', icon: '📈',
      applicableStages: ['considering'], defaultDueDays: 3),
  (id: 'other_facility_withdrawal', label: '他事業所退所手続き', icon: '🚪',
      applicableStages: ['considering'], defaultDueDays: 7),
  (id: 'recipient_cert_application', label: '受給者証申請', icon: '📋',
      applicableStages: ['considering'], defaultDueDays: 14),
  (id: 'attendance_schedule_adjust', label: '通所日程調整', icon: '📅',
      applicableStages: ['considering'], defaultDueDays: 3),
  // 入会手続中（v3: 進捗を進めるための汎用カテゴリ。
  //  項目自体は進捗チェックリスト 5 項目で達成記録、ここはその補助アクション）
  (id: 'contact_confirm', label: '連絡・確認', icon: '📞',
      applicableStages: ['onboarding'], defaultDueDays: 3),
  (id: 'schedule_adjust', label: '日程調整', icon: '🗓️',
      applicableStages: ['onboarding'], defaultDueDays: 3),
  (id: 'document_creation', label: '書類作成', icon: '📝',
      applicableStages: ['onboarding'], defaultDueDays: 7),
  (id: 'meeting_adjust', label: '会議調整', icon: '👥',
      applicableStages: ['onboarding'], defaultDueDays: 7),
  // 全ステージ共通
  (id: 'status_check', label: '状況確認', icon: '💬',
      applicableStages: ['*'], defaultDueDays: 7),
  (id: 'other', label: 'その他', icon: '📝',
      applicableStages: ['*'], defaultDueDays: 7),
];

/// 次のアクションを更新（種別ピッカー + 日付 + メモ）。
/// v3: カスタム Dialog でデザイン刷新（種別をアイコン付きカードのグリッド表示）。
Future<void> _showUpdateNextActionDialog(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  String? typeId = lead.nextActionType;
  DateTime when =
      lead.nextActionAt ?? DateTime.now().add(const Duration(days: 1));
  final note = TextEditingController(text: lead.nextActionNote);
  final stage = lead.stage;
  // ステージに応じた選択肢
  final available = _nextActionTypes
      .where((t) =>
          t.applicableStages.contains('*') ||
          t.applicableStages.contains(stage))
      .toList();

  final childName = lead.childFullName.isEmpty ? '名前未登録' : lead.childFullName;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final c = ctx.colors;
      return Dialog(
        backgroundColor: c.cardBg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ヘッダ
                Row(
                  children: [
                    Icon(Icons.flag_outlined,
                        size: 22, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('次のアクションを更新',
                              style: TextStyle(
                                fontSize: AppTextSize.title,
                                fontWeight: FontWeight.bold,
                                color: c.textPrimary,
                              )),
                          const SizedBox(height: 2),
                          Text(childName,
                              style: TextStyle(
                                fontSize: AppTextSize.caption,
                                color: c.textSecondary,
                              )),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx, false),
                      tooltip: 'キャンセル',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: c.borderLight, height: 1),
                const SizedBox(height: 20),

                // ─── 種別 ───
                _dialogSectionLabel(context, '種別', required: true),
                const SizedBox(height: 8),
                LayoutBuilder(builder: (ctx, cons) {
                  // 1 行 3 列のグリッド（最小幅 140px）
                  final cols = cons.maxWidth >= 480 ? 3 : 2;
                  const spacing = 8.0;
                  final itemW =
                      (cons.maxWidth - spacing * (cols - 1)) / cols;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final t in available)
                        SizedBox(
                          width: itemW,
                          child: _NextActionTypeCard(
                            label: t.label,
                            icon: t.icon,
                            selected: typeId == t.id,
                            onTap: () => setS(() {
                              typeId = t.id;
                              when = DateTime.now()
                                  .add(Duration(days: t.defaultDueDays));
                            }),
                          ),
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 24),

                // ─── 期日 ───
                _dialogSectionLabel(context, '期日'),
                const SizedBox(height: 8),
                _DialogDateButton(
                  date: when,
                  onPick: () async {
                    final d = await showDatePicker(
                        context: ctx,
                        initialDate: when,
                        firstDate: DateTime(2024, 1, 1),
                        lastDate: DateTime(2030, 12, 31));
                    if (d == null) return;
                    setS(() => when = DateTime(d.year, d.month, d.day));
                  },
                ),
                const SizedBox(height: 24),

                // ─── メモ ───
                _dialogSectionLabel(context, 'メモ'),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  maxLines: 4,
                  minLines: 3,
                  style: TextStyle(
                      fontSize: AppTextSize.body, color: c.textPrimary),
                  decoration: InputDecoration(
                    hintText: '補足や前提共有など（任意）',
                    hintStyle: TextStyle(color: c.textTertiary),
                    filled: true,
                    fillColor: c.scaffoldBgAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.borderLight),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.borderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 24),

                // ─── アクション ───
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: Text('キャンセル',
                            style: TextStyle(
                                fontSize: AppTextSize.body,
                                color: c.textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        if (typeId == null) {
                          AppFeedback.warning(ctx, '種別を選択してください');
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      child: Text('更新',
                          style: TextStyle(
                              fontSize: AppTextSize.body,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }),
  );
  if (ok != true) return;
  // typeId が選択されていれば label を nextActionNote のデフォルトとして使う
  final label = available.firstWhere((t) => t.id == typeId,
      orElse: () => available.last);
  final saveNote = note.text.trim().isEmpty ? label.label : note.text.trim();
  await leadRef.update({
    'nextActionAt': Timestamp.fromDate(when),
    'nextActionNote': saveNote,
    'nextActionType': typeId,
  });
  if (context.mounted) AppFeedback.success(context, '次のアクションを更新しました');
}

/// ダイアログ内のセクション小見出し（必須マーク対応）。
Widget _dialogSectionLabel(BuildContext context, String label,
    {bool required = false}) {
  final c = context.colors;
  return Row(
    children: [
      Text(label,
          style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.bold,
              color: c.textPrimary)),
      if (required) ...[
        const SizedBox(width: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: context.alerts.urgent.background,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text('必須',
              style: TextStyle(
                  fontSize: AppTextSize.xs,
                  fontWeight: FontWeight.bold,
                  color: context.alerts.urgent.icon)),
        ),
      ],
    ],
  );
}

/// 種別カード（アイコン + ラベル）。選択時はprimary色で強調。
class _NextActionTypeCard extends StatelessWidget {
  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;
  const _NextActionTypeCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : c.scaffoldBgAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : c.borderLight,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTextSize.caption,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.w500,
                    color:
                        selected ? AppColors.primary : c.textPrimary,
                  ),
                  maxLines: 2,
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

/// 期日ピッカーボタン（フル幅、明示的な期日表示）。
class _DialogDateButton extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPick;
  const _DialogDateButton({required this.date, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);
    final diff = dateDay.difference(today).inDays;
    final relative = diff == 0
        ? '今日'
        : diff == 1
            ? '明日'
            : diff > 0
                ? '$diff日後'
                : '${-diff}日前';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.scaffoldBgAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.borderLight),
          ),
          child: Row(
            children: [
              Icon(Icons.event, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(
                DateFormat('yyyy/M/d (E)', 'ja').format(date),
                style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(relative,
                    style: TextStyle(
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
              const Spacer(),
              Icon(Icons.arrow_drop_down,
                  size: 20, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 完了 + 次のアクション必須入力
Future<void> _showCompleteNextActionDialog(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  // 完了履歴記録 + 新しい次のアクションを入力
  DateTime when = DateTime.now().add(const Duration(days: 3));
  final note = TextEditingController();
  final completedNote =
      TextEditingController(text: '【完了】${lead.nextActionNote}');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        title: const Text('次のアクションを完了'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('完了内容（履歴に追加）',
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: context.colors.textSecondary)),
              const SizedBox(height: 4),
              TextField(
                controller: completedNote,
                maxLines: 2,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), isDense: true),
              ),
              const Divider(height: 24),
              Text('次のアクション（必須）',
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      fontWeight: FontWeight.bold,
                      color: AppColors.warning)),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 16),
                label: Text(DateFormat('yyyy/M/d (E)', 'ja').format(when)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: when,
                      firstDate: DateTime(2024, 1, 1),
                      lastDate: DateTime(2030, 12, 31));
                  if (d == null) return;
                  setS(() => when = DateTime(d.year, d.month, d.day, when.hour, when.minute));
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: '内容（空にできません）',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () {
                if (note.text.trim().isEmpty) {
                  AppFeedback.warning(ctx, '次のアクションの内容は必須です');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('完了')),
        ],
      );
    }),
  );
  if (ok != true) return;
  final user = FirebaseAuth.instance.currentUser;
  final existing = (lead.raw['activities'] as List?)?.cast<dynamic>() ?? [];
  final entry = {
    'id': 'a_${DateTime.now().millisecondsSinceEpoch}',
    'type': 'memo',
    'body': completedNote.text.trim(),
    'at': Timestamp.now(),
    'authorId': user?.uid ?? '',
    'authorName': user?.displayName ?? '',
    'outcome': 'completed',
  };
  await leadRef.update({
    'activities': [...existing, entry],
    'lastActivityAt': Timestamp.now(),
    'nextActionAt': Timestamp.fromDate(when),
    'nextActionNote': note.text.trim(),
  });
  if (context.mounted) AppFeedback.success(context, '次のアクションを完了しました');
}

/// 入会手続き開始モーダル
Future<void> _showStartOnboardingDialog(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  DateTime contractDate =
      lead.enrolledAt ?? DateTime.now().add(const Duration(days: 14));
  final preferredStart =
      TextEditingController(text: (lead.raw['preferredStart'] as String?) ?? '');
  String permitStatus =
      (lead.raw['permitStatus'] as String?) ?? 'none';
  DateTime nextActionAt = DateTime.now().add(const Duration(days: 2));
  final nextActionNote = TextEditingController(text: '契約書送付');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        title: const Text('入会手続きを開始'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('契約予定日',
                    style: TextStyle(fontSize: AppTextSize.caption)),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(DateFormat('yyyy/M/d (E)', 'ja').format(contractDate)),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: ctx,
                        initialDate: contractDate,
                        firstDate: DateTime(2024, 1, 1),
                        lastDate: DateTime(2030, 12, 31));
                    if (d != null) setS(() => contractDate = d);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: preferredStart,
                  decoration: const InputDecoration(
                      labelText: '希望通所開始日', hintText: '6月から / 4/15 など',
                      border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: permitStatus,
                  decoration: const InputDecoration(
                      labelText: '受給者証ステータス',
                      border: OutlineInputBorder(), isDense: true),
                  items: CrmOptions.permitStatus
                      .map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.label)))
                      .toList(),
                  onChanged: (v) => setS(() => permitStatus = v ?? 'none'),
                ),
                const Divider(height: 24),
                Text('1 つ目の次のアクション', style: TextStyle(fontSize: AppTextSize.caption)),
                Wrap(
                  spacing: 6,
                  children: ['契約書送付', '契約日確定の連絡', '受給者証申請サポート']
                      .map((s) => ActionChip(
                            label: Text(s, style: const TextStyle(fontSize: AppTextSize.caption)),
                            onPressed: () => setS(() => nextActionNote.text = s),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(DateFormat('M/d (E)', 'ja').format(nextActionAt)),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: ctx,
                        initialDate: nextActionAt,
                        firstDate: DateTime(2024, 1, 1),
                        lastDate: DateTime(2030, 12, 31));
                    if (d == null) return;
                    setS(() => nextActionAt = DateTime(d.year, d.month, d.day));
                  },
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: nextActionNote,
                  decoration: const InputDecoration(
                      labelText: '内容', border: OutlineInputBorder(), isDense: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () {
                if (nextActionNote.text.trim().isEmpty) {
                  AppFeedback.warning(ctx, '次のアクションの内容は必須です');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('開始')),
        ],
      );
    }),
  );
  if (ok != true) return;
  // v4: ステージ遷移時に checklistDates を空にリセット（新ステージ用に再入力）。
  // firstContactedAt / trialAt / trialActualDate は履歴として残す。
  await leadRef.update({
    'stage': 'onboarding',
    // 契約予定日は Phase 1 で別フィールド化予定。今は enrolledAt に格納。
    'enrolledAt': Timestamp.fromDate(contractDate),
    'preferredStart': preferredStart.text.trim(),
    'permitStatus': permitStatus,
    'nextActionAt': Timestamp.fromDate(nextActionAt),
    'nextActionNote': nextActionNote.text.trim(),
    'checklistDates': <String, dynamic>{},
  });
  if (context.mounted) AppFeedback.success(context, '入会手続きを開始しました');
}

/// 入会完了
Future<void> _showWonDialog(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  DateTime wonDate = DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        title: const Text('入会完了'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('入会日を選択してください',
                  style: TextStyle(fontSize: AppTextSize.caption)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 16),
                label: Text(DateFormat('yyyy/M/d (E)', 'ja').format(wonDate)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: wonDate,
                      firstDate: DateTime(2024, 1, 1),
                      lastDate: DateTime(2030, 12, 31));
                  if (d != null) setS(() => wonDate = d);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('入会完了')),
        ],
      );
    }),
  );
  if (ok != true) return;
  await leadRef.update({
    'stage': 'won',
    'enrolledAt': Timestamp.fromDate(wonDate),
  });
  if (context.mounted) AppFeedback.success(context, '入会を完了しました');
}

/// 退会処理（理由必須）
Future<void> _showWithdrawDialog(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  String? reason;
  final detail = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        title: const Text('退会処理'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(
                    labelText: '退会理由（必須）',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: CrmOptions.withdrawalReasons
                    .map((r) =>
                        DropdownMenuItem(value: r.id, child: Text(r.label)))
                    .toList(),
                onChanged: (v) => setS(() => reason = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: detail,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: '詳細', border: OutlineInputBorder(), isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () {
                if (reason == null) {
                  AppFeedback.warning(ctx, '退会理由を選択してください');
                  return;
                }
                if (reason == 'other' && detail.text.trim().isEmpty) {
                  AppFeedback.warning(ctx, '退会理由「その他」の詳細を入力してください');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('退会')),
        ],
      );
    }),
  );
  if (ok != true) return;
  await leadRef.update({
    'stage': 'withdrawn',
    'withdrawnAt': Timestamp.now(),
    'withdrawReason': reason,
    'withdrawDetail': detail.text.trim(),
  });
  if (context.mounted) AppFeedback.success(context, '退会処理を記録しました');
}

/// 失注として記録（理由必須）
Future<void> _showLostDialog(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  String? reason;
  final detail = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        title: const Text('失注として記録'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(
                    labelText: '失注理由（必須）',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: CrmOptions.lossReasons
                    .map((r) =>
                        DropdownMenuItem(value: r.id, child: Text(r.label)))
                    .toList(),
                onChanged: (v) => setS(() => reason = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: detail,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: '詳細', border: OutlineInputBorder(), isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () {
                if (reason == null) {
                  AppFeedback.warning(ctx, '失注理由を選択してください');
                  return;
                }
                if (reason == 'other' && detail.text.trim().isEmpty) {
                  AppFeedback.warning(ctx, '失注理由「その他」の詳細を入力してください');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('失注')),
        ],
      );
    }),
  );
  if (ok != true) return;
  await leadRef.update({
    'stage': 'lost',
    'lostAt': Timestamp.now(),
    'lossReason': reason,
    'lossDetail': detail.text.trim(),
  });
  if (context.mounted) AppFeedback.success(context, '失注として記録しました');
}

/// 失注からの差し戻し
Future<void> _reopenToConsidering(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  final ok = await AppFeedback.confirm(context,
      title: '検討中に戻す', message: '失注を取り消して「検討中」に戻しますか？');
  if (!ok) return;
  await leadRef.update({
    'stage': 'considering',
    'lostAt': null,
    'lossReason': null,
    'lossDetail': '',
  });
  if (context.mounted) AppFeedback.success(context, '検討中に戻しました');
}

// ============================================================
// 進捗セクション（v4: 日程セクション統合・各項目に日付を持たせる）
// ============================================================

/// チェックリスト項目。
/// - dateField != null  : Lead の既存 Timestamp フィールドを直接読み書き
/// - dateField == null  : checklistDates マップに id をキーで保存
/// - hasNote == true    : checklistNotes に内容メモを保存（事前ヒアリング等）
typedef _ChecklistItem = ({
  String id,
  String label,
  String? dateField,
  bool hasNote,
});

/// 検討中フェーズ（5 項目）。
/// アンケート回収はフォーム自動取り込みで自動チェック（surveyReceivedAt が非 null）。
const _checklistConsidering = <_ChecklistItem>[
  (id: 'inquired', label: '問い合わせ受付', dateField: 'inquiredAt', hasNote: false),
  (id: 'trial_scheduled', label: '体験日決定', dateField: 'trialAt', hasNote: false),
  (id: 'survey_received', label: 'アンケート回収', dateField: 'surveyReceivedAt', hasNote: false),
  (id: 'trial_completed', label: '体験実施', dateField: 'trialActualDate', hasNote: false),
  (id: 'intent_confirmed', label: '入会意向の確認', dateField: null, hasNote: false),
];

/// 入会手続中フェーズ（v3: 5 項目固定、業務フロー反映）。
const _checklistOnboarding = <_ChecklistItem>[
  (id: 'assessment_hearing_date_set', label: 'アセスメントヒアリング日決定',
      dateField: null, hasNote: false),
  (id: 'contract_date_set', label: '契約日決定',
      dateField: null, hasNote: false),
  (id: 'assessment_created', label: 'アセスメント作成',
      dateField: null, hasNote: false),
  (id: 'support_plan_created', label: '個別支援計画書作成',
      dateField: null, hasNote: false),
  (id: 'planning_meeting_done', label: '策定会議',
      dateField: null, hasNote: false),
];

List<_ChecklistItem> _checklistFor(String stage) {
  return stage == 'onboarding' ? _checklistOnboarding : _checklistConsidering;
}

DateTime? _dateFor(_ChecklistItem item, CrmLead lead) {
  if (item.dateField != null) {
    return (lead.raw[item.dateField] as Timestamp?)?.toDate();
  }
  return lead.checklistDates[item.id];
}

class _ProgressSection extends StatelessWidget {
  final CrmLead lead;
  final LeadViewReference leadRef;
  const _ProgressSection({required this.lead, required this.leadRef});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stage = lead.stage;
    if (stage != 'considering' && stage != 'onboarding') {
      return const SizedBox.shrink(); // won/lost/withdrawn では非表示
    }
    final items = _checklistFor(stage);
    final permit = lead.permitStatus;

    return _SectionCard(
      frameless: true,
      icon: Icons.checklist_rtl,
      title: '進捗',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                    width: 80,
                    child: Text('受給者証',
                        style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: c.textSecondary))),
                DropdownButton<String>(
                  value: permit,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    color: c.textPrimary,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('無')),
                    DropdownMenuItem(value: 'applying', child: Text('申請中')),
                    DropdownMenuItem(value: 'have', child: Text('有')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await leadRef.update({'permitStatus': v});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final item in items) _itemRow(context, item),
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, _ChecklistItem item) {
    final c = context.colors;
    final date = _dateFor(item, lead);
    final done = date != null;
    final display = date == null
        ? '未設定'
        : DateFormat('yyyy/M/d (E)', 'ja').format(date);
    final note = item.hasNote ? (lead.checklistNotes[item.id] ?? '') : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _editDate(context, item, date),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: done ? AppColors.success : c.textTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.label,
                      style: TextStyle(
                          fontSize: AppTextSize.body, color: c.textPrimary)),
                ),
                Text(
                  display,
                  style: TextStyle(
                    fontSize: AppTextSize.caption,
                    color: done ? c.textSecondary : c.textTertiary,
                    fontStyle: done ? null : FontStyle.italic,
                  ),
                ),
                if (done) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _clearDate(context, item),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 14, color: c.textTertiary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (item.hasNote)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 4, 8),
            child: _InlineTextEditor(
              key: ValueKey('note-${item.id}-${note.hashCode}'),
              initialText: note,
              hint: '${item.label}の内容を入力',
              onCommit: (v) => _writeNote(item, v),
            ),
          ),
      ],
    );
  }

  Future<void> _writeNote(_ChecklistItem item, String value) async {
    final next = Map<String, dynamic>.from(
        (lead.raw['checklistNotes'] as Map?) ?? {});
    if (value.trim().isEmpty) {
      next.remove(item.id);
    } else {
      next[item.id] = value.trim();
    }
    await leadRef.update({'checklistNotes': next});
  }

  Future<void> _editDate(
      BuildContext context, _ChecklistItem item, DateTime? current) async {
    final picked = await _quickPickDate(
      context,
      title: '${item.label} の日付を選択',
      initial: current ?? DateTime.now(),
    );
    if (picked == null) return;
    await _writeDate(item, picked);
    if (context.mounted) {
      AppFeedback.success(context, '${item.label} を更新しました');
    }
  }

  Future<void> _clearDate(BuildContext context, _ChecklistItem item) async {
    await _writeDate(item, null);
    if (context.mounted) {
      AppFeedback.success(context, '${item.label} をクリアしました');
    }
  }

  Future<void> _writeDate(_ChecklistItem item, DateTime? date) async {
    if (item.dateField != null) {
      await leadRef.update({
        item.dateField!: date == null ? FieldValue.delete() : Timestamp.fromDate(date),
      });
    } else {
      final next = Map<String, dynamic>.from(
          (lead.raw['checklistDates'] as Map?) ?? {});
      if (date == null) {
        next.remove(item.id);
      } else {
        next[item.id] = Timestamp.fromDate(date);
      }
      await leadRef.update({'checklistDates': next});
    }
  }
}

// ============================================================
// 待ち状態セクション（reason / deadline / note。null なら CTA のみ）
// ============================================================

/// 日付選択ダイアログ（タップ即決定）。OK ボタン不要、キャンセルのみ。
Future<DateTime?> _quickPickDate(
  BuildContext context, {
  required String title,
  required DateTime initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) {
      return Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(title,
                    style: TextStyle(
                        fontSize: AppTextSize.body,
                        fontWeight: FontWeight.w600,
                        color: ctx.colors.textSecondary)),
              ),
              CalendarDatePicker(
                initialDate: initial,
                firstDate: firstDate ?? DateTime(2024, 1, 1),
                lastDate: lastDate ?? DateTime(2030, 12, 31),
                onDateChanged: (d) => Navigator.of(ctx).pop(d),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('キャンセル'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// インライン編集 TextField。focus 喪失時に自動コミット。
/// 未 focus 時はテキスト表示風（border なし）、focus 時は通常の TextField スタイル。
class _InlineTextEditor extends StatefulWidget {
  final String initialText;
  final String hint;
  final int? maxLines; // null = 自動拡張
  final TextInputType? keyboardType;
  final Future<void> Function(String) onCommit;
  const _InlineTextEditor({
    super.key,
    required this.initialText,
    required this.hint,
    required this.onCommit,
    this.maxLines,
    this.keyboardType,
  });

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _focus = FocusNode();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() => _focused = _focus.hasFocus);
    if (!_focus.hasFocus) {
      // blur 時に commit
      final text = _ctrl.text.trim();
      widget.onCommit(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      maxLines: widget.maxLines, // null = 自動拡張
      minLines: 1,
      keyboardType: widget.keyboardType,
      style: TextStyle(
          fontSize: AppTextSize.body,
          color: _ctrl.text.isEmpty ? c.textTertiary : c.textPrimary),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(
            fontSize: AppTextSize.body,
            color: c.textTertiary,
            fontStyle: FontStyle.italic),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: _focused
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: c.borderMedium))
            : InputBorder.none,
        enabledBorder: _focused
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: c.borderMedium))
            : InputBorder.none,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        filled: _focused,
        fillColor: _focused ? c.cardBg : null,
      ),
    );
  }
}

