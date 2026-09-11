# Streamer Mode addon

Runtime components for Godot 4.7.2 (GDScript). No editor plugin or demo-game files are required. An Autoload is optional for service persistence; live chat needs a separately configured Node relay.

- `core/streamer_mode_controller.gd`: master state and feature preferences.
- `audio/stream_safe_audio.gd`: managed music playback and replacement.
- `ui/streamer_mode_panel.tscn`: optional reusable settings panel.
- `audio/stream_safe_music_bus.gd`: replacement around an existing music manager.
- `privacy/`: registered fields, supported-text scanning, copy fields and manual masks.
- `chat/`: native chat overlay and browser pairing through a separate relay.

Copy this entire folder to `addons/streamer_mode/` in your game. Let Godot finish
its first import so it registers the classes. Add a controller, configure and bind
the audio adapter, then instance the panel under your game's UI. Bind the same
controller to the panel and mark AUDIO available. You can instead use your own UI.

Supply your own tracks and route the game's music through the adapter. Existing
music players are not discovered or stopped automatically. The addon does not
detect copyrighted content, provide music rights, or guarantee platform outcomes.

See the UI and audio READMEs for their public APIs. Keep this directory independent
of game resources: all tracks, private fields, account connections and game-specific
layout are supplied by the host.

For installation and host wiring, see [the complete walkthrough](../../README.md#install-in-your-own-godot-game).
