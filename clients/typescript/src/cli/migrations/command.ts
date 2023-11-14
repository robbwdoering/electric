import { Command, InvalidArgumentError } from 'commander'
import { dedent } from '../utils'
import { generate, defaultOptions, GeneratorOptions } from './migrate'

export function makeGenerateCommand(): Command {
  const command = new Command('generate')
  command
    .description('Generate ElectricSQL client')

    .option(
      '-s, --service <url>',
      dedent`
      Optional argument providing the url to connect to Electric.
      
      If not provided, it uses the url set in the ELECTRIC_URL environment variable. 

      If that variable is not set, it resorts to the default url which is 
      'http://localhost:5133'.
    `
    )

    .option(
      '-p, --proxy <url>',
      dedent`
      Optional argument providing the url to connect to the PG database via the proxy.

      If not provided, it uses the url set in the PG_PROXY_URL environment variable.

      If that variable is not set, it resorts to the default url which is
      'postgresql://prisma:proxy_password@localhost:65432/electric'.
      
      NOTE: the generator introspects the PG database via the proxy,
      the URL must therefore connect using the "prisma" user.
    `
    )

    .option(
      '-o, --out <path>',
      dedent`
      Optional argument to specify where to write the generated client.

      If this argument is not provided the generated client is written
      to './src/generated/client'.
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

    .action(async (opts: Partial<GeneratorOptions>) => {
      if (opts.pollingInterval !== undefined) {
        opts.watch = true
      }
      if (opts.service && !/^https?:\/\//.test(opts.service)) {
        opts.service = 'http://' + opts.service
      }
      if (opts.proxy && !/^postgresql?:\/\//.test(opts.proxy)) {
        opts.proxy = 'postgresql://' + opts.proxy
      }
      await generate({ ...defaultOptions, ...opts })
    })

  return command
}
