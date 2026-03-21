type
  CliTokenKind* = enum
    ctkEnd
    ctkArgument
    ctkLongOption
    ctkShortOption

  CliToken* = object
    kind*: CliTokenKind
    key*: string
    val*: string

  CliState* = object
    parser: OptParser

proc initCliState*(): CliState =
  CliState(parser: initOptParser())

proc nextToken*(state: var CliState; token: var CliToken): bool =
  next state.parser
  token.key = state.parser.key
  token.val = state.parser.val
  case state.parser.kind
  of cmdEnd:
    token.kind = ctkEnd
    token.key = ""
    token.val = ""
  of cmdArgument:
    token.kind = ctkArgument
  of cmdLongOption:
    token.kind = ctkLongOption
  of cmdShortOption:
    token.kind = ctkShortOption
  result = token.kind != ctkEnd

proc writeSpec(spec: string) =
  stdout.write spec
  if not spec.endsWith('\n'):
    stdout.write '\n'
  stdout.flushFile()

proc cliExitHelp*(spec: string) {.noreturn.} =
  writeSpec(spec)
  quit 0

proc cliExitVersion*(spec: string) {.noreturn.} =
  var title = ""
  var i = 0
  while i < spec.len and spec[i] notin {'\n', '\r'}:
    title.add spec[i]
    inc i
  title = title.strip()
  if title.len == 0:
    title = spec.strip()
  stdout.write title
  stdout.write '\n'
  stdout.flushFile()
  quit 0

proc cliFail*(spec, message: string) {.noreturn.} =
  stdout.write "[Error] "
  stdout.write message
  stdout.write '\n'
  writeSpec(spec)
  quit 1

proc cliUnknownLongOption*(spec, key: string) {.noreturn.} =
  cliFail(spec, "unknown option: --" & key)

proc cliUnknownShortOption*(spec, key: string) {.noreturn.} =
  cliFail(spec, "unknown option: -" & key)

proc cliUnexpectedArgument*(spec, arg: string) {.noreturn.} =
  cliFail(spec, "unexpected argument: " & arg)

proc cliMissingArguments*(spec: string) {.noreturn.} =
  cliFail(spec, "missing arguments")

proc cliInvalidValue*(spec, optionName, value: string) {.noreturn.} =
  cliFail(spec, "invalid value for " & optionName & ": " & value)

template cliapp*(spec: string): untyped {.plugin: "smartcliplugin".}
