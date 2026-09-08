# Testing Patterns

- Run `python3 scripts/benchmark_detection.py --compare benchmarks/detection-baseline.json` for deterministic pitch/voicing/segmentation evidence across 39 synthetic cases. Keep the baseline immutable; read benchmarks/README.md for matching thresholds and missing-value semantics. Passing synthetic fixtures is not evidence of real-vocal accuracy.
- Slide fragmentation can be a segmentation failure despite accurate frame F0. Compare note matches and frame pitch separately; retain actual octave jumps/legato fixtures when changing continuity rules. Never flatten the contour simply to make note blocks look stable.

- `scripts/build_editor.py` also runs an AppKit context-menu integration test (`pitch_canvas_structure_test.mm`) without a visible window. It verifies split/join menu actions publish edits and structural undo clamps selection. This does not establish right-click event delivery inside Live; keep native UI verification distinct.

- `pitch_document_store_test.mm` exercises same-source clip isolation, session/source mismatch, split/fractional recovery and malformed JSON rejection using a private temporary directory. It is a store-level test, not a Live round-trip test. Adapter reload restores edit state but not serialized undo history.

- Region-edit verification should compare recovery JSON with the pre-test backup after undoing UI tests. Revision 34 verified exact restoration after Delete plus expanding the next region in Live, in addition to model/AppKit/stream tests.

- Gain migration UI verification compares the first five fields of schema-1/2 note rows, then checks the new gain field separately. `build_render.py` now links the core document into streaming tests to verify gain history/segmentation alongside DSP; do not drop that dependency.

- `build_render.py` runs `pitch-expression-audio-test`: independent positive zero crossings and sine/cosine depth estimates catch dynamic correction timing failures that static note-pitch tests miss. Keep both oracle and production-detector paths; the measured synthetic attenuation is not a real-vocal quality score.
- Recovery JSON can shift an NSNumber round-trip by a few binary ULPs. Compare note IDs exactly and numerical parameters within 1e-12 when verifying reload plus undo, rather than overwriting a valid user edit because textual/bitwise equality failed.

- Drift acoustic validation measures early/late pitch difference and retained vibrato separately. A flattened output alone is not success if vibrato was also removed; the 44.1/48 kHz shared-DSP test checks both, alongside independent endpoint/combined-curve model tests.
