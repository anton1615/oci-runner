# Verify-install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lightweight local verification script for installed `oci-runner` deployments and document how to use it.

**Architecture:** Build a small Bash verifier that checks the deployed file layout, required environment keys, rendered systemd unit paths, and basic systemd visibility without calling OCI APIs. Drive the implementation with a shell regression test first, then update the README to document the verifier's scope and usage.

**Tech Stack:** Bash, Markdown, shell-based regression tests, systemd command mocking, git

---

### Task 1: Add verifier regression test first

**Files:**
- Create: `oci-runner/tests/verify-install.test.sh`
- Reference: `oci-runner/verify-install.sh`, `oci-runner/check-runner.sh`

- [ ] **Step 1: Write the failing verifier test**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${1:?usage: verify-install.test.sh /path/to/verify-install.sh}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_grep() {
  local pattern="$1"
  local file="$2"
  grep -qE "$pattern" "$file" || fail "expected pattern [$pattern] in $file"
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

root_dir="$workdir/root"
service_name='custom-oci-a1-runner.service'
mock_bin="$workdir/mock-bin"
mkdir -p "$mock_bin" "$root_dir/bin" "$root_dir/etc" "$root_dir/log" "$workdir/etc/systemd/system"

cat > "$root_dir/bin/launch-a1.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$root_dir/bin/launch-a1.sh"

cat > "$root_dir/bin/check-runner.sh" <<'EOF'
#!/usr/bin/env bash
printf 'check-runner-ok\n'
EOF
chmod +x "$root_dir/bin/check-runner.sh"

cat > "$root_dir/etc/a1.env" <<'EOF'
COMPARTMENT_ID=compartment
SUBNET_ID=subnet
IMAGE_ID=image
OCI_CLI=/usr/bin/oci
OCI_CLI_PROFILE=DEFAULT
SUCCESS_SENTINEL=/tmp/a1-success.json
EOF

cat > "$workdir/etc/systemd/system/$service_name" <<EOF
[Service]
Environment=ENV_FILE=$root_dir/etc/a1.env
Environment=LOG_DIR=$root_dir/log
ExecStart=$root_dir/bin/launch-a1.sh
EOF

cat > "$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  is-enabled)
    printf 'enabled\n'
    ;;
  is-active)
    printf 'inactive\n'
    ;;
  status)
    printf 'mock status\n'
    ;;
  *)
    printf 'unexpected systemctl args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$mock_bin/systemctl"

PATH="$mock_bin:$PATH" SYSTEMD_DIR="$workdir/etc/systemd/system" bash "$SCRIPT_PATH" --root "$root_dir" --service "$service_name" > "$workdir/output.log"

assert_grep '^\[OK\] launch script present$' "$workdir/output.log"
assert_grep '^\[WARN\] service is not active: custom-oci-a1-runner.service$' "$workdir/output.log"
assert_grep '^\[OK\] required env key present: IMAGE_ID$' "$workdir/output.log"
assert_grep '^\[OK\] check-runner helper executed$' "$workdir/output.log"

printf 'PASS\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash ./tests/verify-install.test.sh ./verify-install.sh
```

Expected: FAIL because `verify-install.sh` does not exist yet.

- [ ] **Step 3: Expand the test for failure cases and argument handling**

```bash
# Missing key should fail
grep -v '^IMAGE_ID=' "$root_dir/etc/a1.env" > "$root_dir/etc/a1.env.tmp"
mv "$root_dir/etc/a1.env.tmp" "$root_dir/etc/a1.env"
if PATH="$mock_bin:$PATH" SYSTEMD_DIR="$workdir/etc/systemd/system" bash "$SCRIPT_PATH" --root "$root_dir" --service "$service_name"; then
  fail 'expected missing IMAGE_ID to fail'
fi

# Path mismatch should fail
```

- [ ] **Step 4: Read back the test file**

Run read for:

```text
oci-runner/tests/verify-install.test.sh
```

Expected: the test covers success, warning-only inactive service, missing env
key failure, and service path mismatch failure.

### Task 2: Implement `verify-install.sh`

**Files:**
- Create: `oci-runner/verify-install.sh`
- Test: `oci-runner/tests/verify-install.test.sh`

- [ ] **Step 1: Create the minimal verifier implementation**

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="/home/ubuntu/oci-runner"
SERVICE_NAME="oci-a1-runner.service"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
FAILED=0

ok() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail_check() { printf '[FAIL] %s\n' "$1"; FAILED=1; }

while (($#)); do
  case "$1" in
    --root)
      ROOT_DIR="$2"
      shift 2
      ;;
    --service)
      SERVICE_NAME="$2"
      shift 2
      ;;
    *)
      printf 'unsupported argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

LAUNCH_PATH="$ROOT_DIR/bin/launch-a1.sh"
CHECK_PATH="$ROOT_DIR/bin/check-runner.sh"
ENV_PATH="$ROOT_DIR/etc/a1.env"
SERVICE_PATH="$SYSTEMD_DIR/$SERVICE_NAME"

check_file() {
  local path="$1"
  local label="$2"
  if [ -f "$path" ]; then
    ok "$label present"
  else
    fail_check "$label missing: $path"
  fi
}

check_exec() {
  local path="$1"
  local label="$2"
  if [ -x "$path" ]; then
    ok "$label executable"
  else
    fail_check "$label not executable: $path"
  fi
}

check_file "$LAUNCH_PATH" 'launch script'
check_file "$CHECK_PATH" 'check-runner helper'
check_file "$ENV_PATH" 'env file'
check_file "$SERVICE_PATH" 'service unit'
check_exec "$LAUNCH_PATH" 'launch script'
check_exec "$CHECK_PATH" 'check-runner helper'

if [ -f "$SERVICE_PATH" ]; then
  grep -qF "Environment=ENV_FILE=$ENV_PATH" "$SERVICE_PATH" && ok 'service env path matches selected root' || fail_check 'service env path mismatch'
  grep -qF "Environment=LOG_DIR=$ROOT_DIR/log" "$SERVICE_PATH" && ok 'service log path matches selected root' || fail_check 'service log path mismatch'
  grep -qF "ExecStart=$LAUNCH_PATH" "$SERVICE_PATH" && ok 'service ExecStart matches selected root' || fail_check 'service ExecStart mismatch'
fi

for key in COMPARTMENT_ID SUBNET_ID IMAGE_ID OCI_CLI OCI_CLI_PROFILE SUCCESS_SENTINEL; do
  if grep -qE "^${key}=.+$" "$ENV_PATH"; then
    ok "required env key present: $key"
  else
    fail_check "missing required env key: $key"
  fi
done

enabled_state="$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true)"
if [ "$enabled_state" = 'enabled' ]; then
  ok "service is enabled: $SERVICE_NAME"
else
  warn "service is not enabled: $SERVICE_NAME"
fi

active_state="$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)"
if [ "$active_state" = 'active' ]; then
  ok "service is active: $SERVICE_NAME"
else
  warn "service is not active: $SERVICE_NAME"
fi

if "$CHECK_PATH" >/dev/null 2>&1; then
  ok 'check-runner helper executed'
else
  fail_check 'check-runner helper failed'
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
```

- [ ] **Step 2: Run the verifier test to verify it passes**

Run:

```bash
bash ./tests/verify-install.test.sh ./verify-install.sh
```

Expected: PASS

- [ ] **Step 3: Read back the verifier implementation**

Run read for:

```text
oci-runner/verify-install.sh
```

Expected: script behavior matches the approved local-only verification design.

### Task 3: Update README for verification flow

**Files:**
- Modify: `oci-runner/README.md`

- [ ] **Step 1: Add verifier file listing**

```markdown
- `verify-install.sh`
  Local post-install verification helper.
```

- [ ] **Step 2: Add a `Verify an installation` section**

```markdown
## Verify an installation

Default root:

```bash
bash ./verify-install.sh
```

Custom root and service:

```bash
bash ./verify-install.sh --root /srv/oci-runner --service oci-a1-runner.service
```
```

- [ ] **Step 3: Document verifier scope clearly**

```markdown
- `verify-install.sh` checks local deployment state only.
- It does not call OCI APIs or submit a launch request.
- Inactive services are reported as warnings, not automatic hard failures.
```

- [ ] **Step 4: Read back the README**

Run read for:

```text
oci-runner/README.md
```

Expected: README accurately explains the verifier behavior and limitations.

### Task 4: Run full verification and review

**Files:**
- Verify: `oci-runner/verify-install.sh`, `oci-runner/tests/*.sh`, `oci-runner/README.md`

- [ ] **Step 1: Run all shell regression tests**

Run:

```bash
bash ./tests/verify-install.test.sh ./verify-install.sh
bash ./tests/install.test.sh ./install.sh
bash ./tests/launch-a1.test.sh ./launch-a1.sh
bash ./tests/check-runner.test.sh ./check-runner.sh
```

Expected: all commands print `PASS`.

- [ ] **Step 2: Dispatch implementation review**

```text
Review against:
- `docs/superpowers/specs/2026-04-09-verify-install-design.md`
- `docs/superpowers/plans/2026-04-09-verify-install.md`
- `verify-install.sh`
- `tests/verify-install.test.sh`
- `README.md`
```

- [ ] **Step 3: Fix any review findings and rerun impacted checks**

```text
If review finds a bug or documentation mismatch, make the minimal fix and rerun
the affected tests before claiming completion.
```

### Task 5: Commit the verifier change

**Files:**
- Commit: verifier, README, tests, spec, plan

- [ ] **Step 1: Inspect git state in `oci-runner`**

Run:

```bash
git status --short
git diff
```

Expected: only verifier-related changes appear.

- [ ] **Step 2: Create the commit**

Run:

```bash
git add verify-install.sh tests/verify-install.test.sh README.md docs/superpowers/specs/2026-04-09-verify-install-design.md docs/superpowers/plans/2026-04-09-verify-install.md
git commit -m "feat: add install verification script"
```

- [ ] **Step 3: Verify the commit exists and the tree is clean**

Run:

```bash
git log --oneline -n 1
git status --short
```

Expected: the new commit is visible and `git status --short` is empty.

## Self-review

- Spec coverage: the plan covers verifier creation, README updates, output
  semantics, local-only scope, testing, review, and commit.
- Placeholder scan: no `TODO`, `TBD`, or missing paths remain.
- Consistency: all tasks refer to the same final verifier name, flags, and
  output behavior throughout the plan.
