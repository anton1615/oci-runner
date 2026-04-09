#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${1:?usage: check-runner.test.sh /path/to/check-runner.sh}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_grep() {
  local pattern="$1"
  local file="$2"
  grep -qE "$pattern" "$file" || fail "expected pattern [$pattern] in $file"
}

assert_not_grep() {
  local pattern="$1"
  local file="$2"
  if grep -qE "$pattern" "$file"; then
    fail "did not expect pattern [$pattern] in $file"
  fi
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

mkdir -p "$workdir/log"

cat > "$workdir/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'mock-systemctl:%s\n' "$*"
EOF
chmod +x "$workdir/systemctl"

cat > "$workdir/journalctl" <<'EOF'
#!/usr/bin/env bash
printf 'mock-journalctl:%s\n' "$*"
EOF
chmod +x "$workdir/journalctl"

cat > "$workdir/a1.env" <<EOF
SUCCESS_SENTINEL='$workdir/custom-success.json'
EOF

cat > "$workdir/custom-success.json" <<'EOF'
{"source":"launch-success","instance_id":"ocid1.instance.oc1.test"}
EOF

for i in $(seq 1 25); do
  printf 'line%02d\n' "$i" >> "$workdir/log/launch-a1.log"
done

PATH="$workdir:$PATH" SERVICE_NAME="test-runner.service" ENV_FILE="$workdir/a1.env" LOG_DIR="$workdir/log" bash "$SCRIPT_PATH" > "$workdir/output.log"

assert_grep 'mock-systemctl:status test-runner.service --no-pager' "$workdir/output.log"
assert_grep '"source":"launch-success"' "$workdir/output.log"
assert_grep 'line25' "$workdir/output.log"
assert_not_grep 'line01' "$workdir/output.log"
assert_grep 'mock-journalctl:-u test-runner.service -n 20 --no-pager -o short-iso' "$workdir/output.log"

printf 'PASS\n'
