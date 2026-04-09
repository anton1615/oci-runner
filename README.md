# OCI A1 Runner

This repository packages a small OCI Always Free runner that keeps retrying
`VM.Standard.A1.Flex` launches until capacity becomes available or a matching
instance already exists.

It is extracted from an operational Oracle VM workspace and reduced to the
minimum set of files needed to understand, test, deploy, and reproduce the
runner on another machine.

## Included files

- `launch-a1.sh`
  Main retry loop and launch logic.
- `check-runner.sh`
  Small helper to inspect service state, success artifacts, and recent logs.
- `oci-a1-runner.service`
  Sample `systemd` unit.
- `a1.env.example`
  Sanitized configuration template.
- `install.sh`
  Minimal Linux installer for `systemd` deployments with root checks and service-user derivation.
- `verify-install.sh`
  Local post-install verification helper for deployment layout and service wiring.
- `tests/launch-a1.test.sh`
  Shell regression test with mocked OCI and Discord behavior.
- `tests/check-runner.test.sh`
  Shell regression test for helper-script path overrides and log display.
- `tests/install.test.sh`
  Shell regression test for installer path rendering and config preservation.
- `tests/verify-install.test.sh`
  Shell regression test for local install verification behavior and warning handling.
- `docs/superpowers/specs/2026-04-09-oci-runner-repo-design.md`
  Design document for this extracted repository.

## What the runner does

`launch-a1.sh` continuously tries to launch an OCI Always Free
`VM.Standard.A1.Flex` instance.

Current behavior:

- loads runtime settings from `ENV_FILE`
- creates and writes logs under `LOG_DIR`
- queries availability domains dynamically
- checks for an already existing matching instance before each launch cycle
- retries across returned ADs in order
- classifies failures into capacity, transient network, and non-capacity cases
- writes success artifacts after detecting an existing instance or creating a
  new one successfully
- sends Discord notifications for success and non-capacity failures only

## Prerequisites

You need a Linux machine with:

- `bash`
- `jq`
- `curl`
- `systemd` if you want to run it as a service
- OCI CLI installed and authenticated for the target profile

## Quick start

Default install:

```bash
sudo bash ./install.sh
sudo editor /home/ubuntu/oci-runner/etc/a1.env
sudo systemctl start oci-a1-runner.service
```

Quick validation after start:

```bash
bash ./check-runner.sh
sudo systemctl status oci-a1-runner.service --no-pager
```

You also need OCI-side prerequisites:

- permission to launch instances in the target compartment
- a valid subnet in the target region
- a valid image in the target region
- a usable SSH authorized keys file

Important environment note:

- The target machine does not have to be the exact original Oracle VM.
- It does need to operate against the same kind of OCI environment described by
  your own `a1.env`, meaning the machine must be able to use the OCI CLI
  profile and resource IDs you configure.
- If you want to reuse the same subnet, image, and compartment values from an
  existing deployment, the machine must have access to that same tenancy and
  resource topology.

## Environment setup

1. Copy `a1.env.example` to `a1.env`.
2. Replace all placeholder values.
3. Confirm `SSH_AUTHORIZED_KEYS_FILE` points to a real public key file.
4. Confirm `OCI_CLI` points to an executable OCI CLI binary.
5. Create the log directory referenced by `LOG_DIR` if you plan to override it.

Minimal example:

```bash
cp a1.env.example a1.env
```

Key settings in `a1.env`:

- `COMPARTMENT_ID`
- `SUBNET_ID`
- `IMAGE_ID`
- `DISPLAY_NAME`
- `SHAPE`
- `OCPUS`
- `MEMORY_IN_GBS`
- `BOOT_VOLUME_SIZE_GBS`
- `BOOT_VOLUME_VPUS_PER_GB`
- `SUCCESS_SENTINEL`
- `DISCORD_BOT_TOKEN`
- `DISCORD_CHANNEL_ID`

Format note:

- `a1.env` is expected to be a simple `KEY=value` file.
- The launcher only accepts a fixed allowlist of known keys.
- Do not add shell commands, command substitutions, or arbitrary script content.

## Deployment layout and path expectations

The sample files assume this deployment shape on the target host:

```text
/home/ubuntu/oci-runner/
  bin/launch-a1.sh
  bin/check-runner.sh
  etc/a1.env
  log/
```

The bundled `oci-a1-runner.service` points to:

- `ENV_FILE=/home/ubuntu/oci-runner/etc/a1.env`
- `LOG_DIR=/home/ubuntu/oci-runner/log`
- `ExecStart=/home/ubuntu/oci-runner/bin/launch-a1.sh`

If your target layout differs, edit the service file accordingly.

## Manual usage

Run the script directly:

```bash
ENV_FILE=/path/to/a1.env LOG_DIR=/path/to/log bash ./launch-a1.sh
```

This is useful for first-run validation before enabling `systemd`.

## systemd setup

1. Copy `launch-a1.sh` and `check-runner.sh` into your target `bin/` directory.
2. Copy your real `a1.env` into the target `etc/` directory.
3. Copy `oci-a1-runner.service` into `/etc/systemd/system/`.
4. Adjust absolute paths if your deployment layout is different.
5. Reload and enable the service.

Example:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now oci-a1-runner.service
```

## Install with install.sh

`install.sh` is a small Linux-only installer for hosts that already have the
required runtime dependencies such as OCI CLI, `jq`, `curl`, and `systemd`.

It must be run as `root`.

Supported flags:

- `--root <path>`
- `--start`

`--root` must be an absolute path.

Default install:

```bash
sudo bash ./install.sh
```

Custom root:

```bash
sudo bash ./install.sh --root /srv/oci-runner
```

Install and start immediately:

```bash
sudo bash ./install.sh --start
```

What the installer does:

- creates `<root>/bin`, `<root>/etc`, and `<root>/log`
- installs `launch-a1.sh` and `check-runner.sh` into `<root>/bin`
- creates `<root>/etc/a1.env` from `a1.env.example` only when the file is missing
- derives the service user from `<root>` when it matches `/home/<user>/...`; otherwise it uses `SUDO_USER` only if that account exists
- fails fast if it cannot derive a valid existing service user
- renders `/etc/systemd/system/oci-a1-runner.service` so `User`, `ENV_FILE`, `LOG_DIR`, and `ExecStart` match the selected root
- sets ownership and permissions so the service user can read a newly created `a1.env` and write logs under `<root>/log`
- runs `systemctl daemon-reload` and `systemctl enable oci-a1-runner.service`
- runs `systemctl start oci-a1-runner.service` only when `--start` is supplied

Safety notes:

- `install.sh` does not populate live OCI or Discord secrets.
- If `<root>/etc/a1.env` already exists, the installer keeps it unchanged.
- If `<root>/etc/a1.env` already exists, it must already be readable by the
  derived service user or the installer will fail fast.
- The installer fails fast unless it is run as `root`.
- The installer fails fast if `--root` is not absolute.
- Review and edit `a1.env` before the first real service start.
- The installer overwrites `/etc/systemd/system/oci-a1-runner.service` with the rendered unit for the selected root.
- Unsupported arguments fail fast.

## Verify an installation

Use `verify-install.sh` after installation to check local deployment state.

Default root and service:

```bash
bash ./verify-install.sh
```

Custom root and service:

```bash
bash ./verify-install.sh --root /srv/oci-runner --service custom-oci-a1-runner.service
```

Current verifier scope:

- checks local file layout under the selected root
- checks required non-empty env keys in `a1.env`
- checks the effective service configuration, or falls back to the installed
  unit file content, to confirm the selected root paths
- checks basic `systemctl is-enabled` and `systemctl is-active` visibility
- runs the installed `check-runner.sh` helper in a local-only way

Important limits:

- `verify-install.sh` checks local deployment state only
- it does not call OCI APIs or submit a launch request
- inactive or disabled services are reported as `[WARN]`, not automatic hard failures
- blocking local problems are reported as `[FAIL]` and cause a non-zero exit

## Checking runner state

You can inspect the runner with:

```bash
bash ./check-runner.sh
```

The helper shows:

- `systemd` service status
- success summary from `a1-success.txt` or `a1-success.json`
- last 20 lines from `launch-a1.log`
- recent journal entries

Override support:

- `SERVICE_NAME`
- `ENV_FILE`
- `LOG_DIR`
- `SUCCESS_JSON`
- `SUCCESS_TXT`
- `RUN_LOG`

If `SUCCESS_JSON` is not provided, the helper will try to read
`SUCCESS_SENTINEL` from `ENV_FILE` before falling back to
`$LOG_DIR/a1-success.json`.

## Success artifacts

When the runner succeeds, it writes:

- `a1-success.json`
- `a1-success.txt`

These include values such as:

- instance id
- boot volume id
- public IP
- availability domain
- success source

The source is either:

- `launch-success`
- `existing-instance-check`

## Testing

Run the bundled shell regression test from the repository root:

```bash
bash ./tests/install.test.sh ./install.sh
bash ./tests/launch-a1.test.sh ./launch-a1.sh
bash ./tests/check-runner.test.sh ./check-runner.sh
bash ./tests/verify-install.test.sh ./verify-install.sh
```

Expected result:

```text
PASS
```

The test uses mocked OCI CLI and mocked Discord posting. It does not contact
live OCI resources.

## Operational notes and caveats

- The runner exits immediately if `SUCCESS_SENTINEL` already exists.
- The existing-instance guard matches on `DISPLAY_NAME` and `SHAPE`.
- There is still a small race window between the last existing-instance check
  and the next launch request.
- Capacity and rate-limit errors are treated as expected retry conditions.
- Transient network errors are logged and snapshotted without Discord alerts.
- Non-capacity errors are snapshotted and sent to Discord.
- The script uses `--no-retry` and depends on its own loop plus
  `systemd Restart=on-failure` behavior.
- If the script exits cleanly after success, the service does not restart.

## Security notes

- This repository intentionally does not include a real `a1.env`.
- Do not commit live OCI identifiers, Discord tokens, or private local paths.
- The launcher parses `a1.env` as restricted key/value data instead of sourcing
  it as shell code.
- Keep the real `a1.env` permissions restricted on the target machine.
- Review `SUCCESS_SENTINEL` and logs before sharing them, because they may
  contain instance IDs and public IPs.

## Source mapping from the original workspace

This standalone repository was extracted from files that originally existed as:

- `tmp-launch-a1.sh`
- `tmp-check-runner.sh`
- `tmp-oci-a1-runner.service`
- `tmp-launch-a1.test.sh`
- `tmp-a1.env`

The first four were copied with stable names. The env file was converted into a
sanitized example.
