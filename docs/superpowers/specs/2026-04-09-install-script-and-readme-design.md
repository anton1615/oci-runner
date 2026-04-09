# Install script and README update design

This document defines the next change for the standalone `oci-runner`
repository: add a minimal deployment installer and update the README so the
repository is easier to deploy on another Linux machine.

## Goals

- Add a minimal `install.sh` for Linux + `systemd` deployments.
- Keep the installer small and predictable.
- Avoid writing or overwriting live secrets automatically.
- Update `README.md` so it documents both manual deployment and scripted
  installation.
- Add regression tests for the installer behavior.

## Non-goals

- Do not add remote copy or SSH orchestration.
- Do not install OCI CLI or other system dependencies automatically.
- Do not auto-fill `a1.env` with secrets.
- Do not build a cross-platform installer for macOS or Windows.

## Recommended approach

Use a small Bash installer with two optional flags:

- `--root <path>`
- `--start`

Default root stays aligned with current documentation:

- `/home/ubuntu/oci-runner`

This approach keeps the script easy to audit while still allowing deployment to
another path when needed.

## Alternatives considered

### Option 1: Hard-coded installer

Pros:

- smallest implementation
- easiest to explain

Cons:

- too rigid for reuse on another machine with a different layout

### Option 2: Minimal parameterized installer

Pros:

- still small
- supports a different deployment root
- matches current reusable-repo goal well

Cons:

- slightly more logic than a fixed installer

### Option 3: Fully configurable installer

Pros:

- most flexible

Cons:

- too much complexity for the current repo scope
- higher documentation and testing cost

Chosen approach: Option 2.

## Functional design

### `install.sh`

The installer will:

1. run on Linux with Bash
2. accept optional `--root <path>`
3. accept optional `--start`
4. create:
   - `<root>/bin`
   - `<root>/etc`
   - `<root>/log`
5. install:
   - `launch-a1.sh` -> `<root>/bin/launch-a1.sh`
   - `check-runner.sh` -> `<root>/bin/check-runner.sh`
6. create `<root>/etc/a1.env` from `a1.env.example` only if the file does not
   already exist
7. generate a service file whose paths match the chosen root
8. install that generated service file to:
   - `/etc/systemd/system/oci-a1-runner.service`
9. run:
   - `systemctl daemon-reload`
   - `systemctl enable oci-a1-runner.service`
10. if `--start` is supplied, also run:
   - `systemctl start oci-a1-runner.service`

### Safety rules

The installer must:

- fail fast on unsupported arguments
- fail if not running on Linux
- not overwrite an existing `a1.env`
- remind the operator to edit `a1.env` before first real use
- avoid editing source repo files in place

### Service generation

Instead of modifying the checked-in `oci-a1-runner.service` file directly, the
installer should treat it as the template source and render a temporary or
in-memory variant with the selected root path.

This keeps the repo default files stable while still allowing path overrides.

## Documentation design

`README.md` will be updated to include:

1. a quick-start section
2. an `Install with install.sh` section
3. the new installer flags and examples
4. explicit note that the installer does not populate secrets
5. explicit note that an existing `a1.env` is preserved
6. post-install validation guidance

The README should continue to support both:

- manual deployment
- scripted installation

## Testing design

Use shell-based regression tests.

### New test file

- `tests/install.test.sh`

### Coverage requirements

The installer test should validate:

- default or custom root path handling
- directory creation
- script installation targets
- service file path rewriting
- `a1.env` is created from the example when missing
- `a1.env` is not overwritten when already present
- `systemctl daemon-reload` and `enable` are called
- `systemctl start` is called only when `--start` is provided

Use mocks for `sudo`, `install`, and `systemctl` so the test does not require
real root access or host service changes.

## File changes

Create:

- `install.sh`
- `tests/install.test.sh`

Modify:

- `README.md`

Reference only:

- `launch-a1.sh`
- `check-runner.sh`
- `oci-a1-runner.service`
- `a1.env.example`

## Verification plan

Before completion, verify:

1. `tests/install.test.sh` passes
2. existing tests still pass:
   - `tests/launch-a1.test.sh`
   - `tests/check-runner.test.sh`
3. `README.md` reflects actual installer behavior
4. no live secrets are introduced
5. implementation review finds no remaining issues before claiming completion

## Risks and mitigations

- Risk: installer accidentally overwrites a real config file
  Mitigation: preserve existing `a1.env` and emit a clear message.

- Risk: installer writes incorrect service paths
  Mitigation: cover service rendering with a dedicated test using a custom root.

- Risk: README drifts from installer behavior
  Mitigation: update README only after installer behavior is defined and verify
  examples against the final script.
