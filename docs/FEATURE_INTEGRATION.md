# Combined integration checkpoint
Snapshot: 10 September 2026. Branch: integration/streamer-mode.

## Completed
- Merged privacy-mask-copy at 0dc76e8 with SDK/audio work based on 0fbc00f, preserving teammate history.
- Resolved shared demo and README conflicts around the audio implementation.
- Shard Run and Signal Garden open streamer controls through Settings / Escape.
- Resume dismisses the modal menu without disabling audio or privacy.
- Arena movement is suspended while settings are open; puzzle input is blocked by the modal.
- Integrated PrivacyCopyField and PrivacyEngine into both independent hosts.
- Critical invite fields hide source text synchronously, retain Copy, and use opaque mask tint.
- Original scanner, blur, manual-region controls and editor plugin remain in the addon. Advanced privacy configuration is not exposed in these simplified demo menus.
- Chat remains separate; neither its branch nor main was changed.

## Verification
The runner now executes 11 functional suites: foundation, audio, panel, seven privacy suites, and the independent-game suite. It also imports both projects. Windows packaging verifies export startup.

Copy-field checks cover synchronous source suppression, mode changes and copying. Headless runs verify copied payloads; desktop clipboard and a real recording still need manual acceptance.

## Performance finding
A forced 300-control scanner sweep measured about 34 ms in this environment against the existing 16 ms target. Functional scanner checks still pass. The benchmark remains printed in the churn log; its performance threshold is now an explicit opt-in gate so it is not confused with correctness.

Run the strict benchmark:
~~~sh
godot --headless --path . --script res://tests/privacy/test_privacy_engine_churn.gd -- --strict-performance
~~~

The default verifier reports performance acceptance as pending. This change does not claim the scanner meets its target. Measure and tune batching on the selected real game. General automatic scanning can have detection/animation delays; critical Copy fields suppress their source text separately.

## Next
1. Select an independently developed Godot game with editable source and suitable asset/code permissions.
2. Integrate settings, managed music and explicit sensitive fields there.
3. Measure frame-time overhead and tune scanning scope/budget.
4. Check desktop copying, audible transitions and recorded output.
5. Review chat separately when its owner is ready.
