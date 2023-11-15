import { spawn } from 'child_process'
import path from 'path'
import { fileURLToPath } from 'url'
import { getAppName } from '../utils'

// This code could be placed in a chunk and so import.meta.url may not be what
// you expect. We find the root of the library by looking for /dist/ in the URL
// and work from there.
const thisFileUrl = import.meta.url
const libRoot = thisFileUrl.slice(0, thisFileUrl.lastIndexOf('/dist/') + 5)

const composeFile = path.join(
  path.dirname(fileURLToPath(libRoot)),
  'dist',
  'cli',
  'docker-commands',
  'docker',
  'compose.yaml'
)

export function dockerCompose(
  command: string,
  userArgs: string[] = [],
  env: { [key: string]: string } = {}
) {
  const appName = getAppName() ?? 'electric'
  const args = [
    'compose',
    '--ansi',
    'always',
    '-f',
    composeFile,
    command,
    ...userArgs,
  ]
  return spawn('docker', args, {
    stdio: 'inherit',
    env: {
      ...process.env,
      APP_NAME: appName,
      COMPOSE_PROJECT_NAME: appName,
      ...env,
    },
  })
}
