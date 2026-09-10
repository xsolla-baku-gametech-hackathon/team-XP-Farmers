# Streamer Mode SDK

A reusable Godot addon that gives developers one switch for streamer features,
with a small playable game to demonstrate integration. Built by Team XP Farmers
for the Xsolla Baku GameTech Hackathon.

## Run

1. Use **Godot 4.7.2 standard**, with GDScript (no .NET required).
2. Import `project.godot` in the Godot Project Manager.
3. Press **F5**. Move using WASD or arrow keys and collect green shards.
4. Click the Streamer Mode button or press Escape to change the shared state.

The project uses the Compatibility renderer and no external packages. The
`streamer_mode` addon ships a `plugin.cfg`; enabling it is optional and only
adds an editor menu item for tagging private nodes. No Twitch account is needed
for the foundation demo.

## Current milestone

- Playable 2D collection arena and Streamer Mode panel.
- Reusable controller with master toggle, feature preferences, and signals.
- Explicit integration points for audio, privacy and Twitch chat.
- Automated controller and demo wiring checks.

On this branch privacy masking is integrated: enabling Streamer Mode runs
`PrivacyEngine`, which pixelate-blurs registered private UI and text the scanner
matches, adapting as the layout or window changes. The join code stays copyable
while masked. A dev control panel (the "PANEL" button) tunes the blur live.
Music replacement and chat are still pending and their controls are labeled as
such. The sample lobby code is fictional.

## Product scope

A game developer integrates this addon into a Godot project. They identify private
UI, supply appropriately licensed replacement music, and configure Twitch access.
Both the player and viewers receive the same modified interface and audio.
This is not an automatic overlay for arbitrary installed games. It reduces
specific exposures; it cannot guarantee freedom from copyright claims or stream
sniping. Separate engine adapters would be needed for Unity and Unreal.

## Addon integration

Copy `addons/streamer_mode/` into another Godot project. Create a Node with
`core/streamer_mode_controller.gd` attached. Pass that controller to feature
components; connect the game's settings to `set_enabled(bool)`. No autoload or
editor plugin is required. The addon has no dependency on `demo/`.

See [team workflow and public API](docs/TEAM_WORKFLOW.md) for branch ownership,
component contracts and how to start feature work. Each feature folder includes
its handoff notes. Use standalone feature scenes before editing the shared demo.

## Checks

Replace `godot` with the path to your Godot console executable if needed:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_foundation.gd
```

Optional screenshots (requires a graphical session):

```sh
godot --path . --script res://tests/capture_demo.gd
```

Screenshots go to the ignored `.artifacts/` folder. Commit source and `.uid`
files, not `.godot/` caches, exports, account credentials or access tokens.

## Demo completion criteria

One toggle must activate integrated features: switch managed music while keeping
sound effects, conceal private text while preserving Copy, and show actual Twitch
chat. Verify a real OBS recording and then integrate the addon into a second
small project. These are upcoming milestones, not foundation capabilities.
