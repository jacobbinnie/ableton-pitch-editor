# Pitch editor core — first implementation

The C++ core consumes normalized mono PCM and returns source-time pitch frames
and note segments. It has no Ableton addresses, GUI dependencies, or host APIs.
The `Document` model stores pitch offsets separately from detected pitches and
provides local undo/redo. `PitchCanvas` draws and edits that model in an AppKit
development harness. Neither is registered as a Live editor yet.

## Detection

The detector uses a squared-difference / cumulative-mean-normalized-difference
approach with a first-trough threshold and parabolic lag refinement, based on
[de Cheveigné and Kawahara's YIN paper](https://doi.org/10.1121/1.1458024).
This is our initial implementation, not the authors' code or a reproduction of
the full paper's evaluated system. Pitch search is 65–1100 Hz with a 10 ms hop.
DC-adjusted RMS gating and a periodicity threshold reject unvoiced frames.
Confidence is a periodicity score, not a calibrated probability.

Segmentation preserves source seconds, rejects runs shorter than 60 ms, and
requires three consecutive frames beyond 0.8 semitones from an onset anchor
before splitting a voiced run. The original contour stays available for visual
assessment. Smoothing, breath-gap bridging, repeated-note onset detection,
manual splitting/merging, and robust handling of portamento remain future work.
Leading/trailing analysis-window margins are not extrapolated to clip edges.

## Execution and editing

- Decode and detection run on a background queue. No detector work runs in an
  audio callback. Direct YIN is intentionally simple and not yet optimized for
  long recordings or realtime analysis.
- The UI harness accepts clips up to 60 seconds and 48 kHz; it bounds channels to
  mono/stereo and chooses the channel with higher AC energy. This avoids stereo
  phase cancellation but does not separate vocals from accompaniment.
- Pitch edits are absolute offsets in [-24, 24] semitones from original pitch.
  Time boundaries and source samples are unchanged. A gesture commits one edit;
  a new edit after undo clears the redo branch.
- History is in memory only. Loading another file replaces it. There is no audio
  playback, resynthesis, file export, sidecar persistence, or Live Set state yet.
- The display fits the clip's initial pitch range. Zoom, scrolling and automatic
  range expansion for large transpositions remain outstanding.

## Verification

`python3 scripts/build_editor.py` compiles with warnings treated as errors and
runs tests for harmonic-rich tones at three sample rates, pitch accuracy,
DC/noise rejection, vibrato, silence-separated and legato notes, preserved timing,
undo/redo branching, and invalid edit/audio input. These synthetic checks do not
establish accuracy on real sung vocals; annotated vocal recordings are needed.

The development app was exercised through its file picker with a generated
six-note phrase. It displayed six notes and exposed the selected note through
accessibility. Keyboard transposition and Command-Z/Shift-Command-Z produced
+1/0/+1 semitone states with the same 0.01–0.50 second boundaries. Visual review
confirmed the shifted block and unchanged original contour. Mouse dragging is
implemented but has not yet been exercised by the automated UI check.

## Native integration boundary

An AppKit canvas cannot simply be attached to Live's virtual accessibility
nodes. This harness validates the detector/model and interaction design only.
The native lifecycle investigation remains in `native-tab-trace.md`: establish
a verified owner, activation callback, layout and teardown boundary before
attempting to connect this core to Live's actual Pitch Editor control.
