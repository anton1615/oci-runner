# Discord README documentation design

This document defines a small documentation-only update for the standalone
`oci-runner` repository: clarify how Discord notifications are configured and
when they are sent.

## Goals

- Make the README explicitly describe the Discord notification feature.
- Document the required and optional Discord-related environment variables.
- Document which runner outcomes send Discord messages and which do not.
- Document that Discord delivery failure should not stop the runner.

## Non-goals

- Do not change `launch-a1.sh` behavior.
- Do not change the notification message format.
- Do not add new environment variables.
- Do not modify tests unless a documentation test or review gap appears.

## Current observed behavior

The current `launch-a1.sh` behavior is:

- if `DISCORD_BOT_TOKEN` or `DISCORD_CHANNEL_ID` is missing, notification is
  skipped silently
- success after a new instance launch sends a Discord message
- detecting an already existing matching instance sends a Discord message
- unknown non-capacity failures send a Discord message
- capacity and rate-limit failures do not send a Discord message
- transient network failures do not send a Discord message
- if the Discord API call fails, the script logs `discord notification failed`
  and continues

## Recommended approach

Keep this change documentation-only.

Update `README.md` in two places:

1. make the env setup section more explicit that Discord settings are optional
   but recommended
2. add a dedicated `Discord notifications` section with behavior details

This keeps the scope small and aligns the docs with already implemented logic.

## Documentation design

### `Environment setup` updates

Near the env key list, clarify:

- Discord notification settings are optional
- they are useful for long-running unattended retries

The README should call out these fields clearly:

- `DISCORD_BOT_TOKEN`
- `DISCORD_CHANNEL_ID`
- `DISCORD_API_BASE`

### New section: `Discord notifications`

Add a standalone section that explains:

1. what the feature is for
2. what needs to be configured
3. when messages are sent
4. when messages are not sent
5. what happens if delivery fails

### Content requirements

The section should explicitly state:

- `DISCORD_BOT_TOKEN` and `DISCORD_CHANNEL_ID` are both required for message
  delivery
- `DISCORD_API_BASE` defaults to `https://discord.com/api/v10`
- notifications are sent for:
  - successful launch
  - existing matching instance detected
  - unknown non-capacity error
- notifications are not sent for:
  - capacity / rate-limit failures
  - transient network failures
- a Discord API failure does not stop the runner; it only logs a warning

### Example block

Add a small env example such as:

```dotenv
DISCORD_API_BASE='https://discord.com/api/v10'
DISCORD_BOT_TOKEN='<replace-me>'
DISCORD_CHANNEL_ID='<replace-me>'
```

## File changes

Modify only:

- `README.md`

Reference only:

- `launch-a1.sh`
- `a1.env.example`

## Verification plan

Before completion, verify:

1. README language matches the actual `launch-a1.sh` behavior
2. no claims are made that are not implemented in the script
3. the change stays documentation-only unless a review finds a clear mismatch
4. documentation review finds no remaining issues before claiming completion

## Risks and mitigations

- Risk: README overstates notification guarantees.
  Mitigation: state clearly that delivery failure only logs a warning.

- Risk: README implies Discord is mandatory.
  Mitigation: describe it as optional but recommended.

- Risk: docs drift from current script behavior.
  Mitigation: base the section directly on the observed `launch-a1.sh` logic and
  verify against the code before completion.
