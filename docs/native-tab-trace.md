# Native Clip View tab trace — first pass

Scope: offline arm64 code tracing for the installed Live 12.4.5 build. This establishes control flow, not a working hook or a complete object ABI. No Live code, license checks, preferences or signatures were changed.

## Reproduce

Run `python3 scripts/trace_tabs.py`. It verifies the executable SHA-256 before recording 17 bounded disassembly ranges under `build/research/`. `manifest.json` identifies the binary and ranges; `tabs-disassembly.txt` is the local evidence. Addresses below are file virtual addresses and must not be used directly as runtime addresses under ASLR.

## Confirmed in the instructions

| Path | File address | Observation |
| --- | --- | --- |
| Content/Sample callback | `0x103c93d58` | Loops over a returned pointer collection, obtains a property-like object and calls the shared setter with 0. |
| Envelopes callback | `0x103c93e34` | Same sequence, setter argument 1. |
| Expression callback | `0x103c93ea8` | Same sequence, setter argument 2. |
| Shared setter target | `0x102756f80` | Called by all three callbacks; exact type and side effects not yet established. |
| Effective-mode controller | `0x103c9457c` | Handles 0, conditionally permits 1/2, and sends 0 for other values. |
| Next/previous tab helper | `0x103c8f93c` | Advances in either direction modulo 3 and skips unavailable modes. The arithmetic helper at `0x1011e8e60` confirms modulo behavior. |
| Effective-mode changed | `0x103c95cc8` | Tail-branches to `0x103c85684`, which updates state and invokes several UI-update helpers. |
| Rebuild callback | `0x103c94658` | Calls `0x103c8702c` when its preconditions hold. |

Equivalent high-level interpretation of the effective-mode controller:

```text
requested = 0       -> effective = 0
requested = 1       -> effective = supports_envelopes ? 1 : 0
requested = 2       -> effective = supports_expression ? 2 : 0
anything else       -> effective = 0
```

The support-function names are inferred from the named callbacks that call them. Their entire implementations have not been audited. This controller behavior does not prove a fourth enum value can safely be stored elsewhere.

## Construction and lifecycle leads

| Named factory | Factory address | Allocation argument | Constructor candidate |
| --- | --- | --- | --- |
| `AClipContentHeaderViewModel` | `0x103c7de78` | `0x190` | `0x103c7e308` |
| `AClipDetailViewComponentManager` | `0x103c82318` | `0xc8` | `0x103c825d4` |
| `AClipDetailView` | `0x103c832e8` | `0x4d8` | `0x103c837b0` |
| `AWarpedAudioTimelineEditor` | `0x103de1eec` | `0x508` | `0x103de2270` |

Each factory calls the same allocator-like function, then the listed constructor candidate. The manager constructor also allocates `0x190` bytes and calls the same header constructor candidate. These are concrete ownership leads; allocation sizes alone are not C++ declarations.

The effective-mode-changed body calls `0x103c85760`. This helper accesses a current-editor candidate at `this + 0x438`, compares it to two other pointers, calls virtual methods, updates the host through `this + 0x310`, and handles null/current editor states. The rebuild path also clears the `+0x438` field after several virtual calls. **Interpretation:** this is a promising editor switching/lifecycle boundary. Exact field ownership, types and vtable method signatures remain unverified; do not synthesize an editor or call those methods from the probe yet.

## What a fourth tab would need

1. Visual insertion is now verified: see `native-tab-resource.md` for `ClipContentHeader.xml` and the new native button. Binding that button to custom state is still outstanding.
2. Define and propagate a fourth mode through the model, effective-mode controller, availability checks and keyboard cycling. There are multiple separate constraints, including the fallback and modulo-3 logic above.
3. Attach a custom editor through the verified native lifecycle, including focus, layout, destruction and selection changes.
4. Keep the new mode experimental until persistence/undo behavior is understood. No DSP or project serialization has been built.

An AppKit overlay would not satisfy these requirements. A patch only to the mode filter or modulo constant would also be insufficient.

## Runtime tracing status

Attempted normal `lldb` attachment to process name `Live`, outside the shell sandbox with user-approved escalation. macOS returned “Not allowed to attach to process.” No debugger session was established, no breakpoints were installed, and no re-signing or system-security changes were performed. The precise denying subsystem has not been identified; do not assume granting another shell approval fixes it.

The existing Max external remains a proven in-process loader. It has not been upgraded into a native C++ callback tracer. Next runtime milestone: capture and validate the actual header/Clip View instances and their lifecycle through an allowed instrumentation path, then correlate Sample/Envelopes clicks with these static paths. Static addresses and guessed offsets are not enough for a safe hook.
