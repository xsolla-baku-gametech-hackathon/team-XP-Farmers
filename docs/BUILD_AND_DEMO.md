# Verify and build the Windows demo

Use Godot 4.7.2 standard and its matching Windows x86_64 export templates.
Install templates using Godot's Editor > Manage Export Templates window. Node.js
runs the repository helpers; no Node installation is required to play the export.

## One-command verification

```sh
node tools/verify.cjs "<path to Godot console executable>"
```

The helper imports the project, runs the controller/demo, audio and panel checks,
copies the addon into a fresh Signal Garden project, imports it, and runs its
integration check. Logs and a JSON result go into a new .artifacts/verify-* folder.

Each suite must exit successfully and print its expected PASS marker. Script
errors fail the run even when Godot returns zero. Processes have timeouts. Known
Windows certificate-store/user-cache access diagnostics are retained in the report;
they are not treated as successful network tests. All other ERROR lines fail.

This is the reviewed suite list, not automatic coverage of all future features.
Add privacy/chat checks to the helper when their implementations are integrated.

## Windows export

```sh
node tools/build_windows.cjs "<path to Godot console executable>" "<empty output directory>"
```

This runs verification, exports the Windows Demo preset, then launches the
exported program headlessly outside the source project and checks its runtime log.
The helper refuses to overwrite a nonempty output directory. Keep the entire
output folder together when sharing it.

The preset exports runtime resources with project data embedded in the executable.
It includes preloaded scripts explicitly through the all-resources export mode. Source tests, docs, tools and the other example project are
excluded. It targets Windows x86_64 with the Compatibility renderer.

Engine and third-party license notices are included alongside the executable.
The build manifest records the source revision, whether the working tree had
changes, and file hashes. Builds are generated artifacts, not committed binaries.
The current demo implements audio and settings only; privacy/chat remain pending.

## Presentation-machine acceptance

1. Launch StreamerMode.exe from the exported folder, without the editor.
2. Hear normal music and collect a shard to hear its separate sound.
3. Enable Streamer Mode; hear replacement music and another collection sound.
4. Uncheck audio replacement while mode remains on; confirm normal music returns.
5. Record a short OBS clip with the actual game capture and audio setup, then play
   it back. A headless build check cannot establish capture or speaker behavior.
6. After privacy/chat integration, check hidden information, Copy, real messages,
   disconnection and scene changes in the same recording.

## One-minute demo after all features are integrated

- 0-10 seconds: explain the developer addon and show normal game behavior.
- 10-25 seconds: enable mode; show music replacement and information protection.
- 25-40 seconds: send a real Twitch message and show it in-game.
- 40-50 seconds: demonstrate Copy and preserved gameplay sound effects.
- 50-60 seconds: show the second Godot project using the same addon.

Until privacy and chat are complete, demonstrate audio and portability honestly
and identify the remaining features as work in progress.
