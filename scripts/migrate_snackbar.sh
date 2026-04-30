#!/usr/bin/env bash
# ============================================================
# ScaffoldMessenger.of(context).showSnackBar(SnackBar(...)) を
# AppFeedback.success/error/warning/info(context, '...') に置換する。
#
# 対象パターン:
#   ScaffoldMessenger.of(context).showSnackBar(
#     [const ]SnackBar(content: Text('msg'), [backgroundColor: AppColors.X])
#   );
#
# X が success/error/warning/info の場合に対応する AppFeedback メソッドへ。
# X 指定なし、または duration / action を含む複雑なケースはそのまま残す（手動移行）。
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
total_replaced=0

for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue
  [[ "$f" =~ $EXEMPT ]] && continue

  before=$(grep -c "ScaffoldMessenger\.of(context)\.showSnackBar" "$f" 2>/dev/null || true)
  before=${before:-0}

  # AppFeedback の import を必要なら追加（lib 直下なら 'widgets/app_feedback.dart' でOK）
  # Text(...) の中身は文字列リテラルだけでなく、変数・三項・補間文字列も許容する。
  # ただし SnackBar に action: / duration: / Row( / Column( 等が混ざる複雑形は対象外。
  perl -i -0777 -pe '
    # backgroundColor 指定ありパターン
    s{
      ScaffoldMessenger\.of\(context\)\.showSnackBar\(\s*
      (?:const\s+)?SnackBar\(\s*
        content:\s*Text\(\s*(?<msg>(?:[^()]|\([^()]*\))*)\s*\)\s*,
        \s*backgroundColor:\s*AppColors\.(?<sev>success|error|warning|info)\s*,?\s*
      \)\s*,?\s*\)
    }{
      my $sev = $+{sev};
      my $msg = $+{msg};
      "AppFeedback.$sev(context, $msg)"
    }gxes;

    # backgroundColor なし → info 扱い
    s{
      ScaffoldMessenger\.of\(context\)\.showSnackBar\(\s*
      (?:const\s+)?SnackBar\(\s*
        content:\s*Text\(\s*(?<msg>(?:[^()]|\([^()]*\))*)\s*\)\s*,?\s*
      \)\s*,?\s*\)
    }{
      my $msg = $+{msg};
      "AppFeedback.info(context, $msg)"
    }gxes;
  ' "$f"

  after=$(grep -c "ScaffoldMessenger\.of(context)\.showSnackBar" "$f" 2>/dev/null || true)
  after=${after:-0}
  diff=$((before - after))
  if [[ "$diff" -gt 0 ]]; then
    total_replaced=$((total_replaced + diff))
    # AppFeedback 利用箇所が 1 件以上できたか確認し、import がなければ追加
    if grep -q "AppFeedback\." "$f" && ! grep -qE "import.*widgets/app_feedback\.dart" "$f"; then
      # 既存 app_theme.dart の import 行を見つけて、その下に挿入
      perl -i -pe "
        if (\$_ =~ /^import.*app_theme\.dart/ && !\$inserted) {
          \$_ .= \"import 'widgets/app_feedback.dart';\n\";
          \$inserted = 1;
        }
      " "$f"
    fi
    echo "  $f: -$diff 件"
  fi
done

echo "✅ SnackBar 機械置換: 合計 $total_replaced 件"
