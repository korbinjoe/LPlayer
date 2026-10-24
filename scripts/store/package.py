#!/usr/bin/env python3
"""Bundle only audited dependency bytes, then sign a separate sandbox app."""
import ctypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

root = Path(os.environ['LPLAYER_PACKAGE_ROOT'])
prefix = Path(os.environ['LPLAYER_PACKAGE_PREFIX']).resolve()
binary = Path(os.environ['LPLAYER_PACKAGE_BINARY'])
staging = Path(os.environ['LPLAYER_PACKAGE_STAGING'])
release = os.environ['LPLAYER_PACKAGE_MODE'] == '--release'
name = 'LPlayer App Store' if release else 'LPlayer Sandbox'
identifier = 'dev.joebon.PalmPlayer' if release else 'dev.joebon.LPlayer.Sandbox'
app = staging / (name + '.app')
contents = app / 'Contents'
frameworks = contents / 'Frameworks'
resources = contents / 'Resources'
executable = contents / 'MacOS' / 'LPlayer'
metadata = prefix / 'share' / 'lplayer-deps'

def run(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(stream.read()).hexdigest()

manifest = json.loads((metadata / 'manifest.json').read_text())
audited = {str(Path(entry['path']).resolve()): entry for entry in manifest['libraries']}
if not audited:
    raise RuntimeError('受控依赖清单为空。')

for directory in (executable.parent, frameworks, resources):
    directory.mkdir(parents=True, exist_ok=True)
shutil.copy2(binary, executable)
shutil.copy2(root / 'Resources' / 'LPlayer.icns', resources / 'LPlayer.icns')
fonts = resources / 'Fonts'
fonts.mkdir()
for filename in ('Manrope.ttf', 'Manrope-OFL.txt', 'Manrope-METADATA.pb'):
    shutil.copy2(root / 'Resources' / 'Fonts' / filename, fonts / filename)
shutil.copytree(root / 'Resources' / 'Demo', resources / 'Demo')
for filename in ('PrivacyInfo.xcprivacy', 'PrivacyPolicy.en.html', 'PrivacyPolicy.zh-Hans.html'):
    shutil.copy2(root / 'Resources' / filename, resources / filename)
# Keep source archives in the adjacent reviewable source bundle; the app carries
# exact notices, build configs and a manifest that identifies those archives.
for directory in ('licenses', 'build-configs'):
    shutil.copytree(metadata / directory, resources / 'licenses' / directory)
shutil.copy2(metadata / 'manifest.json', resources / 'licenses' / 'dependency-manifest.json')

def dependencies(path):
    return [line.strip().split(' (compatibility version', 1)[0]
            for line in run('/usr/bin/otool', '-L', path).splitlines()[1:]]

def rpaths(path):
    lines = run('/usr/bin/otool', '-l', path).splitlines()
    return [lines[i + 2].strip().split(' (offset', 1)[0][5:]
            for i, line in enumerate(lines) if line.strip() == 'cmd LC_RPATH']

def minimum_os(path):
    versions = []
    command = ''
    for line in run('/usr/bin/otool', '-l', path).splitlines():
        words = line.strip().split()
        if words[:1] == ['cmd']:
            command = words[1]
        if (command == 'LC_BUILD_VERSION' and words[:1] == ['minos']) or (command == 'LC_VERSION_MIN_MACOSX' and words[:1] == ['version']):
            versions.append(tuple(int(part) for part in words[1].split('.')))
    return max(versions, default=(13, 0))

def expand(reference, owner):
    return Path(reference.replace('@loader_path', str(owner.parent))
                .replace('@executable_path', str(binary.parent)))

def resolve(reference, owner):
    if reference.startswith(('/System/Library/', '/usr/lib/')):
        return None
    candidates = [expand(reference, owner)]
    if reference.startswith('@rpath/'):
        candidates = [expand(p, owner) / reference[7:] for p in rpaths(owner)]
        candidates += [expand(p, binary) / reference[7:] for p in rpaths(binary)]
        candidates += [prefix / 'lib' / reference[7:]]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise RuntimeError(f'无法解析依赖 {reference}，引用方 {owner}')

edges, names, sources = {}, {}, {}
queue = [binary]
while queue:
    owner = queue.pop(0)
    if owner in edges:
        continue
    edges[owner] = []
    for reference in dependencies(owner):
        library = resolve(reference, owner)
        if library is None or library == owner:
            continue
        entry = audited.get(str(library))
        if not entry or digest(library) != entry['sha256']:
            raise RuntimeError(f'未审计或已改变的动态库：{library}')
        if 'GPL' in entry['license'] and 'LGPL' not in entry['license']:
            raise RuntimeError(f'拒绝 GPL-only 依赖：{library}')
        if library.name in names and names[library.name] != library:
            raise RuntimeError(f'动态库重名：{library}')
        edges[owner].append((reference, library))
        if library not in sources:
            sources[library] = library.name
            names[library.name] = library
            queue.append(library)

for source, filename in sources.items():
    shutil.copy2(source, frameworks / filename)
for owner, links in edges.items():
    target = executable if owner == binary else frameworks / sources[owner]
    arguments = ['/usr/bin/install_name_tool']
    if owner != binary:
        arguments += ['-id', '@rpath/' + sources[owner]]
    for reference, dependency in links:
        replacement = ('@executable_path/../Frameworks/' if owner == binary else '@loader_path/') + sources[dependency]
        arguments += ['-change', reference, replacement]
    # Remove SDK/Homebrew build paths so the delivered app is self-contained.
    for path in rpaths(target):
        if path.startswith(('/opt/', '/usr/local/', str(root))):
            arguments += ['-delete_rpath', path]
    if len(arguments) > 1:
        run(*arguments, target)
    for reference in dependencies(target):
        if not reference.startswith(('/System/Library/', '/usr/lib/', '@loader_path/', '@executable_path/', '@rpath/')):
            raise RuntimeError(f'包内仍有外部依赖：{target}: {reference}')

required_os = max([(13, 0), minimum_os(binary), *(minimum_os(source) for source in sources)])
required_os_string = '.'.join(str(part) for part in required_os)
info = dict(CFBundleName=name, CFBundleDisplayName=name, CFBundleIdentifier=identifier,
            CFBundleExecutable='LPlayer', CFBundleIconFile='LPlayer.icns', CFBundlePackageType='APPL',
            CFBundleShortVersionString='0.10.0', CFBundleVersion='20',
            CFBundleDevelopmentRegion='en', CFBundleLocalizations=['en', 'zh-Hans'],
            LSMinimumSystemVersion=required_os_string, LSUIElement=False, NSHighResolutionCapable=True,
            NSPrincipalClass='NSApplication', NSSupportsAutomaticGraphicsSwitching=True,
            LSApplicationCategoryType='public.app-category.video',
            NSHumanReadableCopyright='LPlayer. Third-party notices are included in Resources/licenses.',
            CFBundleDocumentTypes=[dict(CFBundleTypeName='Video', CFBundleTypeRole='Viewer',
                LSHandlerRank='Alternate',
                LSItemContentTypes=['public.movie', 'public.video', 'public.mpeg-4', 'com.apple.quicktime-movie'],
                CFBundleTypeExtensions=['mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'mpg', 'mpeg',
                                        'ts', 'm2ts', 'flv', 'wmv', 'vob'])])
with (contents / 'Info.plist').open('wb') as stream:
    plistlib.dump(info, stream, sort_keys=False)
entitlements_path = root / 'Resources' / 'Store.entitlements'
if release:
    profile_path = Path(os.environ['LPLAYER_APP_PROVISION_PROFILE'])
    profile = plistlib.loads(subprocess.check_output(['/usr/bin/security', 'cms', '-D', '-i', str(profile_path)]))
    profile_entitlements = profile['Entitlements']
    if not set(profile.get('Platform', [])).intersection({'OSX', 'macOS'}):
        raise RuntimeError('Profile 不支持 macOS。')
    if profile.get('ProvisionsAllDevices'):
        raise RuntimeError('不能使用 Developer ID profile 作为 App Store profile。')
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    teams = profile.get('TeamIdentifier', [])
    app_identifier = profile_entitlements.get('com.apple.application-identifier', '')
    if not prefixes or not teams or app_identifier != f'{prefixes[0]}.{identifier}':
        raise RuntimeError('Profile 的显式 App ID 与正式应用 bundle ID 不匹配。')
    if profile_entitlements.get('get-task-allow') or profile_entitlements.get('com.apple.security.get-task-allow'):
        raise RuntimeError('不能使用允许调试的 development profile 发行。')
    if profile.get('ExpirationDate', datetime.datetime.min) <= datetime.datetime.utcnow():
        raise RuntimeError('Provisioning profile 已过期。')
    with entitlements_path.open('rb') as stream:
        distribution_entitlements = plistlib.load(stream)
    distribution_entitlements['com.apple.application-identifier'] = app_identifier
    distribution_entitlements['com.apple.developer.team-identifier'] = teams[0]
    entitlements_path = staging / 'Distribution.entitlements'
    with entitlements_path.open('wb') as stream:
        plistlib.dump(distribution_entitlements, stream)
    shutil.copy2(profile_path, contents / 'embedded.provisionprofile')
identity = os.environ.get('LPLAYER_APP_SIGN_IDENTITY', '-') if release else '-'
for library in sorted(frameworks.iterdir()):
    run('/usr/bin/codesign', '--force', '--sign', identity, library)
run('/usr/bin/codesign', '--force', '--sign', identity, '--entitlements', entitlements_path, app)
run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
if release:
    signing = subprocess.run(['/usr/bin/codesign', '-dvv', str(app)], check=True, capture_output=True, text=True).stderr
    authorities = [line.removeprefix('Authority=') for line in signing.splitlines() if line.startswith('Authority=')]
    if not authorities or not authorities[0].startswith(('Apple Distribution:', '3rd Party Mac Developer Application:', 'Mac App Distribution:')):
        raise RuntimeError('签名证书不是 Mac App Store 应用分发证书。')
    if f'TeamIdentifier={teams[0]}' not in signing.splitlines():
        raise RuntimeError('签名团队与 provisioning profile 不匹配。')
    certificate_prefix = str(staging / 'signing-certificate-')
    subprocess.run(['/usr/bin/codesign', '-d', '--extract-certificates', certificate_prefix, str(app)], check=True, capture_output=True)
    leaf = Path(certificate_prefix + '0').read_bytes()
    if leaf not in profile.get('DeveloperCertificates', []):
        raise RuntimeError('实际签名证书不在 provisioning profile 的允许列表中。')
with tempfile.NamedTemporaryFile() as entitlement_file:
    subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', entitlement_file.name, '--xml', str(app)], check=True, capture_output=True)
    entitlements = plistlib.loads(Path(entitlement_file.name).read_bytes())
    if entitlements.get('com.apple.security.app-sandbox') is not True:
        raise RuntimeError('沙盒 entitlement 未写入签名。')
    if entitlements.get('com.apple.security.network.client'):
        raise RuntimeError('本地播放器不应申请网络访问。')

source_bundle = root / 'dist' / f'LPlayer-{info["CFBundleShortVersionString"]}-dependency-sources.zip'
source_temp = staging / source_bundle.name
with zipfile.ZipFile(source_temp, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(metadata.rglob('*')):
        if path.is_file():
            archive.write(path, str(Path('lplayer-deps') / path.relative_to(metadata)))
    archive.write(root / 'scripts' / 'build-store-deps.sh', 'scripts/build-store-deps.sh')
    archive.write(root / 'scripts' / 'store' / 'package.py', 'scripts/store/package.py')
    archive.write(root / 'Dependencies' / 'store' / 'README.md', 'Dependencies/store/README.md')
os.replace(source_temp, source_bundle)

destination = root / 'dist' / app.name
if destination.exists():
    # Preserve the running preview's inodes while installing a new build.
    system = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    swap = system.renamex_np
    swap.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    swap.restype = ctypes.c_int
    if swap(os.fsencode(app), os.fsencode(destination), 2):
        raise OSError(ctypes.get_errno(), '无法原子更新沙盒预览版')
else:
    os.rename(app, destination)
print(f'已构建：{destination}')
print(f'对应源码与构建材料：{source_bundle}')
print(f'动态库：{len(sources)}；签名：{"商店发行身份" if release else "本机 ad-hoc"}；沙盒：已启用。')
print(f'最低 macOS（按实际二进制计算）：{required_os_string}；架构：arm64。')
