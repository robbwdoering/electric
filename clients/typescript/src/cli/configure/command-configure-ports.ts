import { Command } from 'commander'
// import { dedent } from '../utils'

export function makeConfigurePortsCommand() {
  const command = new Command('configure-ports')
  command
    .description('Configure the ports used by the ElectricSQL sync service')

    .action(async () => {
      configurePorts()
    })

  return command
}

export function configurePorts() {
  // TODO: Implement this
}
