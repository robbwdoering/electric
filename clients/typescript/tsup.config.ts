import packageJson from './package.json'
import { defineConfig } from 'tsup'

// Entry points from package.json
let entry = Object.values(packageJson.exports)
  .filter((path) => path.startsWith('./dist/') && path.endsWith('.js'))
  .map((path) => path.replace('./dist/', './src/').replace('.js', '.ts'))

// Add entry points from typesVersions
Object.values(packageJson.typesVersions['*']).map((paths: string[]) => {
  paths.map((path) => {
    entry.push(path.replace('./dist/', './src/').replace('.d.ts', '.ts'))
  })
})

entry = [...new Set(entry)] // Remove duplicates

export default defineConfig({
  entryPoints: entry,
  format: ['esm'],
  sourcemap: true,
  dts: false,
})
