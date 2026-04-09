# Install Script and README Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small Linux deployment installer and update the README so the `oci-runner` repo is easier to install and verify on another machine.

**Architecture:** Introduce a minimal Bash installer that copies scripts into a deployment root, preserves an existing config file, renders a root-specific systemd unit, and optionally starts the service. Drive the behavior with shell regression tests first, then update the README to document both manual and scripted installation.

**Tech Stack:** Bash, systemd unit files, Markdown, shell-based regression tests, git

---

### Task 1: Add installer regression test first

**Files:**
- Create: `oci-runner/tests/install.test.sh`
- Reference: `oci-runner/install.sh`, `oci-runner/a1.env.example`, `oci-runner/oci-a1-runner.service`

- [ ] **Step 1: Write the failing installer test**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${1:?usage: install.test.sh /path/to/install.sh}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_exists() {
  [ -f "$1" ] || fail "expected file to exist: $1"
}

assert_grep() {
  local pattern="$1"
  local file="$2"
  grep -qE "$pattern" "$file" || fail "expected pattern [$pattern] in $file"
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

repo_root="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
target_root="$workdir/custom-root"
mock_bin="$workdir/mock-bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
"$@"
EOF
chmod +x "$mock_bin/sudo"

cat > "$mock_bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "systemctl:$*" >> "$workdir/systemctl.log"
EOF
chmod +x "$mock_bin/systemctl"

PATH="$mock_bin:$PATH" bash "$SCRIPT_PATH" --root "$target_root"

assert_file_exists "$target_root/bin/launch-a1.sh"
assert_file_exists "$target_root/bin/check-runner.sh"
assert_file_exists "$target_root/etc/a1.env"
assert_file_exists "$workdir/systemctl.log"
assert_grep 'systemctl:daemon-reload' "$workdir/systemctl.log"
assert_grep 'systemctl:enable oci-a1-runner.service' "$workdir/systemctl.log"

printf 'PASS\n'
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
bash ./tests/install.test.sh ./install.sh
```

Expected: FAIL because `install.sh` does not exist yet.

- [ ] **Step 3: Expand the test to cover non-overwrite and `--start` behavior**

```bash
printf 'DISPLAY_NAME=keep-me\n' > "$target_root/etc/a1.env"
PATH="$mock_bin:$PATH" bash "$SCRIPT_PATH" --root "$target_root" --start
assert_grep '^DISPLAY_NAME=keep-me$' "$target_root/etc/a1.env"
assert_grep 'systemctl:start oci-a1-runner.service' "$workdir/systemctl.log"
```

- [ ] **Step 4: Read back the test file**

Run read for:

```text
oci-runner/tests/install.test.sh
```

Expected: the test describes installer creation, service enablement, config
preservation, and optional start behavior.

### Task 2: Implement `install.sh`

**Files:**
- Create: `oci-runner/install.sh`
- Reference: `oci-runner/launch-a1.sh`, `oci-runner/check-runner.sh`, `oci-runner/a1.env.example`, `oci-runner/oci-a1-runner.service`
- Test: `oci-runner/tests/install.test.sh`

- [ ] **Step 1: Create the minimal installer implementation**

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="/home/ubuntu/oci-runner"
START_SERVICE=0
SERVICE_NAME="oci-a1-runner.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: install.sh [--root <path>] [--start]
EOF
}

while (($#)); do
  case "$1" in
    --root)
      ROOT_DIR="$2"
      shift 2
      ;;
    --start)
      START_SERVICE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unsupported argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [ "$(uname -s)" != 'Linux' ]; then
  printf 'install.sh only supports Linux\n' >&2
  exit 1
fi

BIN_DIR="$ROOT_DIR/bin"
ETC_DIR="$ROOT_DIR/etc"
LOG_DIR="$ROOT_DIR/log"
ENV_PATH="$ETC_DIR/a1.env"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

mkdir -p "$BIN_DIR" "$ETC_DIR" "$LOG_DIR"
install -m 755 "$SCRIPT_DIR/launch-a1.sh" "$BIN_DIR/launch-a1.sh"
install -m 755 "$SCRIPT_DIR/check-runner.sh" "$BIN_DIR/check-runner.sh"

if [ ! -f "$ENV_PATH" ]; then
  install -m 600 "$SCRIPT_DIR/a1.env.example" "$ENV_PATH"
  printf 'created %s from a1.env.example\n' "$ENV_PATH"
else
  printf 'keeping existing %s\n' "$ENV_PATH"
fi

tmp_service="$(mktemp)"
trap 'rm -f "$tmp_service"' EXIT
sed \
  -e "s|Environment=ENV_FILE=/home/ubuntu/oci-runner/etc/a1.env|Environment=ENV_FILE=$ETC_DIR/a1.env|" \
  -e "s|Environment=LOG_DIR=/home/ubuntu/oci-runner/log|Environment=LOG_DIR=$LOG_DIR|" \
  -e "s|ExecStart=/home/ubuntu/oci-runner/bin/launch-a1.sh|ExecStart=$BIN_DIR/launch-a1.sh|" \
  "$SCRIPT_DIR/oci-a1-runner.service" > "$tmp_service"
install -m 644 "$tmp_service" "$SERVICE_PATH"

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
if [ "$START_SERVICE" -eq 1 ]; then
  systemctl start "$SERVICE_NAME"
fi

printf 'install complete for %s\n' "$ROOT_DIR"
printf 'edit %s before first real use\n' "$ENV_PATH"
```

- [ ] **Step 2: Run the installer test to verify it passes**

Run:

```bash
bash ./tests/install.test.sh ./install.sh
```

Expected: PASS

- [ ] **Step 3: Read back the installer implementation**

Run read for:

```text
oci-runner/install.sh
```

Expected: installer behavior matches the approved design.

### Task 3: Update README for installer flow

**Files:**
- Modify: `oci-runner/README.md`
- Reference: `oci-runner/install.sh`, `oci-runner/a1.env.example`

- [ ] **Step 1: Add installer file listing and quick-start section**

```markdown
- `install.sh`
  Minimal Linux installer for `systemd` deployments.

## Quick start

```bash
bash ./install.sh
sudo editor /home/ubuntu/oci-runner/etc/a1.env
sudo systemctl start oci-a1-runner.service
```
```

- [ ] **Step 2: Add an `Install with install.sh` section**

```markdown
## Install with install.sh

Default install:

```bash
bash ./install.sh
```

Custom root:

```bash
bash ./install.sh --root /srv/oci-runner
```

Install and start immediately:

```bash
bash ./install.sh --start
```
```

- [ ] **Step 3: Add safety and post-install notes**

```markdown
- `install.sh` does not populate live OCI or Discord secrets.
- If `etc/a1.env` already exists, the installer keeps it unchanged.
- Review and edit `a1.env` before the first real service start.
- The installer writes `/etc/systemd/system/oci-a1-runner.service`.
```

- [ ] **Step 4: Read back the README**

Run read for:

```text
oci-runner/README.md
```

Expected: README documents both manual and scripted install paths accurately.

### Task 4: Run full verification and review

**Files:**
- Verify: `oci-runner/install.sh`, `oci-runner/README.md`, `oci-runner/tests/*.sh`

- [ ] **Step 1: Run all shell regression tests**

Run:

```bash
bash ./tests/install.test.sh ./install.sh
bash ./tests/launch-a1.test.sh ./launch-a1.sh
bash ./tests/check-runner.test.sh ./check-runner.sh
```

Expected: all commands print `PASS`.

- [ ] **Step 2: Scan for accidental secrets after the change**

Run content search for:

```text
ocid1\.tenancy\.oc1\..*[a-z0-9]{20,}
MT[A-Za-z0-9._-]+
150\.230\.197\.63
1472668627332235285
```

Expected: no live secret matches in the standalone repo.

- [ ] **Step 3: Dispatch implementation review**

```text
Review against:
- `docs/superpowers/specs/2026-04-09-install-script-and-readme-design.md`
- `docs/superpowers/plans/2026-04-09-install-script-and-readme.md`
- `install.sh`
- `README.md`
- `tests/install.test.sh`
```

- [ ] **Step 4: Fix any review findings and re-run affected verification**

```text
If review reports an issue, make the minimal fix and rerun the impacted test or
scan before claiming completion.
```

### Task 5: Commit the installer change

**Files:**
- Commit: installer, README, tests, spec, plan

- [ ] **Step 1: Inspect git state in `oci-runner`**

Run:

```bash
git status --short
git diff
```

Expected: only the intended installer-related changes appear.

- [ ] **Step 2: Create the commit**

Run:

```bash
git add install.sh README.md tests/install.test.sh docs/superpowers/specs/2026-04-09-install-script-and-readme-design.md docs/superpowers/plans/2026-04-09-install-script-and-readme.md
git commit -m "feat: add installer for oci runner"
```

- [ ] **Step 3: Verify the commit exists and the tree is clean**

Run:

```bash
git log --oneline -n 1
git status --short
```

Expected: the new commit is visible and `git status --short` is empty.

## Self-review

- Spec coverage: the plan covers installer creation, README updates, safety
  rules, test coverage, verification, review, and commit.
- Placeholder scan: no `TODO`, `TBD`, or unspecified file paths remain.
- Consistency: all tasks target the same final files and the installer behavior
  matches the approved spec throughout the plan.
