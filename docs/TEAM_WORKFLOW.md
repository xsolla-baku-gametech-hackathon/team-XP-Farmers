# Team workflow

Use Godot 4.7.2 standard (GDScript), Compatibility renderer, Windows first.
The product is an integrated Godot addon, demonstrated by a small collection game.
It cannot modify arbitrary installed games.

## Ownership

| Branch | Owns |
| --- | --- |
| godot-sdk-foundation | project.godot, addon core, demo/, shared docs |
| privacy-mask-copy | addons/streamer_mode/privacy/, tests/privacy/ |
| stream-safe-audio | addons/streamer_mode/audio/, tests/audio/ |
| twitch-chat | addons/streamer_mode/chat/, tests/chat/ |

The integration owner wires completed components into demo/. Avoid editing
project.godot or the shared scene concurrently. Each teammate uses a separate
clone, commits their source and .uid files, and excludes .godot/ caches.

## Starting a feature

After the foundation PR is merged into main:

```sh
git fetch origin
git switch privacy-mask-copy
git merge origin/main
```

Substitute your branch name. If the foundation PR is still awaiting review, merge
origin/godot-sdk-foundation instead, then target that branch with your feature PR
until the foundation lands. Do not force-push shared branches.

Import project.godot. Run the project with F6 only for a feature test scene;
use F5 for the full demo. Push small working commits and open a PR. Include a
short description and the checks performed. Keep network credentials local.

## Shared API

```gdscript
var controller: StreamerModeController
controller.set_enabled(true)
controller.set_feature_enabled(StreamerModeController.AUDIO, false)
controller.state_changed.connect(_sync)

func _sync() -> void:
    var active := controller.is_feature_active(StreamerModeController.PRIVACY)
    # Apply to your component.
```

The controller combines master enable state with per-feature preferences; it does
not implement features. Bind components explicitly (no global autoload required).
Synchronize immediately after binding so late-added components receive current
state. Disconnect before rebinding or removing a component. Changing preferences
while the mode is off takes effect on the next enable.

## Order of integration

1. Foundation with runnable demo and controller checks.
2. Audio feature, playback checks and demo integration.
3. Privacy component and real clipboard check.
4. Twitch connection and actual channel message.
5. Second-game integration and OBS recording verification.

