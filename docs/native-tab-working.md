> Current audio workflow: [revision 24 streams edits during Live playback and auditions drags in memory](live-audio.md). Earlier export controls described below are superseded.

# Experimental native Pitch Editor tab

## Verified implementation

`src/pitch_native.mm` is loaded by `Native Pitch Editor.amxd` / `pitchnative19.mxo`.
It resolves the resource tab and warped audio editor through their AX proxies,
then mounts AppKit views through native `APlatformViewHost` children. The tab's
original disabled native control still exists underneath its hosted toggle;
the toggle supplies the experimental action and accessibility control.

This is an internal native-view-host integration, not a new registered Live
content enum. It is deliberately restricted to the hashed local 12.4.5 build
and the experimental copy path. Private calls execute only on the main thread.

- Host factory: `0x10179eb40`, indirect `TPtr` return in arm64 x8. The small
  assembly shim preserves this calling convention.
- Host vtable: `0x10671d9c8` (file VA, before ASLR).
- Parent add-child: vtable +0x268, verified target `0x1017d1fb8`.
- Parent remove-child: +0x270, target `0x1017d23a8`.
- Size setter: `0x1017cefbc`, width/height packed as two 32-bit integers.
- Factory reference release: `0x10179ea38`, taking the address of the pointer.
- Host +0x170 holds the Objective-C `TPlatformViewContainer`. Its StrongRef
  helper resolves to Objective-C retain/autorelease, not another C++ wrapper.

The separate 20-second `Pitch Mount Test.amxd` verified creation, native parent
attachment, display and detachment before installing the pitch adapter. Its
code is in `pitch_mount.mm`; it is not required for normal use.

## Interaction and data flow

The native-hosted toggle opens a second host inside the warped audio editor.
The existing beat ruler and loop brace remain outside the mounted canvas.
A qelem requests `live_set view detail_clip` and its `file_path`; AVAudioFile
decoding and pitch analysis run off the UI thread. Generation checks reject
analysis results after a tab/clip change. The canvas owns the local edit model.

An app-local key monitor routes ⌘Z/⇧⌘Z to the pitch model only while its canvas
is the first responder. This is necessary because Live otherwise handles the
shortcut before AppKit `keyDown:` and may undo insertion of the loader itself.
An app-local pointer monitor closes pitch mode when the neighboring header
selectors are clicked. Both pointer transitions were verified with revision 5.

Runtime verification on the stock vocal:

- Pitch toggle became accessible as `PitchEditor.Toggle` and opened
  `PitchEditor.Notes` within the audio editor.
- Selected file was analyzed into 18 segments.
- Keyboard edit, undo and redo produced +1 / 0 / +1 semitones for note 1,
  with its 0.04–0.29 second boundaries unchanged.
- Toggling the Pitch button off/on preserved that edit.
- Switching to Device View detached the canvas.
- Portable core tests passed after the embedded-canvas changes.

The native drag test could not execute: coordinate actions returned
`noWindowsAvailable` while AX actions continued to work. Do not describe native
dragging as verified. Screenshot: `build/research/native-pitch-editor-working.jpg`.

## Tab appearance (revision 10)

Sample and Envelopes are always drawn by Live. The temporary AppKit label
replacement from revisions 5–7 is removed. While Pitch is active, the native
selector's selected background/text color IDs are set to its unselected color
IDs using verified setters, then restored on exit. Font and layout properties
are untouched. Pitch's AppKit label keeps its 10-point font and text color in
both states; only its background changes.

Verified property-loader fields: selected background +0x32c, unselected
background +0x330, selected text +0x334, unselected text +0x338. Setters
0x10358ca48 and 0x10358ca78 take (object, uint32 color ID) and invalidate drawing.
The selector has a retained TPtr reference while overridden, using the +8
refcount increment proven in its factory and release helper 0x10358bc80.
All operations remain restricted to the fingerprinted build and main thread.

Do not mount an empty or hidden APlatformViewHost over this selector: the native
renderer still excludes that rectangle, blanking the original labels. Mouse
hit bounds instead derive from native child/parent rectangles and the button's
AX screen frame. Pitch → Sample and Pitch → Envelopes were tested, along with
reopening Pitch. Screenshot: build/research/tab10-on.jpg.

Native selector colors follow Live's theme IDs. Pitch's background still targets
Default Dark Neutral Medium; arbitrary theme/zoom synchronization is pending.

## Remaining behavior

There is no resynthesis or audio replacement, no host undo or Set persistence,
and no crop/warp/horizontal viewport synchronization. The canvas fits the full
source duration; matching the initial full-clip ruler does not prove correct
mapping after zooming or warping. Vertical pitch labels share space with notes.
Envelope footer controls remain visible if Pitch was opened from Envelopes.
Edits survive Pitch off/on but are discarded on a clip or Device View switch.
Detection on this choir sample has octave jumps. Broader native lifecycle,
multiple-instance, pointer interaction and unload testing remain necessary.

The public Live API exposes clip `file_path` as read-only, so audible application
needs a separately designed render/import path rather than a property write.
Source: [Cycling '74 Clip documentation](https://docs.cycling74.com/apiref/lom/clip/).

## Canvas navigation (revision 14)

The canvas now owns a bounded source-time/pitch viewport. It supports scroll
panning, Command-scroll and pinch for pointer-anchored time zoom, Option-scroll
for pitch zoom, Option-drag or seconds-ruler drag for panning, Shift-arrows for
panning, +/- for time zoom (Option +/- for pitch zoom), and F or Fit to reset.
A fixed pitch-label gutter and adaptive seconds ruler describe the viewport.
Keyboard note selection reveals offscreen notes; edits still use the same model.

This supersedes the full-source-only viewport limitation above. The outer Live
beat ruler/loop brace still belongs to Live and is NOT synchronized to this
source-seconds viewport. No warp/crop mapping or audio rendering is added.

Verified in Live: time zoom 0–5.18 → 1.44–3.74 seconds, ruler drag to 1.59–3.89,
F restoring 0–5.18, vertical zoom 23 → 15.3 rows, vertical scrolling,
Shift-arrow horizontal panning, and +1 / undo to 0 after zooming. Horizontal
wheel, pinch and modifier-wheel hardware gestures remain unverified by the UI
tool; their handlers are implemented. Portable viewport tests cover zoom anchor
invariance, pan bounds, short clips, zoom limits, and reset; core tests pass.

## Playback cursor (revision 17)

The Max loader polls selected-clip and song transport data at 30 Hz only while
Pitch is open. The canvas draws a thin playhead and triangle using the same
source-time transform as the notes and highlights the note it crosses. Stopping
freezes a dimmed cursor at its last valid position. It does not auto-scroll.

For this Arrangement clip, is_playing/playing_position stayed zero during
actual audio playback. Warped Arrangement playback therefore uses song beat
position relative to clip start_time, plus start_marker, with loop wrapping.
Playback is gated by song transport, Arrangement start/end and clip mute.
Session clips use their reported playing_position/is_playing. Beat positions
are interpolated through warp_markers into source seconds (including the hidden
final marker); missing/invalid maps suppress the cursor. Unwarped Arrangement
playback and Session playback are not runtime-verified, nor are track mute/solo
or Session override states reflected in Arrangement gating.

Verified track 3 at source positions 0.986 → 1.966 → 2.996 → 3.976 seconds,
loop restart, cropped start_marker=2 beats, a zoomed viewport during playback,
and Stop freezing the cursor at 3.44 seconds. Screenshot:
build/research/pitch-playhead-playing.jpg. Portable mapping tests cover nonlinear
segments, exact marker boundaries, extrapolation and invalid/missing markers.

Reference: https://docs.cycling74.com/apiref/lom/clip/ (playing_position,
warp_markers, start_time and loop properties). Polling currently rereads warp
metadata each frame; reducing metadata refresh frequency is a future optimization.

## Envelopes reference behavior (revision 18)

Compared Envelopes during stopped and playing states on the same clip. Pitch
now draws a plain neutral-gray line without the triangular cap, bright note
outline, or stopped-state color change from revision 17. It remains our canvas
cursor, not Live's own native drawing primitive.

Song.View.follow_song is polled along with transport data. When enabled, the
pitch viewport pages when playback leaves its visible range; with Follow off,
the viewport remains stationary across playback and loop restarts. Manual
pan/zoom suspends local following until playback restarts or Follow toggles.
This models Follow behavior but does not synchronize the pitch seconds viewport
with Live's beat ruler, nor reproduce its optional continuous-scroll preference.

Verified Follow on moved the viewport to 0.63–2.93 seconds on restart. With
Follow off, 2.74–5.05 remained fixed while playback wrapped to 1.00 second.
Transport was stopped and the original Follow-on setting restored afterward.
Reference screenshots: build/research/envelope-cursor-playing.jpg,
envelope-cursor-stopped.jpg, and pitch-envelope-style-playhead.jpg.
API reference: https://docs.cycling74.com/apiref/lom/song_view/#follow_song .

## Envelopes palette (revision 19)

Canvas background, ruler/gutter and text now use the neutral gray roles from
Default Dark Neutral Medium, replacing the blue-gray custom palette. Subtle
semitone shading remains for pitch readability; purple note blocks and selected
note colors are preserved. Verified visually in the experimental app. Screenshot:
build/research/pitch-envelope-palette.jpg. Other themes do not auto-sync yet.

## Background waveform (revision 20)

The original analysis-channel waveform is drawn behind note blocks and contour,
using offline 32-sample min/max peaks. Visible peaks are aggregated per display
column, preserving transients without decoding audio on the UI thread. The dark
neutral silhouette uses source amplitude and the same seconds viewport as notes;
pitch scrolling does not move its center line. Stereo uses the analysis channel.

Verified in Live with the track 3 recording: full 0–5.18s view, zoom and pan to
1.90–4.20s, then Fit. Screenshot: build/research/pitch-waveform.jpg.
Core peak boundary, impulse, tail and silence tests pass, along with existing
core/viewport/playback checks and both native and standalone builds.

## Audio render controls (revision 22)

Committed note edits now render through a serial background session. The footer
adds Original/Edited audition and Show File, with waiting/rendering/ready/error
feedback. Undo invalidates old render access and redo regenerates it. Source-time
audition requires Live stopped and is separate from Live's device chain/warp.
See audio-renderer.md for verified behavior and remaining Apply/persistence work.
Screenshot: build/research/pitch-native-audio-rendering.jpg.
