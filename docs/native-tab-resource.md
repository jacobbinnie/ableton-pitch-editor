# Native Pitch Editor control — verified 2026-09-08

The experimental application displays **Sample / Envelopes / Pitch Editor**
inside Live's own bottom Clip View. This is a native `ButtonControlSimple`
created by Live's XML view loader. It is disabled and does not switch editors
or process audio yet. No overlay, runtime injection, or executable patch was
needed to demonstrate this control.

## Exact insertion point

`Contents/App-Resources/GUI.alp` contains `ClipContentHeader.xml`. Its
`ModeSwitchControl` has `ViewId=EditorViewModeSelector`,
`ConnectTo=EditorViewMode`, and `ShowWhen=ContentEditEnabled`. Insert a fixed-size native sibling after this selector and set the existing
row gap to zero. A `BorderedCellView` supplies the new button's full-height
outline; its inner `ButtonControlSimple` has no contrasting inset frame.

`scripts/prepare_tab.py` performs this change in **build/Ableton Pitch Lab.app
only**, assigning `ViewId=PitchEditorButton` and label `Pitch Editor`. The
original installed application remains unchanged. The replacement XML and
resource manifest are in ignored `build/research/`; do not distribute the
proprietary extracted resources or application copy.

## Reproduce

With the experimental copy closed, and from the project directory:

```sh
# Run the copy command only if the destination does not exist.
cp -cR '/Applications/Ableton Live 12 Trial.app' 'build/Ableton Pitch Lab.app'
python3 scripts/prepare_tab.py
open -n 'build/Ableton Pitch Lab.app'
```

The script verifies the exact executable fingerprint, decodes the archive,
locates the directory record for `ClipContentHeader.xml`, appends the new XML
before the directory, updates that record and the directory pointer, and
re-encodes it. All original payload bytes remain in place, and all other
directory bytes remain identical. Decode/encode round trips and XML parsing
are checked. The old XML payload remains unreferenced.

The copy launched successfully without re-signing or changing executable
bytes. This is an observation on this Mac, not a guarantee about distribution
or signature validation on other systems: the resource seal no longer matches
the modified archive. Revert by restoring the original `GUI.alp` into the
closed experimental copy, or use the untouched application in `/Applications`.

Both apps retain the same bundle identifier and share normal Live preferences.
Use the full app path for computer use. Concurrent instances trigger Live's
warning that crash recovery is unavailable; do not use this setup for valuable
Sets. The verification used a fresh Untitled scratch Set only.

## Verification evidence

Loaded stock `Vocal Choir Pure C4.wav` on audio track 3, then double-clicked the
clip. The native header displayed the new label after Envelopes, and the
accessibility tree reported:

```text
button (disabled) Description: Pitch Editor
ID: ClipDetailView.ClipContentHeader.PitchEditorButton
```

Evidence: `build/research/native-tab-verified.png` and
`build/research/native-tab-verified.ax.txt`. The UI still reports saving and
exporting deactivated. No license logic was changed. No Max probe was loaded
in this experimental instance during this verification.

## Binding the control to a real editor

The existing selector does not define its labels as XML children: its native
`ARemoteableEnum` supplies them. Static tracing identifies header property
`+0x178`, initialized at `0x103c7e55c` through `0x1015a609c`. Global label vectors
are `0x106f31338` (three MIDI entries) and `0x106f31350` (two audio entries).
Header refresh `0x103c7f210` selects the vector and calls `0x1015a5d14`.

The extra button is disabled because it has no connected native action/model.
The next step is to bind `PitchEditorButton` to our own native state and mount
our editor through the Clip View's lifecycle. The existing Max external is a
proven route for running the adapter in Live, but its internal callback ABI,
ownership and teardown still need runtime validation. Do not connect this
button to an unrelated existing command just to make it clickable.

If integrating into the existing `ModeSwitchControl` instead of the sibling
control, change the audio label list, availability filter, effective-mode
handling, mutual selection, and keyboard cycling together. Index 2 already
means MIDI expression; index 3 currently falls back to Sample. Merely appending
a label or changing a modulo constant is insufficient. See
`native-tab-trace.md` for the verified controller paths.

Pitch detection, draggable note blocks, audible rendering, undo, and clip
file replacement/persistence are remaining work, not demonstrated by this tab.

## Read-only decoder evidence

The loader at `0x102a29998` opens `.alp` resources; `0x102a2b04c` derives its
32-byte scramble table from the package basename. `0x101471510` applies the
position-dependent reversible transform. `0x102a09f6c` validates the decoded
`pl-a`/`a-lp` package magic. These addresses apply only to the fingerprinted
arm64 build; the script reads its table directly rather than redistributing
resource data.
