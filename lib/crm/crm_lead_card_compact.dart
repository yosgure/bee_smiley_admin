import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../crm_lead_screen.dart' show CrmOptions;
import 'crm_home_utils.dart';

/// 「今日」タブの中央リストで使う 2 行コンパクトカード。
///
/// レイアウト:
///   行1: {名前} {年齢}    [ステージバッジ]              {最終接触}
///   行2: {督促理由}        {媒体} ・ {担当 or "担当未設定"}
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
    // 名前 fallback (F_today_tab_polish_v2 Step 3d): childLastName が空なら
    // parentLastName を使う。兄弟は同じ姓という一般的仮定を活用。
    final lastName = lead.childLastName.isNotEmpty
        ? lead.childLastName
        : lead.parentLastName;
    final firstName = lead.childFirstName;
    final name = lastName.isEmpty && firstName.isEmpty
        ? '（名前未登録）'
        : '$lastName $firstName'.trim();
    final assignee = lead.assigneeName?.isNotEmpty == true
        ? lead.assigneeName!
        : '担当未設定';
    final source = CrmOptions.sources
        .firstWhere(
          (s) => s.id == lead.source,
          orElse: () => (id: 'other', label: 'その他'),
        )
        .label;
    final lastContact =
        crmRelativeTime(lead.lastContactAt ?? lead.inquiredAt);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: selected ? c.scaffoldBgAlt : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: c.scaffoldBgAlt.withValues(alpha: 0.7),
          child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(
                color: c.borderLight.withValues(alpha: 0.5),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 行1: 名前 + 年齢 + ステージバッジ + 最終接触
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: AppTextSize.titleSm,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (age != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '$age歳',
                            style: TextStyle(
                              fontSize: AppTextSize.caption,
                              color: c.textTertiary,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        _stageBadge(context, lead.stage),
                      ],
                    ),
                  ),
                  Text(
                    lastContact,
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 行2: 督促理由 + 媒体 ・ 担当
              Row(
                children: [
                  Expanded(
                    child: Text(
                      crmUrgentReasonLabel(row.topReason),
                      style: TextStyle(
                        fontSize: AppTextSize.body,
                        color: c.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$source ・ $assignee',
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
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
