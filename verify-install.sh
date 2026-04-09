#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR='/home/ubuntu/oci-runner'
SERVICE_NAME='oci-a1-runner.service'
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
FAILED=0

ok() {
  printf '[OK] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

fail_check() {
  printf '[FAIL] %s\n' "$1"
  FAILED=1
}

escape_regex() {
  printf '%s' "$1" | sed 's/[][(){}.^$+*?|\\]/\\&/g'
}

usage() {
  printf 'usage: verify-install.sh [--root <path>] [--service <name>]\n' >&2
}

read_env_value() {
  local env_file="$1"
  local target_key="$2"
  local line=''
  local key=''
  local value=''

  if [ ! -f "$env_file" ]; then
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*)
        continue
        ;;
    esac

    if [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
    else
      continue
    fi

    if [ "$key" != "$target_key" ]; then
      continue
    fi

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [ "${#value}" -ge 2 ]; then
      local first_char="${value:0:1}"
      local last_char="${value:${#value}-1:1}"
      if { [ "$first_char" = '"' ] && [ "$last_char" = '"' ]; } || { [ "$first_char" = "'" ] && [ "$last_char" = "'" ]; }; then
        value="${value:1:${#value}-2}"
      fi
    fi

    printf '%s\n' "$value"
    return 0
  done < "$env_file"
}

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

service_env_matches() {
  local env_dump="$1"
  local assignment="$2"
  local escaped_assignment=''

  escaped_assignment="$(escape_regex "$assignment")"

  if [ -n "$env_dump" ]; then
    if printf '%s\n' "$env_dump" | grep -Eq "(^|[[:space:]])${escaped_assignment}($|[[:space:]])"; then
      return 0
    fi
  fi

  grep -qF "Environment=$assignment" "$SERVICE_PATH" || \
    grep -qF "Environment=\"$assignment\"" "$SERVICE_PATH" || \
    grep -qF "Environment='$assignment'" "$SERVICE_PATH"
}

service_execstart_matches() {
  local exec_dump="$1"

  if [ -n "$exec_dump" ] && printf '%s\n' "$exec_dump" | grep -Fq "$LAUNCH_PATH"; then
    return 0
  fi

  grep -qF "ExecStart=$LAUNCH_PATH" "$SERVICE_PATH"
}

while (($#)); do
  case "$1" in
    --root)
      if [ $# -lt 2 ]; then
        usage
        exit 1
      fi
      ROOT_DIR="$2"
      shift 2
      ;;
    --service)
      if [ $# -lt 2 ]; then
        usage
        exit 1
      fi
      SERVICE_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unsupported argument: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

LAUNCH_PATH="$ROOT_DIR/bin/launch-a1.sh"
CHECK_PATH="$ROOT_DIR/bin/check-runner.sh"
ENV_PATH="$ROOT_DIR/etc/a1.env"
SERVICE_PATH="$SYSTEMD_DIR/$SERVICE_NAME"

check_file "$LAUNCH_PATH" 'launch script'
check_file "$CHECK_PATH" 'check-runner helper'
check_file "$ENV_PATH" 'env file'
check_file "$SERVICE_PATH" 'service unit'
if [ -f "$LAUNCH_PATH" ]; then
  check_exec "$LAUNCH_PATH" 'launch script'
fi
if [ -f "$CHECK_PATH" ]; then
  check_exec "$CHECK_PATH" 'check-runner helper'
fi

if [ -f "$SERVICE_PATH" ]; then
  service_environment="$(systemctl show -p Environment --value "$SERVICE_NAME" 2>/dev/null || true)"
  service_execstart="$(systemctl show -p ExecStart --value "$SERVICE_NAME" 2>/dev/null || true)"

  if service_env_matches "$service_environment" "ENV_FILE=$ENV_PATH"; then
    ok 'service env path matches selected root'
  else
    fail_check 'service env path mismatch'
  fi

  if service_env_matches "$service_environment" "LOG_DIR=$ROOT_DIR/log"; then
    ok 'service log path matches selected root'
  else
    fail_check 'service log path mismatch'
  fi

  if service_execstart_matches "$service_execstart"; then
    ok 'service ExecStart matches selected root'
  else
    fail_check 'service ExecStart mismatch'
  fi
fi

if [ -f "$ENV_PATH" ]; then
  for key in COMPARTMENT_ID SUBNET_ID IMAGE_ID OCI_CLI OCI_CLI_PROFILE SUCCESS_SENTINEL; do
    if [ -n "$(read_env_value "$ENV_PATH" "$key")" ]; then
      ok "required env key present: $key"
    else
      fail_check "missing required env key: $key"
    fi
  done
fi

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

if [ -x "$CHECK_PATH" ]; then
  if ENV_FILE="$ENV_PATH" LOG_DIR="$ROOT_DIR/log" SERVICE_NAME="$SERVICE_NAME" "$CHECK_PATH" >/dev/null 2>&1; then
    ok 'check-runner helper executed'
  else
    fail_check 'check-runner helper failed'
  fi
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
