# External Godot game integrations
Reviewed 11 September 2026. These are third-party source projects, not our games.

| Host | Upstream revision | Why selected |
| --- | --- | --- |
| [Brett Chalupa's Godot 2D Platformer Starter Kit](https://github.com/brettchalupa/godot_2d_platformer) | 8a776826a6c6af92ff9ad3a4cfd29f344a49a47d | Playable three-level platformer with separate original music and jump/collection effects |
| [Juan Medina's Shoot 'em up](https://github.com/juan-medina/godot-shootem-up) | 8415c266dd809b17da1cd9b829be89ad04083c4b | Independent shooter with music/SFX buses, menus, waves and scene changes |

The platformer is a playable starter kit, not a commercial release. The shooter is an independently authored example game. Both are source-level integration tests, not proof of controlling arbitrary installed games.

## Prepare and play
Clone the upstream repositories separately, check out the revisions above, then run:

~~~sh
node tools/prepare_external_game.cjs platformer PATH_TO_PLATFORMER EMPTY_DESTINATION
node tools/prepare_external_game.cjs shooter PATH_TO_SHOOTER EMPTY_DESTINATION
~~~

Import each destination project with Godot 4.7.2. Older upstream import files can produce transient import diagnostics on the initial migration; the completed imports and runtime checks passed in our prepared copies.

F8 opens streamer settings. Enable mode, choose Quiet Orbit, Neon Run, or Silence, and Resume (or F8). The menu scrolls if needed. F8 leaves the game's own Escape/pause controls intact. Settings survive scene changes within a run; they are not saved between launches.

The platformer has music in its levels, so start playing before comparing. Shooter music is present in both menu and gameplay. Use the original game controls for movement, jumping or shooting.

## What changed
- Copied the same SDK into both games and added a small persistent host autoload.
- Added a dedicated StreamOriginalMusic bus and explicitly routed original music players through it.
- Kept replacement playback on Music, so existing music volume/mute settings remain effective.
- Preserved original effects routes. Shooter victory/game-over musical stings are also on the protected original-music route.
- Added a selector with two locally synthesized looping tracks and Silence.
- Selected the Compatibility renderer and disabled upstream editor-only plugins in the modified test copies.
- Preserved upstream readmes, credits and license files.

The bus adapter is optional: existing users can continue using StreamSafeAudio to manage individual streams. StreamSafeMusicBus is for games whose original music players should continue their own lifecycle behind a dedicated muted bus. Disabling mode restores the dedicated bus's previous mute state; playback resumes at the host's current position.

Use one adapter per dedicated source bus. The source bus must contain only original music; replacement output must not route through it. Do not let other systems mutate that dedicated bus or change adapter bus names at runtime. Route host volume controls through its parent Music bus.

These single-player hosts do not provide real lobby/private fields to protect. Their privacy controls now scan supported game text and allow manually drawn regions; no fake sensitive data was inserted. Native chat is also integrated, with Kick selected by default and a configured relay required for live authorization/delivery.

## Validation
Both external host tests passed with:
- actual game music playing on the dedicated bus;
- normal music muted and replacement playback active on enable;
- original jump/shot effects still playing on an audible separate route;
- Silence and switching back to a replacement;
- a real level/menu change with protection retained;
- original music restored on disable;
- menu pause/resume preserving mode.

Run after importing a prepared copy:

~~~sh
godot --headless --path DESTINATION --script res://streamer_integration/check.gd
~~~

The shooter saves its own user settings. Its sandbox run hit a settings-save assertion; the same test passed under the normal Windows account. Graphical captures of both integrations also completed. Physical listening and broadcast capture are still manual acceptance steps.

The SDK runner now has 12 functional suites, including dedicated-bus mute restoration and cleanup. Scanner performance acceptance remains separate and open.

## Credits and distribution
Platformer upstream credits dedicate its code and Kenney sprites to CC0 and identify its Ted Kerr music as CC BY 4.0. Keep that attribution and upstream track links.
Shooter code is MIT; its README separately credits music, art, fonts and sounds. Preserve those notices and review each asset's terms before redistributing a packaged game.

We keep third-party game trees outside the SDK repository. The preparation tool copies them locally; we have not pushed modified upstream games or published game releases.

## Combined external-host update
F8 now exposes all three features. Scroll below the main feature panel for:
- Connect Kick / Chat settings: select Kick, connect through your browser, then Enable chat.
- Draw private area: the menu closes and gameplay pauses; drag a rectangle. Release to resume. Escape or F8 cancels drawing.
- Edit mask positions / sizes: enable handles, close the menu, adjust regions; disable handles afterward for unobstructed input.
- Clear drawn areas and automatic game-text scanning.

Chat starts disabled until explicitly enabled. Drawing enables the shared master and privacy preference; other selected features follow the master as usual.
Manual regions clear on game scene changes and are not persisted across restarts. Automatic scanning excludes the integration UI and chat; chat history is not automatically sanitized.
External tests now also cover native fixture chat, modal close behavior, privacy-region creation, pause restoration, privacy opt-out and scene-change cleanup. Fixtures are test-only, not live Kick messages.
