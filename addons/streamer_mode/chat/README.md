# Twitch component handoff

Owner branch: `twitch-chat`.

Build a network client separate from a reusable chat Control. Accept a supplied
StreamerModeController. Listen to state_changed and query
is_feature_active(StreamerModeController.CHAT) to show/hide the panel. Synchronize
immediately on binding and disconnect signals on unbind.

Use real Twitch EventSub messages. Show disconnected, connecting, connected and
error states honestly; keep offline test messages confined to a labeled test
scene. Escape user content, bound message history, and handle reconnects. Do not
commit credentials, embed a client secret in the game, or log access tokens.

Add your test scene under tests/chat/. Coordinate the public connection API with
the integration owner, who owns demo/main.gd and project.godot.

