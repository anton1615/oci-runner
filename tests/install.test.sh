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

assert_not_grep() {
  local pattern="$1"
  local file="$2"
  if grep -qE "$pattern" "$file"; then
    fail "did not expect pattern [$pattern] in $file"
  fi
}

run_expect_fail() {
  local expected_pattern="$1"
  shift
  local stdout_log="$workdir/failed-stdout.log"
  local stderr_log="$workdir/failed-stderr.log"
  set +e
  "$@" >"$stdout_log" 2>"$stderr_log"
  local status=$?
  set -e
  [ "$status" -ne 0 ] || fail "expected command to fail: $*"
  grep -qE -- "$expected_pattern" "$stderr_log" || fail "expected failure pattern [$expected_pattern] in $stderr_log"
}

workdir="$(mktemp -d)"
target_root="$workdir/custom-root"
trap 'rm -rf "$workdir"' EXIT

real_chmod="$(command -v chmod)"
real_cp="$(command -v cp)"

invalid_root='relative-root'
mock_bin="$workdir/mock-bin"
service_dest="$workdir/etc/systemd/system/oci-a1-runner.service"
mkdir -p "$mock_bin" "$workdir/etc/systemd/system"

cat > "$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 5 ] && [ "$1" = '-u' ] && [ "$3" = 'test' ] && [ "$4" = '-r' ]; then
  if grep -q '^# unreadable$' "$5"; then
    exit 1
  fi
  exit 0
fi

"$@"
EOF
chmod +x "$mock_bin/sudo"

cat > "$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "systemctl:$*" >> "$SYSTEMCTL_LOG"
EOF
chmod +x "$mock_bin/systemctl"

cat > "$mock_bin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Linux\n'
EOF
chmod +x "$mock_bin/uname"

cat > "$mock_bin/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = '-u' ]; then
  if [ "$#" -eq 1 ]; then
    printf '%s\n' "${MOCK_ID_U:-1000}"
    exit 0
  fi
  if [ "$2" = 'root' ] || [ "$2" = 'alice' ] || [ "$2" = 'bob' ]; then
    printf '1000\n'
    exit 0
  fi
  exit 1
fi

printf 'unexpected id args: %s\n' "$*" >&2
exit 2
EOF
chmod +x "$mock_bin/id"

cat > "$mock_bin/getent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" != 'passwd' ]; then
  printf 'unexpected getent database: %s\n' "$1" >&2
  exit 2
fi

case "$2" in
  alice)
    printf 'alice:x:1000:1000::/home/alice:/bin/bash\n'
    ;;
  root)
    printf 'root:x:0:0::/root:/bin/bash\n'
    ;;
  bob)
    printf 'bob:x:1001:1001::/home/bob:/bin/bash\n'
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$mock_bin/getent"

cat > "$mock_bin/chown" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "chown:$*" >> "$CHOWN_LOG"
EOF
chmod +x "$mock_bin/chown"

cat > "$mock_bin/chmod" <<'EOF'
#!/usr/bin/env bash
"$REAL_CHMOD" "$@"
printf '%s\n' "chmod:$*" >> "$CHMOD_LOG"
EOF
chmod +x "$mock_bin/chmod"

cat > "$mock_bin/install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode=''
src=''
dest=''
while (($#)); do
  case "$1" in
    -m)
      mode="$2"
      shift 2
      ;;
    *)
      if [ -z "$src" ]; then
        src="$1"
      elif [ -z "$dest" ]; then
        dest="$1"
      else
        printf 'unexpected install arg: %s\n' "$1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$src" ] || [ -z "$dest" ]; then
  printf 'mock install requires src and dest\n' >&2
  exit 2
fi

if [ "$dest" = '/etc/systemd/system/oci-a1-runner.service' ]; then
  dest="$SERVICE_DEST"
fi

mkdir -p "$(dirname "$dest")"
"$REAL_CP" "$src" "$dest"
if [ -n "$mode" ]; then
  "$REAL_CHMOD" "$mode" "$dest"
fi
printf '%s\n' "install:$src->$dest" >> "$INSTALL_LOG"
EOF
chmod +x "$mock_bin/install"

BASE_ENV=(
  "SYSTEMCTL_LOG=$workdir/systemctl.log"
  "INSTALL_LOG=$workdir/install.log"
  "SERVICE_DEST=$service_dest"
  "CHOWN_LOG=$workdir/chown.log"
  "CHMOD_LOG=$workdir/chmod.log"
  "REAL_CHMOD=$real_chmod"
  "REAL_CP=$real_cp"
  "PATH=$mock_bin:$PATH"
)

run_expect_fail 'install.sh must be run as root' env "${BASE_ENV[@]}" MOCK_ID_U=1000 bash "$SCRIPT_PATH" --root "$target_root"
run_expect_fail '--root must be an absolute path' env "${BASE_ENV[@]}" MOCK_ID_U=0 bash "$SCRIPT_PATH" --root "$invalid_root"
run_expect_fail 'could not derive a valid service user from --root or SUDO_USER' env "${BASE_ENV[@]}" MOCK_ID_U=0 SUDO_USER=missing bash "$SCRIPT_PATH" --root /srv/oci-runner
run_expect_fail 'derived service user does not exist: ghost' env "${BASE_ENV[@]}" MOCK_ID_U=0 bash "$SCRIPT_PATH" --root /home/ghost/oci-runner

env "${BASE_ENV[@]}" MOCK_ID_U=0 SUDO_USER=bob bash "$SCRIPT_PATH" --root "$target_root"

assert_file_exists "$target_root/bin/launch-a1.sh"
assert_file_exists "$target_root/bin/check-runner.sh"
assert_file_exists "$target_root/etc/a1.env"
assert_file_exists "$service_dest"
assert_file_exists "$workdir/systemctl.log"
assert_grep 'systemctl:daemon-reload' "$workdir/systemctl.log"
assert_grep 'systemctl:enable oci-a1-runner.service' "$workdir/systemctl.log"
assert_not_grep 'systemctl:start oci-a1-runner.service' "$workdir/systemctl.log"
assert_grep 'install:.*->.*/etc/systemd/system/oci-a1-runner.service' "$workdir/install.log"
assert_grep '^DISPLAY_NAME=' "$target_root/etc/a1.env"
assert_grep '^User=bob$' "$service_dest"
assert_grep 'Environment=ENV_FILE=.*/custom-root/etc/a1.env' "$service_dest"
assert_grep 'Environment=LOG_DIR=.*/custom-root/log' "$service_dest"
assert_grep 'ExecStart=.*/custom-root/bin/launch-a1.sh' "$service_dest"
assert_grep '^chown:-R bob:bob .*/custom-root/log$' "$workdir/chown.log"
assert_grep '^chown:bob:bob .*/custom-root/etc/a1.env$' "$workdir/chown.log"
assert_grep '^chmod:700 .*/custom-root/log$' "$workdir/chmod.log"
assert_grep '^chmod:600 .*/custom-root/etc/a1.env$' "$workdir/chmod.log"

printf 'DISPLAY_NAME=keep-me\n' > "$target_root/etc/a1.env"

printf '# unreadable\nDISPLAY_NAME=keep-me\n' > "$target_root/etc/a1.env"
run_expect_fail 'existing env is not readable by service user: bob' env "${BASE_ENV[@]}" MOCK_ID_U=0 SUDO_USER=bob bash "$SCRIPT_PATH" --root "$target_root"

printf 'DISPLAY_NAME=keep-me\n' > "$target_root/etc/a1.env"

env "${BASE_ENV[@]}" MOCK_ID_U=0 SUDO_USER=bob bash "$SCRIPT_PATH" --root "$target_root" --start

assert_grep '^DISPLAY_NAME=keep-me$' "$target_root/etc/a1.env"
assert_grep 'systemctl:start oci-a1-runner.service' "$workdir/systemctl.log"

printf 'PASS\n'
