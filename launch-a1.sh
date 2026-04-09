#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${ENV_FILE:-/home/ubuntu/oci-runner/etc/a1.env}"
LOG_DIR="${LOG_DIR:-/home/ubuntu/oci-runner/log}"
mkdir -p "$LOG_DIR"

fatal() {
  printf '[%s] %s\n' "$(date -Is)" "$*" >&2
  exit 1
}

is_allowed_env_key() {
  case "$1" in
    COMPARTMENT_ID|SUBNET_ID|IMAGE_ID|SSH_AUTHORIZED_KEYS_FILE|DISPLAY_NAME|SHAPE|OCPUS|MEMORY_IN_GBS|BOOT_VOLUME_SIZE_GBS|BOOT_VOLUME_VPUS_PER_GB|ASSIGN_PUBLIC_IP|RETRY_MIN_SECONDS|RETRY_MAX_SECONDS|INTER_AD_MIN_SECONDS|INTER_AD_MAX_SECONDS|OCI_CLI|OCI_CLI_PROFILE|SUCCESS_SENTINEL|DISCORD_API_BASE|DISCORD_BOT_TOKEN|DISCORD_CHANNEL_ID)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_matching_quotes() {
  local value="$1"
  local length="${#value}"
  if [ "$length" -ge 2 ]; then
    local first_char="${value:0:1}"
    local last_char="${value:length-1:1}"
    if { [ "$first_char" = '"' ] && [ "$last_char" = '"' ]; } || { [ "$first_char" = "'" ] && [ "$last_char" = "'" ]; }; then
      value="${value:1:length-2}"
    fi
  fi
  printf '%s' "$value"
}

load_env_file() {
  local env_file="$1"
  local line=''
  local line_number=0
  local key=''
  local value=''

  if [ ! -f "$env_file" ]; then
    fatal "env file not found: $env_file"
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))

    case "$line" in
      ''|'#'*)
        continue
        ;;
    esac

    if [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
    else
      fatal "invalid env line ${line_number} in ${env_file}"
    fi

    if ! is_allowed_env_key "$key"; then
      fatal "unsupported env key ${key} in ${env_file}"
    fi

    value="$(trim_whitespace "$value")"
    value="$(strip_matching_quotes "$value")"
    printf -v "$key" '%s' "$value"
  done < "$env_file"
}

load_env_file "$ENV_FILE"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a "$LOG_DIR/launch-a1.log"
}

timestamp_slug() {
  date -u '+%Y%m%dT%H%M%SZ'
}

first_error_summary() {
  local error_file="$1"
  local message
  message="$(sed -n 's/.*"message": "\([^"]*\)".*/\1/p' "$error_file" | head -n 1)"
  if [ -n "$message" ]; then
    printf '%s\n' "$message"
    return 0
  fi
  awk '
    NF {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 ~ /^[{}]$/) next
      if ($0 ~ /^[A-Za-z]+Exception:$/) next
      parts[++count] = $0
      if (count == 2) {
        printf "%s %s\n", parts[1], parts[2]
        exit
      }
    }
    END {
      if (count == 1) print parts[1]
    }
  ' "$error_file"
}

error_is_capacity() {
  local error_file="$1"
  grep -Eiq 'Out of host capacity|Out of capacity|OutOfHostCapacity|LimitExceeded|TooManyRequests' "$error_file"
}

error_is_transient_network() {
  local error_file="$1"
  grep -Eiq 'The connection to endpoint timed out|i/o timeout|Read timed out|Connection timed out|Connection reset by peer|Temporary failure in name resolution|Name or service not known|Remote end closed connection without response' "$error_file"
}

save_error_snapshot() {
  local prefix="$1"
  local error_file="$2"
  local ad="$3"
  local safe_ad="$4"
  local error_snapshot="$LOG_DIR/${prefix}-$(timestamp_slug)-${safe_ad}.log"

  cp "$error_file" "$error_snapshot"
  printf '[%s] AD=%s snapshot=%s\n' "$(date -Is)" "$ad" "$error_snapshot" >> "$LOG_DIR/${prefix}-errors.log"
  printf '%s\n' "$error_snapshot"
}

resolve_boot_volume_id() {
  local instance_id="$1"
  local ad="$2"

  "${OCI_BASE[@]}" compute boot-volume-attachment list \
    --availability-domain "$ad" \
    --compartment-id "$COMPARTMENT_ID" \
    --instance-id "$instance_id" \
    --all \
    --query 'data[0]."boot-volume-id"' \
    --raw-output 2>>"$LOG_DIR/launch-a1.log" || true
}

resolve_public_ip() {
  local instance_id="$1"
  local vnic_id

  vnic_id="$("${OCI_BASE[@]}" compute vnic-attachment list \
    --compartment-id "$COMPARTMENT_ID" \
    --instance-id "$instance_id" \
    --all \
    --query 'data[0]."vnic-id"' \
    --raw-output 2>>"$LOG_DIR/launch-a1.log" || true)"

  if [ -z "$vnic_id" ] || [ "$vnic_id" = 'null' ]; then
    return 0
  fi

  "${OCI_BASE[@]}" network vnic get --vnic-id "$vnic_id" \
    --query 'data."public-ip"' --raw-output 2>>"$LOG_DIR/launch-a1.log" || true
}

write_success_artifacts() {
  local instance_id="$1"
  local boot_volume_id="$2"
  local public_ip="$3"
  local ad="$4"
  local state="$5"
  local source="$6"

  cat > "$SUCCESS_SENTINEL" <<JSON
{
  "instance_id": "$instance_id",
  "boot_volume_id": "$boot_volume_id",
  "public_ip": "$public_ip",
  "availability_domain": "$ad",
  "state": "$state",
  "source": "$source",
  "time": "$(date -Is)"
}
JSON

  cat > "$LOG_DIR/a1-success.txt" <<TXT
display_name: $DISPLAY_NAME
availability_domain: $ad
instance_id: $instance_id
boot_volume_id: ${boot_volume_id:-unknown}
public_ip: ${public_ip:-unknown}
state: $state
source: $source
boot_volume_vpus_per_gb: $BOOT_VOLUME_VPUS_PER_GB
time: $(date -Is)
TXT
}

find_existing_instance() {
  "${OCI_BASE[@]}" compute instance list --all \
    --compartment-id "$COMPARTMENT_ID" \
    --output json 2>>"$LOG_DIR/launch-a1.log" | jq -c \
    --arg display_name "$DISPLAY_NAME" \
    --arg shape "$SHAPE" \
    '.data[]
      | select(."display-name" == $display_name)
      | select(.shape == $shape)
      | select(."lifecycle-state" != "TERMINATED")
      | select(."lifecycle-state" != "TERMINATING")' | head -n 1
}

record_existing_instance_and_exit() {
  local existing_json="$1"
  local instance_id
  local ad
  local state
  local boot_volume_id
  local public_ip

  instance_id="$(jq -r '.id' <<<"$existing_json")"
  ad="$(jq -r '."availability-domain"' <<<"$existing_json")"
  state="$(jq -r '."lifecycle-state"' <<<"$existing_json")"
  boot_volume_id="$(resolve_boot_volume_id "$instance_id" "$ad")"
  public_ip="$(resolve_public_ip "$instance_id")"

  if [ -z "$boot_volume_id" ] || [ "$boot_volume_id" = 'null' ]; then
    boot_volume_id='unknown'
  fi

  if [ -z "$public_ip" ] || [ "$public_ip" = 'null' ]; then
    public_ip='unknown'
  fi

  write_success_artifacts "$instance_id" "$boot_volume_id" "$public_ip" "$ad" "$state" 'existing-instance-check'
  log "existing instance detected: $instance_id state=$state ad=$ad"
  discord_post "OCI A1 已偵測到既有機器: ${DISPLAY_NAME} | AD=${ad} | state=${state} | IP=${public_ip} | instance_id=${instance_id}"
  exit 0
}

random_between() {
  local min="$1"
  local max="$2"
  if [ "$max" -lt "$min" ]; then
    max="$min"
  fi
  local span=$((max - min + 1))
  printf '%s' "$((min + RANDOM % span))"
}

sleep_range() {
  local min="$1"
  local max="$2"
  local label="$3"
  local seconds
  seconds="$(random_between "$min" "$max")"
  log "sleep ${seconds}s before ${label}"
  sleep "$seconds"
}

rand_sleep() {
  sleep_range "${RETRY_MIN_SECONDS:-97}" "${RETRY_MAX_SECONDS:-421}" "next retry"
}

inter_ad_sleep() {
  sleep_range "${INTER_AD_MIN_SECONDS:-11}" "${INTER_AD_MAX_SECONDS:-37}" "next AD attempt"
}

discord_post() {
  local message="$1"
  if [ -z "${DISCORD_BOT_TOKEN:-}" ] || [ -z "${DISCORD_CHANNEL_ID:-}" ]; then
    return 0
  fi

  local payload
  payload="$(jq -cn --arg content "$message" '{content: $content}')"
  curl -fsS \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "${DISCORD_API_BASE:-https://discord.com/api/v10}/channels/${DISCORD_CHANNEL_ID}/messages" \
    >/dev/null || log "discord notification failed"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing required command: $1"
    exit 1
  }
}

require_cmd jq
require_cmd curl
if [ ! -x "$OCI_CLI" ]; then
  log "OCI CLI not executable at $OCI_CLI"
  exit 1
fi

if [ -f "$SUCCESS_SENTINEL" ]; then
  log "success sentinel exists at $SUCCESS_SENTINEL; exiting without launching"
  exit 0
fi

OCI_BASE=("$OCI_CLI" --profile "$OCI_CLI_PROFILE")

log "fetching availability domains"
mapfile -t ADS < <("${OCI_BASE[@]}" iam availability-domain list --all \
  --compartment-id "$COMPARTMENT_ID" \
  --output json | jq -r '.data[].name')

if [ "${#ADS[@]}" -eq 0 ]; then
  log "no availability domains found"
  exit 1
fi

log "target shape=$SHAPE ocpus=$OCPUS mem=${MEMORY_IN_GBS}GB boot=${BOOT_VOLUME_SIZE_GBS}GB vpu=${BOOT_VOLUME_VPUS_PER_GB}"

while true; do
  if [ -f "$SUCCESS_SENTINEL" ]; then
    log "success sentinel detected during loop; exiting"
    exit 0
  fi

  existing_instance_json=''
  if existing_instance_json="$(find_existing_instance)"; then
    if [ -n "$existing_instance_json" ]; then
      record_existing_instance_and_exit "$existing_instance_json"
    fi
  else
    log "existing instance check failed; continuing"
  fi

  for ad_index in "${!ADS[@]}"; do
    AD="${ADS[$ad_index]}"
    safe_ad="$(printf '%s' "$AD" | tr -d '\r' | tr ':/' '__')"
    result="$LOG_DIR/result-${safe_ad}.json"
    error_log="$LOG_DIR/error-${safe_ad}.log"

    existing_instance_json=''
    if existing_instance_json="$(find_existing_instance)"; then
      if [ -n "$existing_instance_json" ]; then
        record_existing_instance_and_exit "$existing_instance_json"
      fi
    else
      log "existing instance check failed before launch; continuing"
    fi

    log "trying AD=$AD"
    shape_config_json="$(jq -cn --argjson ocpus "$OCPUS" --argjson memory "$MEMORY_IN_GBS" '{ocpus: $ocpus, memoryInGBs: $memory}')"
    if "${OCI_BASE[@]}" compute instance launch \
      --no-retry \
      --availability-domain "$AD" \
      --compartment-id "$COMPARTMENT_ID" \
      --display-name "$DISPLAY_NAME" \
      --shape "$SHAPE" \
      --shape-config "$shape_config_json" \
      --subnet-id "$SUBNET_ID" \
      --assign-public-ip "$ASSIGN_PUBLIC_IP" \
      --image-id "$IMAGE_ID" \
      --boot-volume-size-in-gbs "$BOOT_VOLUME_SIZE_GBS" \
      --ssh-authorized-keys-file "$SSH_AUTHORIZED_KEYS_FILE" \
      --wait-for-state RUNNING \
      --max-wait-seconds 1800 \
      --wait-interval-seconds 30 \
      >"$result" 2>"$error_log"; then

      INSTANCE_ID="$(jq -r '.data.id' "$result")"
      if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "null" ]; then
        log "instance launch reported success but no instance id found"
        exit 1
      fi

      log "instance created successfully: $INSTANCE_ID"

      BOOT_VOLUME_ID="$(resolve_boot_volume_id "$INSTANCE_ID" "$AD")"

      if [ -z "$BOOT_VOLUME_ID" ] || [ "$BOOT_VOLUME_ID" = "null" ]; then
        log "could not resolve boot volume id for instance $INSTANCE_ID"
        exit 1
      fi

      log "boot volume found: $BOOT_VOLUME_ID"
      log "updating boot volume VPU to $BOOT_VOLUME_VPUS_PER_GB"

      "${OCI_BASE[@]}" bv boot-volume update \
        --boot-volume-id "$BOOT_VOLUME_ID" \
        --vpus-per-gb "$BOOT_VOLUME_VPUS_PER_GB" \
        --force \
        --wait-for-state AVAILABLE \
        --max-wait-seconds 1800 \
        --wait-interval-seconds 30 \
        >>"$LOG_DIR/launch-a1.log" 2>>"$LOG_DIR/launch-a1.log"

      PUBLIC_IP="$(resolve_public_ip "$INSTANCE_ID")"

      if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = 'null' ]; then
        PUBLIC_IP='unknown'
      fi

      write_success_artifacts "$INSTANCE_ID" "$BOOT_VOLUME_ID" "$PUBLIC_IP" "$AD" 'RUNNING' 'launch-success'

      discord_post "OCI A1 搶到機器了: ${DISPLAY_NAME} | AD=${AD} | IP=${PUBLIC_IP:-unknown} | instance_id=${INSTANCE_ID}"
      log "success instance_id=$INSTANCE_ID public_ip=${PUBLIC_IP:-unknown}"
      exit 0
    else
      log "launch failed in AD=$AD"
      if error_is_capacity "$error_log"; then
        log "capacity or rate-limit error detected"
      elif error_is_transient_network "$error_log"; then
        error_snapshot="$(save_error_snapshot transient "$error_log" "$AD" "$safe_ad")"
        log "transient network error detected"
        log "saved transient error snapshot to $error_snapshot"
        sed 's/^/[oci] /' "$error_log" | tee -a "$LOG_DIR/launch-a1.log"
      else
        error_snapshot="$(save_error_snapshot noncapacity "$error_log" "$AD" "$safe_ad")"
        log "non-capacity error follows"
        log "saved non-capacity error snapshot to $error_snapshot"
        sed 's/^/[oci] /' "$error_log" | tee -a "$LOG_DIR/launch-a1.log"
        error_summary="$(first_error_summary "$error_log")"
        discord_post "OCI A1 非容量錯誤
display_name=${DISPLAY_NAME}
AD=${AD}
snapshot=$(basename "$error_snapshot")
error=${error_summary}"
      fi
    fi

    if [ "$ad_index" -lt $(( ${#ADS[@]} - 1 )) ]; then
      inter_ad_sleep
    fi
  done

  rand_sleep
done
