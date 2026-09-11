# Chat structure validation

Validated on Godot 4.7.2 on 2026-09-11:

- Node provider/server tests: 13 passed (mock platform traffic).
- Godot foundation/shared demo: passed, including the common panel, feature
  availability, forwarded chat status, and settings/gameplay behavior.
- Godot chat: passed, including usernames, literal message text, opacity,
  moderation, master/feature toggles, paused processing, component re-entry,
  and controller removal.
- Local HTTP/Bearer integration: passed with the scene tree paused, using the
  complete StreamerChat component and a local fixture server.
- Shared UI files match audio commit 0fbc00f exactly; the core controller is
  unchanged. Audio/privacy implementations have not been merged.
- git diff --check: passed.

The editor import registered the scripts; sandbox restrictions prevented saving
user-level editor settings/logs. Script tests used the installed Godot runtime.
The graphical renderer could not start in this execution environment, so no
visual screenshot approval is claimed. tests/capture_demo.gd is an optional
manual visual check, with clearly labeled offline fixtures only.

Still to validate with real accounts: OAuth and live delivery for Twitch, Kick
and YouTube, capturing the game in the stream, and combined audio/privacy/chat
behavior after a separately authorized integration. The overlay belongs to the
Godot game; it does not overlay unrelated desktop applications.

## Native channel pairing update

- Added platform selection, browser sign-in, automatic return of the channel to
  Godot, explicit Enable chat, and paired-session disconnect.
- Node suite: 15 tests passed, including separate browser/poll capabilities,
  one-use browser claims, callback cookie binding, cancellation and revocation.
- Godot pairing HTTP fixture: passed while SceneTree was paused, including
  sign-in URL delivery, channel reception and authenticated disconnect.
- Existing Godot chat and foundation suites passed.
- Graphical capture remains unavailable in this execution environment. Live
  provider consent for this new flow requires the user's browser interaction.
