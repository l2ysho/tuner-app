#!/usr/bin/env bash
# PostToolUse hook: formats and lints only the file Claude just edited.
# Silent on success. Remaining problems go to stderr with exit 2, which Claude Code feeds back.
set -uo pipefail
file=$(jq -r '.tool_input.file_path // empty')
[ -n "$file" ] && [ -f "$file" ] || exit 0
root="${CLAUDE_PROJECT_DIR:-$(git -C "$(dirname "$file")" rev-parse --show-toplevel)}"
cd "$root" || exit 0
rel="${file#"$root"/}"

problems=""
case "$rel" in
    apple/TunerKit/.build/* | build/*) exit 0 ;;
    *.swift)
        swift format format -i "$rel" 2>/dev/null
        problems+=$(swift format lint --strict "$rel" 2>&1)
        problems+=$(swiftlint lint --strict --quiet "$rel" 2>&1 | grep -v "^Linting\|^Done")
        ;;
    *.cpp | *.hpp | *.h)
        clang-format -i "$rel"
        ;;
    apple/project.yml)
        problems+=$(xcodegen generate --quiet --spec apple/project.yml 2>&1)
        ;;
    *) exit 0 ;;
esac

if [ -n "$problems" ]; then
    printf '%s\n' "$problems" >&2
    exit 2
fi
