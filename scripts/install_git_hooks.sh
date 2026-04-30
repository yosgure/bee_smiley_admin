#!/usr/bin/env bash
# pre-commit hook をインストールする。
# プロジェクトルートで一度だけ実行すれば OK。
# CI / 同僚にもこのスクリプトを叩いてもらう運用。

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
# worktree では .git がファイルになるため git rev-parse --git-common-dir を使う
COMMON_GIT_DIR="$(git rev-parse --git-common-dir)"
mkdir -p "$COMMON_GIT_DIR/hooks"
HOOK="$COMMON_GIT_DIR/hooks/pre-commit"

cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
# Bee Smiley Admin: design-tokens guard
set -e
"$(git rev-parse --show-toplevel)/scripts/check_design_tokens.sh" --staged
EOF

chmod +x "$HOOK"
echo "✅ pre-commit hook を設置しました: $HOOK"
echo "   今後は scripts/check_design_tokens.sh --staged が自動で走ります。"
echo "   全件レポートは: scripts/check_design_tokens.sh --all"
