import std / syncio
import ".." / "src" / [smartcli]

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

echo "source: ", options.source
echo "dest: ", options.dest
echo "mode: ", options.mode
echo "verbose: ", options.verbose
echo "command: ", options.command
