# Streamer Mode SDK — Team XP Farmers
Reusable Godot components for music replacement, private UI protection and native in-game chat.

## Run the integrated demo
Import project.godot with Godot 4.7.2 standard and press F5.
Move with WASD/arrows. Settings / Escape opens a modal menu.
Enable Streamer Mode, select features, then Resume game. Closing settings keeps protection active.

For chat, choose **Connect channel / Chat settings**, fill in the Chat service URL, select a platform and authorize in your browser. A running configured relay is required. No messages or provider connections are simulated in normal gameplay.

## Integration status
- Audio: managed-stream replacement and a dedicated music-bus adapter; effects stay on their own routes.
- Privacy: registered fields, pattern scanning, manual-region components and Copy support. Critical demo codes hide their source text immediately.
- Chat: native Godot overlay using the same controller; connection/appearance settings are inside the shared demo menu.
- External examples: two third-party Godot source projects include audio selection, privacy scanning/manual masks and native chat settings.
- Chat history remains updated while hidden. Disconnect clears history. Master off hides chat but does not disconnect the provider session.

The feature branches are combined in this hackathon integration. One verification command covers the SDK, chat and relay fixtures. Real-account authorization/delivery, recording/listening acceptance, and the large-scene scanner performance target remain open.

Privacy scanning in this demo covers the game HUD, not chat history or connection controls. Chat visibility is not a privacy scrubber: previously received messages can reappear when chat is enabled again.

## Relay
Use Node 22+ and configure the desired providers in a private .env file based on .env.example.
For the default local demo use PORT=8788. Run npm start.
The host can configure streamer_mode/chat/relay_url in project settings; the component defaults to http://localhost:8788.
Provider secrets remain on the server. Public provider callbacks, especially Kick webhooks, need the setup described in [deployment](docs/DEPLOYMENT.md).
The relay is separate from the exported game executable.

## Install in your own Godot game

This is a **runtime GDScript addon** integrated into your game's source project. You need access to that source and must export the game again after integration. There is no editor plugin to enable and no automatic attachment to an already installed game.

### 1. Copy the addon and choose its lifetime

Use Godot **4.7.2 standard** for the tested setup (Windows, Compatibility renderer). Other engine versions/renderers have not been certified here.

Copy the entire [addons/streamer_mode](addons/streamer_mode) folder into your project at `res://addons/streamer_mode/`. Keep that path and let Godot finish importing so its named classes register. You do not need this repository's demo scenes, project.godot or export presets. Node.js is needed only for running the chat relay or the repository's development tools.

Create a Node named StreamerServices under a persistent game root and attach the script below. An Autoload scene is another option. Keep the controller and services alive when hiding settings or changing levels; do not create another controller in each level. If your whole scene is replaced, use an Autoload/persistent shell and rebind references to the new HUD/settings nodes.

### 2. Route music and wire the settings panel

For an existing game, use the music-bus adapter:

1. In Godot's Audio panel, create a bus named **StreamOriginalMusic** that sends to Master (or your existing Music parent bus).
2. Set every original background-music player's Bus to StreamOriginalMusic, including players created by your music manager. Leave effects, dialogue and voice on separate routes.
3. Import a replacement track you have permission to use and enable its looping import/resource setting if needed. The example sends replacement audio directly to Master; it must not pass through StreamOriginalMusic.
4. Add a VBoxContainer inside your existing settings menu. Assign it to Settings Container on StreamerServices and assign your track to Replacement Track in the Inspector.

~~~gdscript
extends Node

@export var settings_container: VBoxContainer
@export var replacement_track: AudioStream

var controller: StreamerModeController
var music: StreamSafeMusicBus

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    controller = StreamerModeController.new()
    add_child(controller)
    # Only audio is installed in this first example.
    controller.set_feature_enabled(StreamerModeController.PRIVACY, false)
    controller.set_feature_enabled(StreamerModeController.CHAT, false)

    music = StreamSafeMusicBus.new()
    music.source_bus = &"StreamOriginalMusic"
    music.replacement_bus = &"Master"
    music.replacement_stream = replacement_track
    music.bind(controller)
    add_child(music)
    assert(music.is_configured(), "Create and route the music buses first")

    var panel = preload("res://addons/streamer_mode/ui/streamer_mode_panel.tscn").instantiate()
    panel.bind(controller)
    panel.set_feature_available(StreamerModeController.AUDIO, true)
    settings_container.add_child(panel)
~~~

Run your game, open settings, enable Streamer Mode and close settings. Original music is muted and the replacement plays; effects remain audible. Disabling the mode or audio preference restores the source bus's previous mute state. Original music playback continues silently while protected. A missing replacement produces silence. To switch tracks at runtime, call `music.set_replacement(other_track)`; pass `null` for silence.

If you want the SDK to own music playback instead of retaining your existing music manager, use **StreamSafeAudio** and route playback requests through it. See the [managed-player example](docs/INTEGRATION.md) and [audio API](addons/streamer_mode/audio/README.md). Choose one approach for a given music source so two players do not compete.

The panel controls state; it does not open your settings menu, pause gameplay or save preferences. Keep your menu UI processing while paused, and let your host restore the previous pause state on close. Hiding the menu must leave StreamerServices running. With custom UI, call `controller.set_enabled(value)` and `controller.set_feature_enabled(feature, value)`; a feature is active only when both its preference and master mode are enabled. Save/load those values through your game's settings system if persistence is required.

### 3. Select private information for your game

Privacy needs game-specific configuration. Add this inside the host's setup after the panel exists, replacing `game_hud` with your actual HUD Control reference:

~~~gdscript
var privacy := PrivacyEngine.new()
add_child(privacy)
privacy.set_scan_root(game_hud)
privacy.setup(controller)
controller.set_feature_enabled(StreamerModeController.PRIVACY, true)
panel.set_feature_available(StreamerModeController.PRIVACY, true)
~~~

The scanner checks Label, RichTextLabel and LineEdit text against pattern packs. It does not recognize text in textures/custom drawing or know every game's secret format. Limit its roots to the intended game UI; exclude chat/settings if scanning a larger tree using `privacy.exclude_subtree(node)`.

For known sensitive Controls, call `privacy.register_node(&"private_field", control)`. For a critical lobby/invite code with Copy support, use PrivacyCopyField instead of displaying the code in an ordinary Label:

~~~gdscript
var field := PrivacyCopyField.new()
field.caption = "LOBBY CODE"
field.value = actual_lobby_code
hud_container.add_child(field) # Existing HUD container; creates the internal Controls.
field.bind(privacy, &"lobby_code") # Bind AFTER adding it to the active tree.
~~~

Here `actual_lobby_code` and `hud_container` are supplied by your game. The field hides its source text immediately while protection is active; Copy retains the real value. Ordinary scanner detection has latency, so do not rely on pattern matching alone for critical secrets. Update registrations and scan roots when replacing the HUD; unregister obsolete IDs. For user-drawn regions, use PrivacyDrawTool and define when regions are cleared on scene changes. See the [external host implementation](examples/external_games/streamer_integration.gd) for complete draw/edit and pause handling.

### 4. Add chat when your relay is ready

Audio and privacy work without a relay. For chat, run/configure the server described under **Relay** and in [deployment](docs/DEPLOYMENT.md), then add this after the panel setup:

~~~gdscript
var chat := StreamerChat.new()
chat.bind(controller)
add_child(chat)
panel.set_feature_available(StreamerModeController.CHAT, true)
chat.status_changed.connect(func(_state: String, detail: String):
    panel.set_feature_status(StreamerModeController.CHAT, detail)
)
panel.set_feature_status(StreamerModeController.CHAT, chat.get_status())

var connect_button := Button.new()
connect_button.text = "Connect channel / Chat settings"
settings_container.add_child(connect_button)
connect_button.pressed.connect(chat.open_settings)
~~~

The CHAT preference remains off from step 2 until the player connects and chooses **Enable chat**. In Chat settings, enter the relay's HTTPS origin (or localhost HTTP), select Kick/Twitch/YouTube, choose Connect channel, authorize in the browser, then Enable chat. An RTMPS streaming address is not a chat service URL. The URL field lasts for the session; `streamer_mode/chat/relay_url` in project settings supplies the default at startup. Account connections must be authorized again after restarting the game.

This minimal example opens the chat component's own settings Control. For a single modal inside your game's menu, reparent `chat.settings` into it and handle `close_requested` to restore your menu/pause state, as in [demo/main.gd](demo/main.gd). The relay is deployed separately; provider secrets belong in its private environment, never in the game export. See the [chat API](addons/streamer_mode/chat/README.md).

### 5. Verify in your game before exporting

- Toggle master mode and each installed feature independently, then close settings and change levels.
- Check every music source is replaced/muted and effects/dialogue still play; test a missing replacement track.
- Test real sensitive fields, Copy, UI scaling and HUD/scene changes. Confirm masks cover the intended information.
- Authorize a real chat account and send a new message. Hiding chat preserves its buffer; Disconnect clears it.
- Export your game with the addon and your own assets included, then inspect an OBS recording and listen to the result.

For reproducible examples in two third-party source projects, see [external games](docs/EXTERNAL_GAMES.md). For collaboration, see [team workflow](docs/TEAM_WORKFLOW.md).

## Checks
The verification runner checks 17 suites/stages, including 15 server/provider test cases:

~~~sh
node tools/verify.cjs "PATH_TO_GODOT_CONSOLE"
~~~

Additional targeted chat/merge checks:

~~~sh
godot --headless --path . --script tests/test_chat.gd
godot --headless --path . --script tests/test_combined_chat.gd
node --test tests/*.test.mjs
node tests/godot_relay.mjs
node tests/godot_pairing.mjs
~~~

The HTTP and pairing fixtures accept GODOT as the executable environment variable.
Provider tests use mocked traffic and do not certify live-account delivery.
The strict scanner benchmark remains available with -- --strict-performance on tests/privacy/test_privacy_engine_churn.gd; its 16 ms target was exceeded in this environment.

## Scope
This is source-level integration for participating Godot games, not automatic protection for arbitrary installed games.
Both player and captured game receive the same modified UI/audio.
Supplied tracks must have appropriate usage rights; the SDK does not guarantee prevention of copyright claims or stream sniping.
Demo music is synthesized locally; it is not commercial music recognition or filtering.

Windows build tooling is documented in [build instructions](docs/BUILD_AND_DEMO.md). The combined Windows demo is built from the verified integration; the relay is deployed separately.
