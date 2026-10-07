/**
 * Internal platform-profile builders for the local sandbox provider.
 *
 * @module @deepseek-ai/dsh-sandbox-local/profiles
 */

import { grantArgs as landlockGrantArgs } from '@deepseek-ai/node-addon-system/landlock-run'
import { homedir } from 'node:os'
import { join, resolve } from 'node:path'
import { canonicalPath, writableRoots } from '@deepseek-ai/dsh-sandbox'
import type { SandboxPolicy } from '@deepseek-ai/dsh-sandbox'

/**
 * Build the bwrap profile arguments for one file-effect policy.
 * @param policy - file-effect policy to express as bwrap mounts.
 * @returns profile arguments before the trailing separator and command argv.
 */
export function bwrapProfileArgs(policy: SandboxPolicy): string[] {
  const args = ['--ro-bind', '/', '/', '--dev', '/dev', '--unshare-pid', '--proc', '/proc', '--die-with-parent']
  if (policy.mode === 'workspace-write') {
    args.push('--tmpfs', '/tmp')
    args.push('--bind', policy.workspaceRoot, policy.workspaceRoot)
  }
  return args
}

/**
 * Build the Landlock launcher grants for one file-effect policy.
 * @param policy - file-effect policy to express as Landlock allow-list grants.
 * @returns launcher grant arguments before the trailing separator and command argv.
 */
export function landlockProfileArgs(policy: SandboxPolicy): string[] {
  const readWrite = ['/dev/null']
  if (policy.mode === 'workspace-write') {
    readWrite.push('/tmp', policy.workspaceRoot)
  }
  return landlockGrantArgs({ readOnly: ['/'], readWrite })
}

/** Quote one path as an SBPL string literal. */
function sbplString(path: string): string {
  return `"${path.replaceAll('\\', String.raw`\\`).replaceAll('"', String.raw`\"`)}"`
}

/**
 * The Harness-home secrets confined processes must not read: the same set the
 * `fs-local` file tools refuse (`.env`, `.credentials.yaml`, `sessions`,
 * `cordis.patch.yml`) plus every `DSH_PROTECTED_PATHS` entry. Without this a
 * `cat` through bash would read what the read tool refuses.
 * @returns canonical paths, as Seatbelt matches resolved paths.
 */
export function protectedReadPaths(): string[] {
  const configuredHome = process.env.DSH_HOME?.trim()
  const home = resolve(configuredHome === undefined || configuredHome === '' ? join(homedir(), '.dsh') : configuredHome)
  const extra = (process.env.DSH_PROTECTED_PATHS ?? '').split(':').map(entry => entry.trim()).filter(entry => entry !== '')
  const paths = [join(home, '.env'), join(home, '.credentials.yaml'), join(home, 'sessions'), join(home, 'cordis.patch.yml'), ...extra]
  return [...new Set(paths.flatMap(path => [resolve(path), canonicalPath(resolve(path))]))]
}

/**
 * Build the sandbox-exec arguments and SBPL profile for one policy. The
 * writable roots come from the shared {@link writableRoots} helper (canonical,
 * deduplicated) so the Seatbelt grant and the in-process fs fence
 * (`@deepseek-ai/dsh-fs-sandbox`) can never drift apart. Local edition: the
 * profile also denies outbound IP traffic (unless `DSH_ALLOW_AGENT_NETWORK=1`)
 * and reads of {@link protectedReadPaths}; on macOS nothing else stands
 * between agent commands and the network or the Harness secrets.
 * @param policy - file-effect policy to express as an SBPL profile.
 * @returns sandbox-exec arguments before the trailing separator and command argv.
 */
export function seatbeltProfileArgs(policy: SandboxPolicy): string[] {
  const forms = ['(version 1)', '(allow default)', '(deny file-write*)', `(allow file-write* (literal ${sbplString('/dev/null')}))`]
  const roots = writableRoots(policy)
  if (roots.length > 0) {
    forms.push(`(allow file-write* ${roots.map(root => `(subpath ${sbplString(root)})`).join(' ')})`)
  }
  forms.push(`(deny file-read* file-write* ${protectedReadPaths().map(path => `(subpath ${sbplString(path)})`).join(' ')})`)
  if (process.env.DSH_ALLOW_AGENT_NETWORK !== '1') forms.push('(deny network-outbound (remote ip))')
  return ['-p', forms.join(' ')]
}
