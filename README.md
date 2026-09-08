# Ableton Pitch Editor

Target experience: double-click an audio clip in Live, open its existing bottom Clip View, switch to a new Pitch mode, edit detected vocal notes, and apply audible changes. This is a local experimental integration intended for demonstration to Ableton. A floating editor or overlay alone does not satisfy the requested native integration.

## Current implementation status

**The experimental Pitch Editor tab now opens editable pitch notes inside the native audio Clip View. Audio rendering remains unimplemented.**

Build with `python3 scripts/build_native.py`. In `build/Ableton Pitch Lab.app`, load `build/Native Pitch Editor.amxd` on the test audio track, keeping `pitchnative20.mxo` alongside it. Double-click a warped audio clip, then click **Pitch Editor** in its header. Left/right select notes, up/down transpose, and ⌘Z / ⇧⌘Z undo/redo while the pitch canvas has focus. The source file is analyzed automatically (mono/stereo, 8–48 kHz, at most 60 seconds).

The adapter creates `APlatformViewHost` children inside the existing native tab button and `LWarpedAudioTimelineEditor`. Live supplies actual `TPlatformViewContainer` surfaces for an AppKit toggle and pitch canvas. It does not create a floating window or position an unrelated NSView over the main app. The mode is local to this experimental adapter; Live's internal three-mode enum is unchanged. A Max device provides the loader and selected-clip file lookup.

Verified: tab activation; 18 segments from the selected vocal; note 1 changing +1 → 0 → +1 through edit/undo/redo; edits retained when toggling the pitch tab; canvas removed when leaving Clip View. Pointer dragging is implemented but this native adapter's drag test was blocked by the computer-use tool's `noWindowsAvailable` error; keyboard editing was verified instead. See [the working native view](build/research/native-pitch-editor-working.jpg) and [implementation details](docs/native-tab-working.md).

Remaining: audible pitch rendering/application, crop and warp mapping, synchronization with native horizontal zoom/scroll, detection quality, proper Pitch footer controls, host undo/Set persistence, and broader lifecycle tests. The canvas currently fits the entire source file; it must not be presented as aligned to arbitrary cropped/warped/zoomed clips. Leaving Clip View or changing clips currently discards the temporary edit model. The stock choir exposes octave errors and is not a vocal-quality benchmark.

The original app and both Live executables remain unchanged. The experimental copy contains the [resource-only native tab addition](docs/native-tab-resource.md); proprietary copies and generated artifacts stay in ignored `build/`.

The source waveform appears behind the pitch notes and stays aligned with the editor’s time zoom and pan.

The editor shows an Envelopes-style thin playback cursor. It follows Live’s Follow switch for paging through the pitch viewport. Manual navigation suspends following until playback restarts or Follow changes. Verified on track 3, including loop restart, stop, and Follow on/off.

### Navigation

In Pitch Editor, scroll to pan; Command-scroll or pinch zooms time;
Option-scroll zooms pitch. Drag the inner seconds ruler or Option-drag the
canvas to pan. Use +/- to zoom time, Option +/- to zoom pitch, Shift-arrows to
pan, and F (or Fit) to see the whole clip. The inner seconds ruler follows this
viewport; the outer native beat ruler is not yet synchronized.

### Pitch engine and development editor

**An interim device now runs inside Live:** build it with
`python3 scripts/build_live_editor.py`, then load `build/Pitch Editor.amxd` on an
audio track, keeping `pitchclip2.mxo` beside it. Select an audio clip and click
**Analyze clip** in the device. Drag detected blocks vertically; the device's
**Undo** and **Redo** buttons change its local edit history.

This uses Live's **Device View**, not the experimental Clip View tab. It reads
the clip's entire source file in unwarped seconds; crop/loop/warp mapping and
audio rendering are not implemented. Edits are temporary and do not change
playback or get saved with the Set. The audio path is stereo pass-through.
Re-analysis replaces the edit model. Select an audio clip before analyzing;
missing/MIDI clip errors currently appear in Max rather than the device UI.

Verified in the experimental Live copy: the selected stock vocal sample was
read through the Live API, 18 segments appeared, and dragging note 7 followed
by Undo/Redo visibly produced +3/0/+3 semitone states. The choir sample exposed
octave jumps and fragmented detection; this is not a vocal-quality benchmark.
See [the in-Live preview](build/research/pitch-editor-in-live.jpg).

The first portable C++ pitch detector and note-edit model are implemented in
`src/pitch_core.cpp`. A separate AppKit development window can load short audio
files, draw detected note blocks and the original pitch contour, transpose notes
with semitone snapping, and undo/redo edits. This window is a test harness;
it is **not connected to Live's Pitch Editor tab**. Audio rendering, saving edits,
and host undo/clip timing integration are still pending.

```sh
python3 scripts/build_editor.py
```

Open `build/Pitch Editor Lab.app`, choose **Open audio…**, and use a solo vocal
clip up to 60 seconds, mono/stereo, at 8–48 kHz. Drag notes vertically, or use
Left/Right to select and Up/Down to transpose. Command-Z undoes; Shift-Command-Z
redoes. One drag commits one history entry. Loading another file discards these
temporary edits. The source audio is never written.

The script runs detector/model regression tests before building. UI verification
loaded a generated six-note WAV, detected six blocks, and confirmed keyboard
transposition +1 → undo 0 → redo +1 without moving note boundaries.
See [the development preview](build/research/pitch-editor-lab.png) and
[engine design and limitations](docs/pitch-engine.md).

### Build and run the diagnostic

Requires Apple Silicon macOS, Xcode command-line tools, and the official [Cycling ’74 Max SDK base](https://github.com/Cycling74/max-sdk-base) at `vendor/max-sdk-base`.

```sh
python3 scripts/build.py
```

Keep `Pitch Probe.amxd` and `pitchprobe6.mxo` together in `build`. Open the device in an expendable Live Set, then double-click an audio clip within two minutes. The diagnostic records snapshots every five seconds for two minutes in `probe.log`. A `bang` to the external requests another snapshot. Its `plugin~`/`plugout~` connections pass audio through.

Only the generated external is ad-hoc signed. No Live executable has been changed or re-signed. Restart Live after rebuilding an already loaded external: Max caches loaded classes. Earlier numbered bundles in `build` are development iterations, not additional required dependencies.

Remove the probe devices from the scratch Set to remove the loaders from the Set; already scheduled diagnostics stop after two minutes, and the loaded external code remains cached until Live exits. No app-bundle rollback is required.

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

Compare native owner snapshots with `python3 scripts/analyze_probe.py`. See [runtime integration evidence](docs/native-pitch-integration-path.md#runtime-owner-proof-8-september-2026) for verified owner fields and remaining attachment work.
