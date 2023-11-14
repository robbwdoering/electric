import { Command, InvalidArgumentError } from 'commander'
import { dedent } from '../utils'
import {
  generate,
  GeneratorOptions,
  getDefaultOptions,
  defaultPollingInterval,
} from './migrate'

interface GenerateCommandArgs {
  service?: string
  proxy?: string
  out?: string
  watch?: number | true
}

export function makeGenerateCommand(): Command {
  const command = new Command('generate')
  command
    .description('Generate ElectricSQL client')

    .option(
      '-s, --service <url>',
      dedent`
        Optional argument providing the url to connect to Electric.

        If not provided, it uses the url set in the ELECTRIC_URL environment variable,
        or if ELECTRIC_HTTP_PORT is set, it uses 'http://localhost:$ELECTRIC_HTTP_PORT'.

        If neither are set, it resorts to the default url which is 
        'http://localhost:5133'.
      `
    )

    .option(
      '-p, --proxy <url>',
      dedent`
        Optional argument providing the url to connect to the PG database via the proxy.

        If not provided, it uses the url set in the ELECTRIC_PG_PROXY_URL environment variable.

        If that variable is not set, it will use the default url
        'postgresql://prisma:$ELECTRIC_PG_PROXY_PASSWORD@localhost:$ELECTRIC_PG_PORT/electric',
        where ELECTRIC_PG_PROXY_PASSWORD defaults to 'proxy_password', and
        ELECTRIC_PG_PORT defaults to 65432.
        
        NOTE: the generator introspects the PG database via the proxy,
        the URL must therefore connect using the "prisma" user.
      `
    )

    .option(
      '-o, --out <path>',
      dedent`
        Optional argument to specify where to write the generated client.

        If not provided, it uses the url set in the ELECTRIC_CLIENT_PATH environment
        variable.

        If that variable is not set the generated client is written to
        './src/generated/client'.
      `
    )

    .option(
      '-w, --watch [pollingInterval]',
      dedent`
        Optional flag to specify that the migrations should be watched.

        When new migrations are found, the client is rebuilt automatically.

        You can provide an optional polling interval in milliseconds,
        which is how often we should poll Electric for new migrations.
      `,
      (pollingInterval: string) => {
        const parsed = parseInt(pollingInterval)
        if (isNaN(parsed)) {
          throw new InvalidArgumentError(
            `Invalid polling interval: ${pollingInterval}. Should be a time in milliseconds (i.e. a positive integer).`
          )
        }
        return parsed
      }
    )

    .action(async (opts: GenerateCommandArgs) => {
      const { watch, ...restOpts } = opts
      const genOpts: GeneratorOptions = { ...getDefaultOptions(), ...restOpts }
      if (watch !== undefined) {
        genOpts.watch = true
        genOpts.pollingInterval =
          watch === true ? defaultPollingInterval : watch
      }
      if (opts.service && !/^https?:\/\//.test(opts.service)) {
        genOpts.service = 'http://' + opts.service
      }
      if (opts.proxy && !/^postgresql?:\/\//.test(opts.proxy)) {
        genOpts.proxy = 'postgresql://' + opts.proxy
      }
      await generate(genOpts)
    })

  return command
}
