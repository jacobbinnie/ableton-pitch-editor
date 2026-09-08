# Native pitch view: implementation path and remaining proof

Target: the user-provided Clip View screenshot, with Sample / Envelopes / Pitch
Editor across the existing header and draggable pitch blocks in the timeline.
The waveform may remain dimmed behind the blocks. Preserve the native beat ruler,
loop brace, scroll/zoom and clip selection. A device panel does not meet this target.

## New evidence

The installed GUI resources define this structure:

```text
ClipDetailView
  _TopLevelSplitView
    _ClipPanelsLoadableView       clip settings on the left
    _ClipContentAreaLoadableView
      ClipContentHeader          Sample / Envelopes selector
      CardView                   editable content or unavailable-state message
        FindAndSelectMidiNotesToolbar
        _ClipContentContainer    empty CellView filled by native code
      ClipContentFooter          mode-dependent controls
```

The content container has no XML children. Its timeline content is supplied at
runtime; adding note-shaped XML children is not an implementation of a pitch
editor. The footer's `CardView` connects to `EffectiveContentViewMode` and has
three cards. The middle one contains `EnvelopeControls`; Pitch needs its own
footer behavior, so the Mixer / Track Volume controls do not remain active.

Reproduce the resource findings with `python3 scripts/inspect_clip_layout.py`.
It verifies the installed executable fingerprint, decodes the original GUI
resource read-only, validates the container and footer structure, and saves
local evidence under ignored `build/research/`.

In Live, switching the selected audio clip from Envelopes to Sample removed
the envelope footer controls while retaining accessibility IDs for
`WarpedAudioTimelineEditor`, the loop brace, and its markers. This establishes
continuity of the visible timeline structure, not identity of C++ objects.

The newly traced helper at `0x103c85e44` chooses among editor pointers stored
at +0x3e0, +0x3f8, +0x410 and +0x428, compares with current editor +0x438,
and rebinds only when the choice differs. Its branches inspect clip-related
state and a virtual query. Some field meanings remain inferred. This argues
against assuming every tab requires replacing the entire audio editor.
The reproduction is included in `python3 scripts/trace_tabs.py`.

## Preferred experimental design

**Investigate a native pitch interaction layer inside the existing audio
timeline first.** The screenshot resembles the envelope editing arrangement:
common time geometry and waveform, with different editable foreground content.
This is a design inference from the resource, runtime UI, and static evidence;
a registration path for our layer has not been demonstrated.

1. Add a separate Pitch state/action, available only for audio clips. If using
   the existing native mode enum, reserve a new internal value after 0/1/2;
   value 2 already means MIDI Expression. Update availability, effective mode,
   tab selection, and keyboard cycling together. The current unknown-value
   fallback and modulo-three cycling prohibit a label-only change.
2. Attach a native `PitchNoteLayer` to the selected audio timeline's content
   hierarchy. Own it through the same parent lifecycle as other editor content.
   Show it in Pitch mode and detach/deactivate it in Sample and Envelopes.
   The class name is proposed project code, not an existing Live class.
3. Use the timeline's actual time-to-pixel transform and visible time range.
   Map detection's source seconds through crop/warp mapping before drawing.
   Add the vertical pitch grid; a waveform's amplitude axis is not a pitch axis.
4. Route note hit-testing, drag capture, focus and undo to pitch editing while
   preserving ruler/loop controls and native navigation. Native visual placement
   alone does not establish input dispatch.
5. Replace the envelope footer with Pitch controls in that mode. Leave Sample,
   Envelopes and MIDI Expression behavior intact.
6. Connect the existing C++ analysis/edit model. Add resynthesis separately;
   note offsets currently do not alter sound. Before applying audio changes,
   revalidate clip identity and timing against the analyzed source revision.

`APlatformViewHost` remains a fallback if the native drawing-layer interface
cannot be recovered. It could host the reusable AppKit canvas within the native
container, but would still need correct parent registration, time transforms,
mode switching and ownership. Merely positioning that canvas over Live's main
window would not meet the target.

## Runtime owner proof, 8 September 2026

The read-only Max probe now resolves virtual AX nodes to their native owners.
For the exact installed arm64 build, `TAxPlatformNode.mpProxy` is a weak pointer
at Objective-C offset 8 whose object field is at +24 within that weak pointer.
`TAxProxy` stores the owner at +0x28 (also checked against its constructor).
Each pointer read uses `mach_vm_read_overwrite`; RTTI/vtable addresses must belong
to Live's main image. The probe invokes no private C++ methods.

Across 65 snapshots in one process, both Envelopes → Sample and Sample → Envelopes
retained all three owner pointers: `LClipDetailView`,
`LWarpedAudioTimelineEditor`, and `ALoopMarkerParentClipDetail`. Mode was identified
by envelope-footer visibility during this controlled single-audio-clip experiment.
This establishes native object identity across these two transitions, beyond the
earlier accessibility-ID comparison. It is not a lifecycle guarantee for other
clips, windows, or builds.

Observed fields correlate the static selection path to real objects:

| Object / field | Observed object |
| --- | --- |
| Clip Detail +0x310 | `AClipContentEditor` |
| Content Editor +0x2d8 | `LDetailTimelineArea` |
| Clip Detail +0x3e0 and +0x438 | Same `LWarpedAudioTimelineEditor` |
| Clip Detail +0x410 | `AUnwarpedAudioTimelineEditor` |
| Clip Detail +0x428 | `ARecordingOrOfflineClipTimelineEditor` |
| Clip Detail +0x3a8 and Audio Editor +0x390 | Same `AAudioClip` |
| Clip Detail +0x3c8 and Audio Editor +0x3a0 | Same `TClipContentEditorViewModel` |
| Clip Detail +0x4c0 and Audio Editor +0x308 | Same `TTimeZoomScrollBounds` |
| Audio Editor +0x2e8 | `TTimeZoomScrollState` |
| Audio Editor +0x4f8 | Same `LDetailTimelineArea` |

These are observed references, not a complete ownership declaration. Do not keep
raw pointers across clip switches or infer writable state from a matching type.

The runtime vtables resolve previously anonymous lifecycle dispatches:

| Dispatch | File address | Static behavior |
| --- | --- | --- |
| Timeline Area vtable +0x590 | `0x103cc72cc` | Clears existing child, updates weak editor reference, forwards attachment to a nested view |
| Audio Editor vtable +0x6c0 | `0x103de5d0c` | Tears down dependent objects before forwarding context binding |
| Audio Editor vtable +0x7c8 | `0x103de63a4` | Calls +0x7f8 with null arguments |
| Audio Editor vtable +0x7f0 | `0x103de2920` | Area/context binding candidate |
| Audio Editor vtable +0x7f8 | `0x103de5db8` | Clip binding with listener/child teardown and rebuild |

Reproduce the log comparison with `python3 scripts/analyze_probe.py`; the local
report is `build/research/runtime-owners.json`. Reproduce the bounded method traces
with `python3 scripts/trace_tabs.py`. Probe revisions 4/5 supplied the verified
observations. Revision 6 also surveys the timeline area's +0x180…+0x218 fields;
it builds, but that additional survey has not been runtime-verified.

## What is still missing

- Drawing-layer or view registration and destruction signatures.
- A verified way to register the new tab action/state with Live's model.
- Time transform, hit-test and focus interfaces for the active timeline.

Ordinary debugger attach was previously denied by macOS. The working Max external
provides an in-process loading route, but it does not establish these private
interfaces. Next resolve the nested view at `LDetailTimelineArea +0x180` and its
attachment virtual +0x578, then identify the draw/input interfaces of the
foreground envelope layer. Native owner identification is now established;
calling attachment methods still requires recovering their contracts.

**Verdict:** the exact target has a plausible native implementation architecture,
and its content slot is identified. We have not yet demonstrated the private
registration/binding route needed to implement it. This report is not a claim
that the existing tab can already open the pitch editor.
