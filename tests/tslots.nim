import std / assertions
import ".." / "src" / [smartcli]

var
  nifcArgc {.importc: "cmdCount".}: int32
  nifcArgv {.importc: "cmdLine".}: ptr UncheckedArray[cstring]

block:
  nifcArgc = 6
  const cargv = [
    cstring"backup",
    cstring"--mode=delta",
    cstring"--output=backup.log",
    cstring"src",
    cstring"dst",
    cstring"run"
  ]
  nifcArgv = cast[ptr UncheckedArray[cstring]](cargv.addr)

  let options = cliapp"""Backup v0.1
Copies files to a target.

Usage: backup [options] SOURCE DEST run|version

Arguments:
  SOURCE  Source path
  DEST    Destination path

Commands:
  run      Start the backup
  version  Display version and quit

Options:
  --mode=full|delta  Backup mode
  --output=FILE      Log file
  -v, --verbose      Enable verbose output
  -h, --help         Show this help and exit"""

  assert options.source == "src"
  assert options.dest == "dst"
  assert options.output == "backup.log"
  assert $options.mode == "cliModeDelta"
  assert $options.command == "cliCommandRun"
