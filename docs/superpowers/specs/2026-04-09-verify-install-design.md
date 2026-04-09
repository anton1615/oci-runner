# Verify-install script design

This document defines the next addition to the standalone `oci-runner`
repository: a lightweight post-install verification script and matching README
updates.

## Goals

- Add `verify-install.sh` as a local deployment verification helper.
- Keep verification focused on local deployment correctness, not live OCI API
  checks.
- Surface clear `[OK]`, `[WARN]`, and `[FAIL]` style output.
- Add shell regression coverage for the verifier.
- Update the README with a short verification workflow.

## Non-goals

- Do not launch real OCI API requests.
- Do not submit real launch attempts.
- Do not mutate deployment state beyond harmless local inspection.
- Do not replace `check-runner.sh`; the verifier is complementary.

## Recommended approach

Add a small Bash script with these flags:

- `--root <path>`
- `--service <name>`

Default values:

- root: `/home/ubuntu/oci-runner`
- service: `oci-a1-runner.service`

The script should validate local deployment structure, required config keys,
rendered systemd paths, and basic systemd visibility without making OCI network
calls.

## Alternatives considered

### Option 1: Static verification only

Pros:

- very safe
- deterministic

Cons:

- misses useful service visibility checks

### Option 2: Static verification plus light systemd checks

Pros:

- still safe
- more useful operationally
- good fit for this repo

Cons:

- slightly more moving parts in tests

### Option 3: Full OCI/API smoke verification

Pros:

- deeper confidence

Cons:

- no longer a lightweight verifier
- depends on live network, credentials, and tenancy state
- too noisy for a default repo utility

Chosen approach: Option 2.

## Functional design

### `verify-install.sh`

The script will:

1. accept optional `--root <path>`
2. accept optional `--service <name>`
3. verify these files exist under the selected root:
   - `<root>/bin/launch-a1.sh`
   - `<root>/bin/check-runner.sh`
   - `<root>/etc/a1.env`
4. verify the installed service file exists at:
   - `/etc/systemd/system/<service>`
5. verify the service file contains root-matching lines for:
   - `Environment=ENV_FILE=<root>/etc/a1.env`
   - `Environment=LOG_DIR=<root>/log`
   - `ExecStart=<root>/bin/launch-a1.sh`
6. verify `launch-a1.sh` and `check-runner.sh` are executable
7. parse `a1.env` and ensure these keys are present and non-empty:
   - `COMPARTMENT_ID`
   - `SUBNET_ID`
   - `IMAGE_ID`
   - `OCI_CLI`
   - `OCI_CLI_PROFILE`
   - `SUCCESS_SENTINEL`
8. query `systemctl is-enabled <service>`
9. query `systemctl is-active <service>`
10. invoke the installed `check-runner.sh` helper in a non-destructive way

### Result handling

Use these output levels:

- `[OK]` for checks that passed
- `[WARN]` for non-fatal checks such as service not currently active
- `[FAIL]` for blocking problems

The script should exit non-zero when any blocking check fails.

### Severity model

Hard failures include:

- missing required files
- missing required env keys
- missing service unit
- service unit path mismatch
- non-executable installed scripts

Warnings include:

- service is not active
- service is not enabled, if the user is only doing manual deployment without
  enabling the service yet

The script must make those warnings explicit but should not fail only because a
service is currently inactive.

## Documentation design

`README.md` will be updated with:

1. `verify-install.sh` in the included file list
2. a short `Verify an installation` section
3. examples for default root and custom root
4. a note that the verifier checks local deployment state only and does not call
   OCI APIs

## Testing design

### New test file

- `tests/verify-install.test.sh`

### Coverage requirements

The test should verify:

- happy path prints success and exits zero
- missing required env key fails
- service file path mismatch fails
- inactive service is only a warning, not a hard failure
- custom `--root` and `--service` arguments are respected

Use mocks for `systemctl` and any helper execution so the test stays local and
deterministic.

## File changes

Create:

- `verify-install.sh`
- `tests/verify-install.test.sh`

Modify:

- `README.md`

Reference only:

- `install.sh`
- `check-runner.sh`
- `oci-a1-runner.service`

## Verification plan

Before completion, verify:

1. `tests/verify-install.test.sh` passes
2. existing tests still pass:
   - `tests/install.test.sh`
   - `tests/launch-a1.test.sh`
   - `tests/check-runner.test.sh`
3. README reflects actual verifier behavior
4. implementation review finds no remaining issues before claiming completion

## Risks and mitigations

- Risk: verifier becomes a hidden live smoke test.
  Mitigation: keep it local-only and do not call OCI APIs.

- Risk: warnings and failures are mixed confusingly.
  Mitigation: define explicit `[OK]`, `[WARN]`, `[FAIL]` output and non-zero exit
  only for blocking failures.

- Risk: verifier drifts from installer assumptions.
  Mitigation: validate the same root-based file and service layout that
  `install.sh` renders.
