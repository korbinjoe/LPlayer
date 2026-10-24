#!/usr/bin/env bash
# Controlled LGPL 2.1-compatible playback dependencies for the sandbox build.
# This never installs or replaces the development player's Homebrew libraries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${LPLAYER_DEPS_ROOT:-$ROOT/.build/store-deps}"
PREFIX="${LPLAYER_DEPS_PREFIX:-$WORK/prefix}"
JOBS="${LPLAYER_DEPS_JOBS:-2}"
case "$JOBS" in 1|2|3|4) ;; *) echo 'LPLAYER_DEPS_JOBS must be 1–4' >&2; exit 1;; esac
MODE="${1:-build}"
case "$MODE" in build|--audit-only) ;; *) echo 'Usage: scripts/build-store-deps.sh [--audit-only]' >&2; exit 1;; esac
mkdir -p "$WORK"/{downloads,src,build,logs} "$PREFIX"
export LPLAYER_DEPS_WORK="$WORK" LPLAYER_DEPS_PREFIX="$PREFIX" LPLAYER_SOURCE_ROOT="$ROOT"
export MACOSX_DEPLOYMENT_TARGET=13.0
export PATH="$WORK/venv/bin:$PATH"
# Prefix must win: Homebrew's mpv/FFmpeg are deliberately never inputs.
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"

fetch() {
  local name="$1" url="$2" checksum="$3"
  if [ ! -f "$WORK/downloads/$name" ]; then
    curl -L --fail --retry 2 --max-time 180 --silent --show-error "$url" -o "$WORK/downloads/$name.part"
    mv "$WORK/downloads/$name.part" "$WORK/downloads/$name"
  fi
  local actual
  actual="$(shasum -a 256 "$WORK/downloads/$name" | cut -d' ' -f1)"
  if [ "$actual" != "$checksum" ]; then echo "SHA256 mismatch: $name" >&2; exit 1; fi
}

fetch ffmpeg-8.0.1.tar.xz https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz 05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41
fetch mpv-0.41.0.tar.gz https://github.com/mpv-player/mpv/archive/refs/tags/v0.41.0.tar.gz ee21092a5ee427353392360929dc64645c54479aefdb5babc5cfbb5fad626209
fetch mpv-c5d391adba7bd024954d0df1e0405f5749f4d4ca.patch 'https://github.com/mpv-player/mpv/commit/c5d391adba7bd024954d0df1e0405f5749f4d4ca.patch?full_index=1' 769b218df220738cc1cf9f81cf696c16518c5dfe56a5ef028e33b22536e0e924
fetch libplacebo-v7.360.1.tar.bz2 https://code.videolan.org/videolan/libplacebo/-/archive/v7.360.1/libplacebo-v7.360.1.tar.bz2 937aa5eeea596798b3274d362de2e3bd32bc537a66d149dd85043349c74dffb6
fetch fast_float-8.0.2.tar.gz https://github.com/fastfloat/fast_float/archive/refs/tags/v8.0.2.tar.gz e14a33089712b681d74d94e2a11362643bd7d769ae8f7e7caefe955f57f7eacd
fetch harfbuzz-14.6.0.tar.xz https://github.com/harfbuzz/harfbuzz/releases/download/14.6.0/harfbuzz-14.6.0.tar.xz d07a007327277708a2a73ae437887cdbaf282937f6d03ca5467723e9099af586
fetch libass-0.17.5.tar.xz https://github.com/libass/libass/releases/download/0.17.5/libass-0.17.5.tar.xz 2dca25c0e0c837ddf00b52011b3f82cac1e4ddd3ad018227806b0c2288864acc
fetch jinja2-3.1.6.tar.gz https://files.pythonhosted.org/packages/df/bf/f7da0350254c0ed7c72f3e33cef02e048281fec7ecec5f032d4aac52226b/jinja2-3.1.6.tar.gz 0137fb05990d35f1275a587e9aee6d56da821fc83491a0fb838183be43f66d6d
fetch markupsafe-3.0.3.tar.gz https://files.pythonhosted.org/packages/7e/99/7690b6d4034fffd95959cbe0c02de8deb3098cc577c67bb6a24fe5d7caa7/markupsafe-3.0.3.tar.gz 722695808f4b6457b320fdc131280796bdceb04ab50fe1795cd540799ebe1698

if [ "$MODE" = build ]; then
  [ -x "$WORK/venv/bin/python3" ] || /usr/bin/python3 -m venv "$WORK/venv"
  "$WORK/venv/bin/pip" install --disable-pip-version-check meson==1.9.2 ninja==1.13.0 Jinja2==3.1.6 MarkupSafe==3.0.3 > "$WORK/logs/build-tools.log" 2>&1
  for archive in ffmpeg-8.0.1.tar.xz mpv-0.41.0.tar.gz libplacebo-v7.360.1.tar.bz2 fast_float-8.0.2.tar.gz harfbuzz-14.6.0.tar.xz libass-0.17.5.tar.xz; do
    case "$archive" in libplacebo*) dir=libplacebo-v7.360.1;; *) dir="${archive%.tar.*}";; esac
    [ -d "$WORK/src/$dir" ] || tar -xf "$WORK/downloads/$archive" -C "$WORK/src"
  done
  if ! patch --dry-run --reverse -d "$WORK/src/mpv-0.41.0" -p1 < "$WORK/downloads/mpv-c5d391adba7bd024954d0df1e0405f5749f4d4ca.patch" >/dev/null 2>&1; then
    patch -d "$WORK/src/mpv-0.41.0" -p1 < "$WORK/downloads/mpv-c5d391adba7bd024954d0df1e0405f5749f4d4ca.patch"
  fi
  [ -d "$WORK/src/libplacebo-v7.360.1/3rdparty/fast_float/include" ] || cp -R "$WORK/src/fast_float-8.0.2/include" "$WORK/src/libplacebo-v7.360.1/3rdparty/fast_float/"
  mkdir -p "$WORK/build/ffmpeg"
  (
    cd "$WORK/build/ffmpeg"
    "$WORK/src/ffmpeg-8.0.1/configure" --prefix="$PREFIX" --cc=clang --enable-shared --disable-static --enable-pic \
      --disable-gpl --disable-nonfree --disable-version3 --disable-autodetect --disable-network --disable-doc --disable-debug \
      --disable-ffplay --disable-avdevice --disable-devices --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-bzlib \
      --enable-pthreads --extra-cflags=-mmacosx-version-min=13.0 --extra-ldflags=-mmacosx-version-min=13.0 > "$WORK/logs/ffmpeg-configure.log" 2>&1
    make -j"$JOBS" > "$WORK/logs/ffmpeg-build.log" 2>&1
    make install > "$WORK/logs/ffmpeg-install.log" 2>&1
  )
  setup_meson() {
    local component="$1" source="$2"; shift 2
    local reconfigure=()
    [ ! -f "$WORK/build/$component/build.ninja" ] || reconfigure=(--reconfigure)
    meson setup "${reconfigure[@]}" "$WORK/build/$component" "$WORK/src/$source" --prefix="$PREFIX" --libdir=lib --buildtype=release \
      -Ddefault_library=shared -Dauto_features=disabled "$@" > "$WORK/logs/$component-configure.log" 2>&1
    meson compile -C "$WORK/build/$component" -j"$JOBS" > "$WORK/logs/$component-build.log" 2>&1
    meson install -C "$WORK/build/$component" > "$WORK/logs/$component-install.log" 2>&1
  }
  # libmpv's classic OpenGL API uses mpv's own ra_gl implementation. Only
  # libplacebo's CPU shader helpers are needed, so omit its GPU backends and
  # the generated GLAD/Khronos code those backends would otherwise incorporate.
  setup_meson libplacebo libplacebo-v7.360.1 -Dopengl=disabled -Dvulkan=disabled -Dshaderc=disabled -Dglslang=disabled -Dlcms=disabled -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false
  setup_meson harfbuzz harfbuzz-14.6.0 -Dfreetype=enabled -Dcoretext=enabled -Dglib=disabled -Dgobject=disabled -Dgraphite2=disabled \
    -Dsubset=disabled -Draster=disabled -Dvector=disabled -Dgpu=disabled -Dtests=disabled -Ddocs=disabled -Dutilities=disabled
  mkdir -p "$WORK/build/libass"
  (
    cd "$WORK/build/libass"
    CFLAGS=-mmacosx-version-min=13.0 LDFLAGS=-mmacosx-version-min=13.0 "$WORK/src/libass-0.17.5/configure" --prefix="$PREFIX" \
      --disable-static --enable-shared --disable-fontconfig --enable-coretext --disable-test --disable-profile > "$WORK/logs/libass-configure.log" 2>&1
    make -j"$JOBS" > "$WORK/logs/libass-build.log" 2>&1
    make install > "$WORK/logs/libass-install.log" 2>&1
  )
  setup_meson mpv mpv-0.41.0 -Dgpl=false -Dcplayer=false -Dlibmpv=true -Dbuild-date=false -Dlua=disabled -Drubberband=disabled \
    -Dcocoa=enabled -Dcoreaudio=enabled -Dgl=enabled -Dgl-cocoa=enabled -Dplain-gl=enabled -Dvideotoolbox-gl=enabled -Dswift-build=enabled \
    -Diconv=enabled -Dzlib=enabled -Dvector=enabled -Djavascript=disabled -Dlibarchive=disabled -Dlibbluray=disabled \
    -Dlibavdevice=disabled -Dvulkan=disabled -Dshaderc=disabled -Dlcms2=disabled -Dvapoursynth=disabled -Dzimg=disabled \
    -Duchardet=disabled -Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled
fi

# The audit rejects every non-system dylib outside an explicit reviewed list.
# It also fetches and verifies actual source archives for reused font libraries.
/usr/bin/python3 <<'PY'
import hashlib, json, os, pathlib, re, shutil, subprocess, tarfile
from urllib.parse import urlparse
P = pathlib.Path
work, prefix, root = (P(os.environ[k]) for k in ('LPLAYER_DEPS_WORK', 'LPLAYER_DEPS_PREFIX', 'LPLAYER_SOURCE_ROOT'))
metadata = prefix / 'share/lplayer-deps'
if metadata.exists(): shutil.rmtree(metadata)
for sub in ('licenses', 'build-configs', 'sources'):
    (metadata/sub).mkdir(parents=True, exist_ok=True)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def output(*args): return subprocess.check_output(args, text=True)
def rpaths(path):
    lines=output('/usr/bin/otool','-l',str(path)).splitlines(); result=[]
    for i,line in enumerate(lines):
        if line.strip()=='cmd LC_RPATH':
            for following in lines[i+1:i+5]:
                if following.strip().startswith('path '):
                    result.append(following.strip()[5:].split(' (offset')[0]);break
    return result
def copy(src, dest):
    dest.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dest)
specs = {
 'ffmpeg': ('8.0.1', 'LGPL-2.1-or-later', 'ffmpeg-8.0.1.tar.xz'),
 'mpv': ('0.41.0+c5d391adba7b', 'LGPL-2.1-or-later', 'mpv-0.41.0.tar.gz'),
 'libplacebo': ('7.360.1', 'LGPL-2.1-or-later', 'libplacebo-v7.360.1.tar.bz2'),
 'harfbuzz': ('14.6.0', 'MIT', 'harfbuzz-14.6.0.tar.xz'),
 'libass': ('0.17.5', 'ISC', 'libass-0.17.5.tar.xz'),
 'freetype': ('2.15.0', 'FTL', 'freetype-2.15.0.tar.xz'),
 'fribidi': ('1.0.17', 'LGPL-2.1-or-later', 'fribidi-1.0.17.tar.xz'),
 'libunibreak': ('8.0', 'Zlib', 'libunibreak-8.0.tar.gz'),
 'libpng': ('1.6.59', 'libpng-2.0', 'libpng-1.6.59.tar.xz'),
 'brotli': ('1.2.0', 'MIT', 'brotli-1.2.0.tar.gz'),
 'fast_float': ('8.0.2', 'MIT', 'fast_float-8.0.2.tar.gz'),
 'jinja2': ('3.1.6', 'BSD-3-Clause', 'jinja2-3.1.6.tar.gz'),
 'markupsafe': ('3.0.3', 'BSD-3-Clause', 'markupsafe-3.0.3.tar.gz'),
}
# These installed libraries have no source patches. Their full exact formulae
# (including inreplace operations and build switches) are retained below.
external = {'freetype','fribidi','libunibreak','libpng','brotli'}
queue=[(prefix/'lib/libmpv.2.dylib').resolve()]; seen=set(); libraries=[]; components={}
while queue:
    path=queue.pop(0)
    if path in seen: continue
    if not path.is_file(): raise RuntimeError(f'Missing dependency: {path}')
    seen.add(path)
    if path.is_relative_to(prefix):
        name=path.name
        component=('mpv' if name.startswith('libmpv.') else 'ffmpeg' if name.startswith(('libav','libsw'))
                   else 'libplacebo' if name.startswith('libplacebo.') else 'harfbuzz' if name.startswith('libharfbuzz.')
                   else 'libass' if name.startswith('libass.') else None)
    elif 'Cellar' in path.parts:
        i=path.parts.index('Cellar'); component=path.parts[i+1]; installed=path.parts[i+2]
        if component not in external or specs[component][0] != installed:
            raise RuntimeError(f'Unreviewed Homebrew dependency/version: {path}')
    else: component=None
    if component not in specs: raise RuntimeError(f'Unreviewed dependency: {path}')
    version, license_id, archive=specs[component]
    libraries.append(dict(path=str(path), component=component, name=path.name, sha256=sha(path), license=license_id))
    entry=components.setdefault(component,dict(name=component, version=version, license=license_id, source_archives=[], bundled_libraries=[]))
    entry['bundled_libraries'].append(path.name)
    if component in external:
        i=path.parts.index('Cellar'); keg=P(*path.parts[:i+3]); recipe=next((keg/'.brew').glob('*.rb'))
        text=recipe.read_text(); url=re.search(r'^\s*url "([^"]+)"',text,re.M)[1]; checksum=re.search(r'^\s*sha256 "([^"]+)"',text,re.M)[1]
        if re.search(r'^\s*patch\b', text, re.M): raise RuntimeError(f'Unrecorded external patch: {component}')
        source=work/'downloads'/archive
        if not source.exists():
            subprocess.run(['curl','-L','--fail','--retry','2','--max-time','180','--silent','--show-error',url,'-o',str(source)],check=True)
        if sha(source)!=checksum: raise RuntimeError(f'Source checksum mismatch: {component}')
        copy(recipe, metadata/'build-configs'/component/'Homebrew-Formula.rb')
        receipt=json.loads((keg/'INSTALL_RECEIPT.json').read_text())
        # Preserve build provenance without machine-local paths or timestamps.
        summary={k:receipt[k] for k in ('homebrew_version','compiler','built_as_bottle','poured_from_bottle','built_on','used_options','runtime_dependencies') if k in receipt}
        (metadata/'build-configs'/component/'provenance.json').write_text(json.dumps(summary,indent=2)+'\n')
    for line in output('/usr/bin/otool','-L',str(path)).splitlines()[1:]:
        ref=line.strip().split(' (compatibility version')[0]
        if ref.startswith(('/usr/lib/','/System/Library/')): continue
        if ref.startswith('@rpath/'):
            candidates=[prefix/'lib'/ref[7:]]
            candidates += [P(r.replace('@loader_path',str(path.parent)))/ref[7:] for r in rpaths(path)]
            candidates += [P('/opt/homebrew/lib')/ref[7:]]
            candidate=next((p for p in candidates if p.is_file()),candidates[0])
        elif ref.startswith('@loader_path/'):
            candidate=path.parent/ref[len('@loader_path/'):]
        elif ref.startswith('/'):
            candidate=P(ref)
        else: raise RuntimeError(f'Unresolved dependency: {path}: {ref}')
        dep=candidate.resolve()
        if dep!=path: queue.append(dep)

# Include build-time code generators and headers because their output enters
# libplacebo. fast_float is used under its MIT option.
for name in ('fast_float','jinja2','markupsafe'):
    version,license_id,archive=specs[name]
    components[name]=dict(name=name,version=version,license=license_id,source_archives=[],bundled_libraries=[],role='build-time or incorporated headers')
for name,entry in components.items():
    archive=specs[name][2]; source=work/'downloads'/archive
    copy(source,metadata/'sources'/archive)
    script_text=(root/'scripts/build-store-deps.sh').read_text()
    source_line=re.search(r'^fetch '+re.escape(archive)+r' (\S+) ([0-9a-f]{64})$',script_text,re.M)
    source_url=source_line[1].strip("'\"") if source_line else None
    if name in external:
        formula=(metadata/'build-configs'/name/'Homebrew-Formula.rb').read_text()
        source_url=re.search(r'^\s*url "([^"]+)"',formula,re.M)[1]
    entry['source_archives'].append(dict(path='sources/'+archive,sha256=sha(source),url=source_url))
    # Keep all legal texts, including nested font/package notices. Complete
    # original source comments remain available in the accompanying archives.
    with tarfile.open(source) as tar:
        for member in tar.getmembers():
            b=P(member.name).name.lower()
            if not member.isfile() or member.size>2*1024*1024: continue
            if not b.startswith(('license','copying','copyright','notice','ftl','authors','readme')): continue
            if P(member.name).suffix.lower() in ('.c','.h','.cpp','.py','.png','.ttf','.otf','.svg'): continue
            rel=P(*P(member.name).parts[1:])
            if '..' in rel.parts: raise RuntimeError('Unsafe archive path')
            data=tar.extractfile(member).read()
            try:data.decode('utf-8')
            except UnicodeError:continue
            dest=metadata/'licenses'/name/rel; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(data)
    entry['source_modifications'] = ('See build script: upstream CoreAudio patch c5d391adba7b' if name=='mpv'
                                     else 'Upstream source; fast_float header staged into expected subproject directory' if name=='libplacebo'
                                     else 'See recorded Homebrew formula' if name in external else 'None')
patch=work/'downloads/mpv-c5d391adba7bd024954d0df1e0405f5749f4d4ca.patch'
copy(patch,metadata/'sources'/patch.name)
components['mpv']['source_archives'].append(dict(path='sources/'+patch.name,sha256=sha(patch),role='applied patch'))
copy(root/'scripts/build-store-deps.sh',metadata/'build-configs/build-store-deps.sh')
(metadata/'build-configs/toolchain.txt').write_text(output('clang','--version')+'\n'+output(str(work/'venv/bin/pip'),'freeze'))
for name in ('ffmpeg','libass'):
    for filename in ('config.h','config_components.h','config.log','config.mak'):
        src=work/'build'/name/filename
        if src.is_file():copy(src,metadata/'build-configs'/name/filename)
    if name=='ffmpeg':copy(work/'build/ffmpeg/ffbuild/config.mak',metadata/'build-configs/ffmpeg/config.mak')
for name in ('mpv','libplacebo','harfbuzz'):
    for filename in ('intro-buildoptions.json','intro-dependencies.json','intro-buildsystem_files.json'):
        src=work/'build'/name/'meson-info'/filename
        if src.is_file():copy(src,metadata/'build-configs'/name/filename)
    for filename in ('config.h','config.asm'):
        src=work/'build'/name/filename
        if src.is_file():copy(src,metadata/'build-configs'/name/filename)
copy(prefix/'include/libplacebo/config.h',metadata/'build-configs/libplacebo/config.h')

ffconf=(work/'build/ffmpeg/config.h').read_text()
for macro in ('CONFIG_GPL','CONFIG_GPLV3','CONFIG_NONFREE','CONFIG_VERSION3'):
    if f'#define {macro} 0' not in ffconf: raise RuntimeError(f'Forbidden FFmpeg option: {macro}')
if '#define HAVE_GPL 0' not in (work/'build/mpv/config.h').read_text(): raise RuntimeError('mpv GPL mode enabled')
if '#define PL_HAVE_OPENGL' in (prefix/'include/libplacebo/config.h').read_text(): raise RuntimeError('Unreviewed libplacebo OpenGL/GLAD backend enabled')
report=output(str(prefix/'bin/ffmpeg'),'-L')
if 'GNU Lesser General Public' not in report or 'version 2.1' not in report: raise RuntimeError('FFmpeg runtime license mismatch')
(metadata/'build-configs/ffmpeg-license.txt').write_text(report)
manifest=dict(schema_version=1,status='audited LGPL-2.1-or-later and permissive dependency build; distribution obligations require separate review',
              root_library=str((prefix/'lib/libmpv.2.dylib').resolve()), components=sorted(components.values(),key=lambda x:x['name']),
              libraries=sorted(libraries,key=lambda x:x['path']),
              forbidden_components=['rubberband','x264','x265','libbluray','libarchive','lua','javascript','vapoursynth'],
              runtime_network=False, libplacebo_gpu_backends='disabled', patches=['mpv-c5d391adba7bd024954d0df1e0405f5749f4d4ca.patch'])
(metadata/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
readme='''# Controlled playback dependency build

The linked library closure is listed with exact pre-packaging SHA256 hashes in
manifest.json. FFmpeg 8.0.1 disables GPL, version3, nonfree and autodetection;
mpv 0.41.0 uses -Dgpl=false. libass retains CoreText font discovery and ASS/SSA
rendering. VideoToolbox decoding and the libmpv OpenGL render API are enabled.

The source archives and upstream patch in sources/ are actual local files,
not download promises. build-configs/ contains the build script, exact options,
generated configurations, and installed formulas for reused font libraries.
Rebuild the source components with build-configs/build-store-deps.sh in the
LPlayer repository. Reused font components can be rebuilt from the supplied
upstream archive using their recorded formula and inreplace operations.

FreeType is used under the FreeType License (FTL). Portions of this software
are copyright © The FreeType Project (www.freetype.org). All rights reserved.
FriBidi's linked library is LGPL 2.1 or later; its separate GPL command-line
utilities are not bundled. fast_float is used under its MIT license option.
libplacebo's GPU backends are disabled; its GLAD-generated OpenGL loader is
not incorporated. mpv's own classic OpenGL render API and VideoToolbox remain
enabled. fast_float's upstream archive includes an alternative Apache license;
this build selects its MIT option and retains the original upstream texts.

All LGPL libraries are dynamically linked. A developer must still provide an
effective mechanism for recipient relinking or replacement and the applicable
license exceptions/terms before distribution. An ad-hoc signed sandbox build
and this dependency audit do not establish App Store approval or legal advice.
'''
(metadata/'README.md').write_text(readme)
archive=work/'lplayer-store-deps-corresponding-source.tar.xz'
with tarfile.open(archive,'w:xz') as tar:
    for name in ('sources','licenses','build-configs','manifest.json','README.md'):
        tar.add(metadata/name,arcname='lplayer-store-deps/'+name)
(work/'lplayer-store-deps-corresponding-source.tar.xz.sha256').write_text(sha(archive)+'  '+archive.name+'\n')
print(f'Audited {len(libraries)} runtime libraries; metadata: {metadata}')
print(f'Corresponding source: {archive}')
PY
printf 'PKG_CONFIG_PATH=%s\n' "$PREFIX/lib/pkgconfig"
