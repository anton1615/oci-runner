#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="${SERVICE_NAME:-oci-a1-runner.service}"
ENV_FILE="${ENV_FILE:-/home/ubuntu/oci-runner/etc/a1.env}"
LOG_DIR="${LOG_DIR:-/home/ubuntu/oci-runner/log}"

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
      first_char="${value:0:1}"
      last_char="${value:${#value}-1:1}"
      if { [ "$first_char" = '"' ] && [ "$last_char" = '"' ]; } || { [ "$first_char" = "'" ] && [ "$last_char" = "'" ]; }; then
        value="${value:1:${#value}-2}"
      fi
    fi

    printf '%s\n' "$value"
    return 0
  done < "$env_file"
}

success_sentinel="$(read_env_value "$ENV_FILE" SUCCESS_SENTINEL)"
SUCCESS_JSON="${SUCCESS_JSON:-${success_sentinel:-$LOG_DIR/a1-success.json}}"
SUCCESS_TXT="${SUCCESS_TXT:-$LOG_DIR/a1-success.txt}"
RUN_LOG="${RUN_LOG:-$LOG_DIR/launch-a1.log}"

echo "== service =="
systemctl status "$SERVICE_NAME" --no-pager || true

echo
echo "== success summary =="
if [ -f "$SUCCESS_TXT" ]; then
  cat "$SUCCESS_TXT"
elif [ -f "$SUCCESS_JSON" ]; then
  cat "$SUCCESS_JSON"
else
  echo "no success sentinel yet"
fi

echo
echo "== latest runner log =="
if [ -f "$RUN_LOG" ]; then
  tail -n 20 "$RUN_LOG"
else
  echo "launch log missing"
fi

echo
echo "== recent journal =="
journalctl -u "$SERVICE_NAME" -n 20 --no-pager -o short-iso || true
