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

- Options become typed fields on `options`.
- Entries under `Commands:` become values of `options.command`.
- A command can declare its own positional arguments inline, for example `greet INPUT`.
- If commands do not declare inline arguments, they all share the arguments listed under `Arguments:`.
- `Usage:` is documentation only. It does not define parser behavior.

## Current Limitations

- Use the section headers exactly as written: `Usage:`, `Commands:`, `Arguments:`, and `Options:`.
- Each command, argument, or option must fit on a single line. Wrapped descriptions are not supported.
- Leave at least two consecutive whitespace characters between the
  entry itself and its description.
- For inline command arguments, keep the whole command before the description, for example `run ENV TARGET  Execute a deployment`.
- `Usage:` is only shown to the user. It does not control how the parser is generated.

## What `cliapp` Actually Gives You

The pleasant part of the greeter example is that it looks tiny:

```nim
let options = cliapp"""..."""
```

The useful part is what that one line buys you at compile time.

For the greeter spec, `smartcli` does not give you a loose bag of strings. It
generates a real parser and a typed result model:

- a `CliCommand` enum for `greet|version`
- a generated `CliMode` enum for `fast|slow`
- a `CliOptions` object with `input`, `command`, `mode`, `output`, and `verbose`
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

    CliMode = enum
      cliModeNone
      cliModeFast
      cliModeSlow

    CliOptions = object
      input: string
      command: CliCommand
      mode: CliMode
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
        of "mode":
          case p.val
          of "fast":
            result.mode = cliModeFast
          of "slow":
            result.mode = cliModeSlow
          else:
            cliInvalidValue(spec, "--mode", p.val)
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
- [tests/tcommandargs.nim](tests/tcommandargs.nim): mixed command arity and repeated-whitespace separator test
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
