import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../crm_lead_screen.dart' show CrmOptions;
import 'crm_home_utils.dart';

/// v2.1: 3 カラムレイアウト + 左端ステータスバー + 種別アイコン。
/// 左カラム: 名前 + 年齢 + ステージバッジ
/// 中央カラム: 種別アイコン + ラベル（最も目立つ）
/// 右カラム: 期日（今日/明日/N日超過/未設定 で色分け）
class CrmLeadCardCompact extends StatelessWidget {
  final CrmUrgentRow row;
  final bool selected;
  final VoidCallback onTap;
  const CrmLeadCardCompact({
    super.key,
    required this.row,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lead = row.lead;
    final age = lead.childAge;
    // v3 名前 fallback
    final lastName = lead.childLastName.isNotEmpty
        ? lead.childLastName
        : lead.parentLastName;
    final firstName = lead.childFirstName;
    final name = lastName.isEmpty && firstName.isEmpty
        ? '（名前未登録）'
        : '$lastName $firstName'.trim();

    // 期日関連
    final na = lead.nextActionAt;
    final waiting = lead.isWaiting;
    final statusColor = _statusBarColor(na, waiting);
    final due = _dueDisplay(context, na);

    // 種別アイコン + ラベル
    final typeId = lead.nextActionType;
    final actionLabel = lead.nextActionNote.isNotEmpty
        ? lead.nextActionNote
        : '次の一手を決める';
    final typeIcon = _iconForType(typeId);
    final isUnset = na == null && lead.nextActionNote.isEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: selected ? c.scaffoldBgAlt : c.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: c.scaffoldBgAlt.withValues(alpha: 0.7),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ステータスバー（左端 5px）
                  Container(width: 5, color: statusColor),
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 左カラム（誰）— flex 4
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: AppTextSize.body,
                                          fontWeight: FontWeight.w600,
                                          color: c.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (age != null) ...[
                                      const SizedBox(width: 4),
                                      Text('$age歳',
                                          style: TextStyle(
                                              fontSize: AppTextSize.caption,
                                              color: c.textTertiary)),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                _stageBadge(context, lead.stage),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 中央カラム（何を）— flex 6、最も目立たせる
                          Expanded(
                            flex: 6,
                            child: Row(
                              children: [
                                Text(typeIcon,
                                    style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    actionLabel,
                                    style: TextStyle(
                                      fontSize: AppTextSize.body,
                                      fontWeight: isUnset
                                          ? FontWeight.normal
                                          : FontWeight.w600,
                                      color: isUnset
                                          ? c.textTertiary
                                          : c.textPrimary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 右カラム（いつ）— flex 3
                          SizedBox(
                            width: 64,
                            child: Text(
                              due.text,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: AppTextSize.caption,
                                fontWeight: due.bold
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: due.color,
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _stageBadge(BuildContext context, String stage) {
    final color = CrmOptions.stageColor(stage);
    final label = CrmOptions.stageLabel(stage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTextSize.xs,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// v2.1: ステータスバー色。待ち状態 > 期日状態の優先順。
Color _statusBarColor(DateTime? na, bool waiting) {
  if (waiting) return const Color(0xFFA855F7); // 紫
  if (na == null) return const Color(0xFF9CA3AF); // グレー
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final naDay = DateTime(na.year, na.month, na.day);
  final diff = naDay.difference(today).inDays;
  if (diff <= 0) return const Color(0xFFEF4444); // 赤（今日 / 過去）
  if (diff <= 3) return const Color(0xFFF59E0B); // オレンジ
  return const Color(0xFF3B82F6); // 青
}

/// 期日表示（テキスト + 色 + 太字）
({String text, Color color, bool bold}) _dueDisplay(
    BuildContext context, DateTime? na) {
  final c = context.colors;
  if (na == null) {
    return (text: '⚠️ 未設定', color: c.textTertiary, bold: false);
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final naDay = DateTime(na.year, na.month, na.day);
  final diff = naDay.difference(today).inDays;
  if (diff < 0) {
    return (
      text: '${-diff}日超過',
      color: const Color(0xFFEF4444),
      bold: true
    );
  }
  if (diff == 0) {
    return (text: '今日', color: const Color(0xFFEF4444), bold: true);
  }
  if (diff == 1) {
    return (text: '明日', color: const Color(0xFFF59E0B), bold: true);
  }
  return (
    text: DateFormat('M/d (E)', 'ja').format(na),
    color: c.textSecondary,
    bold: false,
  );
}

/// 種別 ID → アイコン
String _iconForType(String? typeId) {
  switch (typeId) {
    case 'trial_schedule':
    case 'trial_reminder':
    case 'trial_followup':
      return '📅';
    case 'contract_send':
    case 'contract_receive':
      return '📄';
    case 'recipient_cert_check':
    case 'recipient_cert_copy':
      return '📋';
    case 'enrollment_date_confirm':
      return '✅';
    case 'status_check':
      return '📞';
    case 'pre_trial_hearing':
      return '🎧';
    case 'other':
      return '📝';
    default:
      return '⚠️';
  }
}
