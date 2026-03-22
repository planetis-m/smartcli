import std / syncio
import ".." / "src" / [smartcli]

let options = cliapp"""Greeter v0.1
This program greets.

Usage: greeter [options] (greet INPUT | version)

Commands:
  greet INPUT  Greets NAME
  version  Displays version and quits

Arguments:
  INPUT  Input file

Options:
  --output=FILE     Output file
  -v, --verbose     Enable verbose output
  -h, --help        Show this help and exit"""

echo "input: ", options.input
echo "output: ", options.output
echo "verbose: ", options.verbose
echo "command: ", options.command
