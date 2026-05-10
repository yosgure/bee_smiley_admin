// F_lead_detail_refactor (Phase 2): リード詳細パネル新版。
//
// 概念整理:
// - 「次の一手」は 1 リードに 1 つだけ（nextActionAt + nextActionNote）
// - メモは 3 種類:
//     (a) 対応履歴 = activities[]（過去の実施記録）
//     (b) 次の一手 = nextActionNote（未来の予定）
//     (c) プロフィールメモ = memo（常時メモ）
//   TODO: memo → profileNote にリネーム（Phase 1 スキーマ移行で実施）
// - 下部アクションは 3 ボタンのみ:
//     ① 履歴を追加  ② 次の一手を更新  ③ ステージを進める（context 依存）
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
  // インライン編集化に伴い _editingMemo / _memoCtrl / _saveMemo は廃止。
  // 備考は _editableMultiline (_InlineTextEditor) で blur 自動保存。

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final c = context.colors;
    return _SectionCard(
      frameless: true,
      icon: Icons.contact_mail_outlined,
      title: '基本情報',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lead.parentFullName.isNotEmpty)
            _row(context, '保護者', lead.parentFullName),
          if (lead.parentTel.isNotEmpty)
            _phoneRow(context, '電話', lead.parentTel),
          if (lead.parentEmail.isNotEmpty)
            _emailRow(context, 'メール', lead.parentEmail),
          _row(
              context,
              '媒体',
              CrmOptions.labelOf(CrmOptions.sources, lead.source)),
          // ── 児童の属性（v2.1: 客観 + ケア情報を集約） ──
          const SizedBox(height: 6),
          Divider(height: 1, color: c.borderLight),
          const SizedBox(height: 6),
          if (lead.childBirthDate != null)
            _row(context, '生年月日',
                DateFormat('yyyy/M/d', 'ja').format(lead.childBirthDate!)),
          if (lead.childGender != null && lead.childGender!.isNotEmpty)
            _row(context, '性別', _genderLabelStatic(lead.childGender!)),
          if (lead.kindergarten.isNotEmpty)
            _row(context, '園', lead.kindergarten),
          // ケア情報（旧 児童プロフィール）
          _editableMultiline(context, '主訴', lead.mainConcern,
              'mainConcern', '困りごと・相談内容', widget.leadRef),
          _editableMultiline(context, '好きなこと', lead.likes, 'likes',
              'トング、コーヒーミル 等', widget.leadRef),
          _editableMultiline(context, '苦手なこと', lead.dislikes, 'dislikes',
              '風船バレー、音過敏 等', widget.leadRef),
          _editableMultiline(context, '体験メモ', lead.trialNotes,
              'trialNotes', '発語は単語のみ 等', widget.leadRef),
          // 備考: インライン編集（blur で自動保存）。
          _editableMultiline(context, '備考', lead.memo, 'memo',
              'アレルギー、家庭事情、保護者意向など', widget.leadRef),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 60,
              child: Text(label,
                  style: TextStyle(
                      fontSize: AppTextSize.caption, color: c.textSecondary))),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: AppTextSize.body, color: c.textPrimary)),
          ),
        ],
      ),
    );
  }

  /// インライン編集（ポップアップを使わず、直接 TextField で編集）。
  /// blur (focus 喪失) で自動保存。
  Widget _editableMultiline(BuildContext context, String label, String value,
      String fieldKey, String hint, LeadViewReference leadRef) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
              width: 60,
              child: Text(label,
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textSecondary))),
          Expanded(
            child: _InlineTextEditor(
              key: ValueKey('$fieldKey:$value'),
              initialText: value,
              hint: '未入力',
              onCommit: (text) async {
                if (text == value) return; // 無変更は保存しない
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

  Widget _phoneRow(BuildContext context, String label, String tel) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 60,
              child: Text(label,
                  style: TextStyle(
                      fontSize: AppTextSize.caption, color: c.textSecondary))),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final uri = Uri.parse('tel:${tel.replaceAll(RegExp(r"[^0-9+]"), "")}');
                final ok = await launchUrl(uri);
                if (!ok && context.mounted) {
                  await Clipboard.setData(ClipboardData(text: tel));
                  if (context.mounted) {
                    AppFeedback.info(context, '電話発信できないためコピーしました: $tel');
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(tel,
                    style: TextStyle(
                        fontSize: AppTextSize.body,
                        color: AppColors.primary,
                        decoration: TextDecoration.underline)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emailRow(BuildContext context, String label, String email) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 60,
              child: Text(label,
                  style: TextStyle(
                      fontSize: AppTextSize.caption, color: c.textSecondary))),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => launchUrl(Uri.parse('mailto:$email')),
              child: Text(email,
                  style: TextStyle(
                      fontSize: AppTextSize.body,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 次の一手セクション（強調表示）
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
      title: '次の一手',
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
                  ? Text('次の一手が未設定です（クリックで設定）',
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
      // 履歴追加・次の一手更新は各セクションのアイコンに移動。
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

/// F_lead_detail_refactor v2: 次の一手の種別マスタ。
/// applicableStages: ステージで絞り込み（'*' = 全ステージ）
/// defaultDueDays: 種別選択時に「今日 + N 日」を期日デフォルトに
const _nextActionTypes = <({
  String id,
  String label,
  List<String> applicableStages,
  int defaultDueDays
})>[
  (id: 'trial_schedule', label: '体験日程',
      applicableStages: ['considering'], defaultDueDays: 3),
  (id: 'trial_reminder', label: '体験リマインド',
      applicableStages: ['considering'], defaultDueDays: 1),
  (id: 'trial_followup', label: '体験後フォロー',
      applicableStages: ['considering'], defaultDueDays: 1),
  (id: 'recipient_cert_check', label: '受給者証確認',
      applicableStages: ['considering', 'onboarding'], defaultDueDays: 7),
  (id: 'contract_send', label: '契約書送付',
      applicableStages: ['onboarding'], defaultDueDays: 1),
  (id: 'contract_receive', label: '契約書回収',
      applicableStages: ['onboarding'], defaultDueDays: 7),
  (id: 'enrollment_date_confirm', label: '入会日確定',
      applicableStages: ['onboarding'], defaultDueDays: 3),
  (id: 'recipient_cert_copy', label: '受給者証コピー受領',
      applicableStages: ['onboarding'], defaultDueDays: 7),
  (id: 'status_check', label: '状況確認',
      applicableStages: ['*'], defaultDueDays: 7),
  (id: 'other', label: 'その他',
      applicableStages: ['*'], defaultDueDays: 7),
];

/// 次の一手を更新（種別ピッカー + 日付 + 補足）
Future<void> _showUpdateNextActionDialog(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  String? typeId = lead.nextActionType;
  DateTime when = lead.nextActionAt ?? DateTime.now().add(const Duration(days: 1));
  final note = TextEditingController(text: lead.nextActionNote);
  final stage = lead.stage;
  // ステージに応じた選択肢
  final available = _nextActionTypes
      .where((t) =>
          t.applicableStages.contains('*') ||
          t.applicableStages.contains(stage))
      .toList();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        title: const Text('次の一手を更新'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('種別（必須）',
                    style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: context.colors.textSecondary)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in available)
                      ChoiceChip(
                        label: Text(t.label,
                            style:
                                const TextStyle(fontSize: AppTextSize.caption)),
                        selected: typeId == t.id,
                        onSelected: (_) => setS(() {
                          typeId = t.id;
                          // 種別選択時に期日を自動セット（既存の手動値があればそれを優先）
                          when = DateTime.now()
                              .add(Duration(days: t.defaultDueDays));
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
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
                    setS(() => when = DateTime(d.year, d.month, d.day));
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: typeId == 'other' ? '補足（必須）' : '補足（任意）',
                      hintText: '電話で日程確認、契約書送付 など',
                      border: const OutlineInputBorder(),
                      isDense: true),
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
                if (typeId == null) {
                  AppFeedback.warning(ctx, '種別を選択してください');
                  return;
                }
                if (typeId == 'other' && note.text.trim().isEmpty) {
                  AppFeedback.warning(ctx, '「その他」は補足が必須です');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('更新')),
        ],
      );
    }),
  );
  if (ok != true) return;
  // typeId が選択されていれば label を補足デフォルトとして使う
  final label = available.firstWhere((t) => t.id == typeId,
      orElse: () => available.last);
  final saveNote = note.text.trim().isEmpty ? label.label : note.text.trim();
  await leadRef.update({
    'nextActionAt': Timestamp.fromDate(when),
    'nextActionNote': saveNote,
    'nextActionType': typeId,
  });
  if (context.mounted) AppFeedback.success(context, '次の一手を更新しました');
}

/// 完了 + 次の一手必須入力
Future<void> _showCompleteNextActionDialog(
    BuildContext context, CrmLead lead, LeadViewReference leadRef) async {
  // 完了履歴記録 + 新しい次の一手を入力
  DateTime when = DateTime.now().add(const Duration(days: 3));
  final note = TextEditingController();
  final completedNote =
      TextEditingController(text: '【完了】${lead.nextActionNote}');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        title: const Text('次の一手を完了'),
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
              Text('次の一手（必須）',
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
                  AppFeedback.warning(ctx, '次の一手の内容は必須です');
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
  if (context.mounted) AppFeedback.success(context, '次の一手を完了しました');
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
                Text('1 つ目の次の一手', style: TextStyle(fontSize: AppTextSize.caption)),
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
                  AppFeedback.warning(ctx, '次の一手の内容は必須です');
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

/// 検討中フェーズ（6 項目）。
const _checklistConsidering = <_ChecklistItem>[
  (id: 'inquired', label: '問い合わせ日', dateField: 'inquiredAt', hasNote: false),
  (id: 'pre_trial_hearing', label: '事前ヒアリング', dateField: null, hasNote: false),
  (id: 'trial_scheduled', label: '体験日程', dateField: 'trialAt', hasNote: false),
  (id: 'trial_completed', label: '体験実施', dateField: 'trialActualDate', hasNote: false),
  (id: 'post_trial_followup', label: '体験後フォロー連絡', dateField: null, hasNote: false),
  (id: 'intent_confirmed', label: '入会意向の確認', dateField: null, hasNote: false),
];

/// 入会手続中フェーズ（7 項目）。
const _checklistOnboarding = <_ChecklistItem>[
  (id: 'file_created', label: 'ファイル作成', dateField: null, hasNote: false),
  (id: 'hug_registered', label: 'Hug 入力', dateField: null, hasNote: false),
  (id: 'assessment_done', label: 'アセスメント', dateField: null, hasNote: false),
  (id: 'contract_sent', label: '契約書送付', dateField: null, hasNote: false),
  (id: 'contract_received', label: '契約書回収', dateField: null, hasNote: false),
  (id: 'support_plan_created', label: '個別支援計画作成', dateField: null, hasNote: false),
  (id: 'support_plan_explained', label: '個別支援計画説明', dateField: null, hasNote: false),
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

/// 性別ラベル変換（v2.1: 基本情報セクションからも参照する top-level 関数）。
String _genderLabelStatic(String g) {
  switch (g) {
    case 'male':
      return '男';
    case 'female':
      return '女';
    default:
      return 'その他';
  }
}

/// インライン編集 TextField。focus 喪失時に自動コミット。
/// 未 focus 時はテキスト表示風（border なし）、focus 時は通常の TextField スタイル。
class _InlineTextEditor extends StatefulWidget {
  final String initialText;
  final String hint;
  final Future<void> Function(String) onCommit;
  const _InlineTextEditor({
    super.key,
    required this.initialText,
    required this.hint,
    required this.onCommit,
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
      maxLines: null,
      minLines: 1,
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

