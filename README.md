# Ableton Pitch Editor

Target experience: double-click an audio clip in Live, open its existing bottom Clip View, switch to a new Pitch mode, edit detected vocal notes, and apply audible changes. This is a local experimental integration intended for demonstration to Ableton. A floating editor or overlay alone does not satisfy the requested native integration.

## Current implementation status

**The experimental Pitch Editor tab edits notes inside native audio Clip View. Revision 24 processes the track audio during Live playback; clicking or dragging notes auditions them from memory, including during playback. No export, Apply, or render-file step is required.**

See [live audio behavior and limitations](docs/live-audio.md).

See [audio renderer build, usage and validation](docs/audio-renderer.md) and [the engine implementation plan](docs/audio-engine-plan.md).

Build with `python3 scripts/build_native.py`. In `build/Ableton Pitch Lab.app`, load `build/Native Pitch Editor.amxd` on the test audio track, keeping `pitchnative41.mxo` alongside it. Double-click a warped audio clip, then click **Pitch Editor** in its header. Left/right select notes, up/down transpose, and ⌘Z / ⇧⌘Z undo/redo while the pitch canvas has focus. The source file is analyzed automatically (mono/stereo, 8–48 kHz, at most 60 seconds).

The adapter creates `APlatformViewHost` children inside the existing native tab button and `LWarpedAudioTimelineEditor`. Live supplies actual `TPlatformViewContainer` surfaces for an AppKit toggle and pitch canvas. It does not create a floating window or position an unrelated NSView over the main app. The mode is local to this experimental adapter; Live's internal three-mode enum is unchanged. A Max device provides the loader and selected-clip file lookup.

Verified: tab activation; 18 segments from the selected vocal; note 1 changing +1 → 0 → +1 through edit/undo/redo; edits retained when toggling the pitch tab; canvas removed when leaving Clip View. Revision 24 additionally verified dragging note 2 to +2 semitones, successful in-memory audition startup, and nonzero pitch processing during repeated Live playback loops. See [the working native view](build/research/native-pitch-editor-working.jpg) and [implementation details](docs/native-tab-working.md).

Remaining: precise processing-boundary alignment, Session/unwarped playback support, synchronization with native horizontal zoom/scroll, detection quality, proper Pitch footer controls, host undo/Set persistence, and broader lifecycle tests. The canvas currently fits the entire source file; it must not be presented as aligned to arbitrary cropped/warped/zoomed clips. Leaving Clip View or changing clips currently discards the temporary edit model. The stock choir exposes octave errors and is not a vocal-quality benchmark.

The original app and both Live executables remain unchanged. The experimental copy contains the [resource-only native tab addition](docs/native-tab-resource.md); proprietary copies and generated artifacts stay in ignored `build/`.

The source waveform appears behind the pitch notes and stays aligned with the editor’s time zoom and pan.

The editor shows an Envelopes-style thin playback cursor. It follows Live’s Follow switch for paging through the pitch viewport. Manual navigation suspends following until playback restarts or Follow changes. Verified on track 3, including loop restart, stop, and Follow on/off.

### Detection validation

The [39-case detector benchmark](benchmarks/README.md) now measures pitch, voicing, octave errors and note matching. Revision 28 fixes fragmentation of the tested gradual slide while preserving the other fixture matches. This is synthetic evidence; real-vocal validation remains outstanding. Build revision 28 with `scripts/build_native.py`; a running older revision keeps its existing detector until reloaded.

### Playback cursor

Click empty space or the inner ruler to position playback. Dragging the ruler still pans; clicking notes selects/auditions them. Revision 31 maps source seconds through warp/crop/loop metadata to Live’s transport. While stopped it also sets the next playback start. Revision 41 snaps clicks before the playable clip start to that start (1.1.1 when the clip begins the track), with the cursor showing the resolved position. Verified in Live with existing edits retained after device reload.

### Edit retention

Revision 30 retains separate clip documents and writes local edit recovery data on commit. Switching views keeps undo history; reloading the adapter can restore note edits within the same Live session. This is not saved-Set persistence. See [scope and validation](docs/edit-retention.md). Earlier running revisions still hold only temporary edits.

### Region edges and removal

Drag a note’s left or right edge to expand or shorten its pitch region. Select a note and press Delete, or use **Remove Pitch Region** in its context menu. Audio remains in place; the removed region stops receiving a pitch edit. Regions cannot overlap, and each edge drag/removal is undoable. Revision 34 is loaded and verified in Live.

### Manual note correction

Revision 29 adds a note context menu: **Split Note Here** divides the note at the clicked time; **Join with Next Note** combines touching notes with matching pitch offsets. Splits preserve pitch edits and recompute each region’s detected center. Both actions support undo/redo and update live processing. Joining is disabled across gaps or differing pitch edits.

### Snap

The bottom-right **Snap** toggle controls vertical dragging: on snaps to semitone rows; off allows continuous pitch movement. It defaults on and remembers your preference. Shift-drag always provides slower cents adjustment. Toggling Snap never quantizes existing edits.

### Fine pitch

Shift-drag adjusts pitch in cents (one cent per vertical screen point). Option-Up/Down nudges one cent; normal dragging snaps the destination to exact semitone rows; Up/Down transposes in semitone steps. The footer shows the estimated destination note, deviation in cents, and total transposition. Changes feed live processing and audition with local undo/redo.

### Editing UX

Revision 25 uses direct vertical note dragging, a compact pitch readout, and an estimated contour that follows edited notes. Full navigation help lives in the tooltip. Opening Pitch selects Live’s Sample base view before attaching the canvas, removing unrelated envelope device/parameter controls. Returning to Envelopes restores its normal controls. Double-clicking a note no longer unexpectedly fits the viewport.

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

### Per-note gain

Select a note, then drag the small round Gain handle beneath it up/down. Shift-drag gives finer control; double-click resets to 0 dB. Range: −24 to +12 dB. Changes affect Live playback and note audition immediately, scale the displayed source waveform, and support local undo/redo and same-session recovery. Positive gain can exceed output headroom; this is manual gain, not normalization or limiting.

### Vibrato reduction (experimental)

Select a note and drag the round Vibrato handle above it downward to reduce fast pitch variation. 100% preserves the original; 0% requests maximum reduction. Shift-drag is finer; double-click resets to 100%. The estimated contour updates while dragging. Playback and audition now share the Rubber Band processor and correction curve, while audition still uses the Mac output independently of Live's effects.

Reduction keeps the estimated pitch center and local linear drift, and skips uncertain/unvoiced runs or runs shorter than 300 ms. This is a variation reducer, not a complete vibrato classifier: it can also affect fast ornamentation. 0% is a requested amount, not a promise of a perfectly flat audible result. Synthetic rendered tests at 4–8 Hz show approximately 35–60% depth reduction; real annotated vocal and listening validation remain necessary. Manual drift handles are available below; formant editing is available below.

### Start/end pitch drift (experimental)

The upper-left and upper-right handles adjust the beginning and end of the selected note in cents, with its midpoint anchored. Drag up to raise, down to lower; Shift-drag is finer, and double-click either handle resets that side to zero. The upper middle handle remains Vibrato. Drift is manual contour shaping, not automatic drift detection or a percentage-based correction control.

Each side supports ±200 cents and composes with pitch, vibrato and gain edits through the shared live/audition engine. Reliable voiced runs under 300 ms and uncertain/unvoiced sections are skipped, with 40 ms edge tapers. Changes update the estimated contour immediately and support local undo/recovery. Resize reinterprets drift relative to the new bounds; reset drift before splitting/joining, because those operations would change its midpoint/shape. Source audio is not rewritten.

### Formant tone (experimental)

Drag the selected note’s lower-right handle vertically to change its formant tone independently of note pitch. The range is −6 to +6 semitones; Shift-drag is finer and double-click restores neutral. Playback and audition update immediately, with local undo/redo and recovery. The waveform and pitch contour do not represent spectral tone changes.

The processor compensates existing transposition when applying formant shift. Synthetic spectral-envelope and periodicity tests pass at 44.1/48 kHz with both neutral and transposed notes. It remains an experimental tonal effect requiring real-vocal listening validation, especially at extremes.
