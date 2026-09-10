# Validation notes

Target: Godot 4.7.2 standard, Windows, Compatibility renderer.

## Automated checks

- Foundation: mode and feature preferences, idempotent changes, UI wiring, reset.
- Audio: actual player stream replacement, effects and bus isolation, feature
  opt-out, paused/stopped transitions, missing replacement, recovery, rebinding,
  scene re-entry and already-enabled startup.

Run an editor import before the checks so Godot registers script classes and WAV
imports. A passing process returns exit code zero and prints a PASS line. Check
the full log as well: Godot import may return zero even when script errors occur.

## Manual acceptance on the presentation computer

1. Press F5. Hear Neon Run; collect a shard to hear the separate effect.
2. Enable Streamer Mode. Hear Quiet Orbit and collect another shard.
3. Uncheck Stream-safe audio while mode stays on: hear Neon Run again.
4. Open tests/audio/audio_lab.tscn and press F6. Exercise Pause, Stop, Play and
   missing replacement. Enabling with no replacement must silence music; the
   independent sound-effect button must remain audible.
5. Record these transitions in OBS and listen back with headphones.
6. After privacy and chat are integrated, test Copy without exposing a value on
   stream, receive an actual Twitch message, and verify scene transitions.

Automated playback-state checks do not prove the user's speakers, OBS capture or
Twitch connection. Those require this machine-level acceptance check.

## Portability milestone

Panel lifecycle checks cover unbound controls, component availability, external
state changes, multiple panels, rebinding, removal and re-entry. Signal Garden
is generated into an independent directory from its own host code and an exact
addon copy, then imported by Godot and tested through the actual UI and player.
See INTEGRATION.md for reproducible steps and the limits of this evidence.
