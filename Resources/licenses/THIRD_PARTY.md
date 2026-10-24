# 当前构建的第三方组件

此清单从实际依赖图和已安装的 Homebrew 配方生成；配方及可找到的许可证原文在 components/。
版本号包含 Homebrew revision。源码 URL、补丁 URL 和配方对应当前安装版本；本目录没有打包完整对应源码。

本机 FFmpeg 的 `ffmpeg -L` 输出与配置已保存为 ffmpeg-build-license.txt；当前构建启用 GPL 与 version3，报告为 GPL-3.0-or-later。
mpv 配方同时声明 GPL-2.0-or-later 与 LGPL-2.1-or-later。本产物包含 GPL 组件，不应描述为仅使用 LGPL 的播放器构建。

| 组件 | 安装版本 | Homebrew 许可声明 | 官网 | 对应源码 |
| --- | --- | --- | --- | --- |
| brotli | 1.2.0 | `"MIT"` | [官网](https://github.com/google/brotli) | [源码](https://github.com/google/brotli/archive/refs/tags/v1.2.0.tar.gz) |
| dav1d | 1.5.4 | `"BSD-2-Clause"` | [官网](https://code.videolan.org/videolan/dav1d) | [源码](https://code.videolan.org/videolan/dav1d/-/archive/1.5.4/dav1d-1.5.4.tar.bz2) |
| ffmpeg | 9.0.2_1 | `"GPL-3.0-or-later"` | [官网](https://ffmpeg.org/) | [源码](https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz) |
| fontconfig | 2.18.3 | `all_of: [  "HPND-sell-variant", "Unicode-3.0", "MIT-Modern-Variant", "MIT", :public_domain, ]` | [官网](https://wiki.freedesktop.org/www/Software/fontconfig/) | [源码](https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/2.18.3/fontconfig-2.18.3.tar.gz) |
| freetype | 2.15.0 | `"FTL"` | [官网](https://www.freetype.org/) | [源码](https://downloads.sourceforge.net/project/freetype/freetype2/2.15.0/freetype-2.15.0.tar.xz) |
| fribidi | 1.0.17 | `all_of: ["GPL-2.0-or-later", "LGPL-2.1-or-later"]` | [官网](https://github.com/fribidi/fribidi) | [源码](https://github.com/fribidi/fribidi/releases/download/v1.0.17/fribidi-1.0.17.tar.xz) |
| gettext | 1.0 | `all_of: [  "GPL-3.0-or-later", "LGPL-2.1-or-later", ]` | [官网](https://www.gnu.org/software/gettext/) | [源码](https://ftpmirror.gnu.org/gnu/gettext/gettext-1.0.tar.gz) |
| glib | 2.90.1 | `"LGPL-2.1-or-later"` | [官网](https://docs.gtk.org/glib/) | [源码](https://download.gnome.org/sources/glib/2.90/glib-2.90.1.tar.xz) |
| graphite2 | 1.3.15 | `any_of: ["GPL-2.0-or-later", "LGPL-2.1-or-later", "MPL-1.1+"]` | [官网](https://graphite.sil.org/) | [源码](https://github.com/silnrsi/graphite/releases/download/1.3.15/graphite2-1.3.15.tgz) |
| harfbuzz | 14.6.0 | `"MIT"` | [官网](https://github.com/harfbuzz/harfbuzz) | [源码](https://github.com/harfbuzz/harfbuzz/releases/download/14.6.0/harfbuzz-14.6.0.tar.xz) |
| jpeg-turbo | 3.2.0 | `all_of: [  "IJG", "Zlib", "BSD-3-Clause", ]` | [官网](https://www.libjpeg-turbo.org/) | [源码](https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz) |
| lame | 4.0 | `"LGPL-2.0-or-later"` | [官网](https://lame.sourceforge.io/) | [源码](https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz) |
| libarchive | 3.8.10 | `"BSD-2-Clause"` | [官网](https://www.libarchive.org) | [源码](https://www.libarchive.org/downloads/libarchive-3.8.10.tar.xz) |
| libass | 0.17.5_1 | `"ISC"` | [官网](https://github.com/libass/libass) | [源码](https://github.com/libass/libass/releases/download/0.17.5/libass-0.17.5.tar.xz) |
| libb2 | 0.98.1 | `"CC0-1.0"` | [官网](https://blake2.net/) | [源码](https://github.com/BLAKE2/libb2/releases/download/v0.98.1/libb2-0.98.1.tar.gz) |
| libbluray | 1.5.0 | `"LGPL-2.1-or-later"` | [官网](https://www.videolan.org/developers/libbluray.html) | [源码](https://download.videolan.org/videolan/libbluray/1.5.0/libbluray-1.5.0.tar.xz) |
| libplacebo | 7.360.1 | `"LGPL-2.1-or-later"` | [官网](https://code.videolan.org/videolan/libplacebo) | [源码](https://code.videolan.org/videolan/libplacebo/-/archive/v7.360.1/libplacebo-v7.360.1.tar.bz2) |
| libpng | 1.6.59 | `"libpng-2.0"` | [官网](https://www.libpng.org/pub/png/libpng.html) | [源码](https://downloads.sourceforge.net/project/libpng/libpng16/1.6.59/libpng-1.6.59.tar.xz) |
| libsamplerate | 0.2.2 | `"BSD-2-Clause"` | [官网](https://github.com/libsndfile/libsamplerate) | [源码](https://github.com/libsndfile/libsamplerate/archive/refs/tags/0.2.2.tar.gz) |
| libudfread | 1.2.0 | `"LGPL-2.1-or-later"` | [官网](https://code.videolan.org/videolan/libudfread) | [源码](https://download.videolan.org/videolan/libudfread/libudfread-1.2.0.tar.xz) |
| libunibreak | 8.0 | `"Zlib"` | [官网](https://github.com/adah1972/libunibreak) | [源码](https://github.com/adah1972/libunibreak/releases/download/libunibreak_8_0/libunibreak-8.0.tar.gz) |
| libvmaf | 3.2.1 | `"BSD-2-Clause-Patent"` | [官网](https://github.com/Netflix/vmaf) | [源码](https://github.com/Netflix/vmaf/archive/refs/tags/v3.2.1.tar.gz) |
| libvpx | 1.17.0 | `"BSD-3-Clause"` | [官网](https://www.webmproject.org/code/) | [源码](https://github.com/webmproject/libvpx/archive/refs/tags/v1.17.0.tar.gz) |
| little-cms2 | 2.19.1 | `"MIT"` | [官网](https://www.littlecms.com/) | [源码](https://downloads.sourceforge.net/project/lcms/lcms/2.19.1/lcms2-2.19.1.tar.gz) |
| luajit | 2.1.1792527110 | `"MIT"` | [官网](https://luajit.org/luajit.html) | [源码](https://github.com/LuaJIT/LuaJIT/archive/95f931cb1ee7ab14f249d61fb3734803429025f8.tar.gz) |
| lz4 | 1.10.0 | `"BSD-2-Clause"` | [官网](https://lz4.github.io/lz4/) | [源码](https://github.com/lz4/lz4/archive/refs/tags/v1.10.0.tar.gz) |
| mpg123 | 1.33.7 | `"LGPL-2.1-only"` | [官网](https://www.mpg123.de/) | [源码](https://www.mpg123.de/download/mpg123-1.33.7.tar.bz2) |
| mpv | 0.41.0_11 | `all_of: ["GPL-2.0-or-later", "LGPL-2.1-or-later"]` | [官网](https://mpv.io) | [源码](https://github.com/mpv-player/mpv/archive/refs/tags/v0.41.0.tar.gz) |
| mujs | 1.3.11 | `"ISC"` | [官网](https://www.mujs.com/) | [源码](https://mujs.com/downloads/mujs-1.3.11.tar.gz) |
| openssl@4 | 4.0.3 | `"Apache-2.0"` | [官网](https://openssl-library.org) | [源码](https://github.com/openssl/openssl/releases/download/openssl-4.0.3/openssl-4.0.3.tar.gz) |
| opus | 1.6.1 | `"BSD-3-Clause"` | [官网](https://www.opus-codec.org/) | [源码](https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.1.tar.gz) |
| pcre2 | 10.49 | `"BSD-3-Clause"` | [官网](https://www.pcre.org/) | [源码](https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.49/pcre2-10.49.tar.bz2) |
| rubberband | 4.0.0 | `"GPL-2.0-or-later"` | [官网](https://breakfastquay.com/rubberband/) | [源码](https://breakfastquay.com/files/releases/rubberband-4.0.0.tar.bz2) |
| shaderc | 2026.4 | `"Apache-2.0"` | [官网](https://github.com/google/shaderc) | [源码](https://github.com/google/shaderc/archive/refs/tags/v2026.4.tar.gz) |
| svt-av1 | 4.2.0 | `"BSD-3-Clause"` | [官网](https://gitlab.com/AOMediaCodec/SVT-AV1) | [源码](https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.2.0/SVT-AV1-v4.2.0.tar.bz2) |
| uchardet | 0.0.8 | `any_of: ["MPL-1.1", "GPL-2.0-or-later", "LGPL-2.1-or-later"]` | [官网](https://www.freedesktop.org/wiki/Software/uchardet/) | [源码](https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz) |
| vulkan-loader | 1.4.363.0 | `"Apache-2.0"` | [官网](https://github.com/KhronosGroup/Vulkan-Loader) | [源码](https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz) |
| x264 | r3222 | `"GPL-2.0-or-later"` | [官网](https://www.videolan.org/developers/x264.html) | [源码](https://code.videolan.org/videolan/x264.git) |
| x265 | 4.3 | `"GPL-2.0-or-later"` | [官网](https://github.com/Multicorewareinc/x265) | [源码](https://github.com/Multicorewareinc/x265/releases/download/4.3/x265_4.3.tar.gz) |
| xz | 5.8.4 | `all_of: [  "0BSD", "GPL-2.0-or-later", ]` | [官网](https://tukaani.org/xz/) | [源码](https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.gz) |
| zimg | 3.0.6 | `"WTFPL"` | [官网](https://github.com/sekrit-twc/zimg) | [源码](https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz) |
| zstd | 1.5.7_1 | `all_of: [  { any_of: ["BSD-3-Clause", "GPL-2.0-only"] }, "BSD-2-Clause", "MIT", ]` | [官网](https://facebook.github.io/zstd/) | [源码](https://github.com/facebook/zstd/archive/refs/tags/v1.5.7.tar.gz) |

## 待发布前核对

所带二进制的对应源码、配方补丁、构建说明、许可相容性及 LPlayer 自身的发行授权仍需在正式分发前处理。本清单和本机签名不表示已满足全部发行义务。
有些软件的概述文件还会引用源代码树内的其他许可；复制概述文件也不代表许可文本已完整。

未在安装目录找到许可证原文的组件：libunibreak。请按配方所列源码核对。
