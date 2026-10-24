#!/usr/bin/env python3
"""Audit the delivered bundle rather than the host's FFmpeg executable."""
import ctypes
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'dist/LPlayer Sandbox.app'
contents = app / 'Contents'
libraries = contents / 'Frameworks'
resources = contents / 'Resources'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
with tempfile.NamedTemporaryFile() as temporary:
    subprocess.run(['codesign', '-d', '--entitlements', temporary.name, '--xml', str(app)], check=True, capture_output=True)
    entitlements = plistlib.loads(Path(temporary.name).read_bytes())
assert entitlements.get('com.apple.security.app-sandbox') is True
assert entitlements.get('com.apple.security.files.user-selected.read-only') is True
assert entitlements.get('com.apple.security.files.bookmarks.app-scope') is True
assert not entitlements.get('com.apple.security.network.client')
assert not entitlements.get('com.apple.security.files.user-selected.read-write')
print('PASS: signed App Sandbox, read-only user selection, persistent bookmarks, no network entitlement')

for binary in [contents / 'MacOS/LPlayer', *libraries.iterdir()]:
    output = subprocess.check_output(['otool', '-L', str(binary)], text=True)
    for line in output.splitlines()[1:]:
        reference = line.strip().split(' (compatibility version', 1)[0]
        if reference.startswith(('/System/Library/', '/usr/lib/')):
            continue
        if reference.startswith('@executable_path/'):
            target = contents / 'MacOS' / reference[len('@executable_path/'):]
        elif reference.startswith('@loader_path/'):
            target = binary.parent / reference[len('@loader_path/'):]
        elif reference.startswith('@rpath/'):
            target = libraries / reference[len('@rpath/'):]
        else:
            raise AssertionError(f'external dependency {binary}: {reference}')
        assert target.is_file(), (binary, reference)
print('PASS: every non-system dynamic dependency resolves inside the app bundle')

report = {}
for stem in ('libavcodec.', 'libavformat.', 'libavutil.'):
    paths = list(libraries.glob(stem + '*.dylib'))
    assert len(paths) == 1, (stem, paths)
    library = ctypes.CDLL(str(paths[0]))
    function_name = {'libavcodec.':'avcodec_license', 'libavformat.':'avformat_license', 'libavutil.':'avutil_license'}[stem]
    function = getattr(library, function_name)
    function.restype = ctypes.c_char_p
    license_text = function().decode()
    assert license_text == 'LGPL version 2.1 or later', license_text
    report[paths[0].name] = license_text
assert not any(any(name in path.name.lower() for name in ('rubberband', 'libx264', 'libx265', 'libpostproc', 'libdvdnav', 'libdvdread')) for path in libraries.iterdir())
print('PASS: bundled FFmpeg reports LGPL 2.1+; no Rubber Band/x264/x265/postproc/DVD GPL libraries')

for file in ('PrivacyInfo.xcprivacy', 'PrivacyPolicy.en.html', 'PrivacyPolicy.zh-Hans.html', 'licenses/dependency-manifest.json'):
    assert (resources / file).is_file(), file
manifest = plistlib.loads((resources / 'PrivacyInfo.xcprivacy').read_bytes())
assert manifest.get('NSPrivacyTracking') is False
assert not manifest.get('NSPrivacyCollectedDataTypes')
print('PASS: privacy manifest, policies and dependency notices are included')

report.update(application=str(app), entitlements=entitlements,
              third_party_libraries=len(list(libraries.iterdir())),
              scope='Static/package checks only; real sandbox UI validation is separate.')
destination = root / 'artifacts/store-readiness/package-check.json'
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(report, indent=2) + '\n')
print(f'Report: {destination}')
