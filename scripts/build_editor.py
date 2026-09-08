#!/usr/bin/env python3
"""Build/test the portable pitch core and a standalone macOS UI harness."""
import plistlib
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
build = root / "build"
build.mkdir(exist_ok=True)
flags = ["xcrun", "clang++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-I", str(root / "src")]
core = str(root / "src/pitch_core.cpp")
test = build / "pitch-core-test"
subprocess.run(flags + [core, str(root / "tests/pitch_core_test.cpp"), "-o", str(test)], check=True)
subprocess.run([str(test)], check=True)
expression_test=build / "pitch-expression-test"
subprocess.run(flags + [core, str(root / "tests/pitch_expression_test.cpp"), "-o", str(expression_test)], check=True)
subprocess.run([str(expression_test)], check=True)
viewport_test=build / "pitch-viewport-test"
subprocess.run(flags + [str(root / "tests/pitch_viewport_test.cpp"), "-o", str(viewport_test)], check=True)
subprocess.run([str(viewport_test)], check=True)
gestures_test=build / "pitch-gestures-test"
subprocess.run(flags + [str(root / "tests/pitch_gestures_test.cpp"), "-o", str(gestures_test)], check=True)
subprocess.run([str(gestures_test)], check=True)
playback_test=build / "pitch-playback-test"
subprocess.run(flags + [str(root / "tests/pitch_playback_test.cpp"), "-o", str(playback_test)], check=True)
subprocess.run([str(playback_test)], check=True)
structure_test=build / "pitch-canvas-structure-test"
subprocess.run(flags + ["-fobjc-arc", core, str(root / "src/pitch_canvas.mm"),
    str(root / "tests/pitch_canvas_structure_test.mm"), "-framework", "Cocoa", "-o", str(structure_test)], check=True)
subprocess.run([str(structure_test)], check=True)
store_test=build / "pitch-document-store-test"
subprocess.run(flags + ["-fobjc-arc", core, str(root / "src/pitch_document_store.mm"),
    str(root / "tests/pitch_document_store_test.mm"), "-framework", "Foundation", "-o", str(store_test)], check=True)
subprocess.run([str(store_test)], check=True)
contents = build / "Pitch Editor Lab.app/Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
(contents / "Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "local.jacob.pitch-editor-lab",
    "CFBundleName": "Pitch Editor Lab",
    "CFBundleExecutable": "PitchEditorLab",
    "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1",
    "NSHighResolutionCapable": True,
}))
subprocess.run(flags + ["-fobjc-arc", core, str(root / "src/pitch_canvas.mm"), str(root / "src/pitch_editor_lab.mm"),
    "-framework", "Cocoa", "-framework", "AVFoundation", "-o", str(contents / "MacOS/PitchEditorLab")], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(contents.parent)], check=True)
print(contents.parent)
