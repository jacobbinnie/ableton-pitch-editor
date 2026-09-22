# Ableton Pitch Editor

An experimental vocal pitch editor inside Ableton Live’s audio Clip View. Edit detected notes over the waveform and hear changes during playback, without exporting audio.

[Watch the demo on X](https://x.com/jacobbinnie/status/2102091733114745280)

## Features

- Drag notes to change pitch, with optional semitone snapping and fine adjustment.
- Audition notes when clicking or dragging, including during playback.
- Adjust per-note gain, vibrato, pitch drift and formants.
- Resize, split, join and remove pitch regions, subject to edit compatibility.
- Zoom, pan and click to position playback, with a moving playhead.
- Local undo/redo and edit recovery within the same Live session.

## Compatibility

**This is a developer prototype, not a drop-in device for every Live version.** The native tab uses private Live interfaces and a modified resource in a separate app copy.

- **Validated target:** Apple Silicon Mac, Live **12.4.5 Trial**, build `2026-08-19_225ce5e356`. Setup checks the exact executable fingerprint; other editions are not automatically compatible.
- **Paid Suite / Standard:** not yet validated. Matching the version number alone is insufficient; a different executable is rejected by the fingerprint check. Supporting another edition requires validating its private interfaces, not just changing the app path. The integration does not inherently require a trial license.
- **Live 12.4.6 and other builds:** unsupported until their private interfaces are revalidated. Do not bypass the fingerprint check. Updating Live may break the integration.
- **Required:** Max for Live availability, Python 3.12+ and Xcode Command Line Tools (`xcode-select --install`).
- **Audio:** warped Arrangement clips on the device’s track; mono/stereo, 8–48 kHz, up to 60 seconds. Session View and unwarped playback are not supported.

## Build and run

These steps apply only to the exact supported build installed at `/Applications/Ableton Live 12 Trial.app`. Close Live first and use a disposable test Set.

```sh
git clone https://github.com/jacobbinnie/ableton-pitch-editor.git
cd ableton-pitch-editor

mkdir -p vendor build
git clone https://github.com/Cycling74/max-sdk-base.git vendor/max-sdk-base
git -C vendor/max-sdk-base checkout --detach c03a2922a2a8ff149165a1e2ea134e9321d6e202
python3 scripts/fetch_rubberband.py

# First setup only: create the separate experimental app copy.
test -e 'build/Ableton Pitch Lab.app' || \
  cp -cR '/Applications/Ableton Live 12 Trial.app' 'build/Ableton Pitch Lab.app'
python3 scripts/prepare_tab.py
python3 scripts/build_native.py
open 'build/Ableton Pitch Lab.app'
```

1. Add a vocal clip to an audio track in **Arrangement View** and enable **Warp**.
2. Drag `build/Native Pitch Editor.amxd` onto that track. Keep `pitchnative42.mxo` beside the device file.
3. Double-click the audio clip, then select **Pitch Editor** in the bottom panel.
4. Drag notes to edit or audition. Shift-drag fine-tunes pitch; ⌘Z / ⇧⌘Z undo/redo while the editor has focus.

Keep the device on the track. To reopen the editor, select an audio clip and return to **Pitch Editor**. After moving the project folder, rebuild the native adapter and restart the experimental app because compiled paths are location-specific.

## Current limitations

Edits are **not saved in Live Sets or reliably restored after restarting Live**. Pitch detection, audio quality and tab lifecycle still need broader testing. The editor’s seconds ruler is independent of Live’s native beat zoom. The original installed Live app is not modified; the experimental copy shares Live’s preferences.

For an unsupported Live version, you can run the standalone development editor instead. It does not add a tab to Live:

```sh
python3 scripts/build_editor.py
open 'build/Pitch Editor Lab.app'
```

## More information

[Audio behavior](docs/live-audio.md) · [Edit recovery](docs/edit-retention.md) · [Detection tests](benchmarks/README.md) · [Native integration](docs/native-tab-working.md)

Unofficial experiment, not affiliated with Ableton. No project-wide license has been selected. Rubber Band and the Max SDK retain their own licenses; review those before redistributing a build. Ableton app copies, generated resources and test recordings are not included in the repository.
