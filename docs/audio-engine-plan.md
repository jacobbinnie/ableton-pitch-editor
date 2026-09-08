# Current roadmap — updated after revision 27

The user has replaced the export/apply workflow with immediate Live playback and click/drag audition, including during transport playback. The historical proposal below is retained as design context; its export UI, Apply/Revert milestone and immediate-next CLI instructions are superseded.

Implemented prototype: native note canvas, continuous track processing, in-memory note audition, semitone and cents editing, local undo/redo. See [current behavior and verified limitations](live-audio.md).

Next slices, in order:

1. Separate edit-document lifetime from the canvas and establish clip identity, so switching clips cannot discard or misapply edits. Persistence must store edit data, not require audio export.
2. Add manual split/merge and multi-note selection with grouped undo, allowing correction of detection mistakes.
3. Add pitch-center correction, then independently validated drift/vibrato controls. Expose only functioning controls.
4. Tighten processing-boundary/seek/loop timing, measure end-to-end host latency compensation, and support broader clip/track/rate configurations.
5. Validate vocal quality using dry solo recordings, including breaths, repeated notes, slides and vibrato.

## Detection work in progress

Revision 30 adds shared document ownership and same-session local recovery; see [scope and unverified host round trip](edit-retention.md).

First slice completed: deterministic 39-case benchmark and a measured gradual-slide segmentation fix (revision 28). See [metrics and limitations](../benchmarks/README.md). Revision 29 adds manual split and adjacent equal-offset join, with structural undo and split-invariant streaming curves. Real-vocal annotations, octave-error handling, arbitrary multi-selection, and drift/vibrato controls remain pending. Do not describe the synthetic benchmark as a finished vocal accuracy gate.

## Historical proposal

# Audio engine implementation plan

Planning baseline: 2026-09-08. Proposed work, not implemented or a claim of Melodyne-quality processing.

## Outcome and initial scope

Edit a dry, isolated monophonic vocal in the existing native Pitch Editor, hear a corrected render, and use it in the selected Live clip. Preserve the original recording and make every edit reversible. Start with pitch-only changes at unchanged duration; polyphonic separation, harmonies, and independent timing edits are later projects.

Current source provides a basic YIN-like detector, immutable detected contours, note offsets with local undo, waveform, navigation and a display playhead. No resynthesis, audio preview, persistent edit document, or automatic source replacement exists. The historical pitch-engine.md describes the original harness; native-tab-working.md is the current integration record.

## Architecture

SourceAsset (content hash, sample rate, all PCM channels, frame count)
→ Analysis (F0/confidence/voicing, waveform, onset candidates)
→ EditDocument (stable note IDs, manual boundaries and correction parameters)
→ RenderPlan (continuous pitch ratio, formant/gain curves, later time mapping)
→ Renderer backend (worker thread)
→ immutable RenderAsset (PCM/WAV, source hash, edit revision)
→ preview / Live apply adapter.

Keep the C++ engine independent of AppKit, Max and private Live addresses. Analysis may use the strongest channel; rendering must preserve all source channels with linked processing. Store source positions as sample frames, with explicit conversions to seconds and Live beat positions. Do not derive audio scheduling from the current 30 Hz UI playhead.

A document belongs to a clip editing session, not its NSView. Different clips sharing one source must have independent edits. Serialize a versioned sidecar with source hash, stable note IDs, manual segmentation, edit parameters and engine configuration. Cache renders by source hash + edit revision + backend/version/settings. Cache files are disposable; originals and edit documents are not. Host Set persistence is a separate integration milestone.

## Processing backend decision

| Candidate | Value | Main uncertainty | Plan |
| --- | --- | --- | --- |
| Rubber Band R3 | C++ pitch/time processing, formant preservation and linked channels | Audible quality of changing vocal correction, boundary timing, CPU | First benchmark and renderer adapter |
| WORLD | Explicit F0, spectral envelope and aperiodicity analysis/synthesis | Resynthesis coloration on singing, breath/transient quality and stereo handling | Optional independent quality comparator |
| élastique Pro SDK | Commercial time/pitch/formant processing | Evaluation access, licensing and actual comparative quality | Evaluate if first candidate misses quality gate |
| Custom PSOLA / source-filter / phase-vocoder hybrid | Full control of vocal-specific behavior | Substantial DSP research, pitch-mark errors and unvoiced transitions | Defer until benchmark identifies a specific unmet need |

Rubber Band is GPL v2-or-later with a separate commercial licensing route. Decide repository/distribution licensing before publishing a linked dependency or binary; do not infer that a public GitHub repository is already GPL. WORLD lists a modified BSD license; inspect pinned dependency licenses before integration. No dependency is added by this plan.

Important Rubber Band API distinction: Offline mode fixes pitch ratio after processing/study begins. For a continuously varying correction curve, evaluate ProcessRealTime mode running on a background worker. This does not mean live-input processing. Own process/setPitchScale calls on one worker, handle available/retrieve output counts, start pad/delay, schedule ratio changes with documented delay compensation, drain the tail and enforce intended output duration. Verify timing with impulses and pitch transitions rather than trusting nominal block boundaries.

Avoid rendering each note as an isolated hard-cut file. Render a continuous phrase with context and smoothly scheduled correction. Later incremental renders need measured guard regions and phase-aware seams; full phrase renders first.

## Musical edit model

Treat note blocks as editable regions over a continuous vocal contour, not MIDI synthesis events.

1. Semitone transpose plus cents adjustment; preserve the singer's contour by default.
2. Pitch-center correction amount toward a chosen note or scale; optional snap, never silently force a scale.
3. Manual note split/merge and boundary correction; detection errors must be repairable before advanced controls.
4. Pitch drift and vibrato depth as separate controls, followed by transition shaping.
5. Independent formant shift and per-note gain.
6. Timing moves/stretch through a monotonic source-to-output map, with consonant anchors and explicit interaction with Live warp.

A proposed log-pitch decomposition is p(t) = center + slowDrift(t) + vibratoResidual(t). Target = editedCenter + driftAmount*slowDrift + vibratoAmount*vibratoResidual. Convert target-minus-original MIDI pitch to a ratio with 2^(delta/12). Unity controls must reconstruct the original contour. Drift/vibrato separation is an algorithm to validate, not an exact physical decomposition; preserve portamento and do not smooth across unrelated notes. Blend correction around musical boundaries with configurable transition behavior.

F0 is undefined in unvoiced audio. Breath/sibilant protection needs a smooth voicing mask and backend evaluation; simply setting ratio to one is not guaranteed to preserve noise untouched through a stateful processor. Exact no-edit output should bypass processing. For pitch-only renders, copy untouched source outside processed regions plus guard/crossfade margins; test seams and avoid phase cancellation. Large shifts are creative effects, not promised transparent correction.

Detector improvements: octave-error correction with temporal context, improved voiced/unvoiced classification, repeated-note onset evidence, confidence display and editable boundaries. Benchmark the current detector before selecting a replacement. Keep breaths and consonants represented even when they have no note label.

## Hearing edits in Ableton

First prove render quality independently, then apply a new file in the existing clip. Preserve the original sample, channel count, sample rate and exact frame count for pitch-only edits. Write a temporary file and atomically publish it only when complete; discard results for stale edit revisions.

The documented Clip.file_path property is read-only. Native UI mounting does not establish an audio-source mutation API. Ableton documents replacing a clip sample by dropping a file into Clip View; use that as the first supported integration experiment. Verify markers, crop, loop, clip envelopes and other clips referencing the original before claiming preservation. Begin with a disposable duplicate clip. A native Apply button that automates source replacement remains a separate bounded investigation, with the documented replacement workflow as fallback.

First audible interaction: edit → background render → audition/review → apply rendered asset → normal Live playback. Keep the original analysis/document after application so we never re-detect and compound edits from an already corrected render. Test reversing application separately from local edit undo.

Low-latency audition during playback is later: either a properly scheduled device audio path with host position and latency compensation, or a verified native playback integration. The current pass-through Max device and polling cursor do neither. A replacement player must handle seeks, loops, warp, muted/solo tracks, clip launch and double-playback prevention before it can be the default path.

## Milestones and acceptance gates

### 1. First audible pitch edit
- Add SourceAsset, RenderPlan and replaceable renderer interface.
- Build a CLI test harness: source WAV + per-note shifts → new WAV and timing metadata.
- Prototype the selected backend behind the interface with pinned version/build settings.
- Render track 3 at ±1 and ±3 semitones on selected notes; audition level-matched original/edited examples.
- Gate: original untouched, duration/channels preserved, no-edit PCM identity, correct shifted pitch, no NaNs or unexpected clipping, no obvious clicks at changes. Export ±12 cases as stress tests, not transparency targets.

### 2. Useful editor loop
- Continuous correction curve, fractional semitones, formant-preserve setting, multi-note edits, split/merge.
- Debounced render after gesture commit, cancellation and latest-revision-only publication.
- Versioned sidecars and document ownership outside canvas; reopen retains edits.
- Gate: undo/redo reproduces renders, switching clips cannot apply another clip's result, rapid gestures cannot publish stale audio.

### 3. Apply in Live
- Test same-length replacement in a duplicate clip using the documented workflow.
- Verify warp/crop/loop/envelopes and that sibling clips keep their original audio.
- Bind Apply/Revert to a proven host workflow; keep host limitations explicit.
- Gate: playback from Live audibly matches selected render through the user's existing device chain; original recoverable and no double playback.

### 4. Natural correction quality
- Improve segmentation/voicing and add center correction, drift, vibrato, transitions, formant and gain controls.
- Assemble permission-cleared dry vocals with low/high voices, vibrato, slides, repeated notes, breaths and sibilants. Current synthesized choir recording is useful for regression, not sufficient quality evidence.
- Gate: blind level-matched listening against original and user-created reference renders; check octave errors, breath damage, metallic coloration, transients and stereo image. Track render time, peak memory and edit-to-audition time on this Mac. Establish latency targets from the first measured baseline.

### 5. Timing and live audition
- Add monotonic time maps with fixed anchors and explicit warp composition.
- Add host-synchronous cached playback only after the transport/latency feasibility test passes.
- Gate: seeks/loops/tempo changes and offline host export remain aligned, with no real-time allocation, disk I/O or locks in audio callbacks.

## Immediate next implementation slice

Build milestone 1's CLI renderer and A/B fixtures before changing the tab UI. The concrete demo is: move one detected note up two semitones, generate a same-length stereo-preserving file, and hear that change through Live using the verified replacement workflow. DSP quality and host replacement are separate pass/fail gates.

## Sources

- Rubber Band integration: https://breakfastquay.com/rubberband/integration.html
- Rubber Band API and variable pitch constraints: https://breakfastquay.com/rubberband/code-doc/classRubberBand_1_1RubberBandStretcher.html
- Rubber Band licensing: https://breakfastquay.com/rubberband/license.html
- WORLD source and license: https://github.com/mmorise/World
- élastique Pro SDK: https://licensing.zplane.de/uploads/SDK/ELASTIQUE-PRO/V3/manual/elastique_pro_v3_sdk_documentation.pdf
- Flex Pitch interaction reference: https://support.apple.com/en-gb/guide/logicpro/lgcpc53e6bef/10.7/mac/11.0
- Live Clip API: https://docs.cycling74.com/apiref/lom/clip/
- Ableton Clip View/sample replacement: https://www.ableton.com/en/manual/clip-view/
