// Write a sorted SHA-256 manifest of every regular file under a directory tree.
// Junctions/symlinks are recorded as links (with their target) and not followed,
// so the manifest of a pnpm workspace stays finite and comparable across machines.
// Usage: node hash-tree.mjs <root> <out-file> [--skip-node-modules]
// With --skip-node-modules, node_modules directories are left out (they are rebuilt by
// `pnpm install --offline --frozen-lockfile`, which verifies every package against the lockfile).
import { createHash } from 'node:crypto'
import { createReadStream, writeFileSync } from 'node:fs'
import { lstat, readdir, readlink } from 'node:fs/promises'
import { join, relative } from 'node:path'

const [root, outFile, flag] = process.argv.slice(2)
const skipNodeModules = flag === '--skip-node-modules'
const rows = []

async function hashFile(path) {
  const hash = createHash('sha256')
  for await (const chunk of createReadStream(path)) hash.update(chunk)
  return hash.digest('hex')
}

async function walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (skipNodeModules && entry.name === 'node_modules') continue
    const path = join(dir, entry.name)
    const rel = relative(root, path).replaceAll('\\', '/')
    const info = await lstat(path)
    if (info.isSymbolicLink()) rows.push(`link  ${(await readlink(path)).replaceAll('\\', '/')}  ${rel}`)
    else if (info.isDirectory()) await walk(path)
    else if (info.isFile()) rows.push(`${await hashFile(path)}  ${rel}`)
  }
}

await walk(root)
rows.sort((a, b) => a.slice(a.lastIndexOf('  ')).localeCompare(b.slice(b.lastIndexOf('  '))))
writeFileSync(outFile, rows.join('\n') + '\n')
console.log(`${rows.length} entries`)
