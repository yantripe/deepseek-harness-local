# Desktop native overlay verification

English | [中文](README.zh.md)

## Summary

This distribution ships no update checks, downloads, or mandatory-update policy. The remaining manual qualification covers the shared native overlay that the Windows background-close confirmation uses.

## Native overlay visibility

On macOS, reuse the cached Electron runtime after compiling the Desktop Host sources:

```sh
pnpm exec tsc -b apps/desktop/tsconfig.host.json
apps/desktop/.desktop-build/targets/mac-arm64/electron/Electron.app/Contents/MacOS/Electron apps/desktop/tests/fixtures/update-overlay-visibility.mjs
```

The fixture owns a unique profile and writes `result.json` under `.desktop-build/qualification/update-overlay-*`. It compares native visibility, unfiltered parent content, and listener cleanup with the owner-local expected output for parent hide/show and document readiness while the parent is hidden. It uses no network, product login, or dsh Host.
