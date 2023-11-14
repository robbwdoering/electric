#!/usr/bin/env node

import { Command } from 'commander'
import { LIB_VERSION } from '../version/index'
import { makeGenerateCommand } from './migrations/commands'
import 'dotenv/config' // Enables automatic reading from .env files

const program = new Command()

program
  .name('ElectricSQL CLI')
  .description('CLI to enable building ElectricSQL projects in TypeScript')
  .version(LIB_VERSION)

program.addCommand(makeGenerateCommand())

await program.parseAsync(process.argv)
