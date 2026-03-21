import std / syncio
import ".." / "src" / [smartcli]

let options = cliapp"""Greeter v0.1
This program greets.

Usage: greeter [options] INPUT greet|version

Arguments:
  INPUT  Input file

Commands:
  greet    Greets NAME
  version  Displays version and quits

Options:
  --output=FILE     Output file
  -v, --verbose     Enable verbose output
  -h, --help        Show this help and exit"""

stdout.writeLine "input: " & options.input
stdout.writeLine "output: " & options.output
stdout.writeLine "verbose: " & $options.verbose
stdout.writeLine "command: " & $options.command
