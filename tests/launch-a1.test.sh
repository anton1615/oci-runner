#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${1:?usage: launch-a1.test.sh /path/to/launch-a1.sh}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

wait_for_pattern() {
  local file="$1"
  local pattern="$2"
  local attempts="${3:-50}"
  local delay="${4:-0.1}"
  local i
  for ((i = 0; i < attempts; i++)); do
    if [[ -f "$file" ]] && grep -qE "$pattern" "$file"; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

wait_for_file() {
  local file="$1"
  local attempts="${2:-50}"
  local delay="${3:-0.1}"
  local i
  for ((i = 0; i < attempts; i++)); do
    if [[ -f "$file" ]]; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

assert_file_exists() {
  [ -f "$1" ] || fail "expected file to exist: $1"
}

assert_file_missing() {
  [ ! -f "$1" ] || fail "did not expect file to exist: $1"
}

assert_no_match() {
  local pattern="$1"
  if compgen -G "$pattern" > /dev/null; then
    fail "did not expect files matching: $pattern"
  fi
}

assert_has_match() {
  local pattern="$1"
  if ! compgen -G "$pattern" > /dev/null; then
    fail "expected files matching: $pattern"
  fi
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

make_mock_oci() {
  local path="$1"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"iam availability-domain list"* ]]; then
  printf '{"data":[{"name":"BuyY:AP-TOKYO-1-AD-1"}]}'
  exit 0
fi

if [[ "$*" == *"compute instance list"* ]]; then
  if [[ "${MOCK_EXISTING_INSTANCE:-}" == "1" ]]; then
    cat <<'JSON'
{"data":[{"id":"ocid1.instance.oc1.ap-tokyo-1.exampleexisting","display-name":"oraclelinux-a1-4c24g","shape":"VM.Standard.A1.Flex","lifecycle-state":"RUNNING","availability-domain":"BuyY:AP-TOKYO-1-AD-1"}]}
JSON
  else
    printf '{"data":[]}'
  fi
  exit 0
fi

if [[ "$*" == *"compute boot-volume-attachment list"* ]]; then
  printf 'ocid1.bootvolume.oc1.ap-tokyo-1.exampleboot'
  exit 0
fi

if [[ "$*" == *"compute vnic-attachment list"* ]]; then
  printf 'ocid1.vnic.oc1.ap-tokyo-1.examplevnic'
  exit 0
fi

if [[ "$*" == *"network vnic get"* ]]; then
  printf '203.0.113.10'
  exit 0
fi

if [[ "$*" == *"compute instance launch"* ]]; then
  if [[ "${MOCK_EXISTING_INSTANCE:-}" == "1" ]]; then
    printf 'launch should not be called when existing instance is present\n' >&2
    exit 9
  fi
  if [[ "${MOCK_ERROR_TYPE:-}" == "success" ]]; then
    cat <<'JSON'
{"data":{"id":"ocid1.instance.oc1.ap-tokyo-1.examplesuccess"}}
JSON
    exit 0
  fi
  if [[ "${MOCK_ERROR_TYPE:-}" == "capacity" ]]; then
    cat >&2 <<'ERR'
ServiceError:
{
    "code": "InternalError",
    "message": "Out of host capacity.",
    "status": 500
}
ERR
  elif [[ "${MOCK_ERROR_TYPE:-}" == "rate_limit" ]]; then
    cat >&2 <<'ERR'
ServiceError:
{
    "code": "TooManyRequests",
    "message": "Too many requests for the requested service.",
    "status": 429
}
ERR
  elif [[ "${MOCK_ERROR_TYPE:-}" == "transient" ]]; then
    cat >&2 <<'ERR'
RequestException:
{
    "message": "dial tcp 129.146.1.1:443: i/o timeout"
}
ERR
  elif [[ "${MOCK_ERROR_TYPE:-}" == "transient_endpoint" ]]; then
    cat >&2 <<'ERR'
RequestException:
{
    "message": "The connection to endpoint timed out."
}
ERR
  else
    cat >&2 <<'ERR'
ServiceError:
{
    "code": "InternalError",
    "message": "Unexpected backend failure.",
    "status": 500
}
ERR
  fi
  exit 1
fi

if [[ "$*" == *"bv boot-volume update"* ]]; then
  printf '{}'
  exit 0
fi

printf 'unexpected mock OCI args: %s\n' "$*" >&2
exit 2
EOF
  chmod +x "$path"
}

make_mock_curl() {
  local path="$1"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

payload=''
url=''
while (($#)); do
  case "$1" in
    -d)
      payload="$2"
      shift 2
      ;;
    http*|file://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

target_dir="${MOCK_DISCORD_DIR:?}"
mkdir -p "$target_dir"
printf '%s\n' "$payload" > "$target_dir/messages"
printf '{"id":"mock-message"}\n'
EOF
  chmod +x "$path"
}

make_env_file() {
  local path="$1"
  local base_dir="$2"
  cat > "$path" <<EOF
OCI_CLI=$base_dir/mock-oci.sh
OCI_CLI_PROFILE=DEFAULT
COMPARTMENT_ID=ocid1.tenancy.oc1..example
SHAPE=VM.Standard.A1.Flex
OCPUS=4
MEMORY_IN_GBS=24
BOOT_VOLUME_SIZE_GBS=150
BOOT_VOLUME_VPUS_PER_GB=120
SUBNET_ID=ocid1.subnet.oc1.ap-tokyo-1.example
ASSIGN_PUBLIC_IP=true
IMAGE_ID=ocid1.image.oc1.ap-tokyo-1.example
SSH_AUTHORIZED_KEYS_FILE=$base_dir/authorized_keys
DISPLAY_NAME=oraclelinux-a1-4c24g
SUCCESS_SENTINEL=$base_dir/success.json
RETRY_MIN_SECONDS=1
RETRY_MAX_SECONDS=1
INTER_AD_MIN_SECONDS=1
INTER_AD_MAX_SECONDS=1
DISCORD_BOT_TOKEN=test-bot-token
DISCORD_CHANNEL_ID=test-channel-id
DISCORD_API_BASE=file://$base_dir/discord-api
EOF
}

run_case() {
  local case_name="$1"
  local error_type="$2"
  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  mkdir -p "$workdir/log"
  mkdir -p "$workdir/discord-api/channels/test-channel-id"
  : > "$workdir/authorized_keys"
  make_mock_oci "$workdir/mock-oci.sh"
  make_mock_curl "$workdir/curl"
  make_env_file "$workdir/a1.env" "$workdir"

  set +e
  env MOCK_ERROR_TYPE="$error_type" MOCK_EXISTING_INSTANCE="$([[ "$case_name" == "existing" ]] && printf 1 || printf 0)" MOCK_DISCORD_DIR="$workdir/discord-api/channels/test-channel-id" PATH="$workdir:$PATH" ENV_FILE="$workdir/a1.env" LOG_DIR="$workdir/log" bash "$SCRIPT_PATH" >"$workdir/stdout.log" 2>"$workdir/stderr.log" &
  local script_pid=$!
  if [[ "$case_name" == "existing" ]]; then
    wait_for_pattern "$workdir/log/launch-a1.log" 'existing instance detected' 60 0.1 || true
    wait_for_file "$workdir/success.json" 60 0.1 || true
  elif [[ "$case_name" == "launch_success" ]]; then
    wait_for_pattern "$workdir/log/launch-a1.log" 'instance created successfully' 60 0.1 || true
    wait_for_file "$workdir/success.json" 60 0.1 || true
    wait_for_file "$workdir/discord-api/channels/test-channel-id/messages" 60 0.1 || true
  elif [[ "$case_name" == "unknown" ]]; then
    wait_for_pattern "$workdir/log/launch-a1.log" 'saved non-capacity error snapshot' 60 0.1 || true
    wait_for_file "$workdir/discord-api/channels/test-channel-id/messages" 60 0.1 || true
  elif [[ "$case_name" == "transient" || "$case_name" == "transient_endpoint" ]]; then
    wait_for_pattern "$workdir/log/launch-a1.log" 'saved transient error snapshot' 60 0.1 || true
  else
    wait_for_pattern "$workdir/log/launch-a1.log" 'capacity or rate-limit error detected' 60 0.1 || true
  fi
  sleep 0.2
  local status
  if kill -0 "$script_pid" 2>/dev/null; then
    kill "$script_pid" 2>/dev/null || true
    wait "$script_pid" 2>/dev/null || true
    status=124
  else
    wait "$script_pid"
    status=$?
  fi
  set -e

  if [[ "$status" -ne 0 && "$status" -ne 124 ]]; then
    if [[ -f "$workdir/stdout.log" ]]; then
      printf '%s\n' '--- stdout ---' >&2
      cat "$workdir/stdout.log" >&2
    fi
    if [[ -f "$workdir/stderr.log" ]]; then
      printf '%s\n' '--- stderr ---' >&2
      cat "$workdir/stderr.log" >&2
    fi
    if [[ -f "$workdir/log/launch-a1.log" ]]; then
      printf '%s\n' '--- launch-a1.log ---' >&2
      cat "$workdir/log/launch-a1.log" >&2
    fi
    fail "$case_name exited with unexpected status $status"
  fi

  assert_file_exists "$workdir/log/launch-a1.log"

  if [[ "$case_name" == "existing" ]]; then
    assert_file_exists "$workdir/success.json"
    assert_file_exists "$workdir/log/a1-success.txt"
    assert_grep 'existing instance detected' "$workdir/log/launch-a1.log"
    assert_grep 'existing-instance-check' "$workdir/success.json"
    assert_grep 'ocid1.instance.oc1.ap-tokyo-1.exampleexisting' "$workdir/success.json"
    assert_grep '203.0.113.10' "$workdir/success.json"
    assert_grep 'state: RUNNING' "$workdir/log/a1-success.txt"
    assert_grep 'source: existing-instance-check' "$workdir/log/a1-success.txt"
    assert_not_grep 'trying AD=' "$workdir/log/launch-a1.log"
  elif [[ "$case_name" == "launch_success" ]]; then
    assert_file_exists "$workdir/success.json"
    assert_file_exists "$workdir/log/a1-success.txt"
    assert_grep 'launch-success' "$workdir/success.json"
    assert_grep 'ocid1.instance.oc1.ap-tokyo-1.examplesuccess' "$workdir/success.json"
    assert_grep 'ocid1.bootvolume.oc1.ap-tokyo-1.exampleboot' "$workdir/success.json"
    assert_grep '203.0.113.10' "$workdir/success.json"
    assert_grep 'state: RUNNING' "$workdir/log/a1-success.txt"
    assert_grep 'source: launch-success' "$workdir/log/a1-success.txt"
    assert_grep 'instance created successfully' "$workdir/log/launch-a1.log"
    assert_grep 'updating boot volume VPU to 120' "$workdir/log/launch-a1.log"
    assert_file_exists "$workdir/discord-api/channels/test-channel-id/messages"
    assert_grep 'OCI A1 搶到機器了' "$workdir/discord-api/channels/test-channel-id/messages"
  elif [[ "$case_name" == "unknown" ]]; then
    assert_file_exists "$workdir/log/noncapacity-errors.log"
    assert_has_match "$workdir/log/noncapacity-*-BuyY_AP-TOKYO-1-AD-1.log"
    assert_file_exists "$workdir/discord-api/channels/test-channel-id/messages"
    local snapshot
    snapshot="$(compgen -G "$workdir/log/noncapacity-*-BuyY_AP-TOKYO-1-AD-1.log" | head -n 1)"
    assert_file_exists "$snapshot"
    assert_grep 'Unexpected backend failure\.' "$snapshot"
    assert_grep 'non-capacity error follows' "$workdir/log/launch-a1.log"
    assert_grep 'OCI A1 非容量錯誤' "$workdir/discord-api/channels/test-channel-id/messages"
    assert_grep 'display_name=oraclelinux-a1-4c24g' "$workdir/discord-api/channels/test-channel-id/messages"
    assert_grep 'AD=BuyY:AP-TOKYO-1-AD-1' "$workdir/discord-api/channels/test-channel-id/messages"
    assert_grep 'snapshot=' "$workdir/discord-api/channels/test-channel-id/messages"
    assert_grep 'Unexpected backend failure\.' "$workdir/discord-api/channels/test-channel-id/messages"
    [ ! -f "$workdir/log/transient-errors.log" ] || fail 'did not expect transient-errors.log for unknown case'
  elif [[ "$case_name" == "transient" || "$case_name" == "transient_endpoint" ]]; then
    assert_file_exists "$workdir/log/transient-errors.log"
    assert_has_match "$workdir/log/transient-*-BuyY_AP-TOKYO-1-AD-1.log"
    local transient_snapshot
    transient_snapshot="$(compgen -G "$workdir/log/transient-*-BuyY_AP-TOKYO-1-AD-1.log" | head -n 1)"
    assert_file_exists "$transient_snapshot"
    if [[ "$case_name" == "transient_endpoint" ]]; then
      assert_grep 'The connection to endpoint timed out\.' "$transient_snapshot"
    else
      assert_grep 'i/o timeout' "$transient_snapshot"
    fi
    assert_grep 'transient network error detected' "$workdir/log/launch-a1.log"
    assert_not_grep 'non-capacity error follows' "$workdir/log/launch-a1.log"
    [ ! -f "$workdir/log/noncapacity-errors.log" ] || fail 'did not expect noncapacity-errors.log for transient case'
    [ ! -f "$workdir/discord-api/channels/test-channel-id/messages" ] || fail 'did not expect discord message for transient case'
  else
    assert_no_match "$workdir/log/noncapacity-*-BuyY_AP-TOKYO-1-AD-1.log"
    [ ! -f "$workdir/log/noncapacity-errors.log" ] || fail 'did not expect noncapacity-errors.log for capacity case'
    assert_no_match "$workdir/log/transient-*-BuyY_AP-TOKYO-1-AD-1.log"
    [ ! -f "$workdir/log/transient-errors.log" ] || fail 'did not expect transient-errors.log for capacity case'
    assert_grep 'capacity or rate-limit error detected' "$workdir/log/launch-a1.log"
    assert_not_grep 'non-capacity error follows' "$workdir/log/launch-a1.log"
    [ ! -f "$workdir/discord-api/channels/test-channel-id/messages" ] || fail 'did not expect discord message for capacity case'
  fi

  trap - RETURN
  rm -rf "$workdir"
}

run_invalid_env_case() {
  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  mkdir -p "$workdir/log"
  : > "$workdir/authorized_keys"
  make_mock_oci "$workdir/mock-oci.sh"
  make_mock_curl "$workdir/curl"
  cat > "$workdir/bad.env" <<EOF
OCI_CLI=$workdir/mock-oci.sh
OCI_CLI_PROFILE=DEFAULT
COMPARTMENT_ID=ocid1.tenancy.oc1..example
SHAPE=VM.Standard.A1.Flex
OCPUS=4
MEMORY_IN_GBS=24
BOOT_VOLUME_SIZE_GBS=150
BOOT_VOLUME_VPUS_PER_GB=120
SUBNET_ID=ocid1.subnet.oc1.ap-tokyo-1.example
ASSIGN_PUBLIC_IP=true
IMAGE_ID=ocid1.image.oc1.ap-tokyo-1.example
SSH_AUTHORIZED_KEYS_FILE=$workdir/authorized_keys
DISPLAY_NAME=oraclelinux-a1-4c24g
SUCCESS_SENTINEL=$workdir/success.json
RETRY_MIN_SECONDS=1
RETRY_MAX_SECONDS=1
INTER_AD_MIN_SECONDS=1
INTER_AD_MAX_SECONDS=1
DISCORD_BOT_TOKEN=test-bot-token
DISCORD_CHANNEL_ID=test-channel-id
DISCORD_API_BASE=file://$workdir/discord-api
touch "$workdir/pwned"; exit 99
EOF

  set +e
  PATH="$workdir:$PATH" ENV_FILE="$workdir/bad.env" LOG_DIR="$workdir/log" bash "$SCRIPT_PATH" >"$workdir/stdout.log" 2>"$workdir/stderr.log"
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    fail 'invalid env case unexpectedly succeeded'
  fi

  assert_file_missing "$workdir/pwned"
  assert_grep 'invalid env line' "$workdir/stderr.log"

  trap - RETURN
  rm -rf "$workdir"
}

run_case existing noop
run_case launch_success success
run_case unknown unknown
run_case transient transient
run_case transient_endpoint transient_endpoint
run_case capacity rate_limit
run_case capacity capacity
run_invalid_env_case

printf 'PASS\n'
