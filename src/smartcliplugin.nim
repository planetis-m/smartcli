import std / [parseutils, strutils]

import nimonyplugins

type
  FieldKind = enum
    fkString
    fkBool
    fkEnum

  PositionalMode = enum
    pmNone
    pmFlat
    pmSharedCommand
    pmInlineCommand

  SectionKind = enum
    skNone
    skUsage
    skArguments
    skCommands
    skOptions

  OptionSpec = object
    shortName: string
    longName: string
    kind: FieldKind
    choices: seq[string]

  CommandSpec = object
    name: string
    argumentNames: seq[string]

  CliSpec = object
    commands: seq[CommandSpec]
    argumentNames: seq[string]
    options: seq[OptionSpec]

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

proc argumentFieldName(name: string): string =
  result = toCamelCase(name)

proc commandEnumName(name: string): string =
  result = "cmd" & toPascalCase(name)

proc optionFieldName(option: OptionSpec): string =
  result = toCamelCase(option.longName)

proc optionEnumPrefix(option: OptionSpec): string =
  result = "cli" & toPascalCase(option.longName)

proc optionEnumTypeName(option: OptionSpec): string =
  result = "Cli" & toPascalCase(option.longName)

proc optionEnumNoneName(option: OptionSpec): string =
  result = option.optionEnumPrefix & "None"

proc optionEnumValueName(option: OptionSpec; choice: string): string =
  result = option.optionEnumPrefix & toPascalCase(choice)

proc positionalMode(spec: CliSpec): PositionalMode =
  if spec.commands.len == 0:
    if spec.argumentNames.len == 0:
      result = pmNone
    else:
      result = pmFlat
  else:
    result = pmSharedCommand
    for command in spec.commands:
      if command.argumentNames.len > 0:
        return pmInlineCommand

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
  result = line.strip(trailing = false)
  var i = 0
  while i + 1 < result.len:
    if result[i] in Whitespace and result[i + 1] in Whitespace:
      return result.substr(0, i - 1)
    inc i

proc parseArgument(spec: var CliSpec; head: string) =
  let tokenLen = skipUntil(head, Whitespace)
  if tokenLen > 0:
    spec.argumentNames.add head.substr(0, tokenLen - 1)

proc parseCommand(spec: var CliSpec; head: string) =
  var name = ""
  var argumentNames: seq[string] = @[]
  for token in strutils.splitWhitespace(head):
    if name.len == 0:
      name = token
    else:
      argumentNames.add token
  if name.len > 0:
    spec.commands.add CommandSpec(name: name, argumentNames: argumentNames)

proc parseOption(spec: var CliSpec; head: string) =
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
        else:
          option.kind = fkString
      else:
        option.longName = part.substr(2)
    elif part.startsWith("-"):
      option.shortName = part.substr(1)

  if option.longName.len == 0:
    option.longName = option.shortName
  if option.longName != "help":
    spec.options.add option

proc parseSectionEntry(spec: var CliSpec; section: SectionKind; line: string) =
  let head = parseEntryHead(line)
  if head.len > 0:
    case section
    of skArguments:
      parseArgument spec, head
    of skCommands:
      parseCommand spec, head
    of skOptions:
      parseOption spec, head
    of skUsage, skNone:
      discard

proc parseSpec(rawSpec: string): CliSpec =
  result = CliSpec()
  var currentSection = skNone
  for rawLine in rawSpec.splitLines():
    let header = parseSectionHeader(rawLine)
    if header != skNone:
      currentSection = header
    elif not rawLine.isEmptyOrWhitespace:
      parseSectionEntry result, currentSection, rawLine

proc extractSpecNode(n: NifCursor): NifCursor =
  result = n
  if result.stmtKind == StmtsS:
    inc result
  if result.kind == ParLe and result.exprKind == SufX:
    inc result

# TYPE
proc emitTypeRef(dest: var NifBuilder; typeName: string)
  {.ensuresNif: addedAny(dest).} =
  dest.addIdent(typeName)

# (dot VALUE FIELD)
proc emitDotExpr(dest: var NifBuilder; valueName, fieldName: string; info: LineInfo)
  {.ensuresNif: addedExpr(dest).} =
  dest.withTree DotX, info:
    dest.addIdent(valueName)
    dest.addIdent(fieldName)

# (infix "<" NAME INT)
proc emitLtIntExpr(dest: var NifBuilder; name: string; value: int; info: LineInfo)
  {.ensuresNif: addedExpr(dest).} =
  dest.withTree InfixX, info:
    dest.addIdent("<")
    dest.addIdent(name)
    dest.addIntLit(value)

# (asgn (dot result FIELD) (dot VALUE SOURCE_FIELD))
proc emitAssignResultFieldFromField(dest: var NifBuilder; fieldName, valueName, sourceField: string; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree AsgnS, info:
    emitDotExpr dest, "result", fieldName, info
    emitDotExpr dest, valueName, sourceField, info

# (asgn (dot result FIELD) VALUE)
proc emitAssignResultFieldIdent(dest: var NifBuilder; fieldName, valueName: string; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree AsgnS, info:
    emitDotExpr dest, "result", fieldName, info
    dest.addIdent(valueName)

# (asgn (dot result FIELD) true)
proc emitAssignResultFieldTrue(dest: var NifBuilder; fieldName: string; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree AsgnS, info:
    emitDotExpr dest, "result", fieldName, info
    dest.addIdent("true")

# (asgn result (call CliOptions))
proc emitInitResultObject(dest: var NifBuilder; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree AsgnS, info:
    dest.addIdent("result")
    dest.withTree CallX, info:
      dest.addIdent("CliOptions")

# (fld FIELD . . TYPE .)
proc emitFieldDecl(dest: var NifBuilder; fieldName, typeName: string; info: LineInfo)
  {.ensuresNif: addedNested(dest).} =
  dest.withTree FldU, info:
    dest.addIdent(fieldName)
    dest.addEmptyNode2()
    emitTypeRef dest, typeName
    dest.addEmptyNode()

# (efld FIELD . . . .)
proc emitEnumField(dest: var NifBuilder; fieldName: string; info: LineInfo)
  {.ensuresNif: addedNested(dest).} =
  dest.withTree EfldU, info:
    dest.addIdent(fieldName)
    dest.addEmptyNode4()

# (fld ARG . . string .)*
proc emitArgumentFieldDecls(dest: var NifBuilder; spec: CliSpec; info: LineInfo)
  {.ensuresNif: addedAny(dest).} =
  case spec.positionalMode()
  of pmNone:
    discard
  of pmFlat, pmSharedCommand:
    for argumentName in spec.argumentNames:
      emitFieldDecl dest, argumentFieldName(argumentName), "string", info
  of pmInlineCommand:
    var emitted: seq[string] = @[]
    for command in spec.commands:
      for argumentName in command.argumentNames:
        if argumentName notin emitted:
          emitted.add argumentName
          emitFieldDecl dest, argumentFieldName(argumentName), "string", info

template withOfIdent(dest: var NifBuilder; valueName: string; info: LineInfo; body: untyped) =
  dest.withTree OfU, info:
    dest.withTree RangesU, info:
      dest.addIdent(valueName)
    dest.withTree StmtsS, info:
      body

template withOfString(dest: var NifBuilder; value: string; info: LineInfo; body: untyped) =
  dest.withTree OfU, info:
    dest.withTree RangesU, info:
      dest.addStrLit(value)
    dest.withTree StmtsS, info:
      body

template withOfInt(dest: var NifBuilder; value: int; info: LineInfo; body: untyped) =
  dest.withTree OfU, info:
    dest.withTree RangesU, info:
      dest.addIntLit(value)
    dest.withTree StmtsS, info:
      body

# (type TYPE . . . (enum . (efld NONE . . . .) (efld VALUE . . . .)*))
proc emitEnumDecl(dest: var NifBuilder; typeName, noneName: string; enumNames: openArray[string]; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree TypeS, info:
    dest.addIdent(typeName)
    dest.addEmptyNode3()
    dest.withTree EnumT, info:
      dest.addEmptyNode()
      emitEnumField dest, noneName, info
      for enumName in enumNames:
        emitEnumField dest, enumName, info

# (type CliCommand . . . (enum . (efld cmdNone . . . .) (efld COMMAND . . . .)*))?
# (type ENUM_TYPE . . . (enum . (efld ENUM_NONE . . . .) (efld ENUM_VALUE . . . .)*))*
# (type CliOptions . . . (object . (fld ARG . . string .)* (fld command . . CliCommand .)? (fld OPTION . . OPTION_TYPE .)*))
proc emitOptionsDecl(dest: var NifBuilder; spec: CliSpec; info: LineInfo)
  {.ensuresNif: addedAny(dest).} =
  if spec.commands.len > 0:
    var commandNames: seq[string] = @[]
    for command in spec.commands:
      commandNames.add commandEnumName(command.name)
    emitEnumDecl dest, "CliCommand", "cmdNone", commandNames, info

  for option in spec.options:
    if option.kind == fkEnum:
      var enumNames: seq[string] = @[]
      for choice in option.choices:
        enumNames.add option.optionEnumValueName(choice)
      emitEnumDecl dest, option.optionEnumTypeName,
        option.optionEnumNoneName, enumNames, info

  dest.withTree TypeS, info:
    dest.addIdent("CliOptions")
    dest.addEmptyNode3()
    dest.withTree ObjectT, info:
      dest.addEmptyNode()
      emitArgumentFieldDecls dest, spec, info
      if spec.commands.len > 0:
        emitFieldDecl dest, "command", "CliCommand", info
      for option in spec.options:
        case option.kind
        of fkString:
          emitFieldDecl dest, option.optionFieldName, "string", info
        of fkBool:
          emitFieldDecl dest, option.optionFieldName, "bool", info
        of fkEnum:
          emitFieldDecl dest, option.optionFieldName, option.optionEnumTypeName, info

# (var NAME . . int INT)
proc emitVarDeclInt(dest: var NifBuilder; name: string; value: int; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree VarS, info:
    dest.addIdent(name)
    dest.addEmptyNode2()
    dest.addIdent("int")
    dest.addIntLit(value)

# (var NAME . . TYPE (call CALLEE))
proc emitVarDeclCall0(dest: var NifBuilder; name, typeName, callee: string; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree VarS, info:
    dest.addIdent(name)
    dest.addEmptyNode2()
    emitTypeRef dest, typeName
    dest.withTree CallX, info:
      dest.addIdent(callee)

# (cmd NAME ARG)
proc emitCallStmt1(dest: var NifBuilder; name, arg: string; info: LineInfo; isString = false)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree CmdS, info:
    dest.addIdent(name)
    if isString:
      dest.addStrLit(arg)
    else:
      dest.addIdent(arg)

# (call cliUnknownShortOption SPEC (dot VALUE KEY))
# (call cliUnknownLongOption SPEC (dot VALUE KEY))
proc emitUnknownOption(dest: var NifBuilder; rawSpec: string; shortOption: bool; info: LineInfo)
  {.ensuresNif: addedExpr(dest).} =
  dest.withTree CallX, info:
    if shortOption:
      dest.addIdent("cliUnknownShortOption")
    else:
      dest.addIdent("cliUnknownLongOption")
    dest.addStrLit(rawSpec)
    emitDotExpr dest, "p", "key", info

# (case (dot p val)
#   (of CHOICE (stmts (asgn (dot result FIELD) ENUM_VALUE)))+
#   (else (stmts (call cliInvalidValue SPEC OPTION (dot p val)))))
proc emitEnumOptionBody(dest: var NifBuilder; rawSpec: string; option: OptionSpec; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree CaseS, info:
    emitDotExpr dest, "p", "val", info
    for choice in option.choices:
      dest.withOfString choice, info:
        emitAssignResultFieldIdent dest, option.optionFieldName,
          option.optionEnumValueName(choice), info
    dest.withTree ElseU, info:
      dest.withTree StmtsS, info:
        dest.withTree CallX, info:
          dest.addIdent("cliInvalidValue")
          dest.addStrLit(rawSpec)
          dest.addStrLit("--" & option.longName)
          emitDotExpr dest, "p", "val", info

# (case (dot p key)
#   (of HELP (stmts (call cliExitHelp SPEC)))?
#   (of OPTION_KEY (stmts OPTION_BODY))*
#   (else (stmts (call cliUnknown{Short,Long}Option SPEC (dot p key))))
proc emitOptionDispatch(dest: var NifBuilder; rawSpec: string; spec: CliSpec; shortOption: bool; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree CaseS, info:
    emitDotExpr dest, "p", "key", info
    if shortOption:
      dest.withOfString "h", info:
        dest.withTree CallX, info:
          dest.addIdent("cliExitHelp")
          dest.addStrLit(rawSpec)
    else:
      dest.withOfString "help", info:
        dest.withTree CallX, info:
          dest.addIdent("cliExitHelp")
          dest.addStrLit(rawSpec)

    for option in spec.options:
      let key = if shortOption: option.shortName else: option.longName
      if key.len > 0:
        dest.withOfString key, info:
          case option.kind
          of fkString:
            emitAssignResultFieldFromField dest, option.optionFieldName, "p", "val", info
          of fkBool:
            emitAssignResultFieldTrue dest, option.optionFieldName, info
          of fkEnum:
            emitEnumOptionBody dest, rawSpec, option, info

    dest.withTree ElseU, info:
      dest.withTree StmtsS, info:
        emitUnknownOption dest, rawSpec, shortOption, info

# (case (dot p key)
#   (of COMMAND (stmts (asgn (dot result command) COMMAND_ENUM)))+
#   (else (stmts (call cliUnexpectedArgument SPEC (dot p key))))
proc emitCommandChoice(dest: var NifBuilder; rawSpec: string; spec: CliSpec; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree CaseS, info:
    emitDotExpr dest, "p", "key", info
    for command in spec.commands:
      dest.withOfString command.name, info:
        emitAssignResultFieldIdent dest, "command", commandEnumName(command.name), info
    dest.withTree ElseU, info:
      dest.withTree StmtsS, info:
        dest.withTree CallX, info:
          dest.addIdent("cliUnexpectedArgument")
          dest.addStrLit(rawSpec)
          emitDotExpr dest, "p", "key", info

# (case argSlot
#   (of INT (stmts SLOT_BODY (cmd inc argSlot)))+
#   (else (stmts (call cliUnexpectedArgument SPEC (dot p key)))))
proc emitArgumentSlots(dest: var NifBuilder; rawSpec: string; argumentNames: seq[string];
    slotOffset: int; info: LineInfo) {.ensuresNif: addedStmt(dest).} =
  dest.withTree CaseS, info:
    dest.addIdent("argSlot")
    for i, argumentName in argumentNames:
      dest.withOfInt i + slotOffset, info:
        emitAssignResultFieldFromField dest,
          argumentFieldName(argumentName), "p", "key", info
        emitCallStmt1 dest, "inc", "argSlot", info
    dest.withTree ElseU, info:
      dest.withTree StmtsS, info:
        dest.withTree CallX, info:
          dest.addIdent("cliUnexpectedArgument")
          dest.addStrLit(rawSpec)
          emitDotExpr dest, "p", "key", info

# (case (dot result command)
#   (of COMMAND_ENUM (stmts (call cliUnexpectedArgument SPEC (dot p key))))?
#   (of COMMAND_ENUM (stmts ARGUMENT_SLOTS))*
#   (else (stmts (call cliUnexpectedArgument SPEC (dot p key)))))
proc emitCommandArgumentDispatch(dest: var NifBuilder; rawSpec: string; spec: CliSpec; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree CaseS, info:
    emitDotExpr dest, "result", "command", info
    for command in spec.commands:
      dest.withOfIdent commandEnumName(command.name), info:
        if command.argumentNames.len == 0:
          dest.withTree CallX, info:
            dest.addIdent("cliUnexpectedArgument")
            dest.addStrLit(rawSpec)
            emitDotExpr dest, "p", "key", info
        else:
          emitArgumentSlots dest, rawSpec, command.argumentNames, 1, info
    dest.withTree ElseU, info:
      dest.withTree StmtsS, info:
        dest.withTree CallX, info:
          dest.addIdent("cliUnexpectedArgument")
          dest.addStrLit(rawSpec)
          emitDotExpr dest, "p", "key", info

# (case argSlot ARGUMENT_SLOTS)?
# (if (elif (infix "<" argSlot 1) (stmts COMMAND_CHOICE (cmd inc argSlot)))
#   (else (stmts ARGUMENT_SLOTS_OR_COMMAND_ARGUMENT_DISPATCH)))?
proc emitArgumentDispatch(dest: var NifBuilder; rawSpec: string; spec: CliSpec; info: LineInfo)
  {.ensuresNif: addedAny(dest).} =
  let mode = spec.positionalMode()
  case mode
  of pmNone:
    discard
  of pmFlat:
    emitArgumentSlots dest, rawSpec, spec.argumentNames, 0, info
  of pmSharedCommand, pmInlineCommand:
    dest.withTree IfS, info:
      dest.withTree ElifU, info:
        emitLtIntExpr dest, "argSlot", 1, info
        dest.withTree StmtsS, info:
          emitCommandChoice dest, rawSpec, spec, info
          emitCallStmt1 dest, "inc", "argSlot", info
      dest.withTree ElseU, info:
        dest.withTree StmtsS, info:
          if mode == pmSharedCommand:
            emitArgumentSlots dest, rawSpec, spec.argumentNames, 1, info
          else:
            emitCommandArgumentDispatch dest, rawSpec, spec, info

# (case (dot result command)
#   (of COMMAND_ENUM (stmts (if (elif (infix "<" argSlot REQUIRED) (stmts (call cliMissingArguments SPEC))))))+
#   (else (stmts (call cliMissingArguments SPEC))))
proc emitInlineCommandMissingCheck(dest: var NifBuilder; rawSpec: string; spec: CliSpec; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree CaseS, info:
    emitDotExpr dest, "result", "command", info
    for command in spec.commands:
      let requiredSlots = 1 + command.argumentNames.len
      dest.withOfIdent commandEnumName(command.name), info:
        dest.withTree IfS, info:
          dest.withTree ElifU, info:
            emitLtIntExpr dest, "argSlot", requiredSlots, info
            dest.withTree StmtsS, info:
              dest.withTree CallX, info:
                dest.addIdent("cliMissingArguments")
                dest.addStrLit(rawSpec)
    dest.withTree ElseU, info:
      dest.withTree StmtsS, info:
        dest.withTree CallX, info:
          dest.addIdent("cliMissingArguments")
          dest.addStrLit(rawSpec)

# (if (elif (infix "<" argSlot REQUIRED) (stmts (call cliMissingArguments SPEC))))
proc emitSharedCommandMissingCheck(dest: var NifBuilder; rawSpec: string; argumentCount: int; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  dest.withTree IfS, info:
    dest.withTree ElifU, info:
      emitLtIntExpr dest, "argSlot", 1 + argumentCount, info
      dest.withTree StmtsS, info:
        dest.withTree CallX, info:
          dest.addIdent("cliMissingArguments")
          dest.addStrLit(rawSpec)

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
proc emitParseProc(dest: var NifBuilder; rawSpec: string; spec: CliSpec; info: LineInfo)
  {.ensuresNif: addedStmt(dest).} =
  let mode = spec.positionalMode()
  dest.withTree ProcS, info:
    dest.addIdent("parseCli")
    dest.addEmptyNode3()
    dest.withTree ParamsU, info:
      discard
    dest.addIdent("CliOptions")
    dest.addEmptyNode2()
    dest.withTree StmtsS, info:
      emitVarDeclCall0 dest, "p", "OptParser", "initOptParser", info
      if mode != pmNone:
        emitVarDeclInt dest, "argSlot", 0, info
      emitInitResultObject dest, info

      dest.withTree WhileS, info:
        dest.addIdent("true")
        dest.withTree StmtsS, info:
          emitCallStmt1 dest, "next", "p", info
          dest.withTree CaseS, info:
            emitDotExpr dest, "p", "kind", info
            dest.withOfIdent "cmdEnd", info:
              dest.withTree BreakS, info:
                dest.addDotToken()
            dest.withOfIdent "cmdArgument", info:
              if mode != pmNone:
                emitArgumentDispatch dest, rawSpec, spec, info
              else:
                dest.withTree CallX, info:
                  dest.addIdent("cliUnexpectedArgument")
                  dest.addStrLit(rawSpec)
                  emitDotExpr dest, "p", "key", info
            dest.withOfIdent "cmdLongOption", info:
              emitOptionDispatch dest, rawSpec, spec, false, info
            dest.withOfIdent "cmdShortOption", info:
              emitOptionDispatch dest, rawSpec, spec, true, info

      if spec.commands.len > 0:
        for command in spec.commands:
          if command.name == "version":
            dest.withTree IfS, info:
              dest.withTree ElifU, info:
                dest.withTree InfixX, info:
                  dest.addIdent("==")
                  emitDotExpr dest, "result", "command", info
                  dest.addIdent(commandEnumName(command.name))
                dest.withTree StmtsS, info:
                  dest.withTree CallX, info:
                    dest.addIdent("cliExitVersion")
                    dest.addStrLit(rawSpec)
            break

      case mode
      of pmNone:
        discard
      of pmFlat:
        dest.withTree IfS, info:
          dest.withTree ElifU, info:
            emitLtIntExpr dest, "argSlot", spec.argumentNames.len, info
            dest.withTree StmtsS, info:
              dest.withTree CallX, info:
                dest.addIdent("cliMissingArguments")
                dest.addStrLit(rawSpec)
      of pmSharedCommand:
        emitSharedCommandMissingCheck dest, rawSpec, spec.argumentNames.len, info
      of pmInlineCommand:
        emitInlineCommandMissingCheck dest, rawSpec, spec, info

proc generate(rawSpec: string; spec: CliSpec; info: LineInfo): NifBuilder =
  result = createTree()
  result.withTree StmtsS, info:
    result.withTree BlockS, info:
      result.addEmptyNode()
      result.withTree StmtsS, info:
        emitOptionsDecl result, spec, info
        emitParseProc result, rawSpec, spec, info
        result.withTree CallX, info:
          result.addIdent("parseCli")

let root = loadPluginInput()
let specNode = extractSpecNode(root)
if specNode.kind == StringLit:
  let rawSpec = specNode.stringValue
  let spec = parseSpec(rawSpec)
  saveTree generate(rawSpec, spec, root.info)
else:
  saveTree errorTree("cliapp expects a string literal", specNode)
