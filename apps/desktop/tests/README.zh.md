# Desktop 原生浮层验证

[English](README.md) | 中文

## 概述

本发行版不包含更新检查、下载或强制更新策略。剩余的人工验证覆盖 Windows 后台关闭确认所用的共享原生浮层。

## 原生浮层可见性

在 macOS 上，编译 Desktop Host 源码后复用缓存的 Electron 运行时：

```sh
pnpm exec tsc -b apps/desktop/tsconfig.host.json
apps/desktop/.desktop-build/targets/mac-arm64/electron/Electron.app/Contents/MacOS/Electron apps/desktop/tests/fixtures/update-overlay-visibility.mjs
```

夹具使用独立 profile，在 `.desktop-build/qualification/update-overlay-*` 下写入 `result.json`。它对照所属测试目录中的预期输出，检查父窗口隐藏／显示、父窗口隐藏期间文档就绪两种顺序中的原生可见性、父页面不受模糊影响及监听清理。它不使用网络、产品登录或 dsh Host。
