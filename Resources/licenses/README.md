# 第三方许可证与构建记录

本目录保存 LPlayer 当前本地构建使用的非系统动态库清单。`THIRD_PARTY.md` 是可读清单，`manifest.json` 记录组件、安装版本、源码网址、Homebrew 许可声明及打包文件。`components/` 保存本机配方和安装目录里找到的许可原文。

运行 `./scripts/build-app.sh --licenses-only` 可按本机 libmpv 的实际依赖图刷新本目录，不编译、不启动应用。正常打包时会将它复制到 `LPlayer.app/Contents/Resources/licenses`，再按 app 的实际依赖图重新生成清单。

当前 Homebrew FFmpeg 使用 `--enable-gpl --enable-version3`，其 `-L` 输出明确声明 GPL-3.0-or-later；mpv 配方同时含 GPL-2.0-or-later 与 LGPL-2.1-or-later。本目录保留原始构建报告，不将这个本地构建描述为仅 LGPL 的发行版本。

这是本地开发快照，不是完整对应源码包、书面源码提供承诺或发行合规证明。正式分发前仍需核对完整对应源码、补丁与构建信息、各组件的许可条件、LPlayer 自身的发行授权及签名公证。某些安装目录只保留了许可概述，完整文本仍需与相应源码核对。
