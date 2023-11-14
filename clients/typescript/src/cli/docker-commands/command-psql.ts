import { Command } from 'commander'
import { dedent, parsePort } from '../utils'

interface PsqlCommandArgs {
  user: string
  password: string
  host: string
  port: number
  dbName: string
}

export function makePsqlCommand() {
  const command = new Command('psql')
  command
    .description('Connect with psql to the ElectricSQL PostgreSQL proxy')

    .option(
      '--user <user>',
      dedent`
        Username to connect with.

        Alternatively, you can set the ELECTRIC_PG_PROXY_USER environment variable.
      `,
      'postgres'
    )

    .option(
      '--password <password>',
      dedent`
        Password to connect with.

        Alternatively, you can set the ELECTRIC_PG_PROXY_PASSWORD environment variable.
      `,
      'postgres'
    )

    .option(
      '--host <host>',
      dedent`
        Hostname that the ElectricSQL sync service is on.

        Alternatively, you can set the ELECTRIC_HOST environment variable.
      `,
      'localhost'
    )

    .option(
      '--pg-proxy-port <port>',
      dedent`
        Port that the ElectricSQL sync service PostgreSQL proxy is listening on.

        Alternatively, you can set the ELECTRIC_PG_PROXY_PORT environment variable.

        Defaults to 65432.
      `,
      parsePort
    )

    .option(
      '--database-name <database-name>',
      dedent`
        Name of the database to connect to.

        Alternatively, you can set the ELECTRIC_DATABASE_NAME environment variable.
        `
    )

    .action(async (opts) => {
      psql(opts)
    })

  return command
}

export function psql(_opts: PsqlCommandArgs) {
  // Default to ELECTRIC_HOST and ELECTRIC_PG_PROXY_PORT
  // const host = opts.host || process.env.ELECTRIC_HOST || 'localhost'
  // const pgProxyPort =
  //   opts.pgProxyPort || process.env.ELECTRIC_PG_PROXY_PORT || 65432
  // const CONTAINER_DATABASE_URL = `postgres://postgres:postgres@${host}:${pgProxyPort}/postgres`
  //dockerCompose('exec', ['-it', 'postgres', 'psql', CONTAINER_DATABASE_URL])
}
