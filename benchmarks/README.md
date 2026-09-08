# Detection benchmark

Run `python3 scripts/benchmark_detection.py --compare benchmarks/detection-baseline.json`.
This compiles the production detector and generates deterministic waveforms in memory;
it does not export audio or replace the user's source. JSON goes to
`build/detection-benchmark.json`. The tracked baseline captures the detector before
the gradual-slide segmentation fix. Do not regenerate it when changing the detector.

The 39 cases cover 13 fixtures at 22.05, 44.1 and 48 kHz: steady tones, strong
harmonics, missing fundamentals, vibrato, legato transitions, true octave jumps,
repeated syllables with quiet gaps, short notes, continuous slides, low/high voices,
noise and silence. These are synthetic signals, not a representative vocal corpus.
In particular, repeated syllables without amplitude gaps remain untested.

Metrics:

- Frame pitch error: absolute cents error against instantaneous generated F0,
  including the known vibrato/slide curve. The 95th percentile includes only frames
  where truth and detection are voiced, so always inspect voicing counts too.
- Voicing: truth, detected and intersection frame counts. Precision is intersection
  divided by detected count; recall is intersection divided by truth count.
- Octave errors: jointly voiced frames within 50 cents of a one/two-octave error.
- Note matching: chronological truth notes matched one-to-one to an unused detected
  region within 50 ms onset, 80 ms offset and 50 cents of the reference center.
  The slide is intentionally labelled one note, centered at its midpoint pitch.
- Boundary errors are for matched notes only. A `-1` percentile means no samples,
  not zero error. Counts expose fragmentation and missed regions.

Initial finding: the two-semitone slide became three notes at 22.05/44.1 kHz and
two at 48 kHz, despite frame pitch p95 below 1.6 cents. Requiring local pitch-change
evidence before a split produces one matched note at every tested rate, without
reducing note matches in the other fixtures. The original contour is preserved.

This does **not** prove real-vocal accuracy, one-cent perceptual accuracy, or robust
octave-error correction. Add permission-cleared, independently annotated dry vocals
and difficult real octave failures before tuning the pitch tracker. Never treat
agreement with the same detector as ground truth.
