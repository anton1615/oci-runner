#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="/home/ubuntu/oci-runner"
START_SERVICE=0
SERVICE_NAME="oci-a1-runner.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fatal() {
  printf '%s\n' "$*" >&2
  exit 1
}

derive_service_user() {
  local root_dir="$1"
  local derived_user=''

  case "$root_dir" in
    /home/*/*)
      derived_user="${root_dir#/home/}"
      derived_user="${derived_user%%/*}"
      ;;
  esac

  if [ -z "$derived_user" ] && [ -n "${SUDO_USER:-}" ] && id -u "$SUDO_USER" >/dev/null 2>&1; then
    derived_user="$SUDO_USER"
  fi

  if [ -z "$derived_user" ]; then
    fatal 'could not derive a valid service user from --root or SUDO_USER'
  fi

  if ! getent passwd "$derived_user" >/dev/null 2>&1; then
    fatal "derived service user does not exist: $derived_user"
  fi

  printf '%s\n' "$derived_user"
}

usage() {
  cat <<'EOF'
Usage: install.sh [--root <path>] [--start]
EOF
}

while (($#)); do
  case "$1" in
    --root)
      if [ $# -lt 2 ]; then
        printf 'missing value for --root\n' >&2
        exit 1
      fi
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

if [ "$(id -u)" -ne 0 ]; then
  fatal 'install.sh must be run as root'
fi

if [ "$(uname -s)" != 'Linux' ]; then
  fatal 'install.sh only supports Linux'
fi

case "$ROOT_DIR" in
  /*)
    ;;
  *)
    fatal '--root must be an absolute path'
    ;;
esac

SERVICE_USER="$(derive_service_user "$ROOT_DIR")"

BIN_DIR="$ROOT_DIR/bin"
ETC_DIR="$ROOT_DIR/etc"
LOG_DIR="$ROOT_DIR/log"
ENV_PATH="$ETC_DIR/a1.env"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

mkdir -p "$BIN_DIR" "$ETC_DIR" "$LOG_DIR"
install -m 755 "$SCRIPT_DIR/launch-a1.sh" "$BIN_DIR/launch-a1.sh"
install -m 755 "$SCRIPT_DIR/check-runner.sh" "$BIN_DIR/check-runner.sh"
chown -R "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"
chmod 700 "$LOG_DIR"

if [ ! -f "$ENV_PATH" ]; then
  install -m 600 "$SCRIPT_DIR/a1.env.example" "$ENV_PATH"
  chown "$SERVICE_USER:$SERVICE_USER" "$ENV_PATH"
  chmod 600 "$ENV_PATH"
  printf 'created %s from a1.env.example\n' "$ENV_PATH"
else
  printf 'keeping existing %s\n' "$ENV_PATH"
  if ! sudo -u "$SERVICE_USER" test -r "$ENV_PATH"; then
    fatal "existing env is not readable by service user: $SERVICE_USER"
  fi
fi

tmp_service="$(mktemp)"
trap 'rm -f "$tmp_service"' EXIT
sed \
  -e "s|User=ubuntu|User=$SERVICE_USER|" \
  -e "s|Environment=ENV_FILE=/home/ubuntu/oci-runner/etc/a1.env|Environment=ENV_FILE=$ETC_DIR/a1.env|" \
  -e "s|Environment=LOG_DIR=/home/ubuntu/oci-runner/log|Environment=LOG_DIR=$LOG_DIR|" \
  -e "s|ExecStart=/home/ubuntu/oci-runner/bin/launch-a1.sh|ExecStart=$BIN_DIR/launch-a1.sh|" \
  "$SCRIPT_DIR/oci-a1-runner.service" > "$tmp_service"

sudo install -m 644 "$tmp_service" "$SERVICE_PATH"

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
if [ "$START_SERVICE" -eq 1 ]; then
  sudo systemctl start "$SERVICE_NAME"
fi

printf 'install complete for %s\n' "$ROOT_DIR"
printf 'edit %s before first real use\n' "$ENV_PATH"
