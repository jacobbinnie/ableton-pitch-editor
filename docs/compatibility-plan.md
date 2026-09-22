# Automatic compatibility and distribution plan

Status: broader roadmap deferred in favor of a basic native path. On 2026-09-22, build detection and exact profiles for 12.4.5/12.4.6 were implemented; the 12.4.6 native tab passed an opening/analysis/edit smoke test. Window fallback, controller extraction, durable Set recall and release packaging below remain proposed. Historical gaps below describe the pre-fix baseline.

## Product goal

Install once, select a vocal clip, edit notes and hear changes immediately. Prefer the native Clip View tab on validated Live builds. Offer the same editor in a Max for Live window when native integration is unavailable. Never describe the window as a native tab or promise arbitrary-version support.

First release scope: macOS Apple Silicon, Live 12 with Max for Live, warped Arrangement clips, current 60-second/8–48 kHz/mono-stereo input limits. Windows, Intel/Rosetta, Session clips and unwarped playback are separate work. Paid editions need validation; Trial is not a fundamental requirement.

## Current evidence and gaps

- The 12.4.5 Trial native prototype used private addresses and object layouts. Installed 12.4.6 is rejected by the build fingerprint guard.
- `pitch_native.mm` combines native attachment, Live metadata, analysis, document ownership, audition and DSP setup. Its singleton state is not suitable for independent devices on multiple tracks.
- `PitchCanvas`, the C++ document, expression curves and streaming processor are reusable. `pitch_clip.mm` is an older pass-through preview, not an audible fallback. The standalone lab is also not an integrated fallback.
- Current processing follows the selected clip. Recovery uses process-local identities and does not survive reopening a Set reliably.
- Compiled app/log/recovery paths depend on the checkout. The fresh-clone test also exposed a Python CA-bundle issue downloading Rubber Band.

## 1. Compatibility preflight and portable paths

Add a read-only preflight that runs before copying Live or downloading build dependencies. Enumerate installed app bundles and let the user select one when there are several. Read version, build, available product metadata, architecture and executable fingerprint without inspecting authorization files. Treat an edition label as descriptive, not proof of Max for Live availability. Runtime capability checks determine whether required Max/Live API features are actually available.

Report independent capabilities: device playback, editor window, native tab, supported clip type and edit recall. Distinguish verified, untested and unsupported configurations; record both Live and Max versions. A version string alone never enables native integration. Unknown builds report native integration unavailable, while a validated public-API window path can remain usable.

Move recovery/logs to per-user Application Support locations and resolve installed resources relative to their bundle. Eliminate the compile-time personal app-path guard in favor of runtime build validation. Keep old recovery files intact; do not relabel process-local clip IDs as persistent IDs. Preserve HTTPS certificate verification and document/fix the Python CA discovery failure.

Acceptance: detects the present 12.4.6 build before any app modification; handles missing/multiple installs, spaces in paths, unavailable capabilities and architecture mismatch; relocating the checkout does not require changing data paths.

## 2. Prove the public integration and persistence boundaries

Before a broad refactor, build a minimal external-owned AppKit window with device audio passthrough in stock 12.4.6. Verify main-thread creation, two device instances, window teardown and device unload. Test a downloaded, signed external on a clean Mac early; successful local compilation does not establish distributability. Resolve dependency licensing before committing to a binary release.

Prototype versioned state stored with the Set using supported Max persistence. The documented pattr facilities can store device state, but that does not establish durable identity for arbitrary Live clips. Prove binding across save/reopen, clip/device duplication, Save As, clip moves and media relocation. Live object IDs are process-local; neither an editor-owned UUID alone nor source hash/name/track position alone solves clip rebinding.

If automatic binding cannot be made reliable, explicitly scope the first version to a device-bound clip with user-assisted rebinding when ambiguous. Never silently apply one clip's edits to another. Keep same-session recovery separate from the saved project format. This feasibility result determines the controller/state schema before implementation expands.

Acceptance: a minimal device opens/closes its window safely and restores a small edit document after reopening a Set; ambiguous bindings remain inactive and request rebinding. Document the verified mechanism and unresolved limitations.

## 3. Separate the host controller from presentation

Extract per-device `ClipController` and `AudioProcessor` components from `pitch_native.mm`. The controller owns clip metadata, source analysis, documents, transport mapping and audition, using documented Live Object Model messages. UI attachment becomes an interface with native-tab and window implementations.

Remove native clip pointers from shared analysis guards. Use controller generation, source identity and Live object identity within the current process to reject stale work. Keep ownership per device/track; only the optional native-tab coordinator is process-wide. Transfer the same document between views, never duplicate processors or reload edits merely to change presentation.

Separate the selected editing target from playback ownership now. Start with one explicitly bound clip per device; selection changes must not disable its edits. For track-wide scheduling, use documented track Arrangement clip enumeration and maintain per-clip documents. Reject unsupported Session overrides, input monitoring and ambiguous audio ownership rather than processing unrelated audio.

Keep all allocation, file I/O, Live API calls and document writes off the audio callback. Gather metadata through deferred control-thread work, use generation checks for coherent snapshots, and continue transport/metadata updates while the UI is closed. The existing 30 Hz UI polling is not an audio scheduling guarantee. Retain immutable DSP snapshots and verify delay compensation rather than assuming the current constants generalize. Close/reopen UI without stopping clip processing; stop audition on view close. Define track-device disposal independently from view disposal.

Acceptance: existing model/audio tests pass, two device instances remain isolated, rapid clip switching cannot install stale analysis, switching views preserves edits and local undo without doubling audio.

## 4. Build and validate the audible window editor

Host the shared canvas in an external-owned AppKit window opened by an **Open Pitch Editor** device button. Use the shared controller and MSP processing, including click/drag audition during transport playback. This is new integration work, not a rename of the old preview device.

First validate this path on the installed 12.4.6 build without resource changes or any native-adapter loading. Query required Live API properties and provide actionable messages for unsupported clip/device configurations. If processing cannot be supported, leave audio passing through and explain the limitation rather than showing a working-looking editor.

Define the supported audio path explicitly: the device receives track audio after Live's clip processing and any preceding devices, while analysis reads the source file. Initially require placement first on an isolated vocal track. Validate supported warp modes and clip transposition; exclude Re-Pitch, reverse and other unmapped transformations until source pitch/time mapping is proven. Cover clip fades/boundaries and unsupported routing without promising independent correction of mixed signals.

Measure end-to-end latency/PDC and note-boundary timing at supported playback sample rates and buffer sizes, including tempo changes, seeks and loops. The hardcoded 2,624-sample patcher latency and 1,024-sample control history are evidence for the tested configuration only. Source file sample-rate limits and Live playback sample rates are separate constraints. Publish supported combinations and block or clearly report others.

Audition currently uses the Mac output independently of Live, despite sharing pitch-processing code. For the first milestone disclose and test that route, level and stop behavior during transport; audition through Live's selected output/effects requires separate integration and must not be implied.

Acceptance: fresh checkout/device install on 12.4.6, audible pitch/gain/expression edits, audition while playing, seek/loop behavior, undo and repeated window close/reopen. Edits continue when another clip/track is selected and survive Set reopen under the binding policy established in phase 2. Test two devices independently. Native private calls must never execute in this path, including during capability probing.

## 5. Versioned native adapters and automatic selection

Move the 12.4.5 knowledge into an explicit compatibility profile. Each profile records architecture, exact executable fingerprint, required symbols, ABI signatures, layouts/vtables, resource schema and validation evidence. Mark the historical 12.4.5 implementation as needing lifecycle revalidation, not release-certified.

Resolve exported symbols dynamically where available; ASLR relocation remains explicit. Fingerprint-bound offsets may still be necessary. Symbol presence or matching instruction patterns are evidence for maintainers, not permission to invoke unknown private interfaces. Do not automatically generate or execute speculative adapters on user machines.

Identify and validate 12.4.6 separately, then paid Suite and Standard with Max for Live. Validate at install time and again inside the running process before the first private call. Load native adapter code only after validation. Unknown or inconsistent builds select the window path. Validation cannot guarantee recovery from an in-process native crash, so a runtime try/catch is not a substitute for compatibility tests.

Resource preparation targets a user-created experimental copy only. Check original and patched resource hashes/schema, make installation idempotent, write changes atomically and retain rollback metadata. Never distribute Ableton app/resources. After an app update, stale profiles are disabled and require revalidation.

Acceptance per profile: tab selection/typography, 50 hide/show and window lifecycle cycles, clip deletion/replacement, device unload/reload, resized views, stopped/playing/looping transport and clean fallback on every failed precondition. No claim of paid-edition support until tested there.

## 6. Package and verify the user installation

Create a GitHub Release with prebuilt, architecture-specific external and frozen Max for Live device, install instructions, checksums, dependency notices and compatibility table. Finish project/dependency licensing review before shipping binaries; assess native resource modification/distribution terms separately from public-API device packaging. Validate signing/notarization and quarantine handling on a separate clean Mac; do not tell users to disable system security or assume the modified Live copy retains a valid resource seal.

Default installation loads the device in stock Live and offers the window editor. Native tab setup is an explicit optional experimental path for a validated local copy. Compatibility data ships with the release initially; future updates should use authenticated, integrity-checked release packages, not downloaded arbitrary executable patches.

Acceptance: a tester without Xcode, Python, our fixtures or development files installs and edits their own vocal. Verify relocation, upgrade, uninstall and retention of user edits. Include two clips sharing a WAV with independent changes, clip/device duplication, Save As, missing media and state-schema migration. Track-wide playback is a separate acceptance gate if the first milestone uses explicit single-clip binding. Test an unknown fingerprint with no private calls, supported native and fallback-only paths, and paid editions only when legitimately available.

## Delivery order and first milestone

Implement phases 1–2 first to resolve compatibility, packaging feasibility and saved-state binding. Then phases 3–4 deliver the audible editor on stock 12.4.6, including playback independent of selection and verified recall within an explicit support scope. Phase 5 restores the preferred native Clip View experience on separately validated builds. Complete phase 6 for distribution; the public-API window release need not wait for native adapter validation, but it does not fulfill the native-tab milestone.

The first implementation task is the read-only preflight, followed by the small window/persistence feasibility prototype before shared-controller extraction. No app resource or compatibility fingerprint changes are needed for that task.

## References

- [Clip properties and warp markers](https://docs.cycling74.com/apiref/lom/clip/)
- [Track Arrangement clip enumeration](https://docs.cycling74.com/apiref/lom/track/)
- [Saving state with pattr](https://docs.cycling74.com/userguide/pattr/)
- [Max for Live device overview](https://docs.cycling74.com/userguide/m4l/_m4l_overview/)
- [Freezing devices for distribution](https://docs.cycling74.com/userguide/m4l/live_freezing/)
- Existing [audio behavior](live-audio.md) and [edit retention limitations](edit-retention.md).
