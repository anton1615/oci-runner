# OCI runner repo design

This document defines how to extract the existing OCI A1 runner assets from the
workspace into a standalone, reproducible repository at
`D:\Downloads\oracle-machine\oci-runner`.

The goal is to preserve the currently useful runner logic while removing live
secrets, making the package easier to move to another machine, and documenting
the operational assumptions needed for successful reuse.

## Goals

- Create a standalone repository for the OCI A1 runner under `oci-runner/`.
- Rename the current `tmp-*` files to stable, production-style names.
- Replace the live env file with a sanitized example file.
- Add a README that explains purpose, prerequisites, setup, usage, and caveats.
- Check the extracted files for security and privacy issues before commit.
- Keep the scope small: only include the files needed to understand, test, and
  run the runner on another machine.

## Non-goals

- Do not generalize the runner into a larger framework.
- Do not add deployment automation beyond what is already represented by the
  existing service file and scripts.
- Do not include any live credentials, tokens, or tenancy-specific identifiers.
- Do not modify the original `tmp-*` source files in place unless a follow-up
  memory update is needed after completion.

## Source mapping

The new repository will be built from these existing local files.

| Current file | New file |
| --- | --- |
| `tmp-launch-a1.sh` | `launch-a1.sh` |
| `tmp-check-runner.sh` | `check-runner.sh` |
| `tmp-oci-a1-runner.service` | `oci-a1-runner.service` |
| `tmp-launch-a1.test.sh` | `tests/launch-a1.test.sh` |
| `tmp-a1.env` | `a1.env.example` (sanitized) |

## Repository layout

The standalone repository will use this layout.

```text
oci-runner/
  .gitignore
  README.md
  a1.env.example
  launch-a1.sh
  check-runner.sh
  oci-a1-runner.service
  tests/
    launch-a1.test.sh
  docs/
    superpowers/
      specs/
        2026-04-09-oci-runner-repo-design.md
```

## Functional design

### `launch-a1.sh`

The main launch script remains the runtime entrypoint. It will keep the current
behavior:

- load settings from `ENV_FILE`
- create `LOG_DIR`
- enumerate availability domains dynamically
- detect an already existing matching instance before launch attempts
- retry launches across ADs
- classify failures into:
  - capacity or rate-limit
  - transient network
  - non-capacity
- write success artifacts when an instance already exists or when a new launch
  succeeds
- send Discord notifications only for success and non-capacity cases

The script content should stay as close as possible to the currently working
source, with only minimal edits needed to make the extracted repository safer
and easier to understand.

### `check-runner.sh`

The check script stays as a simple operational helper for service status,
success artifacts, recent log tail, and journal output. It should remain small
and not turn into a larger management script.

### `oci-a1-runner.service`

The systemd unit remains a sample deployment unit. It documents the expected
runtime paths and restart behavior:

- `Restart=on-failure`
- `RestartSec=20`
- `KillSignal=SIGINT`
- `TimeoutStopSec=30`

The README will explain that users may need to adjust absolute paths if they do
not deploy to `/home/ubuntu/oci-runner`.

### `tests/launch-a1.test.sh`

The existing shell test stays in the repository as the primary local regression
check. It will remain path-parameterized and continue to use mocked OCI and
Discord behavior. The README will document how to run it locally.

## Security and privacy design

The extracted repository must not contain live secrets.

### Files to sanitize

`tmp-a1.env` currently contains live and environment-specific values, including:

- OCI tenancy and resource identifiers
- Discord bot token
- Discord channel id
- local path assumptions tied to the current host

The new `a1.env.example` will preserve the variable names and required shape,
but replace all sensitive values with placeholders such as `<replace-me>` or
representative non-secret examples.

### Ignore rules

The repository will include `.gitignore` rules for at least:

- `a1.env`
- `log/`
- `*.log`
- `a1-success.json`
- `a1-success.txt`
- shell test temp outputs if they are created in-tree later

### Validation pass

Before completion, run a content review across the new repository to check for:

- real OCIDs
- real tokens
- real Discord ids if they are not intended to be public
- IPs or hostnames that should not ship in a reusable package

If any live value is found, replace it with a sanitized placeholder before the
final commit.

## Documentation design

`README.md` will be written as the main operator-facing document.

It will include these sections:

1. Overview
2. Included files
3. What the runner does
4. Prerequisites
5. Environment configuration
6. Deployment layout and path expectations
7. Manual usage
8. systemd setup
9. Testing
10. Operational notes and caveats
11. Security notes

### Prerequisites section requirements

The prerequisites must explicitly explain that successful reuse depends on the
target machine being able to reach and operate on the intended OCI resources.

That includes points such as:

- OCI CLI installed and authenticated
- permission to launch instances in the target compartment
- a valid subnet and image in the target region
- a machine environment that can access the same tenancy and networking context
  required by the configured resource IDs
- `bash`, `jq`, `curl`, `systemd` for the documented service mode

The README should avoid claiming that the exact original subnet, image, or VCN
must be reused, but it must clearly state that the replacement machine needs
equivalent access to the OCI tenancy and resource topology referenced in its
own `a1.env`.

## Git design

The new directory `oci-runner/` will be initialized as its own git repository.

The final requested commit will include:

- scripts
- service file
- sanitized env example
- README
- spec document
- any minimal support files such as `.gitignore`

The commit message should reflect that this is the bootstrap of a standalone
OCI runner repository. A good default is:

`feat: bootstrap standalone oci runner repo`

## Verification plan

Before the task is considered complete, verify:

1. The new repository exists at `oci-runner/`.
2. All intended files are present under their new names.
3. `a1.env.example` contains no live secrets.
4. The README reflects the actual extracted files and usage model.
5. The shell test runs successfully against `launch-a1.sh`.
6. A repository-wide content scan does not show accidental secret leakage.
7. The standalone repo has been reviewed before the final success claim.

## Risks and mitigations

- Risk: a live secret is copied over accidentally.
  Mitigation: sanitize `a1.env.example`, add `.gitignore`, then run an explicit
  content scan before commit.

- Risk: README overstates portability.
  Mitigation: document the OCI tenancy, subnet, image, and CLI prerequisites
  clearly and distinguish between reusable logic and environment-specific
  values.

- Risk: extracted files drift from the currently working source.
  Mitigation: keep the code copy minimal and avoid unnecessary refactors during
  extraction.
