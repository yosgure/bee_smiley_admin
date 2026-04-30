#!/usr/bin/env bash
# ============================================================
# 単純な確認ダイアログ（showDialog<bool> + AlertDialog + Text title/content + 2 ボタン）を
# AppFeedback.confirm(...) に置換する。
#
# 検出対象パターン:
#   await showDialog<bool>(
#     context: context,
#     builder: (ctx|context) => AlertDialog(
#       title: [const ]Text('...'),
#       content: [const ]Text('...'),
#       actions: [
#         TextButton(onPressed: () => Navigator.pop(ctx|context, false), child: [const ]Text('...')),
#         TextButton(onPressed: () => Navigator.pop(ctx|context, true), child: [const ]Text('...' [, style: TextStyle(color: AppColors.error)])),
#       ],
#     ),
#   );
#
# 対象外（パターンが合わないものは無視 = 既存コードのまま）:
#   - actions が 3 ボタン以上
#   - content が SizedBox / Column 等の複雑構造
#   - showDialog<bool> ではない（dynamic / void）
#   - 同期的な onPressed ハンドラに副作用
# ============================================================

set -euo pipefail

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  files=()
  while IFS= read -r line; do files+=("$line"); done < <(find lib -type f -name '*.dart')
fi

EXEMPT='(app_theme\.dart|widgets/app_feedback\.dart)$'
total=0

for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue
  [[ "$f" =~ $EXEMPT ]] && continue
  before=$(grep -c "showDialog<bool>" "$f" 2>/dev/null || true)
  before=${before:-0}

  perl -i -0777 -pe '
    # 文字列リテラル（隣接連結対応）: '\''abc'\'' '\''def'\'' → '\''abcdef'\''
    # ラムダ引数は (ctx)/(context)/(c)/(_) 等で揺れるため CTX_ARG にキャプチャ。
    s{
      showDialog<bool>\(\s*
        context:\s*context\s*,\s*
        builder:\s*\(\s*(?<ctxarg>[a-zA-Z_]+)\s*\)\s*=>\s*
          (?:const\s+)?AlertDialog\(\s*
            title:\s*(?:const\s+)?Text\(\s*(?<title>(?:'\''[^'\'']*'\''|"[^"]*")(?:\s*(?:'\''[^'\'']*'\''|"[^"]*"))*)\s*\)\s*,\s*
            content:\s*(?:const\s+)?Text\(\s*(?<msg>(?:'\''[^'\'']*'\''|"[^"]*")(?:\s*(?:'\''[^'\'']*'\''|"[^"]*"))*)\s*\)\s*,\s*
            actions:\s*\[\s*
              TextButton\(\s*
                onPressed:\s*\(\)\s*=>\s*Navigator\.pop\(\s*\g{ctxarg}\s*,\s*false\s*\)\s*,\s*
                child:\s*(?:const\s+)?Text\(\s*(?<cancel>(?:'\''[^'\'']*'\''|"[^"]*"))\s*\)\s*,?\s*
              \)\s*,\s*
              TextButton\(\s*
                onPressed:\s*\(\)\s*=>\s*Navigator\.pop\(\s*\g{ctxarg}\s*,\s*true\s*\)\s*,\s*
                child:\s*
                  (?:
                    (?:const\s+)?Text\(\s*(?<ok1>(?:'\''[^'\'']*'\''|"[^"]*"))\s*\)
                    |
                    (?:const\s+)?Text\(\s*(?<ok2>(?:'\''[^'\'']*'\''|"[^"]*"))\s*,\s*style:\s*TextStyle\((?<style>[^)]*)\)\s*\)
                  )\s*,?\s*
              \)\s*,?\s*
            \]\s*,?\s*
          \)\s*,?\s*
      \)
    }{
      # 先に %+ から全部取り出す（後の regex マッチで %+ がクリアされるため）
      my $T = $+{title};
      my $M = $+{msg};
      my $CC = $+{cancel};
      my $ok = $+{ok1} // $+{ok2};
      my $style = $+{style} // "";
      my $dest = ($style =~ /AppColors\.error/) ? ", destructive: true" : "";
      "AppFeedback.confirm(context, title: $T, message: $M, confirmLabel: $ok, cancelLabel: $CC$dest)"
    }gxes;
  ' "$f"

  after=$(grep -c "showDialog<bool>" "$f" 2>/dev/null || true)
  after=${after:-0}
  diff=$((before - after))
  if [[ "$diff" -gt 0 ]]; then
    total=$((total + diff))
    echo "  $f: -$diff 件"
    # AppFeedback の import が無ければ追加
    if grep -q "AppFeedback\." "$f" && ! grep -qE "import.*app_feedback\.dart" "$f"; then
      if [[ "$f" == lib/crm/* ]]; then
        rel="../widgets/app_feedback.dart"
      elif [[ "$f" == lib/services/* ]]; then
        rel="../widgets/app_feedback.dart"
      else
        rel="widgets/app_feedback.dart"
      fi
      perl -i -pe "
        if (\$_ =~ /^import.*app_theme\.dart/ && !\$inserted) {
          \$_ .= \"import '$rel';\n\";
          \$inserted = 1;
        }
      " "$f"
    fi
  fi
done

echo "✅ confirm dialog 置換: $total 件"
