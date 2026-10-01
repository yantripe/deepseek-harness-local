import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import * as release from '../scripts/desktop-auto-update-environment.mjs'

describe('desktop release targets', () => {
  it.each([['darwin', 'arm64', 'mac-arm64'], ['darwin', 'x64', 'mac-x64'], ['win32', 'x64', 'win-x64']] as const)
  ('maps %s %s to the %s release directory and completion record', (platform, arch, target) => {
    expect(release.resolveDesktopAutoUpdateTarget(platform, arch)).toBe(target)
    expect(release.desktopBuildRecordFilename(target)).toBe(`${target}-release.json`)
  })

  it('rejects unknown targets', () => {
    expect(() => release.resolveDesktopAutoUpdateTarget('linux', 'x64')).toThrow(/unsupported target/u)
    expect(() => release.desktopBuildRecordFilename('linux-x64' as 'mac-arm64')).toThrow(/unsupported target/u)
  })

  it('exposes no update feed or upload destination', () => {
    expect(Object.keys(release).sort()).toEqual(['desktopBuildRecordFilename', 'resolveDesktopAutoUpdateTarget'])
    const source = readFileSync(new URL('../scripts/desktop-auto-update-environment.mjs', import.meta.url), 'utf8')
    expect(source).not.toMatch(/https?:\/\//u)
  })
})
