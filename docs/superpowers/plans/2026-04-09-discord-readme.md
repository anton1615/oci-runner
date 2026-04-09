# Discord README Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update `README.md` so the `oci-runner` repository clearly documents how Discord notifications are configured and when they are sent.

**Architecture:** Make a documentation-only change that is grounded directly in the observed `launch-a1.sh` behavior. Update the env setup guidance and add a dedicated `Discord notifications` section with a small env example and explicit delivery rules.

**Tech Stack:** Markdown, Bash source inspection, git

---

### Task 1: Update README Discord configuration guidance

**Files:**
- Modify: `oci-runner/README.md`
- Reference: `oci-runner/launch-a1.sh`, `oci-runner/a1.env.example`

- [ ] **Step 1: Expand the env setup area to call out Discord settings**

```markdown
Discord notification settings are optional, but recommended when the runner is
left retrying unattended.

- `DISCORD_BOT_TOKEN`
- `DISCORD_CHANNEL_ID`
- `DISCORD_API_BASE`
```

- [ ] **Step 2: Add a dedicated `Discord notifications` section**

```markdown
## Discord notifications

The runner can send Discord messages for important long-running outcomes. This
is optional, but it is useful when the retry loop runs unattended for long
periods.

Required settings for message delivery:

- `DISCORD_BOT_TOKEN`
- `DISCORD_CHANNEL_ID`

Optional setting:

- `DISCORD_API_BASE`
  Defaults to `https://discord.com/api/v10`.
```

- [ ] **Step 3: Document send / no-send behavior and failure handling**

```markdown
The current runner sends Discord messages for:

- successful launch of a new instance
- detection of an already existing matching instance
- unknown non-capacity failures

The current runner does not send Discord messages for:

- capacity or rate-limit failures
- transient network failures

If the Discord API request fails, the runner logs `discord notification failed`
and continues running. Notification delivery failure does not stop the retry
loop.
```

- [ ] **Step 4: Add a small env example block**

```markdown
```dotenv
DISCORD_API_BASE='https://discord.com/api/v10'
DISCORD_BOT_TOKEN='<replace-me>'
DISCORD_CHANNEL_ID='<replace-me>'
```
```

- [ ] **Step 5: Read back the updated README**

Run read for:

```text
oci-runner/README.md
```

Expected: README now explains Discord setup and behavior without claiming any
logic not present in `launch-a1.sh`.

### Task 2: Verify documentation accuracy and review

**Files:**
- Verify: `oci-runner/README.md`

- [ ] **Step 1: Re-read the relevant `launch-a1.sh` notification logic**

Check these behaviors directly in the script:

```text
- `discord_post()` skip behavior when token/channel are missing
- success notification path
- existing-instance notification path
- non-capacity failure notification path
- no notification for capacity/rate-limit and transient-network classes
- log-only behavior when Discord delivery fails
```

- [ ] **Step 2: Dispatch documentation review**

```text
Review against:
- `docs/superpowers/specs/2026-04-09-discord-readme-design.md`
- `docs/superpowers/plans/2026-04-09-discord-readme.md`
- `README.md`
- `launch-a1.sh`
```

- [ ] **Step 3: Fix any review findings if needed**

```text
If review finds wording drift or an unsupported claim, make the minimal README
fix and re-read the updated section.
```

### Task 3: Commit the documentation change

**Files:**
- Commit: README, spec, plan

- [ ] **Step 1: Inspect git state in `oci-runner`**

Run:

```bash
git status --short
git diff -- README.md docs/superpowers/specs/2026-04-09-discord-readme-design.md docs/superpowers/plans/2026-04-09-discord-readme.md
```

Expected: only the README Discord-doc changes appear.

- [ ] **Step 2: Create the commit**

Run:

```bash
git add README.md docs/superpowers/specs/2026-04-09-discord-readme-design.md docs/superpowers/plans/2026-04-09-discord-readme.md
git commit -m "docs: clarify discord notification setup"
```

- [ ] **Step 3: Verify the commit exists and the tree is clean**

Run:

```bash
git log --oneline -n 1
git status --short
```

Expected: the new commit is visible and `git status --short` is empty.

## Self-review

- Spec coverage: the plan covers env setup wording, the dedicated Discord
  section, behavior documentation, verification against `launch-a1.sh`, review,
  and commit.
- Placeholder scan: no `TODO`, `TBD`, or missing paths remain.
- Consistency: the plan keeps this as a documentation-only change and uses the
  same Discord behavior model throughout.
