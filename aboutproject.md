# About the Project — Streamer Mode SDK
**Team XP Farmers · Xsolla Baku GameTech Hackathon**  
Status snapshot: 10 September 2026

## Project in one sentence
A reusable Godot addon that lets developers give players a Streamer Mode setting for privacy protection and controlled music replacement, with a separately developed live-chat companion.

## Problem and audience
Streamers can accidentally reveal lobby codes, server addresses, and other private information while playing. Game music may also be unsuitable for redistribution in a broadcast. Configuring separate workarounds creates friction.

Our initial audience is Godot developers who can integrate protection directly into their games. Streamers are the end users: they enable a setting and continue playing. We deliberately chose a focused Godot use case for the hackathon instead of promising universal support for every game.

## Intended player experience
1. Open the game's settings and enable Streamer Mode.
2. Choose available features, such as privacy and music replacement.
3. Close settings and continue playing with the features active.
4. Copy an obscured lobby code using its Copy button when needed; the clipboard receives the underlying value.
5. Return to settings to adjust or disable protection.

Both the player and the captured game see the same protected interface and hear the same selected game audio. There is no separate viewer-only output.

Both demos now use a dismissible settings menu. Closing it keeps enabled services active. Privacy masks will remain visible over protected information, but configuration panels should not occupy gameplay space.

## What we are building
The product is a tool integrated into games, not a new game. Our collection arena and Signal Garden puzzle are test hosts that demonstrate the addon.

| Component | Purpose | Current status |
| --- | --- | --- |
| Shared controller | Master switch, independent feature preferences, change signals | Implemented on the SDK/audio branch |
| Stream-safe audio | Switch managed music to a supplied replacement, or silence it if no replacement exists; preserve independent sound effects | Implemented and tested |
| Reusable settings panel | Host-game controls for available features | Implemented; dismissible menu implemented |
| Privacy | Registered sensitive regions, text-pattern scanning, manual regions, copyable protected values | Integrated with audio on integration/streamer-mode; functional checks pass |
| Live chat | Twitch, Kick, and YouTube chat via a Node service and Electron overlay | Separate teammate application; not integrated with the Godot controller |
| Portability example | Independent Signal Garden project using an unchanged addon copy | Audio/controller/panel/privacy integration tested |
| Windows package | Exportable demo plus verification/build tools | Implemented |
| Existing-game acceptance | Integrate into a real, independently developed Godot game | Planned |

“Implemented” does not mean all components have been tested together. The integration runner covers seven privacy suites as well; it does not certify live provider connections or the scanner performance target.

## Technical design
Godot runtime code uses GDScript and the Compatibility renderer. The current project is tested with Godot 4.7.2.

The addon lives under `addons/streamer_mode/`. A shared controller publishes effective feature state. Audio and privacy consume that state; the game decides where to place settings and how to retain services across scene changes. Closing a settings panel must not destroy the feature services.

The audio component manages explicitly connected music. It is not a song-recognition system and cannot separate copyrighted music from arbitrary mixed audio. Developers supply appropriate replacement tracks and route the relevant music through the component. Demo tracks are synthesized locally without external recordings or sample libraries.

Privacy operates inside the game viewport. Its scanner inspects supported Godot text controls and patterns; it is not desktop OCR. Explicit registration is needed for must-protect information and content the scanner cannot inspect, such as texture text or custom drawing. Mask strength and first-frame exposure still require visual acceptance testing.

The chat branch currently uses a separate Node service and Electron desktop overlay. It has its own controls and provider setup. A future shared control connection would require additional work. Desktop chat appearing in a broadcast depends on the actual capture configuration.

## Integration into another game
The developer needs a Godot project they can modify, with permission to use its code and assets.

1. Copy the addon into the project and import it.
2. Create the controller and bind the audio/privacy components.
3. Connect the host game's music and supply a suitable replacement.
4. Register critical private UI and connect protected Copy fields.
5. Bind the game's settings to the controller.
6. Test scene transitions, resizing, input, audio routing, copying, and the actual captured output.

The addon has no dependency on the arena demo. Signal Garden is evidence of reuse, but it is a team-created test project. Final validation in an independently developed game remains necessary. Supporting Godot does not mean every engine version or platform is already certified.

## Branches and teamwork
Reviewed remote heads:

| Branch | Commit | Ownership / contents |
| --- | --- | --- |
| `godot-sdk-foundation` | `c79fda9` | Foundation baseline |
| `stream-safe-audio` | `0fbc00f` | Our SDK, audio, panel, portability, Windows tooling |
| `privacy-mask-copy` | `0dc76e8` | Teammate privacy implementation |
| `twitch-chat` | `ca8f90c` | Teammates' standalone chat application |
| `main` | `b308d51` | Original project template |

Privacy is structurally compatible with the shared SDK. A non-checkout merge preview found conflicts in `demo/main.gd` and `README.md`. Those conflicts have now been resolved on integration/streamer-mode, with joint functional checks passing.

Use a dedicated integration branch based on the audio branch, preserve teammate history, resolve shared UI changes, and test before publishing a combined build. Do not replace whole files blindly or force-push teammates' branches. The chat branch removes the Godot project in its own history, so it should not be merged wholesale into the SDK.

## Validation and definition of done
Existing verification covers controller/foundation behavior, music transitions, settings-panel lifecycle, and independent-game integration. Build tooling exports a Windows executable and checks that it starts independently.

Before presenting the combined SDK as complete:
- Resolve and test the privacy integration, including its own suites.
- Put configuration in settings and confirm protection persists after closing it.
- Verify that enabling privacy conceals the intended values and Copy still yields the correct value.
- Check for readable secrets during initial appearance, resize, and scene changes.
- Listen to mode transitions and verify gameplay sound effects remain.
- Measure frame-time impact with protection on and off in the same scene.
- Test the exported build and its actual broadcast recording.
- Repeat acceptance in an independently developed Godot game.
- Demonstrate real chat separately with configured accounts; label sample messages honestly.

Headless tests cannot establish visual concealment or audible quality. Privacy's headless Copy tests also cannot certify the operating-system clipboard.

## Next milestones
1. **Combined Godot experience:** privacy plus audio on an integration branch, settings-only controls, and joint regression checks.
2. **Real-game integration:** choose a compatible game with available source and suitable permissions, integrate without demo dependencies, and record integration effort and performance.
3. **Final hackathon delivery:** Windows build, install guide, short recorded demonstration, known limitations, and a separate chat demonstration if live setup is ready.

The external game has not yet been selected. Avoid promising a completion date until its structure and integration effort are reviewed.

## Costs and hackathon budget
All amounts below are USD. These are planning assumptions, not invoices, vendor quotations, or a record of actual expenditure. Actual team spending and hours have not been supplied.

### Cash needed for the focused prototype
| Item | Budget treatment |
| --- | --- |
| Godot engine | $0 license fee; free under MIT. Include required notices. |
| Local SDK runtime | No backend required for privacy/audio; no per-player cloud processing charge in this architecture |
| Demo audio | $0 external asset purchase assumed; team-generated tracks |
| Computers, electricity, internet | Existing resources assumed; exclude from incremental cash only if already available |
| Team development | Unpaid during hackathon assumption; account for effort separately |
| Other software subscriptions | Add actual incremental charges if incurred; not included in the estimate |
| Separate hosted chat service | Optional for the core demo; budget separately if deployed |

A local SDK demo can target **$0 incremental software/hosting spending**, provided the team already has hardware and internet and buys no services or assets. This is not a claim that development is free.

### Optional pilot allowance
A proposed spending envelope is **$10–30 per month for chat hosting**, plus **$10–20 per year for an optional domain**. These are internal budget allowances, not checked provider prices or guaranteed capacity. That gives an illustrative annual envelope of **$130–380**, before tax, usage overages, support, signing, or paid assets.

Choose and price an actual hosting service only when live chat deployment requirements are settled. Core offline privacy/audio does not require this expense.

### Showing development value honestly
Present team effort separately from cash:
**estimated development value = recorded person-hours × assumed hourly rate**.

For example, **120 person-hours × $15/hour = $1,800** of illustrative development effort. This is an example calculation, not our recorded cost or a market-rate claim. Replace both inputs with the team's agreed figures before presenting them as project data.

For a hackathon slide, show:
- Incremental cash budget: local prototype target $0 under the stated assumptions.
- Main investment: team engineering and testing time, with actual hours when available.
- Optional operations: a separate chat-hosting allowance.
- Future costs: compatibility testing, maintenance, customer support, music rights if purchased, and desktop distribution requirements.

Godot's free MIT licensing is documented at [Godot's official license page](https://godotengine.org/license/). This does not automatically determine the license for our own repository or third-party game assets.

## Potential sustainability
A possible future model is a free core addon with paid integration assistance, support, or a separately hosted chat service. These are options to investigate, not validated revenue streams. We have not established pricing, demand, customer acquisition costs, or production support requirements.

## Limits and honest claims
- Requires developer integration; it does not retrofit arbitrary installed games.
- Reduces specific exposures; it cannot guarantee prevention of stream sniping or copyright claims.
- Safe music depends on supplied tracks and usage rights; the SDK does not certify licenses.
- Automatic text patterns can miss secrets or hide harmless text.
- Combined functional integration is complete; scanner performance, recording acceptance and independent real-game validation remain unfinished.
- Chat remains a companion application with separate setup, not a completed single-switch integration.

## Suggested presentation pitch
“Team XP Farmers is building a Streamer Mode SDK for Godot games. Developers connect private UI and music once; players enable a setting and keep playing. Our audio component already works in two project hosts, and our privacy branch adds masking with usable Copy controls. They now work together in both test hosts, and we will validate the addon in an existing Godot game. Live chat is a separate companion. The core runs locally, keeping infrastructure costs low.”

## Integration update
The shared settings-menu/privacy/audio milestone is implemented on integration/streamer-mode. Eleven functional suites pass. A forced 300-node scan measured about 34 ms against a 16 ms target; optimization and real-game performance acceptance remain open. A separately selectable strict performance gate retains that target.
