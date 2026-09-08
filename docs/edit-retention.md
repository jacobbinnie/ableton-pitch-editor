# Clip edit retention — revision 30

## Scope

Each document is keyed by Live process launch identity, Song ID, Clip ID and source-file SHA-256. The source hash is computed off the audio thread during analysis. Two clips referencing the same WAV have independent documents. Moving a clip does not deliberately change its identity; the adapter follows the Live object ID rather than a track index or filename.

[Live path IDs follow objects](https://docs.cycling74.com/legacy/max7/refpages/live.path), but this implementation does not assume they are stable after restarting Live. A new process identity intentionally starts fresh. This is recovery within a running Live session, not persistence embedded in a saved Set. Source hashes are checked when analysis runs, not continuously for external file modifications.

## Ownership and saving

The canvas now holds a shared Document. The store owns documents independently, so detaching a canvas does not destroy note boundaries, pitch offsets or undo history. Returning to a cached clip reuses the document. PCM is still decoded for audition when reopening; this is not an audio-file export.

Committed operations, including undo/redo, save versioned JSON note snapshots under ignored `.pitch-state/`. Mouse-drag previews update live processing immediately but do not write recovery data until release. A serial writer creates atomic files; teardown flushes pending saves. Writes never occur in the DSP callback. Small recovery files are read on the control thread when a document is opened.

Reloading the adapter restores note IDs, split/join boundaries, detected centers and fractional pitch offsets. Undo history is retained in memory across view changes but is not serialized across adapter reloads. Existing edits in revisions before 30 cannot be recovered automatically because those versions never wrote recovery files.

## Validation and host boundary

Restore requires matching schema, identity and source hash. Files over 2 MiB, excessive rows, nonnumeric/nonfinite fields, overlapping/out-of-range intervals, duplicate IDs and unsupported offsets are rejected; detection is used as the fallback. Corrupt documents are never partially restored.

Live metadata now includes the detail Clip and Song IDs. Stream enablement requires the analyzed IDs to match the current metadata. Analysis publication also checks its generation, target canvas and native clip pointer, preventing a completed worker from installing a result into a different selected clip.

Tests cover cache ownership, separate clips sharing a source, separate Live sessions, changed sources, fractional/structural recovery, IDs, retained in-memory history and malformed data. Core and AppKit structural tests also pass with shared document ownership. Native revision 30 builds successfully; revision 31 subsequently verified a native device-reload round trip: nine regions and the user’s +1.78-semitone edit were restored. Cross-clip behavior in Live remains unverified.

## Remaining limits

- No saved-Set/restarted-Live restoration or migration of older in-memory edits.
- Processing still follows the selected supported Arrangement clip; this does not enable simultaneous independent processing of all edited clips.
- Recovery errors retain the in-memory edits and report a status; the recovery directory is local/private and not committed.
- Memory retains cached documents until device disposal; an eviction policy and recovery-file cleanup are future work.
