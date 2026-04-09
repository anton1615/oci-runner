# OCI runner repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the OCI A1 runner assets into a standalone git repository with sanitized configuration, runnable tests, and operator-focused documentation.

**Architecture:** Copy the existing runner assets into a new `oci-runner/` repository using stable filenames, keep code changes minimal, replace the live env file with a sanitized example, and document the deployment and operational assumptions in `README.md`. Verify behavior by running the existing shell test against the extracted script and scanning the new repository for accidental secret leakage.

**Tech Stack:** Bash, systemd unit files, Markdown, git, PowerShell host commands, ripgrep-style content scanning

---

### Task 1: Create standalone repo skeleton

**Files:**
- Create: `oci-runner/.gitignore`
- Create: `oci-runner/tests/.gitkeep`
- Modify: `oci-runner/docs/superpowers/specs/2026-04-09-oci-runner-repo-design.md`
- Modify: `oci-runner/docs/superpowers/plans/2026-04-09-oci-runner-repo.md`

- [ ] **Step 1: Create the ignore rules**

```gitignore
a1.env
log/
*.log
a1-success.json
a1-success.txt
tmp/
```

- [ ] **Step 2: Ensure the tests directory exists**

```text
Create `oci-runner/tests/.gitkeep` as an empty file if the directory does not yet
contain tracked content.
```

- [ ] **Step 3: Read back the created files**

Run reads for:

```text
oci-runner/.gitignore
oci-runner/tests/
```

Expected: `.gitignore` contains the ignore list and `tests/` exists.

### Task 2: Copy and rename runner assets

**Files:**
- Create: `oci-runner/launch-a1.sh`
- Create: `oci-runner/check-runner.sh`
- Create: `oci-runner/oci-a1-runner.service`
- Create: `oci-runner/tests/launch-a1.test.sh`
- Source only: `tmp-launch-a1.sh`, `tmp-check-runner.sh`, `tmp-oci-a1-runner.service`, `tmp-launch-a1.test.sh`

- [ ] **Step 1: Copy the main launch script with minimal changes**

```text
Create `oci-runner/launch-a1.sh` from `tmp-launch-a1.sh`.
Preserve behavior. Only allow edits that improve standalone readability or repo
safety without changing runtime semantics.
```

- [ ] **Step 2: Copy the operational helper**

```text
Create `oci-runner/check-runner.sh` from `tmp-check-runner.sh`.
Keep the existing service and log paths because the README will describe how to
adjust them for other deployments.
```

- [ ] **Step 3: Copy the systemd unit**

```ini
[Unit]
Description=OCI A1 capacity runner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Environment=ENV_FILE=/home/ubuntu/oci-runner/etc/a1.env
Environment=LOG_DIR=/home/ubuntu/oci-runner/log
ExecStart=/home/ubuntu/oci-runner/bin/launch-a1.sh
Restart=on-failure
RestartSec=20
KillSignal=SIGINT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 4: Copy the shell regression test**

```text
Create `oci-runner/tests/launch-a1.test.sh` from `tmp-launch-a1.test.sh`.
Keep it path-parameterized so it can be run against `launch-a1.sh` inside the
new repository.
```

- [ ] **Step 5: Read back all copied files**

Run reads for:

```text
oci-runner/launch-a1.sh
oci-runner/check-runner.sh
oci-runner/oci-a1-runner.service
oci-runner/tests/launch-a1.test.sh
```

Expected: files exist under the new names and the content matches the intended
source behavior.

### Task 3: Add sanitized environment example

**Files:**
- Create: `oci-runner/a1.env.example`
- Source only: `tmp-a1.env`

- [ ] **Step 1: Create a sanitized env example**

```dotenv
COMPARTMENT_ID='ocid1.tenancy.oc1..<replace-me>'
SUBNET_ID='ocid1.subnet.oc1..<replace-me>'
IMAGE_ID='ocid1.image.oc1..<replace-me>'
SSH_AUTHORIZED_KEYS_FILE='/home/ubuntu/.ssh/authorized_keys'
DISPLAY_NAME='oraclelinux-a1-4c24g'
SHAPE='VM.Standard.A1.Flex'
OCPUS='4'
MEMORY_IN_GBS='24'
BOOT_VOLUME_SIZE_GBS='150'
BOOT_VOLUME_VPUS_PER_GB='120'
ASSIGN_PUBLIC_IP='true'
RETRY_MIN_SECONDS='50'
RETRY_MAX_SECONDS='70'
INTER_AD_MIN_SECONDS='3'
INTER_AD_MAX_SECONDS='7'
OCI_CLI='/home/ubuntu/bin/oci'
OCI_CLI_PROFILE='DEFAULT'
SUCCESS_SENTINEL='/home/ubuntu/oci-runner/log/a1-success.json'
DISCORD_API_BASE='https://discord.com/api/v10'
DISCORD_BOT_TOKEN='<replace-me>'
DISCORD_CHANNEL_ID='<replace-me>'
```

- [ ] **Step 2: Read back the env example**

Run read for:

```text
oci-runner/a1.env.example
```

Expected: all required keys are present and live values are replaced.

### Task 4: Write operator-facing README

**Files:**
- Create: `oci-runner/README.md`
- Reference: `oci-runner/launch-a1.sh`, `oci-runner/check-runner.sh`, `oci-runner/oci-a1-runner.service`, `oci-runner/tests/launch-a1.test.sh`, `oci-runner/a1.env.example`

- [ ] **Step 1: Write the README overview and included files**

```markdown
# OCI A1 Runner

This repository packages a small OCI Always Free runner that keeps retrying
`VM.Standard.A1.Flex` launches until capacity becomes available or a matching
instance already exists.

## Included files

- `launch-a1.sh`: main retry loop and launch logic
- `check-runner.sh`: service and log inspection helper
- `oci-a1-runner.service`: sample systemd unit
- `a1.env.example`: sanitized configuration template
- `tests/launch-a1.test.sh`: shell regression test with mocked OCI behavior
```

- [ ] **Step 2: Document prerequisites, environment setup, and path assumptions**

```markdown
## Prerequisites

- Linux host with `bash`, `jq`, `curl`, `systemd`, and Python 3 available
- OCI CLI installed and authenticated for the target tenancy/profile
- Permission to launch instances in the target compartment
- Valid OCI resource IDs for the target region, including subnet and image
- A machine that can operate against the same OCI tenancy and networking context
  implied by the values you place in `a1.env`

## Environment setup

1. Copy `a1.env.example` to `a1.env`.
2. Replace all placeholder OCI and Discord values.
3. Confirm `SSH_AUTHORIZED_KEYS_FILE` points to a real public key file.
4. Create a writable log directory that matches your deployment layout.
```

- [ ] **Step 3: Document manual usage, systemd usage, testing, and caveats**

```markdown
## Manual usage

```bash
ENV_FILE=/path/to/a1.env LOG_DIR=/path/to/log bash ./launch-a1.sh
```

## systemd setup

Adjust `oci-a1-runner.service` if your target paths differ from the sample
deployment under `/home/ubuntu/oci-runner`.

## Testing

```bash
bash ./tests/launch-a1.test.sh ./launch-a1.sh
```

## Notes

- The script exits immediately when `SUCCESS_SENTINEL` already exists.
- Existing-instance protection matches on `DISPLAY_NAME` and `SHAPE`.
- Capacity and rate-limit failures do not trigger Discord alerts.
- Do not commit a real `a1.env` file.
```

- [ ] **Step 4: Read back the README**

Run read for:

```text
oci-runner/README.md
```

Expected: README sections align with the actual extracted files.

### Task 5: Verify behavior and scan for secrets

**Files:**
- Verify: `oci-runner/**/*`

- [ ] **Step 1: Run the shell regression test**

Run:

```bash
bash ".\tests\launch-a1.test.sh" ".\launch-a1.sh"
```

Expected: `PASS`

- [ ] **Step 2: Scan the new repository for accidental secrets**

Run content searches for patterns such as:

```text
ocid1\.tenancy\.oc1\..*[a-z0-9]{20,}
MT[A-Za-z0-9._-]+
<real-discord-channel-id>
150\.230\.197\.63
```

Expected: no live secret matches in the new standalone repo, except sanitized
placeholder examples.

- [ ] **Step 3: Inspect git status before review**

Run:

```bash
git status --short
```

Expected: only intended files are present in the standalone repo.

### Task 6: Review and commit

**Files:**
- Review: extracted repo diff and spec alignment

- [ ] **Step 1: Dispatch implementation review**

```text
Use a review subagent to inspect:
- `oci-runner/docs/superpowers/specs/2026-04-09-oci-runner-repo-design.md`
- `oci-runner/docs/superpowers/plans/2026-04-09-oci-runner-repo.md`
- extracted repo files
- verification evidence
```

- [ ] **Step 2: Fix any review findings if needed**

```text
If the review reports a bug, missing documentation, spec mismatch, or security
issue, fix it before commit and re-run the affected verification step.
```

- [ ] **Step 3: Initialize git and create the first commit**

Run:

```bash
git init
git add .
git commit -m "feat: bootstrap standalone oci runner repo"
```

Expected: repository initialized and the extracted package committed.

## Self-review

- Spec coverage: the plan covers extraction, rename mapping, sanitization,
  README authoring, verification, review, and commit.
- Placeholder scan: no `TODO`, `TBD`, or missing file-path steps remain.
- Consistency: all paths use the `oci-runner/` repository layout defined in the
  spec and keep the same final filenames throughout the plan.
