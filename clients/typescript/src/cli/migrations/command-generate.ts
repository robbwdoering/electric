import { Command, InvalidArgumentError } from 'commander'
import { dedent } from '../utils'
import {
  generate,
  type GeneratorOptions,
  defaultPollingInterval,
} from './migrate'
import { addOptionGroupToCommand, getConfig } from '../config'

export { generate }

interface GenerateCommandArgs {
  watch?: number | true
}

export function makeGenerateCommand(): Command {
  const command = new Command('generate')
  command.description('Generate ElectricSQL client')

  addOptionGroupToCommand(command, 'client')

  command
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
      const config = getConfig(restOpts)

      const genOpts: GeneratorOptions = {
        config,
      }
      if (watch !== undefined) {
        genOpts.watch = true
        genOpts.pollingInterval =
          watch === true ? defaultPollingInterval : watch
      }

      await generate(genOpts)
    })

  return command
}
