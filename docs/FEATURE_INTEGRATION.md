# Next integration checkpoint

Last reviewed remote state: 2026-09-10.

| Feature branch | Reviewed state | What is needed next |
| --- | --- | --- |
| twitch-chat | Foundation only (c79fda9) | Push the client and panel implementation |
| privacy-mask-copy | Standalone movable mask preserved (d454e2c) | Push a component connected to the shared controller |
| stream-safe-audio | Audio and reusable panel (9625251) | Combined integration once other features are ready |

These are reviewed snapshots, not a live status board. A teammate may have newer
local work. Fetch again before beginning integration.

## Privacy handoff

Keep the original standalone prototype intact. The shared-game component should
accept a controller and synchronize immediately with PRIVACY effective state.
Its normal mode restores the intended UI. The selected protected area must conceal
the underlying information sufficiently; the current translucent rectangle alone
does not establish readable-text protection. If the approach is protected text,
keep Copy functional without exposing the source value in feedback or tooltips.

Deliver a small test scene demonstrating enable, disable, scene re-entry and
changed values. A manual region mask may need a different host integration from a
protected-text component; settle that API with the integration owner before wiring
the shared game. Do not mark the feature available merely because a prototype exists.

## Twitch handoff

Deliver the client and UI separately, with visible disconnected/connecting/error
states and a bounded message history. Bind chat visibility to the controller's
CHAT effective state. Provide connection setup instructions without committing
credentials. Demonstrate an actual channel message and reconnection; offline test
messages must be explicitly labeled in tests and never presented as live chat.

## Integration owner workflow

1. Fetch current remote branches and inspect commits and shared-file changes.
2. Merge ready feature work into an isolated local integration branch based on the
   latest tested application. Preserve authorship and resolve changes with owners.
3. Connect components in demo/demo_services.gd and demo/main.gd. Use the existing
   controller API and panel availability/status API.
4. Add reviewed feature checks to tools/verify.cjs. Its current four suites do not
   validate privacy or Twitch, and report both as pending.
5. Exercise all features together and repeat integration in Signal Garden.
6. Build Windows Demo, record OBS output, and rehearse the one-minute demonstration.

A successful audio build is not completion of the three-feature MVP.
