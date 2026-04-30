#!/usr/bin/env bash
# ============================================================
# Colors.* 直書きを AppColors.* セマンティックトークンへ機械置換する。
#
# 対応する変換（後ろに英字や . が続かないものだけを対象 = .shade100 や redAccent は除外）:
#   Colors.red    → AppColors.error
#   Colors.green  → AppColors.success
#   Colors.orange → AppColors.warning
#   Colors.blue   → AppColors.info
#   Colors.amber  → AppColors.primary
#   Colors.teal   → AppColors.secondary
#   Colors.indigo → AppColors.secondary
#
# 対象外（人間判断が必要なため残す）:
#   Colors.red.shade100, Colors.blue.withOpacity(.1), Colors.purple, Colors.pink, Colors.yellow,
#   Colors.cyan, Colors.brown, Colors.deepPurple, Colors.deepOrange, Colors.lightBlue, Colors.lightGreen, Colors.blueGrey,
#   Colors.redAccent, Colors.blueAccent, ...
#
# 対象: 引数で渡されたファイル群（指定なければ lib/ 配下全 .dart）。
# 例外: lib/app_theme.dart, lib/widgets/app_feedback.dart は変更しない。
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

  # Perl で否定先読み: 直後に文字 or '.' が来る場合（.shade100, redAccent 等）はスキップ
  perl -i -pe '
    s/\bColors\.red(?![a-zA-Z.])/AppColors.error/g;
    s/\bColors\.green(?![a-zA-Z.])/AppColors.success/g;
    s/\bColors\.orange(?![a-zA-Z.])/AppColors.warning/g;
    s/\bColors\.blue(?![a-zA-Z.])/AppColors.info/g;
    s/\bColors\.amber(?![a-zA-Z.])/AppColors.primary/g;
    s/\bColors\.teal(?![a-zA-Z.])/AppColors.secondary/g;
    s/\bColors\.indigo(?![a-zA-Z.])/AppColors.secondary/g;
  ' "$f"
done

echo "✅ 機械置換完了: ${#files[@]} ファイル"
