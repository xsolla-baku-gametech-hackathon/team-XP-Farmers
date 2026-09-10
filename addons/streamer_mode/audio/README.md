# Audio component handoff

Owner branch: `stream-safe-audio`.

Implement a standalone music adapter supplied with a StreamerModeController,
normal AudioStream and replacement AudioStream. Query AUDIO effective state on
state_changed. Keep music isolated from effects and dialogue. If no approved
replacement is configured, stop normal music while audio protection is active.
Handle repeated toggles, opt-out, stopped/paused playback and scene teardown.

The game developer is responsible for selecting appropriately licensed tracks
and routing every music source through the adapter. Other audio is not scanned.

