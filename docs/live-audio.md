# Live audio prototype — revisions 24–34

## Interaction

Load `build/Native Pitch Editor.amxd` with `pitchnative34.mxo` beside it on the audio track. Select a warped Arrangement clip and open Pitch Editor. Drag notes vertically or use Up/Down; changes update the processing state immediately, including during playback. One drag remains one local undo entry. Selecting/dragging a note loops its original audio through an in-memory pitch unit, then stops shortly after release. The audition continues alongside Live playback, including when transport starts during a drag.

There are no Original/Edited/Show File controls and no audio export in this flow. Existing offline renderer commands remain developer test harnesses. The source audio is never overwritten.

## Audio path

`plugin~ → native MSP processor → plugout~` processes stereo track input with Rubber Band LiveShifter and formant preservation. A control-thread snapshot publishes note offsets and Arrangement/warp/loop mapping. The callback reads that snapshot without allocation or locking; Rubber Band controls run on the audio thread. `plugsync~` provides transport/beat/samples-per-beat information; the callback interpolates between updates. This is not proof of sample-accurate host scheduling.

The shifter adds 2,624 samples of delay at tested rates 44.1/48 kHz (59.5/54.7 ms). The patcher declares this using its `latency` attribute, documented as [Defined Latency](https://docs.cycling74.com/reference/patcher/); Live uses declared latency for [track compensation](https://docs.cycling74.com/userguide/m4l/live_audiodevices/). End-to-end compensation has not been measured. Bypass uses an equally delayed dry signal. Note boundary scheduling, crossfades, seeks and processing-window response still need tighter measurements.

Note audition uses AVAudioEngine/AVAudioUnitTimePitch on the Mac output, sourced from decoded PCM in memory. It does not pass through the Live track or use the same algorithm as streaming playback.

## Verified

- Built the native adapter and editor harness with warnings treated as errors.
- Core/model, viewport, playback mapping, existing offline renderer and new streaming tests pass.
- Streaming tests measure +2 semitones at 44.1/48 kHz, untouched regions, clip/crop/warp/loop lookup and delay-matched no-edit bypass.
- In Live, dragged fixture note 2 from 0 to +2; the audition engine started successfully. Transport playback repeatedly increased the audio callback's shifted-block counter on the owning track. This confirms execution, not a listening-quality assessment.

## Scope and limits

This is a selected, warped Arrangement-clip prototype, not a production replacement for Melodyne. It processes the entire track signal at its device-chain position, including upstream effects. Use one loader on the test track; multiple loaders, tracks, clip switching, unsupported rates, Session clips and unwarped clips need more work. Unsupported mapping bypasses correction. Clips sharing a source still need durable identities and independent edit storage.

Revision 30 adds [same-session edit retention](edit-retention.md). Edits are not saved with the Set; older running revisions can still lose edits on clip change/reload. Detection, short-note transitions and vocal sound quality require listening evaluation. Navigation is in source seconds; native beat zoom is independent. The original Live executable and licensing remain unchanged.

## UX reference and revision 25

[Apple’s Flex Pitch guide](https://support.apple.com/guide/logicpro/edit-pitch-and-timing-with-flex-pitch-lgcpc53e6bef/12.3/mac/15.6) establishes piano-roll-style audio notes and direct vertical pitch dragging. This iteration follows that interaction and retains Ableton’s colors. No unsupported timing, vibrato, gain or formant hotspots are shown.

The envelope device/parameter/Linked footer disappears when Pitch opens: the adapter sends a local click to the existing Sample tab using the measured native selector frame, then mounts the canvas on the next main-thread turn. It does not mutate envelope parameters. Returning to Envelopes restores those controls. Verified twice in the running experimental app, alongside +2 → undo 0 → redo +2 and tab-toggle edit retention.

The footer now shows destination note and semitone offset; detailed navigation shortcuts are in the tooltip/accessibility help. The drawn pitch contour follows edited offsets and is an estimate, not re-analysis of processed audio. Double-clicking notes no longer invokes Fit. Audition status resets when audition ends.

## Fine pitch — revision 27

Shift-drag changes pitch by one cent per vertical screen point; Option-Up/Down nudges one cent. Revision 32 supersedes coarse-drag behavior: normal dragging snaps absolute destination pitch to integer MIDI rows, while Shift-drag retains free cents adjustment. Keyboard transposition still adds semitone steps. The footer distinguishes estimated absolute pitch/deviation from the edit offset; it is not a live output tuner. The existing double-valued model, streaming processor and audition pitch unit retain fractional values.

Verified in Live: note 2 +2.01 → undo +2.00 → redo +2.01. The modifier-drag path is implemented but not separately exercised by UI automation. Core tests retain fractional edits and undo; streaming tests cover +0.50 and −0.35 semitones at 44.1/48 kHz in addition to +2.00. The frequency estimator has finite resolution; these tests establish fractional shifting, not one-cent output accuracy.

## Manual segmentation — revision 29

Right-click a note for **Split Note Here** and **Join with Next Note**. Splits require at least 20 ms on each side. Both children inherit the pitch offset; each displayed original center is recomputed from the existing voiced frames. Joining requires touching boundaries and equal offsets; it keeps the left ID and recomputes the combined center. No audio samples or source timing are moved. This is adjacent joining, not arbitrary multi-selection merging.

Undo/redo now records note-vector snapshots, preserving IDs, boundaries, centers and pitch edits together. New IDs remain monotonic across undo branches. The canvas clamps selection after structural undo and publishes the updated note list to the live processor. Contiguous equal-offset regions share outer transition ramps, preventing split/join alone from introducing pitch dips.

Verified: model tests for invalid splits, IDs, centers, retained offsets, join restrictions, and mixed undo/redo history; AppKit context-menu action tests for publication, enabled states and selection; streaming curve equality before/after a split, plus existing audio tests. The new context menu has not yet been exercised inside Live. Revision 29 is built; the running older loader was retained to avoid discarding the user's temporary edits.

## Click-to-position — revision 31

Empty plot clicks and clicks on the inner seconds ruler request a Live transport seek. Ruler movement beyond three points remains pan; note clicks only select/audition. Stopped cursor painting now follows host position instead of updating only while playing.

Source seconds are inverted through the warp map, then mapped through Arrangement start/start-marker and clip-loop metadata. Loop targets choose the nearest valid occurrence inside the Arrangement clip. Revision 41 clamps positions before the playable start to the clip start; positions at or beyond the end remain rejected. Only the existing supported warped Arrangement path is implemented.

The patch routes `seek` to [Song.current_song_time](https://docs.cycling74.com/apiref/lom/song/) and, while stopped, `seekstart` to Song.start_time. It does not start playback, change recording, or rewrite clip markers. Unit tests cover inverse warp mapping, crop bounds, loop occurrences, invalid maps and empty-space/ruler/note gesture distinctions.

Verified in the running Live copy: stopped click at 2.99 source seconds, playback advancing from that location, and ruler seek during playback. Backed up the local recovery JSON before replacing the prior loader; all nine note regions loaded, and the user's note 6 offset of +1.78 was confirmed. Revision 31 is now loaded. This verifies the first same-session native adapter reload round trip; cross-clip and restarted-Live behavior remain separate tests.

## Grid snapping — revision 32

Normal vertical dragging now snaps `detected pitch + offset + drag delta` to an integer MIDI pitch, then derives the offset from that destination. Merely adding an integer offset preserved the detector's original detuning and left blocks between rows. Shift-drag still changes cents relative to its starting offset. Coarse destinations stay on-grid at the ±24-semitone processing limits.

Gesture tests cover detuned inputs, existing edits, both directions, limits and fine drag. Native UI verification dragged note 6 onto F3 at +0 cents; Undo restored the user's −0.22-semitone edit. Revision 32 is loaded, and no existing notes were automatically quantized.

## Snap toggle — revision 33

An accessible on/off button sits at the bottom-right of the canvas. On (orange) snaps normal drags to absolute semitone rows; off (gray) uses continuous pitch movement at the current row scale. Shift-drag uses one cent per point in both modes. Changing the toggle changes future gestures only and does not publish a pitch edit.

The preference defaults on and is stored separately in the `local.jacob.pitch-editor` user-defaults suite under `snapPitch`. It is an editor preference, not part of clip undo or recovery.

Verified in Live: Snap on/off accessibility state and appearance, free drag landing 43 cents off the row, snapped dragging, and undo restoring existing offsets. Gesture/model/editor/recovery tests pass. Revision 33 is loaded with Snap on; test edits were undone.

## Region removal and boundaries — revision 34

Select a note and press Delete/Backspace, or choose **Remove Pitch Region** from the note context menu. This removes the edit region, not source samples or the Live clip. Removed intervals have zero requested pitch shift through the existing delay-matched track processor. Removing every region is supported and undoable.

Drag the left/right edge to change source-time bounds. The small handles and horizontal-resize cursor distinguish edge dragging from pitch dragging. Bounds stop at neighboring regions and source duration, with a 20 ms minimum region. A region can expand into a gap or a removed region but cannot overlap another. Its pitch offset and original center remain unchanged; expansion applies the same offset to additional audio, not pitch-center correction or time stretching. Snap remains a pitch-only toggle.

Edge previews update live processing; release commits one history entry and recovery snapshot. Invalid/rejected commits restore the committed streaming state. Structural undo, source limits, overlap rejection, remove-all and expansion into a removed region are covered by model tests; AppKit tests exercise the removal menu and horizontal edge drag. Stream tests ensure removed/shrunken intervals stop receiving correction.

Verified in Live: Delete changed nine regions to eight while the device and clip remained; expanding the following region moved its start from 2.54 to 2.32 seconds at unchanged −0.26-semitone offset. Two undos restored the original regions. The saved recovery JSON exactly matched the pre-test backup. Revision 34 is loaded.

## Revision 35 — per-note gain

`Note.gainDb` defaults to zero, accepts finite −24..+12 dB, and shares note-vector undo history. Splits inherit gain; joins require equal pitch offsets and equal gain. The selected-note handle adjusts 0.1 dB per view point (Shift: 0.02); double-click resets. Drag snapshots update playback and audition; only committed gestures persist.

Playback maps gain through the existing crop/warp/loop mapping at host callback rate. The source envelope has 5 ms smoothstep edge ramps, coalescing touching equal-gain regions. A sample-rate-derived 5 ms one-pole smoother handles live parameter changes, and the gain ring follows the existing 2,624-sample audio delay. Gain applies after wet/dry mixing to both channels; neutral gain preserves existing bypass. No new audio-thread allocation, file I/O or locks. Boundary timing is still callback-quantized, and end-to-end host PDC remains unmeasured.

Audition uses AVAudioUnitEQ global gain after TimePitch, including updates to the active note. It retains the existing 0.8 preview attenuation and independent Mac output; it does not reproduce the Live effects chain. Waveform feedback estimates gain-scaled source peaks, not processed-output re-analysis, and clips drawing at plot bounds. No automatic limiter or normalization is introduced.

Recovery writes schema 2 with six-value rows; schema 1 loads existing edits with 0 dB gain. Current Live UI checks verified gain dragging while stopped/playing, waveform response and undo. All eight existing regions and their pitch offsets matched the pre-test recovery backup after undo, with gains zero. Automated tests cover boost/attenuation, stereo equality, smoothing, segmentation invariance, validation, history, gesture/reset and legacy recovery. Listening quality and exact audition smoothing have not been independently measured.

## Revisions 36–37 — vibrato reduction and shared audition DSP

`Note.vibrato` stores retained variation from 0 to 1 (default 1). It participates in region history, split inheritance and join compatibility. Recovery schema 3 adds a seventh row field; schemas 1/2 migrate with neutral vibrato and preserve previous pitch/gain values. The UI adds an upper selected-note handle, with Shift fine control and double-click reset. Derived curves are compiled on control threads on edit/analysis changes; drawing and audio callbacks sample the compiled curve.

`pitch_expression.hpp` uses a triangular 250 ms local linear regression window to separate faster residual variation from the slow trend. Only continuous voiced runs with confidence ≥0.85, gaps ≤25 ms, adjacent changes <0.7 semitones and duration ≥300 ms qualify. Residuals over a semitone are gated; 40 ms run-edge ramps and weighted residual de-meaning preserve the estimated center. This is a conservative heuristic, not a perceptually validated vibrato/ornament classifier. Linear drift is preserved exactly in curve tests; arbitrary nonlinear drift can leak into the residual.

The native callback holds one immutable state through bounded 64-sample control chunks. Time-varying corrections keep the wet processor active across zero crossings, avoiding repeated dry/wet pumping. Audio still uses the pinned R3 512-sample blocks and existing 2,624-sample delay. A separate 1,024-sample parameter-history ring aligns pitch controls more closely with the processing window. This is empirically calibrated for the current backend at 44.1/48 kHz, not sample-exact host PDC or a universal algorithm guarantee. Retest it if the backend, windows or buffering change.

Initial revision 36 failed the acoustic attenuation threshold despite a correct curve: input-time controls were too early. A bounded parameter-delay sweep (0–2,048 samples) identified the correction; some non-selected sweep settings also produced upstream resampler underflow warnings. Revision 37's selected configuration passes the 4/6/8 Hz cases without those warnings. Broader rates/material/ratios still need validation.

Audition now uses AVAudioSourceNode and `AuditionRuntime`, replacing AVAudioUnitTimePitch/EQ. The source-node render block retains a dedicated preallocated runtime and processes looping source PCM through the same StreamShifter, gain smoothing, expression curve and formant-preservation mode as Live. Control-thread snapshots update active auditions; no file export, transport gating, audio-thread allocation or locks are added. The existing 0.8 preview attenuation, 5 ms loop-edge fades, 200 ms release and independent Mac output remain. This does not reproduce Live warp/effects or guarantee identical tone after that host processing.

Validation: curve and model tests cover neutral identity, proportional amount, center preservation, linear drift, voicing/confidence/short-run gates, history and incompatible joins. AppKit tests cover drag/reset/undo/redo. Schema 1/2 migration and invalid schema-3 amount tests pass. Independent zero-crossing measurements of rendered synthetic audio (not output detector agreement) show ~35–60% depth reduction for 4/6/8 Hz modulation at 44.1/48 kHz using both oracle and production-detector curves, with center change under five cents. Existing pitch/gain/bypass tests pass. No representative annotated real-vocal corpus or listening study has been completed.

Live verification: corrected build loaded, existing eight regions and user pitch/gain/vibrato settings recovered; stopped and playing vibrato gestures changed only vibrato and undid successfully. Recovery comparison matched all fields within 1e-12 (JSON NSNumber round-trip can change the last binary digit). Audition-start callbacks succeeded. These UI checks do not prove perceived audio quality.

API references: [Rubber Band LiveShifter](https://www.breakfastquay.com/rubberband/code-doc/classRubberBand_1_1RubberBandLiveShifter.html), [Apple AVAudioSourceNode](https://developer.apple.com/documentation/avfaudio/avaudiosourcenode).

## Revision 39 — manual start/end drift

`Note.driftStart/driftEnd` are endpoint adjustments in cents, each finite and within ±200, default zero. The additional curve is piecewise linear: start adjustment tapers to zero at the note midpoint, and end adjustment grows from that midpoint. It shares expression confidence/run gates and 40 ms boundary tapers. This is manual drift shaping rather than automatic estimation; independent side adjustments can intentionally change average pitch, while the midpoint anchor and existing transposition remain fixed. Endpoint values are nominal before boundary taper and the processor's existing total ±24-semitone clamp.

The upper corner handles edit drift, upper middle edits vibrato, and lower middle edits gain. A single feedback line avoids three overlapping labels. Shift changes drift at 0.2 cents per view point instead of 2; double-click resets one side. Preview snapshots feed the existing streaming and audition curve; resize previews now also rebuild the displayed expression curve. No new processor, latency or audio-thread allocations were introduced.

Drift is relative to region bounds. Splitting or joining a region with nonzero drift is rejected with an explanatory menu tooltip; equal drift settings alone do not imply equal curves after changing the midpoint. Resizing remains allowed and intentionally stretches the shape over the changed bounds. This restriction avoids silently changing an existing audible edit until a curve-preserving structural-edit model is implemented.

Recovery schema 4 uses nine-value note rows; schemas 1–3 migrate with zero drift and preserve all earlier fields. Model and AppKit tests cover invalid values, independent sides, reset/history, structural restrictions and composition with vibrato; schema migration and invalid drift recovery tests pass. Acoustic tests at 44.1/48 kHz applied ±60-cent endpoints to a rising synthetic tone with 6 Hz vibrato: the measured early/late difference dropped from ~0.600 semitones to −0.019/−0.017, with vibrato depth remaining ~0.299 semitones. This is synthetic evidence, not representative real-vocal validation.

In Live, revision 39 loaded with eight existing regions, all prior pitch/gain/vibrato edits intact. Start drift +47 cents while stopped and end drift −47 cents while playing were verified in the editor state; both gestures were undone. Post-test schema comparison preserved previous fields within 1e-12 and confirmed zero drift. Audition remains independent of the Live effects chain.

## Revision 40 — independent formant tone

`Note.formant` is a finite −6..+6 semitone envelope shift, default zero. It shares local history, split inheritance and join compatibility. Schema 5 adds a tenth row field; older schemas load with neutral formant while preserving earlier edits. The lower-right selected-note handle edits formant at 0.05 semitones per view point (Shift 0.01); double-click resets. Pitch blocks and the pitch contour remain unchanged by formant-only editing.

The source-time formant envelope uses existing crop/warp/loop mapping, 15 ms edge ramps and coalescing of touching equal-formant regions. A 10 ms one-pole smoother and the existing 1,024-sample control-history ring deliver updates to R3 on the audio thread. Formant-only edits activate wet processing even at zero pitch shift. No new audio latency, file operations, audio-thread allocation or locks are added.

Pinned R3 applies explicit formant envelope scaling before pitch resampling. Use `exp2(formant/12) / pitchRatio` with the same delayed pitch ratio sent to setPitchScale; using exp2(formant/12) alone also moves tone with note transposition. Neutral uses the library's automatic-preservation sentinel 0. The options must still include OptionFormantPreserved in this pinned implementation. Both Live and audition call the same StreamShifter path.

Validation: synthetic harmonic vowel envelopes centered at 1,000 Hz, at 44.1/48 kHz, with pitch 0/+3 semitones and formant −3/0/+3, moved the measured envelope in the expected direction while retaining the expected fundamental period. Neutral tone stayed within 31 Hz of the original center in these cases. The test also covers linked stereo, finite output, region mapping/coalescing, invalid values and history. AppKit gesture/reset/undo, schema-4 migration/schema-5 rejection and all existing expression/gain/pitch tests pass. Spectral centroids are fixture-level evidence, not estimates of individual human formants or a listening-quality guarantee.

Live checks: loaded revision 40 with prior edits retained; lower-right handle changed formant to +1.55 while stopped and −1.42 while playing without changing pitch/gain/vibrato/drift. Undo restored neutral. Post-test recovery comparison preserved all previous fields within 1e-12. Real-vocal timbre quality, extreme ratios and exact boundary scheduling still need wider validation.

## Revision 41 — seek before clip start

Clicks in cropped source lead-in clamp to the Arrangement clip start after resolving valid loop occurrences. The canvas immediately displays the resolved source position, and successful seeks clear a previous range error. Valid silence inside the clip remains freely seekable.

Playback regression tests and the native build pass. Verified in Live: clicking the empty lead-in moved transport to 1.1.1 and the canvas cursor to 0.86 source seconds, matching the cropped start marker.
