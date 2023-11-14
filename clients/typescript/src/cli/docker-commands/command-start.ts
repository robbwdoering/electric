import { Command } from 'commander'
import { dedent, getAppName } from '../utils'
import { addOptionGroupToCommand, getConfig, Config } from '../config'
import { dockerCompose } from './docker-utils'

/*
To do:
  - image version env var - default to this library's minor version
*/

export function makeStartCommand() {
  const command = new Command('start')
  command.description(
    'Start the ElectricSQL sync service, and an optional PostgreSQL'
  )

  addOptionGroupToCommand(command, 'electric')

  command.option(
    '--detach',
    'Run in the background instead of printing logs to the console'
  )

  command.action(async (opts: any) => {
    if (opts.databaseUrl && opts.withPostgres) {
      console.error('You cannot set --database-url when using --with-postgres.')
      process.exit(1)
    }
    const config = getConfig(opts)
    if (!config.WITH_POSTGRES && !config.DATABASE_URL) {
      console.error(
        'You must set --database-url or the ELECTRIC_DATABASE_URL env var when not using --with-postgres.'
      )
      process.exit(1)
    }
    const startOptions = {
      detach: opts.detach,
      withPostgres: !!config.WITH_POSTGRES,
      pgPort: opts.WITH_POSTGRES ? opts.DATABASE_PORT : undefined,
      config: config,
    }
    start(startOptions)
  })

  return command
}

interface StartSettings {
  detach?: boolean
  withPostgres?: boolean
  pgPort?: number
  config: Config
}

export function start(options: StartSettings) {
  console.log(
    `Starting ElectricSQL sync service${
      options.withPostgres ? ' with PostgreSQL' : ''
    }`
  )
  const appName = getAppName() ?? 'electric'
  console.log('Docker compose project:', appName)

  const env = configToEnv(options.config)

  const dockerConfig = {
    APP_NAME: appName,
    COMPOSE_PROJECT_NAME: appName,
    ...env,
    ...(options.withPostgres
      ? {
          COMPOSE_PROFILES: 'with-postgres',
          COMPOSE_ELECTRIC_SERVICE: 'electric-with-postgres',
          DATABASE_URL: `postgresql://postgres:${
            env?.DATABASE_PASSWORD ?? 'pg_password'
          }@postgres:${env?.DATABASE_PORT ?? '5432'}/${appName}`,
          LOGICAL_PUBLISHER_HOST: 'electric',
        }
      : {}),
  }
  console.log('Docker compose config:', dockerConfig)

  const proc = dockerCompose(
    'up',
    [...(options.detach ? ['--detach'] : [])],
    dockerConfig
  )

  proc.on('close', (code) => {
    if (code !== 0) {
      console.error(
        dedent`
          Failed to start the Electric backend. Check the output from 'docker compose' above.
          If the error message mentions a port already being allocated or address being already in use,
          execute 'npx electric-sql configure-ports' to run Electric on another port.
        `
      )
      process.exit(code ?? 1)
    }
  })
}

function configToEnv(config: Config) {
  const env: { [key: string]: string } = {}
  for (const [key, val] of Object.entries(config)) {
    if (val === true) {
      env[key] = 'true'
    } else if (val !== undefined) {
      env[key] = val.toString()
    }
  }
  return env
}
