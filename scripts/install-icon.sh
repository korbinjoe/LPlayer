#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Resources/LPlayer-icon.png"
ICON="$ROOT/Resources/LPlayer.icns"
if [ ! -f "$SOURCE" ]; then
  echo "找不到图标原图：$SOURCE。请先提供新的 LPlayer 图标；不会使用旧图替代。" >&2
  exit 1
fi
if [ "$#" -eq 0 ]; then
  set -- "$ROOT/dist/LPlayer.app"
fi
if [ ! -f "$ICON" ] || [ "$SOURCE" -nt "$ICON" ] || [ "$ROOT/scripts/make-icon.sh" -nt "$ICON" ]; then
  "$ROOT/scripts/make-icon.sh"
fi

export LPLAYER_ICON_ROOT="$ROOT"
/usr/bin/python3 - "$@" <<'PY'
import ctypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

root = Path(os.environ['LPLAYER_ICON_ROOT'])
icon = root / 'Resources' / 'LPlayer.icns'
backup_root = root / 'artifacts' / 'icon-backup'
allowed_ids = {'dev.joebon.PalmPlayer', 'dev.joebon.LPlayer.Sandbox'}

def run(*arguments):
    subprocess.run([str(argument) for argument in arguments], check=True)

def capture(*arguments):
    return subprocess.run([str(argument) for argument in arguments], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def canonical_plist(value):
    # Canonical plist encoding compares values and types without XML formatting
    # differences (including plist booleans versus integer 0/1).
    return plistlib.dumps(value, fmt=plistlib.FMT_BINARY, sort_keys=True)

def signature_state(app, info):
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or Path(executable).name != executable:
        raise RuntimeError(f'应用可执行文件字段无效：{app}')
    architectures = capture('/usr/bin/lipo', '-archs',
                            app / 'Contents' / 'MacOS' / executable).stdout.decode().split()
    state = {}
    for arch in architectures:
        output = capture('/usr/bin/codesign', '-d', '--verbose=4', '--arch', arch, app)
        details = (output.stdout + output.stderr).decode('utf-8')
        if not re.search(r'^Signature=adhoc$', details, re.MULTILINE):
            raise RuntimeError(f'仅允许更新临时 adhoc 签名的本机应用；拒绝替换发布签名：{app} ({arch})')
        flags = re.search(r'^CodeDirectory .*? flags=(0x[0-9a-fA-F]+)\(([^)]*)\)',
                          details, re.MULTILINE)
        identifier = re.search(r'^Identifier=(.+)$', details, re.MULTILINE)
        runtime = re.search(r'^Runtime Version=(.+)$', details, re.MULTILINE)
        if not flags or not identifier or 'linker-signed' in flags.group(2):
            raise RuntimeError(f'无法可靠保留原签名元数据：{app} ({arch})')
        entitlements_xml = capture('/usr/bin/codesign', '-d', '--entitlements', '-',
                                   '--xml', '--arch', arch, app).stdout.strip()
        entitlements = plistlib.loads(entitlements_xml) if entitlements_xml else None
        if entitlements is not None and not isinstance(entitlements, dict):
            raise RuntimeError(f'原应用 entitlements 格式无效：{app} ({arch})')
        requirements = capture('/usr/bin/codesign', '-d', '-r-', '--arch', arch,
                               app).stdout.decode('utf-8')
        # codesign displays an inferred cdhash requirement as a comment when no
        # explicit designated requirement exists. That hash must change after
        # signing; only actual embedded requirements are preserved and compared.
        embedded_requirements = tuple(line.strip() for line in requirements.splitlines()
                                      if line.strip() and not line.lstrip().startswith('#'))
        state[arch] = {
            'identifier': identifier.group(1),
            'flags': int(flags.group(1), 16),
            'runtime': runtime.group(1) if runtime else None,
            'entitlements': canonical_plist(entitlements) if entitlements is not None else None,
            'requirements': embedded_requirements,
        }
    if not state:
        raise RuntimeError(f'找不到应用架构：{app}')
    return state

def read_info(app):
    with (app / 'Contents' / 'Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    if info.get('CFBundleIdentifier') not in allowed_ids:
        raise RuntimeError(f'应用标识不匹配，未更新任何现有应用文件：{app}')
    return info

# Preflight every target before changing any application. Do not silently turn
# Developer ID / App Store / development certificate signatures into adhoc ones.
targets = []
seen = set()
for argument in sys.argv[1:]:
    app = Path(argument).expanduser().resolve(strict=True)
    if app.suffix != '.app' or not app.is_dir():
        raise RuntimeError(f'必须提供现有 .app 路径：{app}')
    if app in seen:
        continue
    seen.add(app)
    info = read_info(app)
    original_signature = signature_state(app, info)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    targets.append((app, info, original_signature))

def prepare(app, original_info, original_signature):
    staging = Path(tempfile.mkdtemp(prefix='.lplayer-icon-', dir=app.parent))
    staging_directories.append(staging)
    staged_app = staging / app.name
    backup_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = Path(tempfile.mkdtemp(prefix=stamp + '-' + app.stem + '-', dir=backup_root))
    # Work exclusively on a same-volume copy. codesign updates its executable
    # signature, leaving the running application's executable inode untouched.
    run('/usr/bin/ditto', app, staged_app)
    plist_path = staged_app / 'Contents' / 'Info.plist'
    info = read_info(staged_app)
    if canonical_plist(info) != canonical_plist(original_info) or signature_state(staged_app, info) != original_signature:
        raise RuntimeError(f'应用在检查后发生变化，未安装图标：{app}')
    shutil.copy2(plist_path, backup / 'Info.plist')
    old_icon_name = info.get('CFBundleIconFile', '')
    if old_icon_name:
        if not old_icon_name.endswith('.icns'):
            old_icon_name += '.icns'
        old_icon = staged_app / 'Contents' / 'Resources' / old_icon_name
        if old_icon.is_file():
            shutil.copy2(old_icon, backup / 'previous-icon.icns')

    # Keep the complete previous app as a verified ZIP, so no spare .app can
    # become a competing LaunchServices registration after installation.
    archive = backup / (app.stem + '-previous.app.zip')
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', staged_app, archive)
    with zipfile.ZipFile(archive) as handle:
        bad_member = handle.testzip()
    if bad_member:
        raise RuntimeError(f'旧应用备份校验失败：{bad_member}')
    (backup / 'manifest.json').write_text(json.dumps({
        'application': str(app),
        'bundle_identifier': info['CFBundleIdentifier'],
        'previous_icon_name': old_icon_name,
        'new_icon_sha256': hashlib.sha256(icon.read_bytes()).hexdigest(),
        'backup_archive': archive.name,
    }, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

    destination = staged_app / 'Contents' / 'Resources' / 'LPlayer.icns'
    shutil.copy2(icon, destination)
    if info.get('CFBundleIconFile') != 'LPlayer.icns':
        plist_format = plistlib.FMT_BINARY if plist_path.read_bytes().startswith(b'bplist') else plistlib.FMT_XML
        info['CFBundleIconFile'] = 'LPlayer.icns'
        with plist_path.open('wb') as handle:
            plistlib.dump(info, handle, fmt=plist_format, sort_keys=False)
    run('/usr/bin/plutil', '-lint', plist_path)
    expected_info = dict(original_info, CFBundleIconFile='LPlayer.icns')
    if canonical_plist(read_info(staged_app)) != canonical_plist(expected_info):
        raise RuntimeError(f'图标之外的 Info.plist 字段发生变化，未安装：{app}')
    run('/usr/bin/codesign', '--force', '--sign', '-',
        '--preserve-metadata=identifier,entitlements,requirements,flags,runtime', staged_app)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', staged_app)
    if signature_state(staged_app, info) != original_signature:
        raise RuntimeError(f'签名前后的 entitlements / requirements / flags / runtime 不一致，未安装：{app}')
    return app, staged_app, backup

staging_directories = []
try:
    # Complete and verify every staged bundle before the first atomic swap.
    prepared = [prepare(*target) for target in targets]
    # Darwin SDK sys/stdio.h: RENAME_SWAP == 0x00000002. A failed swap leaves
    # the original bundle in place; never remove it to make space for a rename.
    system = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    rename_swap = system.renamex_np
    rename_swap.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename_swap.restype = ctypes.c_int
    registrar = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    for app, staged_app, backup in prepared:
        result = rename_swap(os.fsencode(staged_app), os.fsencode(app), 0x00000002)
        if result != 0:
            error = ctypes.get_errno()
            raise OSError(error, '原子交换失败；原应用保持原位：' + os.strerror(error))
        os.utime(app, None)
        run(registrar, '-f', app)
        print(f'已更新图标：{app}')
        print(f'旧图、Info.plist 和完整应用备份：{backup}')
    print('当前播放器继续运行；正在运行的 Dock 图标可能在下次正常启动时刷新。')
finally:
    # Before the swap this is only the new disposable copy; afterwards this is
    # the old app, already safely archived above. No running process is stopped.
    for staging in staging_directories:
        shutil.rmtree(staging, ignore_errors=True)
PY
