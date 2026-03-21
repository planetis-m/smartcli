# smartcli

`smartcli` turns a help text block into a small CLI parser and a typed options object.

It is aimed at `nimony` projects that want a tiny docopt-like DSL without bringing in a larger parser layer.

## Why try it?

- The help text is the source of truth.
- `cliapp"""..."""` generates the parser at compile time.
- Flags become `bool` fields, value options become `string` fields, and `a|b` choices become enums.
- Commands are generated as a command enum instead of staying as raw strings.

## Quick Start

```nim
import std / syncio
import smartcli

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

stdout.writeLine options.input
stdout.writeLine options.output
stdout.writeLine $options.verbose
stdout.writeLine $options.command
stdout.writeLine $options.mode
```

## DSL Rules

- `INPUT` generates a required positional `string` field.
- `--output=FILE` generates a `string` field named `output`.
- `-v, --verbose` generates a `bool` field named `verbose`.
- `--mode=fast|slow` generates a field named `mode` and a generated enum type.
- Commands come from the `Commands:` section and are exposed through `options.command`.

## Layout

- [src/smartcli.nim](src/smartcli.nim): public runtime API
- [src/smartcliplugin.nim](src/smartcliplugin.nim): compile-time plugin
- [examples/greeter.nim](examples/greeter.nim): minimal app
- [examples/backup.nim](examples/backup.nim): enum and flags
- [tests/tsmoke.nim](tests/tsmoke.nim): parser smoke test
- [tests/tslots.nim](tests/tslots.nim): positional slot test

## Run

Compile an example directly with Nimony:

```sh
nimony c examples/greeter.nim
```

Run the package tests directly:

```sh
nimony c -r tests/tsmoke.nim
nimony c -r tests/tslots.nim
```
