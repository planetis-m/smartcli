# smartcli

`smartcli` turns a help text block into a small CLI parser and a typed options object.

It is aimed at `nimony` projects that want a tiny docopt-like DSL without bringing in a larger parser layer.

The core design direction was inspired by @Araq's [forum post](https://forum.nim-lang.org/t/13777#83561): let `cliapp"""..."""` build a validator plus a typed object, so the result is more convenient than hand-written argument loops and nested `case` statements.

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

Usage: greeter [options] (greet INPUT | version)

Commands:
  greet INPUT  Greets NAME
  version  Displays version and quits

Arguments:
  INPUT  Input file

Options:
  --mode=fast|slow  Output mode
  --output=FILE     Output file
  -v, --verbose     Enable verbose output
  -h, --help        Show this help and exit"""

echo options.input
echo options.output
echo options.verbose
echo options.command
echo options.mode
```

## DSL Rules

- `INPUT` generates a required positional `string` field.
- `--output=FILE` generates a `string` field named `output`.
- `-v, --verbose` generates a `bool` field named `verbose`.
- `--mode=fast|slow` generates a field named `mode` and a generated enum type.
- Commands come from the `Commands:` section and are exposed through `options.command`.
- Command entries may declare their own positional arguments, for example `greet INPUT`.
- When commands declare inline arguments, `Arguments:` is optional and descriptive only.
- If no command entry declares arguments, all commands share the `Arguments:` list.
- The command is parsed first, followed by positional arguments.
- The `Usage:` line is documentation; it does not drive parsing.

## Current Formatting Limits

- Section headers must start exactly with `Usage:`, `Commands:`, `Arguments:`, or `Options:`.
- Entry descriptions must be separated from the entry head by at least two spaces.
- For command entries with inline arguments, keep the full command head before that separator, for example `run ENV TARGET  Execute a deployment`.
- Wrapped description lines inside `Commands:`, `Arguments:`, or `Options:` are not supported and may be parsed as new entries.

## What `cliapp` Actually Gives You

The pleasant part of the greeter example is that it looks tiny:

```nim
let options = cliapp"""..."""
```

The useful part is what that one line buys you at compile time.

For the greeter spec, `smartcli` does not give you a loose bag of strings. It
generates a real parser and a typed result model:

- a `CliCommand` enum for `greet|version`
- a `CliOptions` object with `input`, `command`, `output`, and `verbose`
- a `parseCli()` proc that drives `parseopt` directly
- built-in `-h`/`--help` handling
- built-in `version` handling that prints the title line and exits

That means the nice, tiny source:

```nim
echo options.input
echo options.output
echo options.verbose
echo options.command
```

is backed by something much closer to this:

```nim
block:
  const spec = """..."""

  type
    CliCommand = enum
      cmdNone
      cmdGreet
      cmdVersion

    CliOptions = object
      input: string
      command: CliCommand
      output: string
      verbose: bool

  proc parseCli(): CliOptions =
    var p = initOptParser()
    var argSlot = 0
    result = CliOptions()

    while true:
      next(p)
      case p.kind
      of cmdEnd:
        break
      of cmdArgument:
        case argSlot
        of 0:
          case p.key
          of "greet":
            result.command = cmdGreet
          of "version":
            result.command = cmdVersion
          else:
            cliUnexpectedArgument(spec, p.key)
          inc argSlot
        else:
          case result.command
          of cmdGreet:
            case argSlot
            of 1:
              result.input = p.key
              inc argSlot
            else:
              cliUnexpectedArgument(spec, p.key)
          of cmdVersion:
            cliUnexpectedArgument(spec, p.key)
          else:
            cliUnexpectedArgument(spec, p.key)
      of cmdLongOption:
        case p.key
        of "help":
          cliExitHelp(spec)
        of "output":
          result.output = p.val
        of "verbose":
          result.verbose = true
        else:
          cliUnknownLongOption(spec, p.key)
      of cmdShortOption:
        case p.key
        of "h":
          cliExitHelp(spec)
        of "v":
          result.verbose = true
        else:
          cliUnknownShortOption(spec, p.key)

    if result.command == cmdVersion:
      cliExitVersion(spec)

    case result.command
    of cmdGreet:
      if argSlot < 2:
        cliMissingArguments(spec)
    of cmdVersion:
      discard
    else:
      cliMissingArguments(spec)
```

The point is not that you could write this parser yourself. The point is that
you do not have to. You keep the help text as the source of truth, and you still
end up with typed fields, command enums, and real parser behavior instead of
manual string matching spread across your app.

## Layout

- [src/smartcli.nim](src/smartcli.nim): public runtime API
- [src/smartcliplugin.nim](src/smartcliplugin.nim): compile-time plugin
- [examples/greeter.nim](examples/greeter.nim): minimal app
- [examples/backup.nim](examples/backup.nim): enum and flags
- [tests/tsmoke.nim](tests/tsmoke.nim): parser smoke test
- [tests/tcommandargs.nim](tests/tcommandargs.nim): mixed command arity test
- [tests/tsharedargs.nim](tests/tsharedargs.nim): shared argument compatibility test
- [tests/tslots.nim](tests/tslots.nim): positional slot test

## Run

Compile an example directly with Nimony:

```sh
nimony c examples/greeter.nim
```

Run the package tests directly:

```sh
nimony c -r tests/tsmoke.nim
nimony c -r tests/tcommandargs.nim
nimony c -r tests/tsharedargs.nim
nimony c -r tests/tslots.nim
```

## License

MIT. See [LICENSE](LICENSE).
