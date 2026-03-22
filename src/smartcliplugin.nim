import std / [os, strutils]

import nimonyplugins

include nifprelude

type
  FieldKind = enum
    fkString
    fkBool
    fkEnum

  SectionKind = enum
    skNone
    skUsage
    skArguments
    skCommands
    skOptions

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

proc toPascalCase(s: string): string =
  result = newStringOfCap(s.len)
  var upperNext = true
  for c in s:
    if c.isAlphaNumeric:
      let lower = c.toLowerAscii
      if upperNext:
        result.add lower.toUpperAscii
        upperNext = false
      else:
        result.add lower
    else:
      upperNext = true
  if result.len == 0:
    result = "Value"

proc toCamelCase(s: string): string =
  result = newStringOfCap(s.len)
  var seenWord = false
  var upperNext = false
  for c in s:
    if c.isAlphaNumeric:
      let lower = c.toLowerAscii
      if not seenWord:
        result.add lower
        seenWord = true
      elif upperNext:
        result.add lower.toUpperAscii
        upperNext = false
      else:
        result.add lower
    elif seenWord:
      upperNext = true
  if result.len == 0:
    result = "value"

proc parseSectionHeader(line: string): SectionKind =
  if line.startsWith("Usage:"):
    result = skUsage
  elif line.startsWith("Arguments:"):
    result = skArguments
  elif line.startsWith("Commands:"):
    result = skCommands
  elif line.startsWith("Options:"):
    result = skOptions
  else:
    result = skNone

proc parseEntryHead(line: string): string =
  let stripped = line.strip()
  var splitAt = -1
  var i = 0
  while i + 1 < stripped.len:
    if stripped[i] == ' ' and stripped[i + 1] == ' ':
      splitAt = i
      break
    inc i
  if splitAt < 0:
    result = stripped
  else:
    result = stripped.substr(0, splitAt - 1)

proc parseFirstToken(s: string): string =
  var endAt = 0
  while endAt < s.len and s[endAt] notin Whitespace:
    inc endAt

  if endAt == 0:
    result = ""
  elif endAt >= s.len:
    result = s
  else:
    result = s.substr(0, endAt - 1)

proc parseArgument(spec: var CliSpec; line: string) =
  let head = parseEntryHead(line)
  if head.len == 0:
    return
  spec.args.add ArgSpec(
    name: parseFirstToken(head),
    fieldName: toCamelCase(head)
  )

proc parseCommand(spec: var CliSpec; line: string) =
  let head = parseEntryHead(line)
  if head.len == 0:
    return
  let name = parseFirstToken(head)
  spec.commands.add CommandSpec(
    name: name,
    enumName: "cmd" & toPascalCase(name)
  )

proc parseOption(spec: var CliSpec; line: string) =
  let head = parseEntryHead(line)
  if head.len == 0:
    return

  var option = OptionSpec(kind: fkBool)
  for rawPart in head.split(','):
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

proc parseSpec(rawSpec: string): CliSpec =
  result = CliSpec(rawSpec: rawSpec)
  var currentSection = skNone

  for rawLine in rawSpec.splitLines():
    let stripped = rawLine.strip()
    if result.title.len == 0 and stripped.len > 0:
      result.title = stripped

    let header = parseSectionHeader(rawLine)
    if header != skNone:
      currentSection = header
    elif stripped.len > 0:
      case currentSection
      of skUsage:
        discard
      of skArguments:
        parseArgument result, rawLine
      of skCommands:
        parseCommand result, rawLine
      of skOptions:
        parseOption result, rawLine
      of skNone:
        discard

  if result.args.len > 0 or result.commands.len > 0:
    result.slots = @[]
    if result.commands.len > 0:
      result.slots.add UsageSlot(kind: uskCommand, index: 0)
      result.hasCommandSlot = true
    for i in 0 ..< result.args.len:
      result.slots.add UsageSlot(kind: uskArgument, index: i)

proc extractSpec(n: Node): string =
  var n = n
  if n.stmtKind == StmtsS:
    inc n
  if n.kind == ParLe and n.exprKind == SufX:
    inc n
  if n.kind != StringLit:
    fail("cliapp expects a string literal")
  result = pool.strings[n.litId]

proc addDots(dest: var Tree; count: int) =
  for _ in 0 ..< count:
    dest.addDotToken()

# TYPE
proc emitTypeRef(dest: var Tree; typeName: string) =
  dest.addIdent(typeName)

# (dot VALUE FIELD)
proc emitDotExpr(dest: var Tree; valueName, fieldName: string) =
  dest.withTree DotX, NoLineInfo:
    dest.addIdent(valueName)
    dest.addIdent(fieldName)

# (infix "<" NAME INT)
proc emitLtIntExpr(dest: var Tree; name: string; value: int) =
  dest.withTree InfixX, NoLineInfo:
    dest.addIdent("<")
    dest.addIdent(name)
    dest.addIntLit(value)

# (asgn (dot result FIELD) (dot VALUE SOURCE_FIELD))
proc emitAssignResultFieldFromField(dest: var Tree; fieldName, valueName,
    sourceField: string) =
  dest.withTree AsgnS, NoLineInfo:
    emitDotExpr dest, "result", fieldName
    emitDotExpr dest, valueName, sourceField

# (asgn (dot result FIELD) VALUE)
proc emitAssignResultFieldIdent(dest: var Tree; fieldName, valueName: string) =
  dest.withTree AsgnS, NoLineInfo:
    emitDotExpr dest, "result", fieldName
    dest.addIdent(valueName)

# (asgn (dot result FIELD) true)
proc emitAssignResultFieldTrue(dest: var Tree; fieldName: string) =
  dest.withTree AsgnS, NoLineInfo:
    emitDotExpr dest, "result", fieldName
    dest.addIdent("true")

# (asgn result (call CliOptions))
proc emitInitResultObject(dest: var Tree) =
  dest.withTree AsgnS, NoLineInfo:
    dest.addIdent("result")
    dest.withTree CallX, NoLineInfo:
      dest.addIdent("CliOptions")

# (fld FIELD . . TYPE .)
proc emitFieldDecl(dest: var Tree; fieldName, typeName: string) =
  dest.withTree FldU, NoLineInfo:
    dest.addIdent(fieldName)
    dest.addDots(2)
    emitTypeRef dest, typeName
    dest.addDotToken()

# (efld FIELD . . . .)
proc emitEnumField(dest: var Tree; fieldName: string) =
  dest.withTree EfldU, NoLineInfo:
    dest.addIdent(fieldName)
    dest.addDots(4)

template withOfIdent(dest: var Tree; valueName: string; body: untyped) =
  dest.withTree OfU, NoLineInfo:
    dest.withTree RangesU, NoLineInfo:
      dest.addIdent(valueName)
    dest.withTree StmtsS, NoLineInfo:
      body

template withOfString(dest: var Tree; value: string; body: untyped) =
  dest.withTree OfU, NoLineInfo:
    dest.withTree RangesU, NoLineInfo:
      dest.addStrLit(value)
    dest.withTree StmtsS, NoLineInfo:
      body

template withOfInt(dest: var Tree; value: int; body: untyped) =
  dest.withTree OfU, NoLineInfo:
    dest.withTree RangesU, NoLineInfo:
      dest.addIntLit(value)
    dest.withTree StmtsS, NoLineInfo:
      body

# (type TYPE . . . (enum . (efld NONE . . . .) (efld VALUE . . . .)*))
proc emitEnumDecl(dest: var Tree; typeName, noneName: string;
    enumNames: openArray[string]) =
  dest.withTree TypeS, NoLineInfo:
    dest.addIdent(typeName)
    dest.addDots(3)
    dest.withTree EnumT, NoLineInfo:
      dest.addDotToken()
      emitEnumField dest, noneName
      for enumName in enumNames:
        emitEnumField dest, enumName

# (type CliCommand . . . (enum . (efld cmdNone . . . .) (efld COMMAND . . . .)*))?
# (type ENUM_TYPE . . . (enum . (efld ENUM_NONE . . . .) (efld ENUM_VALUE . . . .)*))*
# (type CliOptions . . . (object . (fld ARG . . string .)* (fld command . . CliCommand .)? (fld OPTION . . OPTION_TYPE .)*))
proc emitOptionsDecl(dest: var Tree; spec: CliSpec) =
  if spec.hasCommandSlot:
    var commandNames: seq[string] = @[]
    for command in spec.commands:
      commandNames.add command.enumName
    emitEnumDecl dest, "CliCommand", "cmdNone", commandNames

  for option in spec.options:
    if option.kind == fkEnum:
      emitEnumDecl dest, option.enumTypeName,
        "cli" & toPascalCase(option.fieldName) & "None",
        option.enumNames

  dest.withTree TypeS, NoLineInfo:
    dest.addIdent("CliOptions")
    dest.addDots(3)
    dest.withTree ObjectT, NoLineInfo:
      dest.addDotToken()
      for arg in spec.args:
        emitFieldDecl dest, arg.fieldName, "string"
      if spec.hasCommandSlot:
        emitFieldDecl dest, "command", "CliCommand"
      for option in spec.options:
        case option.kind
        of fkString:
          emitFieldDecl dest, option.fieldName, "string"
        of fkBool:
          emitFieldDecl dest, option.fieldName, "bool"
        of fkEnum:
          emitFieldDecl dest, option.fieldName, option.enumTypeName

# (var NAME . . int INT)
proc emitVarDeclInt(dest: var Tree; name: string; value: int) =
  dest.withTree VarS, NoLineInfo:
    dest.addIdent(name)
    dest.addDots(2)
    dest.addIdent("int")
    dest.addIntLit(value)

# (var NAME . . TYPE (call CALLEE))
proc emitVarDeclCall0(dest: var Tree; name, typeName, callee: string) =
  dest.withTree VarS, NoLineInfo:
    dest.addIdent(name)
    dest.addDots(2)
    emitTypeRef dest, typeName
    dest.withTree CallX, NoLineInfo:
      dest.addIdent(callee)

# (cmd NAME ARG)
proc emitCallStmt1(dest: var Tree; name, arg: string; isString = false) =
  dest.withTree CmdS, NoLineInfo:
    dest.addIdent(name)
    if isString:
      dest.addStrLit(arg)
    else:
      dest.addIdent(arg)

# (call cliUnknownShortOption SPEC (dot VALUE KEY))
# (call cliUnknownLongOption SPEC (dot VALUE KEY))
proc emitUnknownOption(dest: var Tree; spec: CliSpec; shortOption: bool) =
  dest.withTree CallX, NoLineInfo:
    if shortOption:
      dest.addIdent("cliUnknownShortOption")
    else:
      dest.addIdent("cliUnknownLongOption")
    dest.addStrLit(spec.rawSpec)
    emitDotExpr dest, "p", "key"

# (case (dot p val)
#   (of CHOICE (stmts (asgn (dot result FIELD) ENUM_VALUE)))+
#   (else (stmts (call cliInvalidValue SPEC OPTION (dot p val)))))
proc emitEnumOptionBody(dest: var Tree; spec: CliSpec; option: OptionSpec) =
  dest.withTree CaseS, NoLineInfo:
    emitDotExpr dest, "p", "val"
    for i, choice in option.choices:
      dest.withOfString choice:
          emitAssignResultFieldIdent dest, option.fieldName, option.enumNames[i]
    dest.withTree ElseU, NoLineInfo:
      dest.withTree StmtsS, NoLineInfo:
        dest.withTree CallX, NoLineInfo:
          dest.addIdent("cliInvalidValue")
          dest.addStrLit(spec.rawSpec)
          dest.addStrLit("--" & option.longName)
          emitDotExpr dest, "p", "val"

# (case (dot p key)
#   (of HELP (stmts (call cliExitHelp SPEC)))?
#   (of OPTION_KEY (stmts OPTION_BODY))*
#   (else (stmts (call cliUnknown{Short,Long}Option SPEC (dot p key))))
proc emitOptionDispatch(dest: var Tree; spec: CliSpec; shortOption: bool) =
  dest.withTree CaseS, NoLineInfo:
    emitDotExpr dest, "p", "key"
    if shortOption:
      dest.withOfString "h":
          dest.withTree CallX, NoLineInfo:
            dest.addIdent("cliExitHelp")
            dest.addStrLit(spec.rawSpec)
    else:
      dest.withOfString "help":
          dest.withTree CallX, NoLineInfo:
            dest.addIdent("cliExitHelp")
            dest.addStrLit(spec.rawSpec)

    for option in spec.options:
      let key = if shortOption: option.shortName else: option.longName
      if key.len > 0:
        dest.withOfString key:
            case option.kind
            of fkString:
              emitAssignResultFieldFromField dest, option.fieldName, "p", "val"
            of fkBool:
              emitAssignResultFieldTrue dest, option.fieldName
            of fkEnum:
              emitEnumOptionBody dest, spec, option

    dest.withTree ElseU, NoLineInfo:
      dest.withTree StmtsS, NoLineInfo:
        emitUnknownOption dest, spec, shortOption

# (case (dot p key)
#   (of COMMAND (stmts (asgn (dot result command) COMMAND_ENUM)))+
#   (else (stmts (call cliUnexpectedArgument SPEC (dot p key))))
proc emitCommandChoice(dest: var Tree; spec: CliSpec) =
  dest.withTree CaseS, NoLineInfo:
    emitDotExpr dest, "p", "key"
    for command in spec.commands:
      dest.withOfString command.name:
          emitAssignResultFieldIdent dest, "command", command.enumName
    dest.withTree ElseU, NoLineInfo:
      dest.withTree StmtsS, NoLineInfo:
        dest.withTree CallX, NoLineInfo:
          dest.addIdent("cliUnexpectedArgument")
          dest.addStrLit(spec.rawSpec)
          emitDotExpr dest, "p", "key"

# (case argSlot
#   (of INT (stmts SLOT_BODY (cmd inc argSlot)))+
#   (else (stmts (call cliUnexpectedArgument SPEC (dot p key)))))
proc emitArgumentDispatch(dest: var Tree; spec: CliSpec) =
  dest.withTree CaseS, NoLineInfo:
    dest.addIdent("argSlot")
    for i, slot in spec.slots:
      dest.withOfInt i:
          case slot.kind
          of uskArgument:
            emitAssignResultFieldFromField dest, spec.args[slot.index].fieldName, "p", "key"
          of uskCommand:
            emitCommandChoice dest, spec
          emitCallStmt1 dest, "inc", "argSlot"
    dest.withTree ElseU, NoLineInfo:
      dest.withTree StmtsS, NoLineInfo:
        dest.withTree CallX, NoLineInfo:
          dest.addIdent("cliUnexpectedArgument")
          dest.addStrLit(spec.rawSpec)
          emitDotExpr dest, "p", "key"

# (proc parseCli . . . (params) CliOptions . .
#   (stmts
#     (var p . . OptParser (call initOptParser))
#     (var argSlot . . int 0)
#     (asgn result (call CliOptions))
#     (while true
#       (stmts
#         (cmd next p)
#         (case (dot p kind)
#           (of cmdEnd (stmts (break .)))
#           (of cmdArgument (stmts ARG_DISPATCH))
#           (of cmdLongOption (stmts LONG_OPTION_DISPATCH))
#           (of cmdShortOption (stmts SHORT_OPTION_DISPATCH)))))
#     (if (elif (infix "<" argSlot INT) (stmts (call cliMissingArguments SPEC))))?
#     (if (elif (infix "==" (dot result command) VERSION_ENUM) (stmts (call cliExitVersion SPEC))))?))
proc emitParseProc(dest: var Tree; spec: CliSpec) =
  dest.withTree ProcS, NoLineInfo:
    dest.addIdent("parseCli")
    dest.addDots(3)
    dest.withTree ParamsU, NoLineInfo:
      discard
    dest.addIdent("CliOptions")
    dest.addDots(2)
    dest.withTree StmtsS, NoLineInfo:
      emitVarDeclCall0 dest, "p", "OptParser", "initOptParser"
      emitVarDeclInt dest, "argSlot", 0
      emitInitResultObject dest

      dest.withTree WhileS, NoLineInfo:
        dest.addIdent("true")
        dest.withTree StmtsS, NoLineInfo:
          emitCallStmt1 dest, "next", "p"
          dest.withTree CaseS, NoLineInfo:
            emitDotExpr dest, "p", "kind"
            dest.withOfIdent "cmdEnd":
                dest.withTree BreakS, NoLineInfo:
                  dest.addDotToken()
            dest.withOfIdent "cmdArgument":
              emitArgumentDispatch dest, spec
            dest.withOfIdent "cmdLongOption":
              emitOptionDispatch dest, spec, false
            dest.withOfIdent "cmdShortOption":
              emitOptionDispatch dest, spec, true

      if spec.hasCommandSlot:
        for command in spec.commands:
          if command.name == "version":
            dest.withTree IfS, NoLineInfo:
              dest.withTree ElifU, NoLineInfo:
                dest.withTree InfixX, NoLineInfo:
                  dest.addIdent("==")
                  emitDotExpr dest, "result", "command"
                  dest.addIdent(command.enumName)
                dest.withTree StmtsS, NoLineInfo:
                  dest.withTree CallX, NoLineInfo:
                    dest.addIdent("cliExitVersion")
                    dest.addStrLit(spec.rawSpec)
            break

      if spec.slots.len > 0:
        dest.withTree IfS, NoLineInfo:
          dest.withTree ElifU, NoLineInfo:
            emitLtIntExpr dest, "argSlot", spec.slots.len
            dest.withTree StmtsS, NoLineInfo:
              dest.withTree CallX, NoLineInfo:
                dest.addIdent("cliMissingArguments")
                dest.addStrLit(spec.rawSpec)

proc generate(spec: CliSpec; info: LineInfo): Tree =
  result = createTree()
  result.withTree StmtsS, info:
    result.withTree BlockS, info:
      result.addDotToken()
      result.withTree StmtsS, info:
        emitOptionsDecl result, spec
        emitParseProc result, spec
        result.withTree CallX, NoLineInfo:
          result.addIdent("parseCli")

var input = loadTree()
let root = beginRead(input)
let rawSpec = extractSpec(root)
let spec = parseSpec(rawSpec)
saveTree generate(spec, root.info), os.paramStr(2)
