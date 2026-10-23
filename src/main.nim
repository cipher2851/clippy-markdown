import os, strutils, parseopt

const
  VERSION = "0.1.0"
  DEFAULT_STYLE = "body { font-family: sans-serif; line-height: 1.6; max-width: 800px; margin: 40px auto; padding: 0 20px; color: #333; } pre { background: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; border: 1px solid #ddd; } table { border-collapse: collapse; width: 100%; margin: 1em 0; } th, td { border: 1px solid #ddd; padding: 8px; } th { background: #eee; } .md-blockquote { border-left: 4px solid #ccc; padding-left: 16px; color: #666; font-style: italic; margin: 1em 0; } .math-display { text-align: center; margin: 1em 0; font-family: serif; } .math-inline { font-family: serif; } .md-footnote { margin-top: 2em; border-top: 1px solid #eee; padding-top: 1em; }"

proc printUsage() =
  echo "Usage: clippy-markdown [options] [input.md]"
  echo ""
  echo "Convert Markdown to a complete HTML document."
  echo ""
  echo "Options:"
  echo "  -h, --help            Show this help message and exit"
  echo "  -v, --version         Show the version and exit"
  echo "  -o, --output FILE     Write HTML to FILE instead of standard output"
  echo ""
  echo "Arguments:"
  echo "  input.md              Markdown file to convert (use - for standard input)"
  echo ""
  echo "If no input file is given, Markdown is read from standard input."

proc run() =
  var inputFile = ""
  var outputFile = ""
  var showHelp = false
  var showVersion = false

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        showHelp = true
      of "version", "v":
        showVersion = true
      of "output", "o":
        outputFile = val
      else:
        echo "Error: unknown option: --", key
        quit(1)
    of cmdArgument:
      if inputFile == "":
        inputFile = key
      else:
        echo "Error: only one input file may be specified"
        quit(1)
    of cmdEnd:
      discard

  if showHelp:
    printUsage()
    return

  if showVersion:
    echo "clippy-markdown ", VERSION
    return

  if inputFile == "":
    inputFile = "-"

  let content =
    if inputFile == "-":
      stdin.readAll()
    else:
      if not fileExists(inputFile):
        echo "Error: File not found: ", inputFile
        quit(1)
      readFile(inputFile)

  var parser = newParser()

  # Example plugin: Replace custom TODO markers
  parser.addPlugin(proc(s: string): string =
    s.replace("TODO:", "<span style='color: red; font-weight: bold;'>TODO:</span>")
  )

  let body = parser.parse(content)

  # Wrap in basic HTML5 structure
  let html = "<!DOCTYPE html>\n<html lang='en'>\n<head>\n  <meta charset='UTF-8'>\n  <title>Converted Markdown</title>\n  <style>" & DEFAULT_STYLE & "</style>\n</head>\n<body>\n" & body & "\n</body>\n</html>"

  if outputFile == "":
    echo html
  else:
    writeFile(outputFile, html & "\n")

when isMainModule:
  run()
