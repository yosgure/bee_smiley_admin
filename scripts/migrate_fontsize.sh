#!/usr/bin/env bash
# ============================================================
# fontSize: <数値> 直書きを AppTextSize.<name> 経由に置換する。
#
# 既存数値はそのまま維持（可視サイズに変化なし）。
# 新規コードは主軸 5 段（caption/body/bodyLarge/title/display）を優先する運用。
#
# マッピング:
#   9  → AppTextSize.xxs       10 → AppTextSize.xs
#   11 → AppTextSize.caption   12 → AppTextSize.small
#   13 → AppTextSize.body      14 → AppTextSize.bodyMd
#   15 → AppTextSize.bodyLarge 16 → AppTextSize.titleSm
#   17 → AppTextSize.title     18 → AppTextSize.titleLg
#   20 → AppTextSize.xl        22 → AppTextSize.display
#   24 → AppTextSize.headline  28 → AppTextSize.hero
#   32 → AppTextSize.heroLg    38 → AppTextSize.heroXl
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
total=0

for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue
  [[ "$f" =~ $EXEMPT ]] && continue

  before=$(grep -cE "fontSize\s*:\s*[0-9]+" "$f" 2>/dev/null || true)
  before=${before:-0}

  perl -i -pe '
    s/\bfontSize\s*:\s*9(?!\.\d)/fontSize: AppTextSize.xxs/g;
    s/\bfontSize\s*:\s*10(?!\.\d)/fontSize: AppTextSize.xs/g;
    s/\bfontSize\s*:\s*11(?!\.\d)/fontSize: AppTextSize.caption/g;
    s/\bfontSize\s*:\s*12(?!\.\d)/fontSize: AppTextSize.small/g;
    s/\bfontSize\s*:\s*13(?!\.\d)/fontSize: AppTextSize.body/g;
    s/\bfontSize\s*:\s*14(?!\.\d)/fontSize: AppTextSize.bodyMd/g;
    s/\bfontSize\s*:\s*15(?!\.\d)/fontSize: AppTextSize.bodyLarge/g;
    s/\bfontSize\s*:\s*16(?!\.\d)/fontSize: AppTextSize.titleSm/g;
    s/\bfontSize\s*:\s*17(?!\.\d)/fontSize: AppTextSize.title/g;
    s/\bfontSize\s*:\s*18(?!\.\d)/fontSize: AppTextSize.titleLg/g;
    s/\bfontSize\s*:\s*20(?!\.\d)/fontSize: AppTextSize.xl/g;
    s/\bfontSize\s*:\s*22(?!\.\d)/fontSize: AppTextSize.display/g;
    s/\bfontSize\s*:\s*24(?!\.\d)/fontSize: AppTextSize.headline/g;
    s/\bfontSize\s*:\s*28(?!\.\d)/fontSize: AppTextSize.hero/g;
    s/\bfontSize\s*:\s*32(?!\.\d)/fontSize: AppTextSize.heroLg/g;
    s/\bfontSize\s*:\s*38(?!\.\d)/fontSize: AppTextSize.heroXl/g;
  ' "$f"

  after=$(grep -cE "fontSize\s*:\s*[0-9]+" "$f" 2>/dev/null || true)
  after=${after:-0}
  diff=$((before - after))
  if [[ "$diff" -gt 0 ]]; then
    total=$((total + diff))
  fi
done

echo "✅ fontSize 機械置換: $total 件"
