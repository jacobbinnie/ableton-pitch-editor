> Current audio workflow: [revision 24 streams edits during Live playback and auditions drags in memory](live-audio.md). Earlier export controls described below are superseded.

# First audio renderer

Implemented 2026-09-08 as a CLI and portable C++ worker API. This is the first
engine slice. Revision 22 connects it to the native Pitch Editor with background rendering and source-time audition; it does not yet replace Live clip playback.

## Build and use

Requires macOS command-line developer tools and Python 3.12+ (safe tar extraction).

```sh
python3 scripts/fetch_rubberband.py
python3 scripts/build_render.py
mkdir -p build/renders
build/pitch-render fixtures/local/track-3-vocal-pitch-demo.wav build/renders/track-3-original.wav > build/renders/original.json
build/pitch-render fixtures/local/track-3-vocal-pitch-demo.wav build/renders/track-3-note-2-up-2.wav 2 2 > build/renders/up-2.json
build/pitch-render fixtures/local/track-3-vocal-pitch-demo.wav build/renders/track-3-note-2-down-2.wav 2 -2 > build/renders/down-2.json
build/pitch-render build/renders/track-3-note-2-up-2.wav build/renders/reanalysis-up-2.wav > build/renders/reanalysis-up-2.json
python3 scripts/verify_render.py
```

Output paths must not already exist. Choose new names for subsequent experiments.
CLI note numbers are one-based. Omitting the note and shift arguments produces a
PCM-exact bypass. JSON stdout reports input detection, edits in source sample
frames, processor settings, timing, peak level and dimensions. The explicit
reanalysis command detects output pitches; normal render reports describe input
notes. Output is 32-bit float WAV, not necessarily the source container/bit depth.

## Implementation

`AudioAsset` retains all PCM channels; analysis chooses the strongest AC-energy
channel. `RenderPlan` is a sorted non-overlapping list of sample-frame regions
with fractional semitone offsets and smooth 20 ms edge ramps. RubberBandRenderer
implements an independent Renderer interface and processes a continuous phrase.
Its immutable input contract and separate result allow a future worker queue;
the CLI currently runs synchronously outside Live.

The local dependency is unmodified Rubber Band 4.0.0, verified against a pinned
archive SHA256. It is built using its single translation unit and Apple's
Accelerate FFT. R3 uses RealTime mode on the command-line worker, short windows,
formant preservation, linked channels, and high-consistency pitch mode.

The renderer pads startup, drains all available output and trims startup delay
and excess tail to retain source frame count. Pitch scheduling uses the drained
output clock, excluding startup delay. Scheduling from incoming PCM with an
added getStartDelay shifted corrections early in the first implementation;
the default R3 window also smeared corrections farther into neighboring regions.
The current behavior is tested for this pinned configuration, not guaranteed
sample-exact control timing for every backend, pitch or sample rate.

No-edit bypass avoids processing entirely. Edited renders currently process the
whole phrase: unedited regions keep their pitch, but are not guaranteed PCM
identity. There is no explicit breath/sibilant protection yet. No limiter or
normalization hides output overs; peak is reported and float WAV preserves them.
A temporary file is closed before rename, and existing output is refused.

## Measurements and verification

- Synthetic 220 Hz cases at 44.1/48 kHz, ±2 and ±3 semitones: independent
  autocorrelation within 0.12 semitones of target in stable edited sections.
- Region scheduling checked on both sides of edits, outside transition windows;
  diagnostic sweeps show finite window settling, not instantaneous boundaries.
- Test transients outside edited regions remain within 5 ms; output frame count
  is exact. This does not establish preservation of edited consonants.
- Identical stereo inputs stay matched; sample steps remain below the synthetic
  discontinuity threshold. Empty edits bypass exactly; 64-frame edited silence
  retains length and silence. Overlapping edits and NaN shifts are rejected.
- Independent WAV parser checks source hash, PCM identity for bypass, dimensions,
  finite/unclipped fixture output and overwrite refusal.
- Track 3 note 2 (about 1.22–1.57 seconds) measured MIDI 57.923 before editing and
  59.95 after a +2 edit. Its detector boundaries moved slightly after processing.
- 228,352 frames at 44.1 kHz (5.178 s) rendered in approximately 66 ms on this Mac;
  excludes decoding, pitch detection and file writing. This is one measurement,
  not a latency guarantee. Existing core, viewport and playback tests pass.

Listening quality, formant fidelity and stereo-image preservation on real vocals
remain unverified. Compare the A/B files before selecting this as the final
backend. The fixture is a recorded choir sample, not a diverse dry-vocal corpus.

## Dependency/distribution

Rubber Band is GPL v2-or-later, with a commercial licensing alternative. Its
source and linked binaries stay in ignored vendor/ and build/ for local testing.
This work does not choose a project-wide license or publish a linked binary.
Resolve distribution licensing before sharing the integrated dependency/build.
https://breakfastquay.com/rubberband/license.html

Next: validate listening quality, then persistent documents/render job handling
and the Live sample-replacement experiment described in audio-engine-plan.md.

## Native integration (revision 22)

Native builds now include the renderer and PitchRenderSession. The original PCM
is retained after analysis. A committed drag, arrow-key transpose or undo/redo
notifies the session, clears the obsolete render immediately, and schedules work
after a 200 ms debounce. A serial worker owns processing/file I/O; monotonic
revision tokens suppress superseded jobs and prevent stale publication. An
already-running DSP call finishes, then its result is discarded if obsolete.

The footer provides Original, Edited and Show File. Audition uses AVAudioPlayer
in source time through the default macOS output, bypassing Live's device chain,
warp and transport; stop Live first. Clicking the same audition button stops it,
clicking the other switches sources. Starting Live, editing or closing Pitch
stops audition. The visible cursor still represents Live transport, not audition.

Complete WAVs and per-render JSON metadata are stored in ignored
build/renders/native. Show File reveals the current result for manual use; it
does not apply it. Published files remain available after later edits. Metadata
records frame regions and shifts but is not a restorable Live Set edit document.
Changing clips, leaving Clip View or reloading the adapter still loses local
edit history. Source persistence and automated Apply remain separate work.

Verified in Live: note 2 +2, Ready status, audition play acknowledgement, undo
to zero disabling Edited/Show File, redo to +2 and matching final render metadata.
Coordinator tests verify debouncing to the latest edit, immediate invalidation
on undo and suppression after session teardown. Subjective audio quality and
all transport interruption cases are not established by these checks.
