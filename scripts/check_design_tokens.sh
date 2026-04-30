#!/usr/bin/env bash
# ============================================================
# デザイントークン違反チェッカ
# ------------------------------------------------------------
# 目的:
#   - lib/ 配下で Colors.red / Colors.blue / ... の直書き
#   - fontSize: の数値直書き
#   が新規に追加されていないかを検査する。
#
# 使い方:
#   - ローカル / pre-commit hook / CI から呼び出す
#   - ステージ済みの差分のみを対象にする（pre-commit 用）
#       scripts/check_design_tokens.sh --staged
#   - 既存の全ファイルを対象にする（移行進捗の把握用）
#       scripts/check_design_tokens.sh --all
#
# ルール:
#   - lib/app_theme.dart, lib/widgets/app_feedback.dart は例外
#   - Colors.transparent / Colors.white / Colors.black* は許容（中間色は alpha 用途で頻出のため）
#     → ただし Colors.white70 等は許容、red/blue/green/orange/purple/pink/yellow/cyan/teal/indigo/grey/amber は禁止
# ============================================================

set -euo pipefail

MODE="${1:---staged}"

EXEMPT_FILES=(
  "lib/app_theme.dart"
  "lib/widgets/app_feedback.dart"
)

is_exempt() {
  local f="$1"
  for e in "${EXEMPT_FILES[@]}"; do
    [[ "$f" == "$e" ]] && return 0
  done
  return 1
}

# 禁止する Colors.* の正規表現
FORBIDDEN_COLORS='Colors\.(red|blue|green|orange|purple|pink|yellow|cyan|teal|indigo|amber|brown|lime|deepOrange|deepPurple|lightBlue|lightGreen|blueGrey)'
# fontSize の数値直書き（fontSize: 14 / fontSize:14 など）
# 小数（fontSize: 13.5 等）は意図したケースが多いので許容
FORBIDDEN_FONT='fontSize[[:space:]]*:[[:space:]]*[0-9]+([^.0-9]|$)'

violations=0
font_violations=0

case "$MODE" in
  --staged)
    files=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^lib/.*\.dart$' || true)
    check_diff_only=1
    ;;
  --all)
    files=$(git ls-files 'lib/*.dart' 'lib/**/*.dart' || true)
    check_diff_only=0
    ;;
  *)
    echo "usage: $0 [--staged|--all]" >&2
    exit 2
    ;;
esac

if [[ -z "$files" ]]; then
  echo "[design-tokens] チェック対象なし"
  exit 0
fi

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  is_exempt "$f" && continue
  [[ ! -f "$f" ]] && continue

  if [[ "$check_diff_only" == "1" ]]; then
    # 追加行（+ で始まり +++ ヘッダではない）だけを対象にする
    diff_added=$(git diff --cached -U0 -- "$f" | awk '/^\+[^+]/ {print substr($0,2)}' || true)
    if [[ -z "$diff_added" ]]; then continue; fi
    if hits=$(echo "$diff_added" | grep -nE "$FORBIDDEN_COLORS" || true); [[ -n "$hits" ]]; then
      echo "::error file=$f::Colors.* 直書きは禁止です（context.alerts.* / AppColors.* / colorScheme.* を使用）"
      echo "$hits" | sed "s|^|  (added) $f:|"
      violations=$((violations + $(echo "$hits" | wc -l | tr -d ' ')))
    fi
    if hits=$(echo "$diff_added" | grep -nE "$FORBIDDEN_FONT" || true); [[ -n "$hits" ]]; then
      echo "::warning file=$f::fontSize 直書きは AppText.* / Theme.of(context).textTheme.* に置き換えてください"
      echo "$hits" | sed "s|^|  (added) $f:|"
      font_violations=$((font_violations + $(echo "$hits" | wc -l | tr -d ' ')))
    fi
  else
    if hits=$(grep -nE "$FORBIDDEN_COLORS" "$f" || true); [[ -n "$hits" ]]; then
      echo "::error file=$f::Colors.* 直書きは禁止です（context.alerts.* / AppColors.* / colorScheme.* を使用）"
      echo "$hits" | sed "s|^|  $f:|"
      violations=$((violations + $(echo "$hits" | wc -l | tr -d ' ')))
    fi
    if hits=$(grep -nE "$FORBIDDEN_FONT" "$f" || true); [[ -n "$hits" ]]; then
      echo "::warning file=$f::fontSize 直書きは AppText.* / Theme.of(context).textTheme.* に置き換えてください"
      echo "$hits" | sed "s|^|  $f:|"
      font_violations=$((font_violations + $(echo "$hits" | wc -l | tr -d ' ')))
    fi
  fi
done <<< "$files"

echo
echo "[design-tokens] Colors.* 違反: $violations 件 / fontSize 直書き: $font_violations 件"

# Colors.* は強制エラー / fontSize は警告のみ（移行段階のため）
# 移行が一定進んだら font_violations もエラーに昇格させる。
if [[ "$violations" -gt 0 ]]; then
  echo
  echo "❌ Colors.* 直書きが検出されました。lib/app_theme.dart のトークンを使用してください。"
  echo "   どうしても必要な場合は EXEMPT_FILES に追加（要レビュー）。"
  exit 1
fi

exit 0
