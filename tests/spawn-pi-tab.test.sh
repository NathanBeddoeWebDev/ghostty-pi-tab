#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/tmp"

cat >"$test_root/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
cat >"$test_root/bin/ps" <<'EOF'
#!/usr/bin/env bash
printf 'null\n'
EOF
cat >"$test_root/bin/osascript" <<'EOF'
#!/usr/bin/env bash
cat >"$CAPTURE_PATH"
EOF
cat >"$test_root/bin/pi" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$test_root/bin/"*

capture_path="$test_root/applescript"
CAPTURE_PATH=$capture_path \
PATH="$test_root/bin:$PATH" \
TERM_PROGRAM=ghostty \
TMPDIR="$test_root/tmp" \
bash "$repo_root/scripts/spawn-pi-tab.sh" "$repo_root" "test prompt" >/dev/null

input_line=$(grep -n 'input text commandText to targetTerm' "$capture_path" | cut -d: -f1 || true)
enter_line=$(grep -n 'send key "enter" to targetTerm' "$capture_path" | cut -d: -f1 || true)

if [[ -z $input_line || -z $enter_line || $enter_line -le $input_line ]]; then
  printf 'FAIL: the new tab receives pasted command text without a following Return keystroke.\n' >&2
  exit 1
fi

printf 'PASS: the new tab receives command text followed by a Return keystroke.\n'
