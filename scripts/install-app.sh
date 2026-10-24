#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -ne 1 ]; then
  echo '用法：scripts/install-app.sh <已签名的 LPlayer.app>' >&2
  exit 1
fi

export LPLAYER_INSTALL_ROOT="$ROOT"
export LPLAYER_STAGED_APP="$1"
/usr/bin/python3 <<'PY'
import ctypes
import datetime
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

root = Path(os.environ['LPLAYER_INSTALL_ROOT'])
app = root / 'dist' / 'LPlayer.app'
staged_app = Path(os.environ['LPLAYER_STAGED_APP']).resolve()

def run(*arguments):
    subprocess.run([str(argument) for argument in arguments], check=True)

if not staged_app.is_dir() or staged_app == app:
    raise RuntimeError('需要独立的已构建应用；不会就地修改现有应用。')
if staged_app.stat().st_dev != app.parent.stat().st_dev:
    raise RuntimeError('新应用必须与 dist 位于同一磁盘，才能原子安装。')
with (staged_app / 'Contents' / 'Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
if info.get('CFBundleIdentifier') != 'dev.joebon.PalmPlayer':
    raise RuntimeError('应用标识不匹配，未更新现有应用。')
if info.get('CFBundleExecutable') != 'LPlayer' or info.get('CFBundleIconFile') != 'LPlayer.icns':
    raise RuntimeError('应用入口或图标资源不匹配，未更新现有应用。')
if not os.access(staged_app / 'Contents' / 'MacOS' / 'LPlayer', os.X_OK):
    raise RuntimeError('新应用缺少可执行的 LPlayer 入口。')
if not (staged_app / 'Contents' / 'Resources' / 'LPlayer.icns').is_file():
    raise RuntimeError('新应用缺少 LPlayer 图标。')
run('/usr/bin/codesign', '--verify', '--deep', '--strict', staged_app)

backup = None
if app.exists():
    with (app / 'Contents' / 'Info.plist').open('rb') as handle:
        previous_info = plistlib.load(handle)
    if previous_info.get('CFBundleIdentifier') != info['CFBundleIdentifier']:
        raise RuntimeError('现有应用标识不匹配，未替换。')
    backup_root = root / 'artifacts' / 'app-backup'
    backup_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = Path(tempfile.mkdtemp(prefix=stamp + '-', dir=backup_root))
    archive = backup / 'LPlayer-previous.app.zip'
    # A ZIP preserves rollback without leaving another registerable .app copy.
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    with zipfile.ZipFile(archive) as handle:
        bad_member = handle.testzip()
    if bad_member:
        raise RuntimeError(f'旧应用备份校验失败：{bad_member}')
    (backup / 'manifest.json').write_text(json.dumps({
        'application': str(app),
        'previous_version': previous_info.get('CFBundleShortVersionString'),
        'installed_version': info.get('CFBundleShortVersionString'),
        'backup_archive': archive.name,
    }, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

    # Darwin RENAME_SWAP atomically exchanges directory entries. The old
    # executable and libraries retain their inodes for the live player process.
    system = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    rename_swap = system.renamex_np
    rename_swap.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename_swap.restype = ctypes.c_int
    if rename_swap(os.fsencode(staged_app), os.fsencode(app), 0x00000002) != 0:
        error = ctypes.get_errno()
        raise OSError(error, '原子安装失败；原应用保持原位：' + os.strerror(error))
    # The caller owns the staging directory and removes the swapped-out copy.
else:
    os.rename(staged_app, app)

os.utime(app, None)
registrar = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
registration = subprocess.run([registrar, '-f', str(app)], check=False)
if registration.returncode:
    print('应用已安装；LaunchServices 注册暂未刷新，将在下次正常打开时重试。')
print(f'已安装 LPlayer {info["CFBundleShortVersionString"]}：{app}')
if backup:
    print(f'上一版本备份：{backup}')
print('当前播放器进程保持运行；新版本将在下次正常启动时生效。')
PY
