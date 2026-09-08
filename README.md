# Ableton Clip View pitch demo

Target experience: double-click an audio clip in Live, open its existing bottom Clip View, switch to a new Pitch mode, edit detected vocal notes, and apply audible changes. This is a local experimental integration intended for demonstration to Ableton. A floating editor or overlay alone does not satisfy the requested native integration.

## Current implementation status

**Native placement is proven. Pitch editing is not implemented yet.**

A separate `build/Ableton Pitch Lab.app` now displays **Sample / Envelopes / Pitch Editor** inside the existing bottom Clip View. Live creates the new `ButtonControlSimple` from its modified `ClipContentHeader.xml` resource in `GUI.alp`. The native accessibility ID is `ClipDetailView.ClipContentHeader.PitchEditorButton`. The button is currently disabled because it has no editor-state binding.

Read [the resource patch and verification](docs/native-tab-resource.md) for the exact insertion point, reproduction steps, evidence, and remaining binding work. [The verified screenshot](build/research/native-tab-verified.png) shows the control with a stock audio clip open. The source application in `/Applications` and both executable binaries are unchanged; only the experimental copy's GUI archive was modified. No re-signing or license changes were needed. Saving/exporting remain disabled.

The in-process diagnostic loader also works: `build/Pitch Probe.amxd` loads `pitchprobe3.mxo` on Live's main thread. It reads window/accessibility structure and Objective-C metadata. It has no hooks or audio processing. The diagnostic was not needed to display the native resource button.

[The static tab-control trace](docs/native-tab-trace.md) establishes mode IDs, fallback behavior, keyboard cycling and lifecycle candidates. Run `python3 scripts/trace_tabs.py` for bounded offline evidence. Normal debugger attachment was denied by macOS; no runtime C++ callback trace has been established.

Remaining work: bind the button to custom editor state; integrate native editor creation, focus, resize and teardown; implement monophonic pitch analysis, note-block edits, audible rendering and undo. A visible button does not demonstrate these behaviors.

### Build and run the diagnostic

Requires Apple Silicon macOS, Xcode command-line tools, and the official [Cycling ’74 Max SDK base](https://github.com/Cycling74/max-sdk-base) at `vendor/max-sdk-base`.

```sh
python3 scripts/build.py
```

Keep `Pitch Probe.amxd` and `pitchprobe3.mxo` together in `build`. Open the device in an expendable Live Set, then double-click an audio clip within 60 seconds. The diagnostic records snapshots every five seconds for one minute in `probe.log`. A `bang` to the external requests another snapshot. Its `plugin~`/`plugout~` connections pass audio through.

Only the generated external is ad-hoc signed. No Live executable has been changed or re-signed. Restart Live after rebuilding an already loaded external: Max caches loaded classes. Earlier numbered bundles in `build` are development iterations, not additional required dependencies.

Remove the probe devices from the scratch Set to remove the loaders from the Set; already scheduled diagnostics stop after one minute, and the loaded external code remains cached until Live exits. No app-bundle rollback is required.

## Investigation details

- Installed build: Live 12.4.5 `(2026-08-19_225ce5e356)`, universal arm64/x86_64.
- Desktop Clip View uses native XML resources in `GUI.alp`; Qt/Push QML is unrelated.
- `TAxPlatformNode` is an accessibility element, not an AppKit view. Adding an AppKit child would not establish a native mode.
- `EditorViewModeSelector` is a `ModeSwitchControl` bound to `EditorViewMode`. Its labels come from a C++ enum; the experiment inserts a separate native sibling control.
- Sample, Envelopes and MIDI Expression use mode IDs 0, 1 and 2. Unknown mode IDs fall back to Sample; adding a fully integrated mode requires more than a label.
- Experimental resources and the app copy stay in ignored `build/` and are not redistributable project source.

The original scratch instance and experimental copy may both be running. Use the full app path to distinguish them. Live warns that concurrent instances cannot recover Sets after crashes; the experiment uses disposable Untitled Sets.

## Source control and fresh checkouts

This directory is an independent Git repository on `main`. Track our source,
resource transformation scripts, and documentation. Generated binaries, app
copies, extracted Ableton resources, SDK checkouts, audio, Live Sets, logs and
Python caches are ignored. Recreate the experimental app locally from an
installed copy of the supported Live build; do not upload it as a GitHub release
asset. The native tab script verifies the executable fingerprint before use.

For a fresh checkout, obtain the official Max SDK at the pinned revision:

```sh
git clone https://github.com/Cycling74/max-sdk-base.git vendor/max-sdk-base
git -C vendor/max-sdk-base checkout --detach c03a2922a2a8ff149165a1e2ea134e9321d6e202
python3 scripts/build.py
```

The diagnostic log path is generated from the checkout location at build time.
Follow [the native resource instructions](docs/native-tab-resource.md) to
recreate the experimental application. The SDK is obtained separately and
retains its own license. No project license or GitHub remote has been selected.
