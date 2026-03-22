import std / [os, strutils, tables]

import nimonyplugins

include nifprelude

type
  OptionKind = enum
    okString
    okBool
    okEnum

  SectionKind = enum
    skNone
    skUsage
    skArguments
    skCommands
    skOptions

  ArgumentSpec = object
    name: string

  PendingCommandSpec = object
    name: string
    argNames: seq[string]

  CommandSpec = object
    name: string
    argIndices: seq[int]

  OptionSpec = object
    shortName: string
    longName: string
    kind: OptionKind
    choices: seq[string]

  CliSpec = object
    rawSpec: string
    commands: seq[CommandSpec]
    arguments: seq[ArgumentSpec]
    options: seq[OptionSpec]

proc fail(msg: string) {.noreturn.} =
  quit "[smartcli] " & msg

proc hasCommandSlot(spec: CliSpec): bool =
  result = spec.commands.len > 0

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

proc argumentFieldName(argument: ArgumentSpec): string =
  result = toCamelCase(argument.name)

proc commandEnumName(commandName: string): string =
  result = "cmd" & toPascalCase(commandName)

proc optionFieldName(option: OptionSpec): string =
  result = toCamelCase(option.longName)

proc optionEnumStem(option: OptionSpec): string =
  result = toPascalCase(option.longName)

proc optionEnumTypeName(option: OptionSpec): string =
  result = "Cli" & optionEnumStem(option)

proc optionEnumNoneName(option: OptionSpec): string =
  result = "cli" & optionEnumStem(option) & "None"

proc optionEnumValueName(option: OptionSpec; choice: string): string =
  result = "cli" & optionEnumStem(option) & toPascalCase(choice)

proc optionTypeName(option: OptionSpec): string =
  case option.kind
  of okString:
    result = "string"
  of okBool:
    result = "bool"
  of okEnum:
    result = optionEnumTypeName(option)

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

proc parseArgument(line: string): ArgumentSpec =
  result = ArgumentSpec()
  let head = parseEntryHead(line)
  if head.len == 0:
    return
  let name = parseFirstToken(head)
  if name.len > 0:
    result = ArgumentSpec(name: name)

proc parseCommand(line: string): PendingCommandSpec =
  result = PendingCommandSpec()
  let head = parseEntryHead(line)
  if head.len == 0:
    return
  let tokens = head.splitWhitespace()
  if tokens.len > 0:
    result = PendingCommandSpec(name: tokens[0])
    for i in 1..<tokens.len:
      result.argNames.add(tokens[i])

proc resolveCommand(command: PendingCommandSpec;
    argumentIndices: Table[string, int]): CommandSpec =
  result = CommandSpec(name: command.name)
  for argName in command.argNames:
    if not argumentIndices.hasKey(argName):
      fail("command '" & command.name & "' references unknown argument '" &
        argName & "'")
    result.argIndices.add argumentIndices[argName]

proc parseOption(line: string): OptionSpec =
  let head = parseEntryHead(line)
  if head.len == 0:
    return

  var shortName = ""
  var longName = ""
  var placeholder = ""
  for rawPart in head.split(','):
    let part = rawPart.strip()
    if part.startsWith("--"):
      let valueAt = part.find('=')
      if valueAt >= 0:
        longName = part.substr(2, valueAt - 1)
        placeholder = part.substr(valueAt + 1)
      else:
        longName = part.substr(2)
    elif part.startsWith("-"):
      shortName = part.substr(1)

  if longName.len == 0:
    longName = shortName
  if longName == "help":
    return
  result = OptionSpec(shortName: shortName, longName: longName)
  if placeholder.len == 0:
    result.kind = okBool
  elif placeholder.contains('|'):
    result.kind = okEnum
    result.choices = placeholder.split('|')
  else:
    result.kind = okString

proc parseSpec(rawSpec: string): CliSpec =
  result = CliSpec(rawSpec: rawSpec)
  var currentSection = skNone
  var pendingCommands: seq[PendingCommandSpec] = @[]
  var argumentIndices = initTable[string, int]()

  for rawLine in rawSpec.splitLines():
    let stripped = rawLine.strip()
    let header = parseSectionHeader(rawLine)
    if header != skNone:
      currentSection = header
    elif stripped.len > 0:
      case currentSection
      of skUsage:
        discard
      of skArguments:
        let argument = parseArgument(rawLine)
        if argument.name.len > 0:
          argumentIndices[argument.name] = result.arguments.len
          result.arguments.add argument
      of skCommands:
        let command = parseCommand(rawLine)
        if command.name.len > 0:
          pendingCommands.add command
      of skOptions:
        let option = parseOption(rawLine)
        if option.longName.len > 0:
          result.options.add option
      of skNone:
        discard

  for command in pendingCommands:
    result.commands.add resolveCommand(command, argumentIndices)

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
      commandNames.add commandEnumName(command.name)
    emitEnumDecl dest, "CliCommand", "cmdNone", commandNames

  for option in spec.options:
    if option.kind == okEnum:
      var enumNames: seq[string] = @[]
      for choice in option.choices:
        enumNames.add optionEnumValueName(option, choice)
      emitEnumDecl dest, optionEnumTypeName(option),
        optionEnumNoneName(option), enumNames

  dest.withTree TypeS, NoLineInfo:
    dest.addIdent("CliOptions")
    dest.addDots(3)
    dest.withTree ObjectT, NoLineInfo:
      dest.addDotToken()
      for argument in spec.arguments:
        emitFieldDecl dest, argumentFieldName(argument), "string"
      if spec.hasCommandSlot:
        emitFieldDecl dest, "command", "CliCommand"
      for option in spec.options:
        emitFieldDecl dest, optionFieldName(option), optionTypeName(option)

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

proc emitUnexpectedArgument(dest: var Tree; spec: CliSpec) =
  dest.withTree CallX, NoLineInfo:
    dest.addIdent("cliUnexpectedArgument")
    dest.addStrLit(spec.rawSpec)
    emitDotExpr dest, "p", "key"

# (case (dot p val)
#   (of CHOICE (stmts (asgn (dot result FIELD) ENUM_VALUE)))+
#   (else (stmts (call cliInvalidValue SPEC OPTION (dot p val)))))
proc emitEnumOptionBody(dest: var Tree; spec: CliSpec; option: OptionSpec) =
  dest.withTree CaseS, NoLineInfo:
    emitDotExpr dest, "p", "val"
    for choice in option.choices:
      dest.withOfString choice:
          emitAssignResultFieldIdent dest, optionFieldName(option),
            optionEnumValueName(option, choice)
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
            of okString:
              emitAssignResultFieldFromField dest, optionFieldName(option),
                "p", "val"
            of okBool:
              emitAssignResultFieldTrue dest, optionFieldName(option)
            of okEnum:
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
          emitAssignResultFieldIdent dest, "command", commandEnumName(command.name)
    dest.withTree ElseU, NoLineInfo:
      dest.withTree StmtsS, NoLineInfo:
        emitUnexpectedArgument dest, spec

proc emitCommandArgumentBody(dest: var Tree; spec: CliSpec; command: CommandSpec) =
  if command.argIndices.len == 0:
    emitUnexpectedArgument dest, spec
  else:
    dest.withTree CaseS, NoLineInfo:
      dest.addIdent("argSlot")
      for i, argIndex in command.argIndices:
        dest.withOfInt i + 1:
            emitAssignResultFieldFromField dest,
              argumentFieldName(spec.arguments[argIndex]), "p", "key"
            emitCallStmt1 dest, "inc", "argSlot"
      dest.withTree ElseU, NoLineInfo:
        dest.withTree StmtsS, NoLineInfo:
          emitUnexpectedArgument dest, spec

proc emitCommandArgumentDispatch(dest: var Tree; spec: CliSpec) =
  dest.withTree CaseS, NoLineInfo:
    dest.addIdent("argSlot")
    dest.withOfInt 0:
        emitCommandChoice dest, spec
        emitCallStmt1 dest, "inc", "argSlot"
    dest.withTree ElseU, NoLineInfo:
      dest.withTree StmtsS, NoLineInfo:
        dest.withTree CaseS, NoLineInfo:
          emitDotExpr dest, "result", "command"
          for command in spec.commands:
            dest.withOfIdent commandEnumName(command.name):
                emitCommandArgumentBody dest, spec, command
          dest.withTree ElseU, NoLineInfo:
            dest.withTree StmtsS, NoLineInfo:
              emitUnexpectedArgument dest, spec

proc emitFlatArgumentDispatch(dest: var Tree; spec: CliSpec) =
  dest.withTree CaseS, NoLineInfo:
    dest.addIdent("argSlot")
    for i, argument in spec.arguments:
      dest.withOfInt i:
          emitAssignResultFieldFromField dest, argumentFieldName(argument),
            "p", "key"
          emitCallStmt1 dest, "inc", "argSlot"
    dest.withTree ElseU, NoLineInfo:
      dest.withTree StmtsS, NoLineInfo:
        emitUnexpectedArgument dest, spec

proc emitMissingArguments(dest: var Tree; spec: CliSpec) =
  dest.withTree CallX, NoLineInfo:
    dest.addIdent("cliMissingArguments")
    dest.addStrLit(spec.rawSpec)

proc emitCommandMissingArgumentsCheck(dest: var Tree; spec: CliSpec) =
  dest.withTree IfS, NoLineInfo:
    dest.withTree ElifU, NoLineInfo:
      dest.withTree InfixX, NoLineInfo:
        dest.addIdent("==")
        emitDotExpr dest, "result", "command"
        dest.addIdent("cmdNone")
      dest.withTree StmtsS, NoLineInfo:
        emitMissingArguments dest, spec

  for command in spec.commands:
    if command.argIndices.len > 0:
      dest.withTree IfS, NoLineInfo:
        dest.withTree ElifU, NoLineInfo:
          dest.withTree InfixX, NoLineInfo:
            dest.addIdent("and")
            dest.withTree InfixX, NoLineInfo:
              dest.addIdent("==")
              emitDotExpr dest, "result", "command"
              dest.addIdent(commandEnumName(command.name))
            dest.withTree InfixX, NoLineInfo:
              dest.addIdent("<")
              dest.addIdent("argSlot")
              dest.addIntLit(command.argIndices.len + 1)
          dest.withTree StmtsS, NoLineInfo:
            emitMissingArguments dest, spec

proc emitFlatMissingArgumentsCheck(dest: var Tree; spec: CliSpec) =
  if spec.arguments.len > 0:
    dest.withTree IfS, NoLineInfo:
      dest.withTree ElifU, NoLineInfo:
        emitLtIntExpr dest, "argSlot", spec.arguments.len
        dest.withTree StmtsS, NoLineInfo:
          emitMissingArguments dest, spec

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
              if spec.hasCommandSlot:
                emitCommandArgumentDispatch dest, spec
              else:
                emitFlatArgumentDispatch dest, spec
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
                  dest.addIdent(commandEnumName(command.name))
                dest.withTree StmtsS, NoLineInfo:
                  dest.withTree CallX, NoLineInfo:
                    dest.addIdent("cliExitVersion")
                    dest.addStrLit(spec.rawSpec)
            break

      if spec.hasCommandSlot:
        emitCommandMissingArgumentsCheck dest, spec
      else:
        emitFlatMissingArgumentsCheck dest, spec

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
