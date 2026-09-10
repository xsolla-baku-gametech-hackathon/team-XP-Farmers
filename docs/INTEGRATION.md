# Installing Streamer Mode into another Godot game

Tested with Godot 4.7.2 standard, Compatibility renderer, Windows desktop.

## Installation steps

1. Copy `addons/streamer_mode/` into your game's `addons/` folder. Wait for
   Godot's import to finish. This is a runtime addon; nothing needs enabling in
   Project Settings > Plugins.
2. Add one `StreamerModeController` to the game's persistent services/UI root.
   Keeping it across gameplay scenes also keeps the current preferences.
3. Add `StreamSafeAudio`, supply the normal and replacement AudioStreams, and
   bind it to that controller. Configure stream loop settings for looping music.
   Disable the old music player or route its playback requests through the adapter.
4. Instance `ui/streamer_mode_panel.tscn` inside your settings UI. Bind the same
   controller and mark AUDIO available. Alternatively, use the game's own UI.
5. Connect playback_changed to update the panel's audio status and start music.
6. Test a mode toggle, audio opt-out, sound effects, and missing replacement using
   the game's actual scenes. Verify the recording on the presentation computer.

Example host code, assuming `normal_track` and `replacement_track` are supplied
AudioStreams and `settings_container` is an existing Control:

```gdscript
var controller := StreamerModeController.new()
add_child(controller)

var music := StreamSafeAudio.new()
music.set_tracks(normal_track, replacement_track)
music.bind(controller)
add_child(music)

var panel = preload("res://addons/streamer_mode/ui/streamer_mode_panel.tscn").instantiate()
panel.bind(controller)
panel.set_feature_available(StreamerModeController.AUDIO, true)
settings_container.add_child(panel)
music.playback_changed.connect(func():
    panel.set_feature_status(StreamerModeController.AUDIO, music.get_status())
)
music.play()
```

The adapter defaults to the Master bus, so no project audio-bus changes are needed
for this example. If assigning another bus name, the game must create that bus.
Keep effects/dialogue on separate players; the adapter never mutes the Master bus.

## What portability has been demonstrated

Two controlled host projects now use the same controller, panel and audio adapter:

| Host | Game UI and gameplay | Audio supplied by |
| --- | --- | --- |
| Main demo | Dark collection arena | Demo-owned WAV tracks and SFX |
| Signal Garden | Light click puzzle | Host-owned procedural sounds |

The preparation script copies the addon into an empty independent project,
verifies its bytes against the source, and records SHA-256 hashes. That project
contains no first-demo files. A Godot integration test exercises the actual panel,
music player, audio opt-out and independent gameplay/SFX.

This establishes reuse across these two projects. It is not evidence of automatic
compatibility with every Godot game. Complex music managers, multiple simultaneous
music sources, video audio and other engines need explicit integration. No
installation-time estimate has been measured with a third-party developer.

## Reproduce

```sh
node tools/prepare_portability_demo.cjs
```

Use the printed directory with Godot's --path option. Import it first, then run:

```sh
godot --headless --path "<printed directory>" --script res://check_integration.gd
```

Node.js is only a convenience for copying and hash verification. You can manually
copy examples/signal_garden/ and the addon into a separate empty project instead.
Never modify generated addon copies to fix a test; fix the source and generate a
fresh copy.

Privacy and Twitch integration remain separate milestones. Once complete, add
them to both host projects and repeat the same checks.

## Dismissible settings and privacy
The optional ui/streamer_settings_menu.gd PopupPanel can host the existing panel using attach_panel(panel) and set_open(bool). Keep the controller/audio/privacy services outside the popup; hiding it does not disable them. The host owns gameplay pause and keyboard handling.

Instantiate PrivacyEngine, call setup(controller), and register must-protect regions. PrivacyCopyField.bind(engine, id) registers its value area and now suppresses source text synchronously while active; Copy uses the stored value. The engine's active_changed(active) signal supports this synchronization. Both demos use opaque tint for these fields.

The scanner remains useful for other supported text, but it has detection latency and a pending large-scene performance target. Do not rely only on pattern discovery for critical secrets.
