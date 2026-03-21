import std / [os, strutils]

import nimonyplugins

include nifprelude

type
  FieldKind = enum
    fkString
    fkBool
    fkEnum

  UsageSlotKind = enum
    uskArgument
    uskCommand

  ArgSpec = object
    name: string
    fieldName: string

  CommandSpec = object
    name: string
    enumName: string

  OptionSpec = object
    shortName: string
    longName: string
    fieldName: string
    kind: FieldKind
    choices: seq[string]
    enumTypeName: string
    enumNames: seq[string]

  UsageSlot = object
    kind: UsageSlotKind
    index: int

  CliSpec = object
    rawSpec: string
    title: string
    commands: seq[CommandSpec]
    args: seq[ArgSpec]
    options: seq[OptionSpec]
    slots: seq[UsageSlot]
    hasCommandSlot: bool

proc fail(msg: string) {.noreturn.} =
  quit "[smartcli] " & msg

proc flushWord(current: var string; words: var seq[string]) =
  if current.len > 0:
    words.add current
    current = ""

proc splitWords(s: string): seq[string] =
  var current = ""
  for c in s:
    if c.isAlphaNumeric:
      current.add c.toLowerAscii
    else:
      flushWord current, result
  flushWord current, result

proc toPascalCase(s: string): string =
  let words = splitWords(s)
  for word in words:
    if word.len > 0:
      result.add word[0].toUpperAscii
      if word.len > 1:
        result.add word.substr(1)
  if result.len == 0:
    result = "Value"

proc toCamelCase(s: string): string =
  let words = splitWords(s)
  if words.len == 0:
    return "value"
  result = words[0]
  for i in 1 ..< words.len:
    let word = words[i]
    result.add word[0].toUpperAscii
    if word.len > 1:
      result.add word.substr(1)

proc sectionKind(line: string): string =
  let stripped = line.strip()
  if stripped.endsWith(':'):
    result = stripped.substr(0, stripped.high - 1)
  else:
    result = ""

proc splitEntry(line: string): tuple[left, right: string] =
  let stripped = line.strip()
  var splitAt = -1
  var i = 0
  while i + 1 < stripped.len:
    if stripped[i] == ' ' and stripped[i + 1] == ' ':
      splitAt = i
      break
    inc i
  if splitAt < 0:
    result = (stripped, "")
  else:
    result.left = stripped.substr(0, splitAt - 1).strip()
    result.right = stripped.substr(splitAt).strip()

proc findArg(args: openArray[ArgSpec]; name: string): int =
  for i, arg in args:
    if arg.name == name:
      return i
  result = -1

proc parseArgument(spec: var CliSpec; line: string) =
  let entry = splitEntry(line)
  if entry.left.len == 0:
    return
  spec.args.add ArgSpec(
    name: entry.left.splitWhitespace()[0],
    fieldName: toCamelCase(entry.left)
  )

proc parseCommand(spec: var CliSpec; line: string) =
  let entry = splitEntry(line)
  if entry.left.len == 0:
    return
  let name = entry.left.splitWhitespace()[0]
  spec.commands.add CommandSpec(
    name: name,
    enumName: "cliCommand" & toPascalCase(name)
  )

proc parseOption(spec: var CliSpec; line: string) =
  let entry = splitEntry(line)
  if entry.left.len == 0:
    return

  var option = OptionSpec(kind: fkBool)
  for rawPart in entry.left.split(','):
    let part = rawPart.strip()
    if part.startsWith("--"):
      let valueAt = part.find('=')
      if valueAt >= 0:
        option.longName = part.substr(2, valueAt - 1)
        let placeholder = part.substr(valueAt + 1)
        if placeholder.contains('|'):
          option.kind = fkEnum
          option.choices = placeholder.split('|')
          option.enumTypeName = "Cli" & toPascalCase(option.longName)
          for choice in option.choices:
            option.enumNames.add(
              "cli" & toPascalCase(option.longName) & toPascalCase(choice)
            )
        else:
          option.kind = fkString
      else:
        option.longName = part.substr(2)
    elif part.startsWith("-"):
      option.shortName = part.substr(1)

  if option.longName.len == 0:
    option.longName = option.shortName
  if option.longName == "help":
    return
  option.fieldName = toCamelCase(option.longName)
  if option.kind == fkEnum and option.enumTypeName.len == 0:
    option.enumTypeName = "Cli" & toPascalCase(option.fieldName)
  spec.options.add option

proc parseUsage(spec: var CliSpec; usageLine: string) =
  let tokens = usageLine.splitWhitespace()
  if tokens.len <= 1:
    return

  var commandInserted = false
  var argInserted = false
  for i in 1 ..< tokens.len:
    let token = tokens[i]
    if token == "[options]" or token == "[option]":
      continue

    let core = token.strip(chars = {'[', ']', '<', '>'})
    if core.len == 0:
      continue

    var isCommand = false
    if core.contains('|'):
      let choices = core.split('|')
      if choices.len > 0:
        isCommand = true
        for choice in choices:
          var found = false
          for cmd in spec.commands:
            if choice == cmd.name:
              found = true
              break
          if not found:
            isCommand = false
            break
    else:
      for cmd in spec.commands:
        if core == cmd.name:
          isCommand = true
          break
    if isCommand:
      if not commandInserted:
        spec.slots.add UsageSlot(kind: uskCommand, index: 0)
        spec.hasCommandSlot = true
        commandInserted = true
      continue

    let argIndex = findArg(spec.args, core)
    if argIndex >= 0:
      spec.slots.add UsageSlot(kind: uskArgument, index: argIndex)
      argInserted = true

  if spec.commands.len > 0 and not commandInserted:
    spec.slots.add UsageSlot(kind: uskCommand, index: 0)
    spec.hasCommandSlot = true
  if spec.args.len > 0 and not argInserted:
    spec.slots = @[]
    for i in 0 ..< spec.args.len:
      spec.slots.add UsageSlot(kind: uskArgument, index: i)
    if spec.commands.len > 0:
      spec.slots.add UsageSlot(kind: uskCommand, index: 0)
      spec.hasCommandSlot = true

proc parseSpec(rawSpec: string): CliSpec =
  result.rawSpec = rawSpec
  var currentSection = ""
  var usageLine = ""

  for rawLine in rawSpec.splitLines():
    let stripped = rawLine.strip()
    if result.title.len == 0 and stripped.len > 0:
      result.title = stripped

    let section = sectionKind(rawLine)
    if section.len > 0:
      currentSection = section
      if section == "Usage":
        let colonAt = rawLine.find(':')
        if colonAt >= 0:
          usageLine = rawLine.substr(colonAt + 1).strip()
      continue

    if stripped.len == 0:
      continue

    case currentSection
    of "Usage":
      if usageLine.len == 0:
        usageLine = stripped
    of "Arguments":
      parseArgument result, rawLine
    of "Commands":
      parseCommand result, rawLine
    of "Options":
      parseOption result, rawLine
    else:
      discard

  if usageLine.len > 0:
    parseUsage result, usageLine
  result.slots = @[]
  for i in 0 ..< result.args.len:
    result.slots.add UsageSlot(kind: uskArgument, index: i)
  if result.commands.len > 0:
    result.slots.add UsageSlot(kind: uskCommand, index: 0)
    result.hasCommandSlot = true

proc extractSpec(n: Node): string =
  var n = n
  if n.stmtKind == StmtsS:
    inc n
  if n.kind == ParLe and n.exprKind == SufX:
    inc n
  if n.kind != StringLit:
    fail("cliapp expects a string literal")
  result = pool.strings[n.litId]

proc emitTypeRef(b: var Builder; typeName: string) =
  b.addIdent(typeName)

proc emitMetaNum(b: var Builder; value: string) =
  b.addRaw(" " & value)

proc emitDotExpr(b: var Builder; valueName, fieldName: string) =
  b.withTree "dot":
    b.addIdent(valueName)
    emitMetaNum b, $(fieldName.len + 2)
    b.addIdent(fieldName)

proc emitEqFieldEnum(b: var Builder; valueName, fieldName, enumName: string) =
  b.withTree "infix":
    b.addIdent("==")
    emitDotExpr b, valueName, fieldName
    emitMetaNum b, "1"
    b.addIdent enumName

proc emitEqFieldString(b: var Builder; valueName, fieldName, strValue: string) =
  b.withTree "infix":
    b.addIdent("==")
    emitDotExpr b, valueName, fieldName
    emitMetaNum b, $(fieldName.len + 2)
    b.addStrLit(strValue)

proc emitLtIntExpr(b: var Builder; name: string; value: int) =
  b.withTree "infix":
    b.addIdent("<")
    b.addIdent(name)
    emitMetaNum b, "6"
    b.addIntLit(value)

proc emitAssignResultFieldFromToken(b: var Builder; fieldName, tokenField: string) =
  b.withTree "asgn":
    emitDotExpr b, "result", fieldName
    emitMetaNum b, "7"
    emitDotExpr b, "token", tokenField

proc emitAssignResultFieldIdent(b: var Builder; fieldName, valueName: string) =
  b.withTree "asgn":
    emitDotExpr b, "result", fieldName
    emitMetaNum b, "2"
    b.addIdent(valueName)

proc emitAssignResultFieldTrue(b: var Builder; fieldName: string) =
  b.withTree "asgn":
    emitDotExpr b, "result", fieldName
    emitMetaNum b, "2"
    b.addIdent("true")

proc emitInitResultObject(b: var Builder) =
  b.withTree "asgn":
    b.addIdent("result")
    emitMetaNum b, "12"
    b.withTree "call":
      b.addIdent("CliOptions")

proc emitFieldDecl(b: var Builder; fieldName, typeName: string) =
  b.withTree "fld":
    b.addIdent(fieldName)
    b.addEmpty()
    b.addEmpty()
    emitMetaNum b, $(fieldName.len + 2)
    emitTypeRef b, typeName
    b.addEmpty()

proc emitEnumDecl(b: var Builder; typeName, noneName: string;
    enumNames: openArray[string]) =
  b.withTree "type":
    b.addIdent(typeName)
    b.addEmpty()
    b.addEmpty()
    b.addEmpty()
    emitMetaNum b, $(typeName.len + 1)
    b.withTree "enum":
      b.addEmpty()
      b.withTree "efld":
        b.addIdent(noneName)
        b.addEmpty()
        b.addEmpty()
        b.addEmpty()
        b.addEmpty()
      for enumName in enumNames:
        b.withTree "efld":
          b.addIdent(enumName)
          b.addEmpty()
          b.addEmpty()
          b.addEmpty()
          b.addEmpty()

proc emitOptionsDecl(b: var Builder; spec: CliSpec) =
  if spec.hasCommandSlot:
    var commandNames: seq[string] = @[]
    for command in spec.commands:
      commandNames.add command.enumName
    emitEnumDecl b, "CliCommand", "cliCommandNone", commandNames

  for option in spec.options:
    if option.kind == fkEnum:
      emitEnumDecl b, option.enumTypeName,
        "cli" & toPascalCase(option.fieldName) & "None",
        option.enumNames

  b.withTree "type":
    b.addIdent("CliOptions")
    b.addEmpty()
    b.addEmpty()
    b.addEmpty()
    emitMetaNum b, "11"
    b.withTree "object":
      b.addEmpty()
      for arg in spec.args:
        emitFieldDecl b, arg.fieldName, "string"
      if spec.hasCommandSlot:
        emitFieldDecl b, "command", "CliCommand"
      for option in spec.options:
        case option.kind
        of fkString:
          emitFieldDecl b, option.fieldName, "string"
        of fkBool:
          emitFieldDecl b, option.fieldName, "bool"
        of fkEnum:
          emitFieldDecl b, option.fieldName, option.enumTypeName

proc emitVarDeclCall0(b: var Builder; name, typeName, callee: string) =
  b.withTree "var":
    b.addIdent(name)
    b.addEmpty()
    b.addEmpty()
    emitMetaNum b, $(name.len + 2)
    emitTypeRef b, typeName
    emitMetaNum b, $(name.len + typeName.len + callee.len + 9)
    b.withTree "call":
      b.addIdent(callee)

proc emitVarDeclInt(b: var Builder; name: string; value: int) =
  b.withTree "var":
    b.addIdent(name)
    b.addEmpty()
    b.addEmpty()
    emitMetaNum b, $(name.len + 2)
    b.addIdent("int")
    emitMetaNum b, $(name.len + 8)
    b.addIntLit(value)

proc emitCallStmt1(b: var Builder; name: string; arg: string; isString = false) =
  b.withTree "cmd":
    b.addIdent(name)
    emitMetaNum b, "4"
    if isString:
      b.addStrLit(arg)
    else:
      b.addIdent(arg)

proc emitUnknownOption(b: var Builder; spec: CliSpec; shortOption: bool) =
  b.withTree "call":
    if shortOption:
      b.addIdent("cliUnknownShortOption")
    else:
      b.addIdent("cliUnknownLongOption")
    emitMetaNum b, "1"
    b.addStrLit(spec.rawSpec)
    emitMetaNum b, "12"
    emitDotExpr b, "token", "key"

proc emitEnumOptionBody(b: var Builder; spec: CliSpec; option: OptionSpec) =
  b.withTree "if":
    for i, choice in option.choices:
      b.withTree "elif":
        emitEqFieldString b, "token", "val", choice
        b.withTree "stmts":
          emitAssignResultFieldIdent b, option.fieldName, option.enumNames[i]
    b.withTree "else":
      b.withTree "stmts":
        b.withTree "call":
          b.addIdent("cliInvalidValue")
          emitMetaNum b, "1"
          b.addStrLit(spec.rawSpec)
          emitMetaNum b, "7"
          b.addStrLit("--" & option.longName)
          emitMetaNum b, "22"
          emitDotExpr b, "token", "val"

proc emitOptionDispatch(b: var Builder; spec: CliSpec; shortOption: bool) =
  b.withTree "if":
    if shortOption:
      b.withTree "elif":
        emitEqFieldString b, "token", "key", "h"
        b.withTree "stmts":
          b.withTree "call":
            b.addIdent("cliExitHelp")
            emitMetaNum b, "1"
            b.addStrLit(spec.rawSpec)
    else:
      b.withTree "elif":
        emitEqFieldString b, "token", "key", "help"
        b.withTree "stmts":
          b.withTree "call":
            b.addIdent("cliExitHelp")
            emitMetaNum b, "1"
            b.addStrLit(spec.rawSpec)

    for option in spec.options:
      let key = if shortOption: option.shortName else: option.longName
      if key.len == 0:
        continue
      b.withTree "elif":
        emitEqFieldString b, "token", "key", key
        b.withTree "stmts":
          case option.kind
          of fkString:
            emitAssignResultFieldFromToken b, option.fieldName, "val"
          of fkBool:
            emitAssignResultFieldTrue b, option.fieldName
          of fkEnum:
            emitEnumOptionBody b, spec, option

    b.withTree "else":
      b.withTree "stmts":
        emitUnknownOption b, spec, shortOption

proc emitCommandChoice(b: var Builder; spec: CliSpec) =
  b.withTree "if":
    for command in spec.commands:
      b.withTree "elif":
        emitEqFieldString b, "token", "key", command.name
        b.withTree "stmts":
          emitAssignResultFieldIdent b, "command", command.enumName
    b.withTree "else":
      b.withTree "stmts":
        b.withTree "call":
          b.addIdent("cliUnexpectedArgument")
          emitMetaNum b, "1"
          b.addStrLit(spec.rawSpec)
          emitMetaNum b, "12"
          emitDotExpr b, "token", "key"

proc emitArgumentDispatch(b: var Builder; spec: CliSpec) =
  b.withTree "if":
    for i, slot in spec.slots:
      b.withTree "elif":
        b.withTree "infix":
          b.addIdent("==")
          b.addIdent("argSlot")
          emitMetaNum b, "3"
          b.addIntLit(i)
        b.withTree "stmts":
          case slot.kind
          of uskArgument:
            emitAssignResultFieldFromToken b, spec.args[slot.index].fieldName, "key"
          of uskCommand:
            emitCommandChoice b, spec
          emitCallStmt1 b, "inc", "argSlot"
    b.withTree "else":
      b.withTree "stmts":
        b.withTree "call":
          b.addIdent("cliUnexpectedArgument")
          emitMetaNum b, "1"
          b.addStrLit(spec.rawSpec)
          emitMetaNum b, "12"
          emitDotExpr b, "token", "key"

proc emitParseProc(b: var Builder; spec: CliSpec) =
  b.withTree "proc":
    emitMetaNum b, "5"
    b.addIdent("parseCli")
    b.addEmpty()
    b.addEmpty()
    b.addEmpty()
    emitMetaNum b, $(len("parseCli") + 5)
    b.withTree "params":
      discard
    emitMetaNum b, "4"
    b.addIdent("CliOptions")
    b.addEmpty()
    b.addEmpty()
    b.addRaw(" 2,1")
    b.withTree "stmts":
      emitVarDeclCall0 b, "state", "CliState", "initCliState"
      emitVarDeclCall0 b, "token", "CliToken", "CliToken"
      emitVarDeclInt b, "argSlot", 0
      emitInitResultObject b

      b.withTree "while":
        emitMetaNum b, "15"
        b.withTree "call":
          b.addIdent("nextToken")
          emitMetaNum b, "1"
          b.addIdent("state")
          emitMetaNum b, "8"
          b.addIdent("token")
        b.addRaw(" 2,1")
        b.withTree "stmts":
          b.withTree "if":
            b.withTree "elif":
              emitEqFieldEnum b, "token", "kind", "ctkArgument"
              b.withTree "stmts":
                emitArgumentDispatch b, spec
            b.withTree "elif":
              emitEqFieldEnum b, "token", "kind", "ctkLongOption"
              b.withTree "stmts":
                emitOptionDispatch b, spec, false
            b.withTree "elif":
              emitEqFieldEnum b, "token", "kind", "ctkShortOption"
              b.withTree "stmts":
                emitOptionDispatch b, spec, true

      if spec.slots.len > 0:
        b.withTree "if":
          b.withTree "elif":
            emitLtIntExpr b, "argSlot", spec.slots.len
            b.withTree "stmts":
              b.withTree "call":
                b.addIdent("cliMissingArguments")
                emitMetaNum b, "1"
                b.addStrLit(spec.rawSpec)

      if spec.hasCommandSlot:
        for command in spec.commands:
          if command.name == "version":
            b.withTree "if":
              b.withTree "elif":
                emitEqFieldEnum b, "result", "command", command.enumName
                b.withTree "stmts":
                  b.withTree "call":
                    b.addIdent("cliExitVersion")
                    emitMetaNum b, "1"
                    b.addStrLit(spec.rawSpec)
            break

      b.addIdent("result")

proc generate(spec: CliSpec): string =
  var b = nifbuilder.open(2000)
  b.withTree "stmts":
    b.withTree "block":
      b.addEmpty()
      b.withTree "stmts":
        emitOptionsDecl b, spec
        emitParseProc b, spec
        b.withTree "call":
          b.addIdent("parseCli")
  result = extract(b)

var input = loadTree()
let rawSpec = extractSpec(beginRead(input))
let spec = parseSpec(rawSpec)
writeFile os.paramStr(2), generate(spec)
