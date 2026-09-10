# Privacy component handoff

Owner branch: `privacy-mask-copy`.

Build a reusable Control with a private source string, opaque masked display,
and a Copy button using DisplayServer.clipboard_set(source_value). Subscribe to
the supplied StreamerModeController.state_changed signal and apply
controller.is_feature_active(StreamerModeController.PRIVACY). Synchronize once
when binding, including when mode is already enabled. Disconnect on unbind.

Do not log the source value. Clear text must not remain in tooltips or accessible
labels while masked. Copy feedback must not contain the copied value. A pasted
value outside the game is outside this component's protection.

Add a standalone scene under tests/privacy/. Test replacing the value while
masked, repeated toggles, clipboard copying, and scene removal/re-entry.
Ask the integration owner to connect the completed component in demo/main.gd.

