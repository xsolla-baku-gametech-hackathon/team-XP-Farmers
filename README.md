# Streamer Mode SDK

A reusable Godot addon that gives developers one switch for streamer features,
with a small playable game to demonstrate integration. Built by Team XP Farmers
for the Xsolla Baku GameTech Hackathon.

## Run

1. Use **Godot 4.7.2 standard**, with GDScript (no .NET required).
2. Import `project.godot` in the Godot Project Manager.
3. Press **F5**. Move using WASD or arrow keys and collect green shards.
4. Press Escape or Settings, enable Streamer Mode, then choose Resume game. Protection stays active after closing settings.

The project uses the Compatibility renderer and no external packages or plugins.
No Twitch account is needed for the foundation demo.

## Current milestone

- Playable 2D collection arena and reusable addon settings panel.
- Reusable controller with master toggle, feature preferences, and signals.
- Working music replacement with independent collection sound effects.
- Independent Signal Garden project using an unchanged copy of the addon.
- Automated controller, panel lifecycle, audio and second-project integration checks.

Privacy is integrated on this integration branch. The lobby code is concealed while Copy keeps the real value available. Chat remains a separate teammate application and its in-game control is unavailable. The sample lobby code is fictional. Enable Streamer Mode to switch from Neon Run to Quiet Orbit. Both tracks are synthesized demo material, not third-party commercial songs.

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
editor plugin is required. The addon has no dependency on `demo/`. You can also instance `ui/streamer_mode_panel.tscn` to use the provided settings UI. See [installation steps and portability evidence](docs/INTEGRATION.md).

See [team workflow and public API](docs/TEAM_WORKFLOW.md) for branch ownership,
component contracts and how to start feature work. Each feature folder includes
its handoff notes. Use standalone feature scenes before editing the shared demo.

## Checks

Replace `godot` with the path to your Godot console executable if needed:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_foundation.gd
godot --headless --path . --script res://tests/audio/test_audio.gd
godot --headless --path . --script res://tests/ui/test_panel.gd
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
small project. Audio replacement is implemented. Audio and the settings panel have been validated in a separate second project. Privacy is also integrated and checked in both project hosts. Live chat, scanner performance acceptance, real-game integration and recording/listening acceptance remain upcoming milestones. See [validation notes](docs/VALIDATION.md).

## Verify and build

Run all reviewed suites with:

```sh
node tools/verify.cjs "<Godot console executable>"
```

Build a standalone Windows demo with matching export templates installed:

```sh
node tools/build_windows.cjs "<Godot console executable>" "<empty build directory>"
```

See [build and presentation instructions](docs/BUILD_AND_DEMO.md) and the
[next feature integration checkpoint](docs/FEATURE_INTEGRATION.md).

## Combined integration

See [integration status](docs/FEATURE_INTEGRATION.md) for menu behavior, privacy checks and the open scanner performance target. Privacy/audio run locally. Chat is a separate application and has not been merged here.

## Existing-game tests
Two third-party Godot source projects now have tested audio integrations with a track/silence selector. See [external game setup](docs/EXTERNAL_GAMES.md). The latest chat branch restores native Godot integration and passed review; see [chat review](docs/CHAT_REVIEW.md). Chat is not merged into this branch yet.
