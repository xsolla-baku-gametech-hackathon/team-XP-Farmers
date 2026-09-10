# Signal Garden: second host project

A separate click puzzle with its own game code, sound generation and integration
glue. It is a portability fixture, not part of the addon.

Prepare a runnable copy from the repository root:

```sh
node tools/prepare_portability_demo.cjs
```

The command prints the generated project directory. Import its project.godot in
Godot 4.7.2, or run these commands with the printed path:

```sh
godot --headless --path "<generated directory>" --editor --import --quit
godot --headless --path "<generated directory>" --script res://check_integration.gd
godot --path "<generated directory>"
```

Do not import this source template before installing the addon: its references
intentionally target res://addons/streamer_mode/. You may instead copy this folder
to an empty directory and copy the repository's addon into addons/streamer_mode/
there, with no Node.js requirement.

The automated preparer refuses to overwrite an existing nonempty destination,
copies rather than links the addon, checks the copied bytes against the originals,
and records SHA-256 hashes. There is no demo/ folder, shared cache or parent-project
resource dependency in the generated game. Generated copies are disposable test
outputs; edit the source addon and template, then prepare a fresh copy.
