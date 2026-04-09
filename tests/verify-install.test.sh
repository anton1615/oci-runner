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

assert_not_grep() {
  local pattern="$1"
  local file="$2"
  if grep -qE "$pattern" "$file"; then
    fail "did not expect pattern [$pattern] in $file"
  fi
}

make_layout() {
  local workdir="$1"
  local root_dir="$2"
  local service_name="$3"
  local mock_bin="$workdir/mock-bin"

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
Environment="ENV_FILE=$root_dir/etc/a1.env"
Environment='LOG_DIR=$root_dir/log'
ExecStart=$root_dir/bin/launch-a1.sh
EOF

  cat > "$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  show)
    if [ "$2" = '-p' ] && [ "$3" = 'Environment' ] && [ "$4" = '--value' ]; then
      printf '%s\n' "${MOCK_SYSTEMCTL_ENVIRONMENT:-}"
    elif [ "$2" = '-p' ] && [ "$3" = 'ExecStart' ] && [ "$4" = '--value' ]; then
      printf '%s\n' "${MOCK_SYSTEMCTL_EXECSTART:-}"
    else
      printf 'unexpected systemctl show args: %s\n' "$*" >&2
      exit 2
    fi
    ;;
  is-enabled)
    printf '%s\n' "${MOCK_SYSTEMCTL_ENABLED:-enabled}"
    ;;
  is-active)
    printf '%s\n' "${MOCK_SYSTEMCTL_ACTIVE:-inactive}"
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
}

run_success_case() {
  local workdir
  local root_dir
  local service_name
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN
  root_dir="$workdir/custom-root"
  service_name='custom-oci-a1-runner.service'

  make_layout "$workdir" "$root_dir" "$service_name"

  PATH="$workdir/mock-bin:$PATH" \
  SYSTEMD_DIR="$workdir/etc/systemd/system" \
  MOCK_SYSTEMCTL_ENABLED='enabled' \
  MOCK_SYSTEMCTL_ACTIVE='inactive' \
  MOCK_SYSTEMCTL_ENVIRONMENT="ENV_FILE=$root_dir/etc/a1.env LOG_DIR=$root_dir/log" \
  MOCK_SYSTEMCTL_EXECSTART="{ path=$root_dir/bin/launch-a1.sh ; argv[]=$root_dir/bin/launch-a1.sh ; }" \
  bash "$SCRIPT_PATH" --root "$root_dir" --service "$service_name" > "$workdir/output.log"

  assert_grep '^\[OK\] launch script present$' "$workdir/output.log"
  assert_grep '^\[OK\] check-runner helper present$' "$workdir/output.log"
  assert_grep '^\[OK\] service unit present$' "$workdir/output.log"
  assert_grep '^\[OK\] service env path matches selected root$' "$workdir/output.log"
  assert_grep '^\[OK\] required env key present: IMAGE_ID$' "$workdir/output.log"
  assert_grep '^\[OK\] service is enabled: custom-oci-a1-runner.service$' "$workdir/output.log"
  assert_grep '^\[WARN\] service is not active: custom-oci-a1-runner.service$' "$workdir/output.log"
  assert_grep '^\[OK\] check-runner helper executed$' "$workdir/output.log"

  trap - RETURN
  rm -rf "$workdir"
}

run_missing_key_case() {
  local workdir
  local root_dir
  local service_name
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN
  root_dir="$workdir/root"
  service_name='oci-a1-runner.service'

  make_layout "$workdir" "$root_dir" "$service_name"
  grep -v '^IMAGE_ID=' "$root_dir/etc/a1.env" > "$root_dir/etc/a1.env.tmp"
  mv "$root_dir/etc/a1.env.tmp" "$root_dir/etc/a1.env"

  if PATH="$workdir/mock-bin:$PATH" SYSTEMD_DIR="$workdir/etc/systemd/system" MOCK_SYSTEMCTL_ENVIRONMENT="ENV_FILE=$root_dir/etc/a1.env LOG_DIR=$root_dir/log" MOCK_SYSTEMCTL_EXECSTART="{ path=$root_dir/bin/launch-a1.sh ; argv[]=$root_dir/bin/launch-a1.sh ; }" bash "$SCRIPT_PATH" --root "$root_dir" --service "$service_name" > "$workdir/output.log" 2>&1; then
    fail 'expected missing IMAGE_ID to fail'
  fi

  assert_grep '^\[FAIL\] missing required env key: IMAGE_ID$' "$workdir/output.log"

  trap - RETURN
  rm -rf "$workdir"
}

run_service_path_mismatch_case() {
  local workdir
  local root_dir
  local service_name
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN
  root_dir="$workdir/root"
  service_name='oci-a1-runner.service'

  make_layout "$workdir" "$root_dir" "$service_name"
  cat > "$workdir/etc/systemd/system/$service_name" <<EOF
[Service]
Environment=ENV_FILE=/wrong/etc/a1.env
Environment=LOG_DIR=$root_dir/log
ExecStart=$root_dir/bin/launch-a1.sh
EOF

  if PATH="$workdir/mock-bin:$PATH" SYSTEMD_DIR="$workdir/etc/systemd/system" MOCK_SYSTEMCTL_ENVIRONMENT="ENV_FILE=/wrong/etc/a1.env LOG_DIR=$root_dir/log" MOCK_SYSTEMCTL_EXECSTART="{ path=$root_dir/bin/launch-a1.sh ; argv[]=$root_dir/bin/launch-a1.sh ; }" bash "$SCRIPT_PATH" --root "$root_dir" --service "$service_name" > "$workdir/output.log" 2>&1; then
    fail 'expected service env path mismatch to fail'
  fi

  assert_grep '^\[FAIL\] service env path mismatch$' "$workdir/output.log"
  assert_not_grep '^\[FAIL\] service log path mismatch$' "$workdir/output.log"

  trap - RETURN
  rm -rf "$workdir"
}

run_warning_only_inactive_case() {
  local workdir
  local root_dir
  local service_name
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN
  root_dir="$workdir/root"
  service_name='oci-a1-runner.service'

  make_layout "$workdir" "$root_dir" "$service_name"

  PATH="$workdir/mock-bin:$PATH" \
  SYSTEMD_DIR="$workdir/etc/systemd/system" \
  MOCK_SYSTEMCTL_ENABLED='disabled' \
  MOCK_SYSTEMCTL_ACTIVE='inactive' \
  MOCK_SYSTEMCTL_ENVIRONMENT="ENV_FILE=$root_dir/etc/a1.env LOG_DIR=$root_dir/log" \
  MOCK_SYSTEMCTL_EXECSTART="{ path=$root_dir/bin/launch-a1.sh ; argv[]=$root_dir/bin/launch-a1.sh ; }" \
  bash "$SCRIPT_PATH" --root "$root_dir" --service "$service_name" > "$workdir/output.log"

  assert_grep '^\[WARN\] service is not enabled: oci-a1-runner.service$' "$workdir/output.log"
  assert_grep '^\[WARN\] service is not active: oci-a1-runner.service$' "$workdir/output.log"
  assert_not_grep '^\[FAIL\]' "$workdir/output.log"

  trap - RETURN
  rm -rf "$workdir"
}

run_fallback_to_unit_file_case() {
  local workdir
  local root_dir
  local service_name
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN
  root_dir="$workdir/root"
  service_name='oci-a1-runner.service'

  make_layout "$workdir" "$root_dir" "$service_name"

  PATH="$workdir/mock-bin:$PATH" \
  SYSTEMD_DIR="$workdir/etc/systemd/system" \
  MOCK_SYSTEMCTL_ENABLED='enabled' \
  MOCK_SYSTEMCTL_ACTIVE='active' \
  MOCK_SYSTEMCTL_ENVIRONMENT='' \
  MOCK_SYSTEMCTL_EXECSTART='' \
  bash "$SCRIPT_PATH" --root "$root_dir" --service "$service_name" > "$workdir/output.log"

  assert_grep '^\[OK\] service env path matches selected root$' "$workdir/output.log"
  assert_grep '^\[OK\] service log path matches selected root$' "$workdir/output.log"
  assert_grep '^\[OK\] service ExecStart matches selected root$' "$workdir/output.log"
  assert_grep '^\[OK\] service is active: oci-a1-runner.service$' "$workdir/output.log"

  trap - RETURN
  rm -rf "$workdir"
}

run_success_case
run_missing_key_case
run_service_path_mismatch_case
run_warning_only_inactive_case
run_fallback_to_unit_file_case

printf 'PASS\n'
