# Stream-safe audio

`StreamSafeAudio` owns one non-positional music player. It selects the normal or
replacement AudioStream according to the supplied controller's effective AUDIO
state. It has no dependencies on the demo, account services or global autoloads.

## Integrate

Copy the addon folder, add a controller and configure the adapter before adding
it to the tree:

```gdscript
var music := StreamSafeAudio.new()
music.set_tracks(normal_track, approved_replacement_track)
music.music_bus = &"Music" # Create this bus in your game, or use the default Master.
music.bind(controller)
add_child(music)
music.play()
```

Alternatively attach the script to a Node, configure the exported streams, bus,
volume and autoplay in the Inspector, then bind your controller before playback.
Set loop options on the supplied streams if you want continuous background music.
Use `set_tracks(normal, replacement)` for runtime changes.

Disable or replace the game's previous music player. Every music source that
needs replacement must use an adapter; this cannot discover or silence unrelated
players, cutscenes, embedded video audio, voice chat or external applications.

## Behavior

- Master mode off, or AUDIO preference off: normal track.
- Mode on and AUDIO selected: replacement track.
- No replacement: the managed music is silent while protection is active.
- No normal track: normal mode is silent.
- Switching tracks stops the old track before starting the new one from zero.
  There is no crossfade that would deliberately keep normal music playing.
- Selecting the same track again does not restart it.
- `stop()` survives mode changes; `play()` resumes the currently selected track.
- `set_paused(true)` survives track changes; `set_paused(false)` resumes.
- Natural completion stops playback; loop settings belong to the supplied stream.
- Rebinding disconnects the previous controller. Scene exit stops playback, and
  scene re-entry synchronizes with the latest mode.
- Independent sound effects, dialogue and bus volume/mute settings are untouched.

Listen to `playback_changed`, and use `get_status()`, `is_playing()`,
`is_paused()` and `is_protection_active()` for UI.

This changes the same audio output heard by the player and viewers. It does not
control OBS or clear audio already buffered or recorded. The developer must check
the streaming rights of replacement tracks; the adapter does not certify music.

## Check

Run `godot --headless --path . --script res://tests/audio/test_audio.gd`.
For an interactive feature-only scene, open `tests/audio/audio_lab.tscn` and press
F6. The main demo uses the same component and provides separate SFX on collection.
