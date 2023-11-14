import { Command } from 'commander'
import { dedent, parsePort, parseTimeout } from '../utils'

type CheckCommandArgs = {
  host?: string
  port?: number
  pbProxyPort?: number
  wait?: boolean | number
}

export function makeCheckCommand() {
  const command = new Command('check')
  command
    .description('Check that the ElectricSQL sync service is running')

    .option(
      '--host [host]',
      dedent`
        Hostname that the ElectricSQL sync service is on.

        Alternatively, you can set the ELECTRIC_HOST environment variable.
      `,
      'localhost'
    )

    .option(
      '--http-port <port>',
      dedent`
        Port that the ElectricSQL sync service is listening on.

        Alternatively, you can set the ELECTRIC_HTTP_PORT environment variable.

        Defaults to 5133.
      `,
      parsePort
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
      '-w --wait [timeout]',
      dedent`
        Wait for the service to start, with an optional timeout in seconds.
      `,
      (str) => (str ? parseTimeout(str) : true)
    )

    .action(async (opts: CheckCommandArgs) => {
      check(opts)
    })

  return command
}

export function check(opts: CheckCommandArgs) {
  // TODO: Implement this
  console.log(opts)
}
