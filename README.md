# Ableton Pitch Editor

An experimental vocal pitch editor in Live’s audio Clip View. Drag detected notes to change pitch and hear edits during playback, without exporting.

[Watch the demo](https://x.com/jacobbinnie/status/2102091733114745280)

Pitch snapping, drag audition, per-note gain/vibrato/drift/formants, region editing, waveform display, zoom and local undo/redo are included.

## Requirements

- Apple Silicon Mac, Python 3.12+, Git and Xcode Command Line Tools (`xcode-select --install`).
- Max for Live available in your Live installation.
- One of these exact Trial builds:

| Live | Build |
| --- | --- |
| 12.4.5 Trial | `2026-08-19_225ce5e356` |
| 12.4.6 Trial | `2026-09-10_0de5c8fa9a` |

Setup detects the installed build and checks its executable fingerprint. Other builds and paid editions are not yet validated. The 12.4.6 tab has been tested locally; broader audio and lifecycle testing is still needed.

## Install

Close Live. These commands create a separate **Ableton Pitch Lab.app** using your installed Live app. The normal setup does not patch the app in `/Applications`.

```sh
git clone https://github.com/jacobbinnie/ableton-pitch-editor.git
cd ableton-pitch-editor
python3 scripts/setup.py --check

mkdir -p vendor build
git clone https://github.com/Cycling74/max-sdk-base.git vendor/max-sdk-base
git -C vendor/max-sdk-base checkout --detach c03a2922a2a8ff149165a1e2ea134e9321d6e202
SSL_CERT_FILE=/etc/ssl/cert.pem python3 scripts/fetch_rubberband.py

python3 scripts/setup.py
open 'build/Ableton Pitch Lab.app'
```

If multiple Live apps are installed, add `--live "/path/to/Live.app"` to both setup commands. Start with an unmodified installation; setup rejects an already-patched source.

## Use

1. Open **Ableton Pitch Lab.app**, then create a test Set.
2. Add your vocal to an audio track in **Arrangement View** and enable **Warp**.
3. Drag `build/Native Pitch Editor.amxd` onto the **same track**. Keep `build/pitchnative42.mxo` beside it.
4. Double-click the audio clip and select **Pitch Editor** beside Sample and Envelopes.
5. Drag notes to edit/audition. Shift-drag fine-tunes; ⌘Z / ⇧⌘Z undo/redo while the editor has focus.

Keep the device on the track. Supported audio: mono/stereo, 8–48 kHz, up to 60 seconds. Session clips and unwarped playback are unsupported.

## If the tab is missing

- **No tab:** check you opened the patched app. Installing the device alone does not add the tab.
- **Tab is disabled:** load the matching `.amxd` and `.mxo` on the vocal track.
- **Moved the repo:** close Live and rebuild with `python3 scripts/build_native.py`.
- **Manually patched the installed Trial app:** rebuild with `python3 scripts/build_native.py --live-app '/Applications/Ableton Live 12 Trial.app'`, then open that app and load the rebuilt device. This command targets an existing patch; it does not install the tab resource. Default setup uses the separate copy.

## Limitations

**Edits are not saved in Live Sets or reliably restored after restarting Live.** Recovery is limited to the same Live session. The editor uses private Live interfaces, so Live updates may require a new compatibility profile. The experimental copy shares Live’s preferences and authorization; demo mode still disables saving/exporting.

[Audio behavior](docs/live-audio.md) · [Edit recovery](docs/edit-retention.md) · [Native integration](docs/native-tab-working.md)

Unofficial and not affiliated with Ableton. No project-wide license has been selected; Rubber Band and the Max SDK retain their own licenses. Review these before redistribution. Ableton app files and test recordings are not included.
