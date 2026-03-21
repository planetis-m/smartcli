import std / assertions
import ".." / "src" / [smartcli]

var
  nifcArgc {.importc: "cmdCount".}: int32
  nifcArgv {.importc: "cmdLine".}: ptr UncheckedArray[cstring]

block:
  nifcArgc = 5
  const cargv = [
    cstring"greeter",
    cstring"--output=out.txt",
    cstring"-v",
    cstring"input.txt",
    cstring"greet"
  ]
  nifcArgv = cast[ptr UncheckedArray[cstring]](cargv.addr)

  let options = cliapp"""Greeter v0.1
This program greets.

Usage: greeter [options] INPUT greet|version

Arguments:
  INPUT  Input file

Commands:
  greet    Greets NAME
  version  Displays version and quits

Options:
  --mode=fast|slow  Output mode
  --output=FILE     Output file
  -v, --verbose     Enable verbose output
  -h, --help        Show this help and exit"""

  assert options.input == "input.txt"
  assert options.output == "out.txt"
  assert options.verbose
  assert $options.command == "cmdGreet"

block:
  nifcArgc = 4
  const cargv = [
    cstring"greeter",
    cstring"--mode=slow",
    cstring"input.txt",
    cstring"greet"
  ]
  nifcArgv = cast[ptr UncheckedArray[cstring]](cargv.addr)

  let options = cliapp"""Greeter v0.1
This program greets.

Usage: greeter [options] INPUT greet|version

Arguments:
  INPUT  Input file

Commands:
  greet    Greets NAME
  version  Displays version and quits

Options:
  --mode=fast|slow  Output mode
  --output=FILE     Output file
  -v, --verbose     Enable verbose output
  -h, --help        Show this help and exit"""

  assert options.input == "input.txt"
  assert $options.mode == "cliModeSlow"
