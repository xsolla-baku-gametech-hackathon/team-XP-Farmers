# Privacy prototype preserved during foundation merge

The original manual movable-mask project from commit fa88930 is preserved under
`tests/privacy/standalone/`. Its scene, script, icon, and project settings are
unchanged. Import that folder's `project.godot` as a separate Godot project to run
it; its transparent, borderless window settings apply only to that prototype.

The repository-root `project.godot` now runs the shared foundation game with F5.
This resolves the conflict between two different root Godot projects while keeping
both runnable. The mask is not yet connected to the demo's Streamer Mode toggle.

Continue reusable privacy-component work in `addons/streamer_mode/privacy/` and
feature tests in `tests/privacy/`. Coordinate integration into `demo/` with the
integration owner. Preserve the existing prototype until the replacement is ready.
