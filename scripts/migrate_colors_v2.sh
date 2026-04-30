#!/usr/bin/env bash
# ============================================================
# Colors.<color>.shade* / .withOpacity / 紫系 を AppColors の
# トーン違いトークンへ置換する 2 周目の移行スクリプト。
#
# マッピング:
#   Colors.red.shade50/100/200      → AppColors.errorBg
#   Colors.red.shade300/400         → AppColors.errorBorder
#   Colors.red.shade500/600/700     → AppColors.error
#   Colors.red.shade800/900         → AppColors.errorDark
#   Colors.red.withOpacity(...)     → AppColors.error.withValues(alpha: ...)
#   Colors.red.withValues(...)      → AppColors.error.withValues(...)
#   green / orange / blue / purple も同様（purple は aiAccent 系）
# ============================================================

set -euo pipefail

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  files=()
  while IFS= read -r line; do
    files+=("$line")
  done < <(find lib -type f -name '*.dart' \
    ! -path 'lib/app_theme.dart' \
    ! -path 'lib/widgets/app_feedback.dart')
fi

EXEMPT='(app_theme\.dart|widgets/app_feedback\.dart)$'

for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue
  [[ "$f" =~ $EXEMPT ]] && continue

  perl -i -pe '
    # red
    s/Colors\.red\.shade(50|100|200)\b/AppColors.errorBg/g;
    s/Colors\.red\.shade(300|400)\b/AppColors.errorBorder/g;
    s/Colors\.red\.shade(500|600|700)\b/AppColors.error/g;
    s/Colors\.red\.shade(800|900)\b/AppColors.errorDark/g;
    s/Colors\.red\.(withOpacity|withValues)/AppColors.error.$1/g;
    # green
    s/Colors\.green\.shade(50|100|200)\b/AppColors.successBg/g;
    s/Colors\.green\.shade(300|400)\b/AppColors.successBorder/g;
    s/Colors\.green\.shade(500|600|700)\b/AppColors.success/g;
    s/Colors\.green\.shade(800|900)\b/AppColors.successDark/g;
    s/Colors\.green\.(withOpacity|withValues)/AppColors.success.$1/g;
    # orange / amber
    s/Colors\.orange\.shade(50|100|200)\b/AppColors.warningBg/g;
    s/Colors\.orange\.shade(300|400)\b/AppColors.warningBorder/g;
    s/Colors\.orange\.shade(500|600|700)\b/AppColors.warning/g;
    s/Colors\.orange\.shade(800|900)\b/AppColors.warningDark/g;
    s/Colors\.orange\.(withOpacity|withValues)/AppColors.warning.$1/g;
    s/Colors\.amber\.shade(50|100|200)\b/AppColors.warningBg/g;
    s/Colors\.amber\.shade(300|400)\b/AppColors.warningBorder/g;
    s/Colors\.amber\.shade(500|600|700)\b/AppColors.primary/g;
    s/Colors\.amber\.shade(800|900)\b/AppColors.primaryDark/g;
    s/Colors\.amber\.(withOpacity|withValues)/AppColors.primary.$1/g;
    # blue
    s/Colors\.blue\.shade(50|100|200)\b/AppColors.infoBg/g;
    s/Colors\.blue\.shade(300|400)\b/AppColors.infoBorder/g;
    s/Colors\.blue\.shade(500|600|700)\b/AppColors.info/g;
    s/Colors\.blue\.shade(800|900)\b/AppColors.infoDark/g;
    s/Colors\.blue\.(withOpacity|withValues)/AppColors.info.$1/g;
    # lightBlue → blue 系に集約
    s/Colors\.lightBlue\.shade(50|100|200)\b/AppColors.infoBg/g;
    s/Colors\.lightBlue\.shade(300|400|500|600)\b/AppColors.info/g;
    s/Colors\.lightBlue(?![a-zA-Z.])/AppColors.info/g;
    # teal / indigo → secondary
    s/Colors\.teal\.shade(50|100|200)\b/AppColors.secondary.withValues(alpha: 0.12)/g;
    s/Colors\.teal\.shade(300|400|500|600|700)\b/AppColors.secondary/g;
    s/Colors\.teal\.shade(800|900)\b/AppColors.secondaryDark/g;
    s/Colors\.teal\.(withOpacity|withValues)/AppColors.secondary.$1/g;
    s/Colors\.indigo\.shade(50|100|200)\b/AppColors.secondary.withValues(alpha: 0.12)/g;
    s/Colors\.indigo\.shade(300|400|500|600|700)\b/AppColors.secondary/g;
    s/Colors\.indigo\.shade(800|900)\b/AppColors.secondaryDark/g;
    s/Colors\.indigo\.(withOpacity|withValues)/AppColors.secondary.$1/g;
    # purple / deepPurple / pink → AI アクセント
    s/Colors\.purple\.shade(50|100|200)\b/AppColors.aiAccentBg/g;
    s/Colors\.purple\.shade(300|400|500|600|700|800|900)\b/AppColors.aiAccent/g;
    s/Colors\.purple\.(withOpacity|withValues)/AppColors.aiAccent.$1/g;
    s/Colors\.purple(?![a-zA-Z.])/AppColors.aiAccent/g;
    s/Colors\.deepPurple\.shade(50|100|200)\b/AppColors.aiAccentBg/g;
    s/Colors\.deepPurple\.shade[0-9]+\b/AppColors.aiAccent/g;
    s/Colors\.deepPurple\.(withOpacity|withValues)/AppColors.aiAccent.$1/g;
    s/Colors\.deepPurple(?![a-zA-Z.])/AppColors.aiAccent/g;
    s/Colors\.pink\.shade(50|100|200)\b/AppColors.aiAccentBg/g;
    s/Colors\.pink\.shade[0-9]+\b/AppColors.aiAccent/g;
    s/Colors\.pink\.(withOpacity|withValues)/AppColors.aiAccent.$1/g;
    s/Colors\.pink(?![a-zA-Z.])/AppColors.aiAccent/g;
    # yellow → warning
    s/Colors\.yellow\.shade(50|100|200)\b/AppColors.warningBg/g;
    s/Colors\.yellow\.shade[0-9]+\b/AppColors.warning/g;
    s/Colors\.yellow(?![a-zA-Z.])/AppColors.warning/g;
    # cyan → info 系
    s/Colors\.cyan\.shade[0-9]+\b/AppColors.info/g;
    s/Colors\.cyan(?![a-zA-Z.])/AppColors.info/g;
    # brown → secondary 系（仮）
    s/Colors\.brown\.shade[0-9]+\b/AppColors.secondary/g;
    s/Colors\.brown(?![a-zA-Z.])/AppColors.secondary/g;
    # lime / lightGreen → success
    s/Colors\.lightGreen\.shade[0-9]+\b/AppColors.success/g;
    s/Colors\.lightGreen(?![a-zA-Z.])/AppColors.success/g;
    s/Colors\.lime\.shade[0-9]+\b/AppColors.warning/g;
    s/Colors\.lime(?![a-zA-Z.])/AppColors.warning/g;
    # deepOrange → warning
    s/Colors\.deepOrange\.shade[0-9]+\b/AppColors.warning/g;
    s/Colors\.deepOrange(?![a-zA-Z.])/AppColors.warning/g;
    # blueGrey → grey と等価で AppColors にないので残す（後で判断）
  ' "$f"
done

echo "✅ v2 機械置換完了: ${#files[@]} ファイル"
