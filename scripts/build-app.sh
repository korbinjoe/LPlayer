#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PALM_BUILD_ROOT="$ROOT"
export PALM_LICENSES_ONLY=0

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != '--licenses-only' ]; }; then
  echo '用法：scripts/build-app.sh [--licenses-only]' >&2
  exit 1
fi

# Package into a fresh directory on the same volume. Never overwrite an
# installed executable or library that a running player may still have mapped.
STAGING=''
cleanup() {
  if [ -n "$STAGING" ]; then
    rm -rf "$STAGING"
  fi
}
trap cleanup EXIT

cd "$ROOT"
if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists mpv; then
  echo '找不到 libmpv。请先运行：brew install mpv pkg-config' >&2
  exit 1
fi

if [ "${1:-}" = '--licenses-only' ]; then
  export PALM_LICENSES_ONLY=1
  APP="$ROOT/dist/LPlayer.app"
else
  if [ ! -f "$ROOT/Resources/LPlayer-icon.png" ]; then
    echo '找不到 Resources/LPlayer-icon.png。请先提供新的 LPlayer 图标原图。' >&2
    exit 1
  fi
  echo '正在构建 LPlayer…'
  swift build -c release --product LPlayer
  BIN_DIR="$(swift build -c release --show-bin-path)"
  mkdir -p "$ROOT/dist"
  STAGING="$(mktemp -d "$ROOT/dist/.lplayer-build-XXXXXX")"
  APP="$STAGING/LPlayer.app"
  CONTENTS="$APP/Contents"
  mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Frameworks" "$CONTENTS/Resources"
  cp "$BIN_DIR/LPlayer" "$CONTENTS/MacOS/LPlayer"
  chmod 755 "$CONTENTS/MacOS/LPlayer"
  if [ ! -f "$ROOT/Resources/LPlayer.icns" ] || [ "$ROOT/Resources/LPlayer-icon.png" -nt "$ROOT/Resources/LPlayer.icns" ] || [ "$ROOT/scripts/make-icon.sh" -nt "$ROOT/Resources/LPlayer.icns" ]; then
    "$ROOT/scripts/make-icon.sh"
  fi
  cp "$ROOT/Resources/LPlayer.icns" "$CONTENTS/Resources/LPlayer.icns"
  mkdir -p "$CONTENTS/Resources/Fonts"
  for filename in Manrope.ttf Manrope-OFL.txt Manrope-METADATA.pb; do
    cp "$ROOT/Resources/Fonts/$filename" "$CONTENTS/Resources/Fonts/$filename"
  done
  cp -R "$ROOT/Resources/Demo" "$CONTENTS/Resources/Demo"
fi
export PALM_APP_PATH="$APP"

# Only Mach-O libraries reachable from this executable are copied. No Homebrew
# package directories, configuration files, or user data enter the app bundle.
/usr/bin/python3 <<'PY'
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

root = Path(os.environ['PALM_BUILD_ROOT'])
contents = Path(os.environ['PALM_APP_PATH']) / 'Contents'
executable = contents / 'MacOS' / 'LPlayer'
frameworks = contents / 'Frameworks'
licenses_only = os.environ.get('PALM_LICENSES_ONLY') == '1'

def output(*args):
    return subprocess.check_output(args, text=True)

def dependencies(path):
    lines = output('/usr/bin/otool', '-L', str(path)).splitlines()[1:]
    return [line.strip().split(' (compatibility version', 1)[0] for line in lines]

def rpaths(path):
    lines = output('/usr/bin/otool', '-l', str(path)).splitlines()
    result = []
    for index, line in enumerate(lines):
        if line.strip() == 'cmd LC_RPATH':
            for following in lines[index + 1:index + 5]:
                if following.strip().startswith('path '):
                    result.append(following.strip()[5:].split(' (offset', 1)[0])
                    break
    return result

def expand(value, owner):
    return Path(value.replace('@loader_path', str(owner.parent)).replace('@executable_path', str(executable.parent)))

mpv_lib = Path(output('/usr/bin/env', 'pkg-config', '--variable=libdir', 'mpv').strip())
scan_root = (mpv_lib / 'libmpv.dylib').resolve() if licenses_only else executable
root_rpaths = rpaths(scan_root)

def resolve(reference, owner):
    if reference.startswith('/System/Library/') or reference.startswith('/usr/lib/'):
        return None
    if reference.startswith('@rpath/'):
        suffix = reference[len('@rpath/'):]
        candidates = [expand(path, owner) / suffix for path in rpaths(owner)]
        candidates += [expand(path, scan_root) / suffix for path in root_rpaths]
        candidates += [mpv_lib / suffix, Path('/opt/homebrew/lib') / suffix, Path('/usr/local/lib') / suffix]
    else:
        candidates = [expand(reference, owner)]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise RuntimeError(f'无法解析动态库 {reference}，引用方 {owner}')

sources = {scan_root: scan_root.name} if licenses_only else {}
edges = {}
queue = [scan_root]
names = {}
while queue:
    owner = queue.pop(0)
    if owner in edges:
        continue
    edges[owner] = []
    for reference in dependencies(owner):
        dependency = resolve(reference, owner)
        if dependency is None or dependency == owner:
            continue
        if dependency not in sources:
            filename = dependency.name
            if filename in names and names[filename] != dependency:
                digest = hashlib.sha256(str(dependency).encode()).hexdigest()[:8]
                filename = f'{dependency.stem}-{digest}{dependency.suffix}'
            names[filename] = dependency
            sources[dependency] = filename
            queue.append(dependency)
        edges[owner].append((reference, dependency))

license_source = root / 'Resources' / 'licenses'
license_target = license_source if licenses_only else contents / 'Resources' / 'licenses'
if not licenses_only:
    shutil.copytree(license_source, license_target, dirs_exist_ok=True)
license_target.mkdir(parents=True, exist_ok=True)
components_directory = license_target / 'components'
if components_directory.exists():
    shutil.rmtree(components_directory)
components_directory.mkdir()

components = {}
for source, bundled_name in sources.items():
    parts = source.parts
    if 'Cellar' not in parts:
        raise RuntimeError(f'缺少非 Homebrew 依赖的许可证元数据：{source}')
    index = parts.index('Cellar')
    keg = Path(*parts[:index + 3])
    components.setdefault(keg, []).append(bundled_name)

manifest = []
for keg, bundled_files in sorted(components.items(), key=lambda item: item[0].parent.name):
    name, installed_version = keg.parent.name, keg.name
    recipe_files = list((keg / '.brew').glob('*.rb'))
    if not recipe_files:
        raise RuntimeError(f'缺少 Homebrew 配方元数据：{name}')
    recipe_file = recipe_files[0]
    recipe = recipe_file.read_text(encoding='utf-8')
    declaration = re.search(r'^\s*license\s+(.+)$', recipe, re.MULTILINE)
    expression = declaration.group(1).split('#', 1)[0].strip() if declaration else 'UNKNOWN - review required'
    if declaration:
        balance = expression.count('[') + expression.count('{') - expression.count(']') - expression.count('}')
        for line in recipe[declaration.end():].splitlines():
            if balance <= 0:
                break
            cleaned = line.split('#', 1)[0].strip()
            expression += ' ' + cleaned
            balance += cleaned.count('[') + cleaned.count('{') - cleaned.count(']') - cleaned.count('}')
    homepage = re.search(r'^\s*homepage\s+"([^"]+)"', recipe, re.MULTILINE)
    urls = re.findall(r'^\s*url\s+"([^"]+)"', recipe, re.MULTILINE)
    checksum = re.search(r'^\s*sha256\s+"([^"]+)"', recipe, re.MULTILINE)
    component_directory = components_directory / name
    component_directory.mkdir()
    shutil.copy2(recipe_file, component_directory / 'Homebrew-Formula.rb')
    installed_licenses = []
    candidates = list(keg.iterdir())
    for directory in (keg / 'share', keg / 'licenses', keg / 'license'):
        if directory.is_dir():
            candidates.extend(directory.rglob('*'))
    for path in sorted(set(candidates)):
        basename = path.name.lower()
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 2 * 1024 * 1024:
            continue
        if not basename.startswith(('license', 'copying', 'copyright', 'notice', 'lgpl', 'gpl', 'ftl')):
            continue
        if path.suffix.lower() in ('.cfg', '.pc', '.rb', '.py', '.h', '.c', '.png', '.html'):
            continue
        try:
            path.read_text(encoding='utf-8')
        except (UnicodeError, OSError):
            continue
        relative = path.relative_to(keg)
        destination = component_directory / 'installed' / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        installed_licenses.append(str(relative))
    entry = {
        'name': name,
        'installed_version': installed_version,
        'homebrew_license_declaration': expression,
        'homepage': homepage.group(1) if homepage else None,
        'source_archive_url': urls[0] if urls else None,
        'source_archive_sha256': checksum.group(1) if checksum else None,
        'recipe_urls_including_patches': urls,
        'bundled_files': sorted(bundled_files),
        'installed_license_files': installed_licenses,
        'license_text_review_required': not installed_licenses,
    }
    manifest.append(entry)

# These exact installed-build reports document the GPL-enabled FFmpeg variant.
# No media files, private config, environment, or full receipts are collected.
reports = [('ffmpeg', ['-L'], 'ffmpeg-build-license.txt'),
           ('mpv', ['--no-config', '--version'], 'mpv-build-version.txt')]
for formula, arguments, filename in reports:
    matching = next((keg for keg in components if keg.parent.name == formula), None)
    if matching:
        command = matching / 'bin' / formula
        report = subprocess.run([str(command), *arguments], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, check=True).stdout
        (license_target / filename).write_text(report, encoding='utf-8')

(license_target / 'manifest.json').write_text(json.dumps({
    'scope': 'Exact transitive non-system Mach-O dependency closure of the current local Homebrew build',
    'license_status': 'Local development snapshot. Not a complete corresponding-source distribution or compliance certification.',
    'components': manifest,
}, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

lines = ['# 当前构建的第三方组件', '',
    '此清单从实际依赖图和已安装的 Homebrew 配方生成；配方及可找到的许可证原文在 components/。',
    '版本号包含 Homebrew revision。源码 URL、补丁 URL 和配方对应当前安装版本；本目录没有打包完整对应源码。', '',
    '本机 FFmpeg 的 `ffmpeg -L` 输出与配置已保存为 ffmpeg-build-license.txt；当前构建启用 GPL 与 version3，报告为 GPL-3.0-or-later。',
    'mpv 配方同时声明 GPL-2.0-or-later 与 LGPL-2.1-or-later。本产物包含 GPL 组件，不应描述为仅使用 LGPL 的播放器构建。', '',
    '| 组件 | 安装版本 | Homebrew 许可声明 | 官网 | 对应源码 |',
    '| --- | --- | --- | --- | --- |']
for entry in manifest:
    homepage = f"[官网]({entry['homepage']})" if entry['homepage'] else '未记录'
    archive = f"[源码]({entry['source_archive_url']})" if entry['source_archive_url'] else '未记录'
    lines.append(f"| {entry['name']} | {entry['installed_version']} | `{entry['homebrew_license_declaration']}` | {homepage} | {archive} |")
missing = [entry['name'] for entry in manifest if entry['license_text_review_required']]
lines += ['', '## 待发布前核对', '',
    '所带二进制的对应源码、配方补丁、构建说明、许可相容性及 LPlayer 自身的发行授权仍需在正式分发前处理。本清单和本机签名不表示已满足全部发行义务。',
    '有些软件的概述文件还会引用源代码树内的其他许可；复制概述文件也不代表许可文本已完整。', '',
    '未在安装目录找到许可证原文的组件：' + ('、'.join(missing) if missing else '无') + '。请按配方所列源码核对。', '']
(license_target / 'THIRD_PARTY.md').write_text('\n'.join(lines), encoding='utf-8')
print(f'已记录 {len(manifest)} 个组件的版本、许可元数据、源码 URL 与本机许可文本。')
if licenses_only:
    print(f'许可证资源已更新：{license_target}')
    raise SystemExit(0)

# Replace just our Frameworks directory so removed dependencies cannot linger.
if frameworks.exists():
    shutil.rmtree(frameworks)
frameworks.mkdir()
for source, filename in sources.items():
    target = frameworks / filename
    shutil.copy2(source, target)
    target.chmod(0o755)

for source, linked_dependencies in edges.items():
    target = executable if source == executable else frameworks / sources[source]
    # Preserve the current LC_CODE_SIGNATURE layout while editing load commands.
    # Removing the signature first can leave newer Homebrew Mach-O __LINKEDIT
    # segments in a layout install_name_tool rejects. Re-sign after all edits.
    changes = ['/usr/bin/install_name_tool']
    if source != executable:
        changes.extend(['-id', '@rpath/' + sources[source]])
    for old_reference, dependency in linked_dependencies:
        new_reference = ('@executable_path/../Frameworks/' if source == executable else '@loader_path/') + sources[dependency]
        changes.extend(['-change', old_reference, new_reference])
    if len(changes) > 1:
        subprocess.run([*changes, str(target)], check=True)
    # Reject accidentally retained external Homebrew dependencies.
    external = [dep for dep in dependencies(target) if dep.startswith(('/opt/homebrew/', '/usr/local/'))]
    if external:
        raise RuntimeError(f'打包后仍有外部依赖：{target}: {external}')

info = {
    'CFBundleName': 'LPlayer',
    'CFBundleDisplayName': 'LPlayer',
    'CFBundleIconFile': 'LPlayer.icns',
    'CFBundleExecutable': 'LPlayer',
    'CFBundleIdentifier': 'dev.joebon.PalmPlayer',
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '20',
    'CFBundleShortVersionString': '0.10.0',
    'CFBundleDevelopmentRegion': 'en',
    'CFBundleLocalizations': ['en', 'zh-Hans'],
    'LSMinimumSystemVersion': '13.0',
    'LSUIElement': False,
    'NSHighResolutionCapable': True,
    'NSPrincipalClass': 'NSApplication',
    'NSSupportsAutomaticGraphicsSwitching': True,
    'CFBundleDocumentTypes': [{
        'CFBundleTypeName': 'Video',
        'CFBundleTypeRole': 'Viewer',
        'LSHandlerRank': 'Alternate',
        'LSItemContentTypes': ['public.movie', 'public.video', 'public.mpeg-4', 'com.apple.quicktime-movie'],
        'CFBundleTypeExtensions': ['mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'mpg', 'mpeg', 'ts', 'm2ts', 'flv', 'wmv', 'vob'],
    }],
}
with (contents / 'Info.plist').open('wb') as handle:
    plistlib.dump(info, handle, sort_keys=False)

total = sum((frameworks / name).stat().st_size for name in sources.values())
print(f'已打包 {len(sources)} 个动态库，合计 {total / 1024 / 1024:.1f} MiB。')
PY

if [ "$PALM_LICENSES_ONLY" = '1' ]; then
  exit 0
fi

# A local ad-hoc signature allows changed embedded libraries to load on Apple
# Silicon. This is not Developer ID signing or notarization for distribution.
# Framework executables (for example a Python.framework binary) need signing
# too, even when their flattened filename has no .dylib suffix.
for library in "$CONTENTS"/Frameworks/*; do
  [ -f "$library" ] || continue
  /usr/bin/codesign --force --sign - "$library"
done
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/plutil -lint "$CONTENTS/Info.plist"
"$ROOT/scripts/install-app.sh" "$APP"
